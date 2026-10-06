"""Payment service on loopback :8766, exposed only through scoped Nginx routes."""
from datetime import datetime, timezone
from functools import lru_cache
import hashlib
import hmac
import io
import json
import logging
from pathlib import Path
import re
import secrets
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

import psycopg
import qrcode
import qrcode.image.svg

from .wechat import APPID, MCHID, ORIGIN, SKU, TITLE, WeChat, PaymentError, decode_json, validate_success
from .alipay import Alipay, is_qr_code

LOG = logging.getLogger('payments')
ORDER = re.compile(r'(?:WX|AL)[0-9a-f]{30}\Z')
CALLS = {'catalog':2,'create_order':4,'get_order':1,'pending':0,'update_gateway':3,'deliver':5,
    'begin_reset':4,'finish_reset':4,'create_order_channel':5}


@lru_cache(maxsize=128)
def qr_matrix(code):
    """Game-native panels avoid browser overlays and remote image restrictions."""
    qr=qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,border=4)
    qr.add_data(code);qr.make(fit=True)
    rows=qr.get_matrix()
    if len(rows)>65:raise PaymentError('game_qr_too_large',502)
    return '|'.join(''.join('1' if cell else '0' for cell in row) for row in rows)


class Database:
    def __init__(self, dsn):
        self.dsn = dsn

    def call(self, name, *values):
        if name not in CALLS or len(values)!=CALLS[name]:
            raise PaymentError('database_call_invalid',500)
        try:
            with psycopg.connect(self.dsn,connect_timeout=3,
                    options='-c statement_timeout=4000 -c lock_timeout=2000 -c search_path=pg_catalog') as conn:
                if conn.info.user!='goufayu_payment':
                    raise PaymentError('database_role_invalid',503)
                query = 'SELECT payments.'+name+'('+','.join(['%s']*len(values))+')'
                result = conn.execute(query,values).fetchone()[0]
            if isinstance(result,dict) and result.get('error'):
                raise PaymentError(result['error'],409)
            return result
        except psycopg.Error:
            raise PaymentError('payment_database_unavailable',503) from None


def expired(order):
    return datetime.fromisoformat(order['expires_at'])<=datetime.now(timezone.utc)


def native_qr(order):
    code=order.get('code_url')
    return is_qr_code(code) if order.get('provider')=='alipay' else isinstance(code,str) and code.startswith('weixin://wxpay/bizpayurl?')


class Payments:
    def __init__(self, config, database, wechat, alipay=None):
        self.config, self.db, self.wechat = config, database, wechat
        self.alipay = alipay
        self.alipay_mode = config.get('alipay_checkout_mode','page_pay')
        if self.alipay_mode not in ('page_pay','precreate'):raise ValueError('alipay_checkout_mode_invalid')
        self.locks = [threading.Lock() for _ in range(64)]

    def lock(self, order_id):
        return self.locks[int(hashlib.sha256(order_id.encode()).hexdigest()[:8],16)%64]

    def identity(self, body):
        account, session = body.get('account_id',''), body.get('match_session_id','')
        if not isinstance(account,str) or not re.fullmatch(r'[1-9][0-9]{0,9}',account):
            raise PaymentError('account_id_invalid')
        if not isinstance(session,str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{8,128}',session):
            raise PaymentError('match_session_invalid')
        if account not in self.config['allowed_accounts']:
            raise PaymentError('test_account_required',403)
        hashed = hmac.new(self.config['pepper'].encode(),account.encode(),hashlib.sha256).hexdigest()
        catalog = self.db.call('catalog',hashed,session)
        return hashed,session,catalog

    def token(self, order_id):
        return hmac.new(self.config['checkout_key'].encode(),('checkout:'+order_id).encode(),hashlib.sha256).hexdigest()

    def public(self, order):
        result = {'ok':True,'sku':order['sku'],'title':order['reward'].get('title',TITLE),
            'description':order['reward'].get('description',''),
            'reward_lines':order['reward'].get('grants',{}).get('lines',[]),
            'effects':order['reward'].get('effects',{}),
            'effect_labels':order['reward'].get('grants',{}).get('effect_labels',{}),
            'catalog_hash':order['reward'].get('catalog_hash',''),
            'amount_fen':order['amount'],'currency':order['currency'],
            'order_id':order['order_id'],'provider':order.get('provider','wechat'),'state':order['state'],'expires_at':order['expires_at'],
            'expired':expired(order), 'effect_changes':order.get('effect_changes',{}),
            'checkout_url':ORIGIN+'/checkout?order='+order['order_id']+'&token='+self.token(order['order_id'])}
        if result['provider']=='alipay':
            result['checkout_url']=ORIGIN+'/checkout/alipay?order='+order['order_id']+'&token='+self.token(order['order_id'])
        result['checkout_mode']='qr' if native_qr(order) else 'page_pay' if order.get('code_url')=='alipay:page_pay' else 'preparing'
        if native_qr(order) and order['state']=='pending' and not result['expired']:
            result['qr_matrix']=qr_matrix(order['code_url'])
        return result

    def success(self, transaction):
        order_id = transaction.get('out_trade_no','')
        if not isinstance(order_id,str) or not ORDER.fullmatch(order_id):
            raise PaymentError('order_id_invalid')
        order = self.db.call('get_order',order_id)
        if order.get('provider','wechat')!='wechat':raise PaymentError('payment_mismatch')
        transaction_id = validate_success(transaction,order)
        result = self.db.call('deliver',order_id,transaction_id,order['amount'],APPID,MCHID)
        LOG.info('payment_confirmed order=%s state=%s',order_id,result['state'])
        return result

    def alipay_notice(self, raw):
        if not self.alipay:raise PaymentError('payment_channel_unavailable',503)
        value=self.alipay.notice(raw)
        order_id=value.get('out_trade_no','')
        if not isinstance(order_id,str) or not ORDER.fullmatch(order_id):raise PaymentError('order_id_invalid')
        with self.lock(order_id):
            order=self.db.call('get_order',order_id)
            self.alipay.validate(value,order,notice=True)
            state=value.get('trade_status')
            if state in ('TRADE_SUCCESS','TRADE_FINISHED'):return self.alipay_success(value,order)
            if state=='TRADE_CLOSED':return self.db.call('update_gateway',order_id,'closed',None)
            if state!='WAIT_BUYER_PAY':raise PaymentError('alipay_trade_state_invalid')
            return order

    def alipay_success(self, value, order):
        transaction=self.alipay.validate(value,order)
        if value.get('trade_status') not in ('TRADE_SUCCESS','TRADE_FINISHED'):raise PaymentError('payment_mismatch')
        result=self.db.call('deliver',order['order_id'],transaction,order['amount'],self.alipay.app_id,self.alipay.seller_id)
        LOG.info('alipay_confirmed order=%s state=%s',order['order_id'],result['state'])
        return result

    def reconcile_alipay(self, order):
        if not self.alipay:raise PaymentError('payment_channel_unavailable',503)
        if order['appid']!=self.alipay.app_id or order['mchid']!=self.alipay.seller_id:raise PaymentError('payment_mismatch')
        try:value=self.alipay.query(order['order_id'])
        except PaymentError as exc:
            if exc.code=='ACQ.TRADE_NOT_EXIST':
                if expired(order):return self.db.call('update_gateway',order['order_id'],'closed',None)
                return order
            raise
        self.alipay.validate(value,order)
        state=value.get('trade_status')
        if state in ('TRADE_SUCCESS','TRADE_FINISHED'):return self.alipay_success(value,order)
        if state=='TRADE_CLOSED':return self.db.call('update_gateway',order['order_id'],'closed',None)
        if state=='WAIT_BUYER_PAY' and expired(order):
            self.alipay.close(order['order_id'])
            return self.db.call('update_gateway',order['order_id'],'closed',None)
        return self.db.call('get_order',order['order_id'])

    def close_order(self, order):
        order=self.reconcile(order)
        if order['state'] not in ('created','pending'):return order
        gateway=self.alipay if order.get('provider')=='alipay' else self.wechat
        try:gateway.close(order['order_id'])
        except PaymentError as exc:
            if exc.code=='ORDER_NOT_EXIST':pass
            elif exc.code=='ACQ.TRADE_NOT_EXIST' and expired(order):pass
            elif exc.code=='ACQ.TRADE_NOT_EXIST':
                # A previously issued page-pay form can still create this trade
                # until its absolute expiry; do not enable a second live payment.
                raise PaymentError('payment_close_pending',409) from None
            elif exc.code in ('ORDERPAID','ACQ.TRADE_STATUS_ERROR'):
                checked=self.reconcile(order)
                if checked['state'] not in ('delivered','paid_review','closed'):raise
                return checked
            else:raise
        return self.db.call('update_gateway',order['order_id'],'closed',None)

    def reconcile(self, order):
        if order['state'] not in ('created','pending'):
            return order
        order_id = order['order_id']
        self.db.call('update_gateway',order_id,'checked',None)
        if order.get('provider')=='alipay':return self.reconcile_alipay(order)
        try:
            transaction = self.wechat.query(order_id)
        except PaymentError as exc:
            # Only a signature-verified missing-order response may close a
            # never-created expired intent. Transport failures remain pending.
            if exc.code=='ORDER_NOT_EXIST':
                if expired(order):
                    return self.db.call('update_gateway',order_id,'closed',None)
                return order
            raise
        if transaction.get('out_trade_no')!=order_id or transaction.get('mchid')!=MCHID or transaction.get('appid')!=APPID:
            raise PaymentError('payment_mismatch')
        state = transaction.get('trade_state')
        if state=='SUCCESS':
            return self.success(transaction)
        if state=='CLOSED':
            return self.db.call('update_gateway',order_id,'closed',None)
        if state=='NOTPAY' and expired(order):
            self.wechat.close(order_id)
            return self.db.call('update_gateway',order_id,'closed',None)
        return self.db.call('get_order',order_id)

    def game(self, path, body):
        fields = {'catalog':set(),'create':{'sku'},'status':{'order_id'},'cancel':{'order_id'},'reset':{'kind','request_id'}}
        if path not in fields:raise PaymentError('route_not_found',404)
        allowed = {'account_id','match_session_id'} | fields[path]
        if path=='create' and 'provider' in body:allowed.add('provider')
        if set(body)!=allowed:
            raise PaymentError('request_fields_invalid')
        account,session,catalog = self.identity(body)
        if path=='catalog':
            return {**catalog,'wechat':True,'alipay':self.alipay is not None,'alipay_checkout_mode':self.alipay_mode}
        if path=='reset':
            # TODO(PAYMENT_TEST_ONLY): disabled by default, both HTTP and SQL gates required.
            if self.config.get('test_reset_enabled') is not True:
                raise PaymentError('test_reset_disabled',403)
            kind,request=body['kind'],body['request_id']
            if kind not in ('refreshdata','refreshmoney') or not isinstance(request,str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{8,128}',request):
                raise PaymentError('reset_invalid')
            started=self.db.call('begin_reset',account,session,kind,request)
            if started.get('completed'):return started
            for pending in started.get('orders',[]):
                with self.lock(pending['order_id']):
                    self.close_order(self.db.call('get_order',pending['order_id']))
            return self.db.call('finish_reset',account,session,kind,request)
        if path in ('status','cancel'):
            order_id=body['order_id']
            if not isinstance(order_id,str) or not ORDER.fullmatch(order_id):
                raise PaymentError('order_id_invalid')
            order=self.db.call('get_order',order_id)
            if order['account_id']!=account:
                raise PaymentError('order_missing',404)
            if path=='cancel':
                with self.lock(order_id):order=self.close_order(self.db.call('get_order',order_id))
            return self.public(order)
        if path!='create':
            raise PaymentError('route_not_found',404)
        if not isinstance(body['sku'],str) or not re.fullmatch(r'[a-z0-9_]{4,64}',body['sku']):
            raise PaymentError('product_unavailable')
        provider=body.get('provider','wechat')
        if provider not in ('wechat','alipay') or (provider=='alipay' and not self.alipay):raise PaymentError('payment_channel_unavailable',409)
        if provider=='wechat':order=self.db.call('create_order',account,session,'WX'+secrets.token_hex(15),body['sku'])
        else:order=self.db.call('create_order_channel',account,session,'AL'+secrets.token_hex(15),body['sku'],provider)
        with self.lock(order['order_id']):
            order=self.db.call('get_order',order['order_id'])
            if order['state']=='created' or expired(order):
                order=self.reconcile(order)
            if order['state']=='created' and not expired(order):
                # Same immutable out_trade_no on every retry, including a crash
                # between gateway acceptance and persisting the QR. Existing
                # pending page-pay orders keep their original flow and expiry.
                if order.get('provider')=='alipay':
                    code=self.alipay.precreate(order) if self.alipay_mode=='precreate' else 'alipay:page_pay'
                else:code=self.wechat.create(order)
                order=self.db.call('update_gateway',order['order_id'],'pending',code)
            return self.public(order)

    def checkout(self, query):
        parsed=parse_qs(query,keep_blank_values=True,strict_parsing=True)
        if set(parsed)!={'order','token'} or any(len(v)!=1 for v in parsed.values()):
            raise PaymentError('checkout_invalid',404)
        order_id,token=parsed['order'][0],parsed['token'][0]
        if not ORDER.fullmatch(order_id) or not hmac.compare_digest(self.token(order_id),token):
            raise PaymentError('checkout_invalid',404)
        return self.db.call('get_order',order_id)

    def worker(self):
        while True:
            try:
                for order in self.db.call('pending'):
                    with self.lock(order['order_id']):
                        try:
                            self.reconcile(self.db.call('get_order',order['order_id']))
                        except PaymentError as exc:
                            LOG.warning('reconcile_pending order=%s code=%s',order['order_id'],exc.code)
            except Exception:
                LOG.error('reconcile_failed')
            time.sleep(10)


PAGE = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>商品商城 · 扫码支付</title>
<link rel="stylesheet" href="/checkout.css"><main><p class="eyebrow">游戏测试商品</p><h1 id="title">正在加载商品</h1><p>请核对商品、金额及游戏内奖励明细</p><strong id="price" class="price">—</strong><p id="scan">请使用订单对应的支付应用扫码，付款后自动发到下单的游戏账号。</p><img id="qr" width="256" height="256" alt="正在加载付款码"><p id="status" role="status">正在查询订单…</p><p id="order" class="muted"></p><button id="refresh">刷新付款状态</button><p class="muted">到账确认可能需要数秒。请勿重复付款；可返回游戏查看存档。</p></main><script src="/checkout.js"></script></html>'''
CSS = '''body{margin:0;background:#101725;color:#e8edf6;font:16px system-ui,sans-serif;line-height:1.6}main{max-width:460px;margin:5vh auto;padding:32px;text-align:center;background:#1b263b;border-radius:20px}h1{font-size:32px;margin:8px}.eyebrow,.muted{color:#aab6cc;font-size:13px}.price{display:block;font-size:44px;color:#ffd68a}img{background:white;border-radius:10px;margin:10px auto;display:block}button{padding:10px 24px;border:0;border-radius:8px;background:#72d5ac;color:#102820;font:inherit;cursor:pointer}button:disabled{opacity:.5}#status{min-height:26px;color:#ffd68a}'''
JS = '''(function(){"use strict";var query=location.search,qr=document.getElementById("qr"),status=document.getElementById("status"),busy=false,done=false;qr.src="/checkout/qr"+query;function poll(){if(busy)return;busy=true;fetch("/checkout/status"+query,{cache:"no-store"}).then(function(r){if(!r.ok)throw Error();return r.json();}).then(function(d){var channel=d.provider==="alipay"?"支付宝":"微信";document.getElementById("scan").textContent="使用手机"+channel+"扫描二维码，付款后自动发到下单的游戏账号。";qr.alt=channel+"付款码";document.getElementById("title").textContent=d.title;document.getElementById("price").textContent="¥"+(d.amount_fen/100).toFixed(2);document.getElementById("order").textContent="订单号："+d.order_id;var labels={created:"订单正在准备，请返回游戏重试。",pending:"等待"+channel+"付款…",delivered:"支付成功，"+d.title+" 的全部奖励已写入存档。返回游戏即可查看。",paid_review:"已收到付款，但账号已拥有该奖励。请保留订单号联系开发者处理退款，请勿重复付款。",closed:"订单已关闭，请返回游戏重新下单。"};status.textContent=labels[d.state]||"正在确认付款…";done=["delivered","paid_review","closed"].indexOf(d.state)>=0;if(done||d.expired){qr.style.display="none";if(!done)status.textContent="付款码已过期，正在确认最终状态。请勿重复付款。";}}).catch(function(){status.textContent="暂时无法查询，请稍后刷新；请勿重复付款。";}).finally(function(){busy=false;});}document.getElementById("refresh").onclick=poll;poll();setInterval(function(){if(!done)poll();},4000);}());'''
RETURN_PAGE = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>返回游戏确认到账</title><link rel="stylesheet" href="/checkout.css"><main><h1>请返回游戏查看订单</h1><p>服务器正在核对支付宝付款结果。确认到账后，奖励会自动写入下单账号的存档。</p><p>在游戏收银页点击“查询付款结果”即可查看。请勿重复付款。</p></main></html>'''


def handler(app):
    class Handler(BaseHTTPRequestHandler):
        server_version='SurvivalPayments/1'
        def log_message(self,*args):
            pass  # Never log checkout capability URLs, headers or body.
        def setup(self):
            self.request.settimeout(5)
            super().setup()
            def expire():
                try:self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:pass
            self.deadline=threading.Timer(25,expire)
            self.deadline.daemon=True
            self.deadline.start()
        def finish(self):
            self.deadline.cancel()
            try:super().finish()
            except OSError:pass
        def send(self,status,body,kind='application/json; charset=utf-8',alipay_form=False):
            if isinstance(body,dict):body=json.dumps(body,ensure_ascii=False,separators=(',',':')).encode()
            elif isinstance(body,str):body=body.encode()
            self.send_response(status)
            for key,value in {'Content-Type':kind,'Content-Length':str(len(body)),
                'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff',
                'Content-Security-Policy':"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action "+('https://openapi.alipay.com https://unitradeprod.alipay.com https://excashier.alipay.com' if alipay_form else "'none'"),
                'Connection':'close'}.items():self.send_header(key,value)
            self.end_headers();self.wfile.write(body);self.close_connection=True
        def run(self,func):
            try:func()
            except PaymentError as exc:self.send(exc.status,{'ok':False,'error':exc.code})
            except (OSError,TimeoutError):pass
            except (ValueError,TypeError):self.send(400,{'ok':False,'error':'request_invalid'})
            except Exception:
                LOG.error('request_failed')
                self.send(503,{'ok':False,'error':'payment_unavailable'})
        def do_GET(self):self.run(self.get)
        def get(self):
            url=urlsplit(self.path)
            if url.path=='/health':return self.send(200,{'ok':True,'service':'payments'})
            if url.path=='/checkout.js':return self.send(200,JS,'application/javascript; charset=utf-8')
            if url.path=='/checkout.css':return self.send(200,CSS,'text/css; charset=utf-8')
            if url.path=='/checkout/return':return self.send(200,RETURN_PAGE,'text/html; charset=utf-8')
            if url.path=='/alipay-redirect.js':return self.send(200,'document.getElementById("alipay-form").submit();','application/javascript; charset=utf-8')
            if url.path not in ('/checkout','/checkout/status','/checkout/qr','/checkout/alipay'):
                raise PaymentError('route_not_found',404)
            order=app.checkout(url.query)
            if url.path=='/checkout/alipay':
                if order.get('provider')!='alipay' or not app.alipay:raise PaymentError('payment_channel_unavailable',409)
                if order['state'] not in ('created','pending') or expired(order):return self.send(200,RETURN_PAGE,'text/html; charset=utf-8')
                if native_qr(order):return self.send(200,PAGE,'text/html; charset=utf-8')
                if order.get('code_url')!='alipay:page_pay':return self.send(200,RETURN_PAGE,'text/html; charset=utf-8')
                return self.send(200,app.alipay.page(order),'text/html; charset=utf-8',alipay_form=True)
            if url.path=='/checkout':return self.send(200,PAGE,'text/html; charset=utf-8')
            if url.path=='/checkout/status':return self.send(200,app.public(order))
            if not native_qr(order) or order['state']!='pending' or expired(order):
                raise PaymentError('qr_unavailable',409)
            qr=qrcode.make(order['code_url'],image_factory=qrcode.image.svg.SvgPathImage,box_size=8,border=4)
            output=io.BytesIO();qr.save(output)
            self.send(200,output.getvalue(),'image/svg+xml')
        def do_POST(self):self.run(self.post)
        def post(self):
            paths={x:'/v1/payments/'+x for x in ('catalog','create','status','cancel','reset')}
            is_alipay=self.path=='/v1/payments/alipay/notify'
            is_notice=self.path=='/v1/payments/wechat/notify' or is_alipay
            if not is_notice:
                if self.path not in paths.values():raise PaymentError('route_not_found',404)
                if len(self.headers.get_all('Authorization',[]))!=1 or not hmac.compare_digest(
                    self.headers.get('Authorization',''),'Bearer '+app.config['game_token']):
                    raise PaymentError('unauthorized',401)
            if self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length',[]))!=1:
                raise PaymentError('body_length_invalid')
            try:length=int(self.headers['Content-Length'])
            except ValueError:raise PaymentError('body_length_invalid') from None
            if not 0<length<=65536:raise PaymentError('body_size_invalid',413)
            raw=self.rfile.read(length)
            if len(raw)!=length:raise PaymentError('body_incomplete')
            if is_notice:
                if is_alipay:
                    if self.headers.get_content_type()!='application/x-www-form-urlencoded':raise PaymentError('content_type_invalid')
                    app.alipay_notice(raw)
                    return self.send(200,'success','text/plain; charset=utf-8')
                app.success(app.wechat.notice(self.headers,raw))
                return self.send(204,b'')
            self.send(200,app.game(self.path.rsplit('/',1)[-1],decode_json(raw)))
    return Handler


class Server(ThreadingHTTPServer):
    daemon_threads=True
    request_queue_size=16
    def __init__(self,app):
        self.slots=threading.BoundedSemaphore(12)
        super().__init__(('127.0.0.1',8766),handler(app))
    def process_request(self,request,address):
        if not self.slots.acquire(False):
            self.shutdown_request(request);return
        try:super().process_request(request,address)
        except Exception:self.slots.release();raise
    def process_request_thread(self,request,address):
        try:super().process_request_thread(request,address)
        finally:self.slots.release()
    def handle_error(self,*args):LOG.error('http_connection_failed')


def main():
    logging.basicConfig(level=logging.INFO,format='[Payments] %(message)s')
    config=json.loads(Path('/etc/goufayu-payment/config.json').read_text())
    if len(config['checkout_key'])<32 or len(config['game_token'])<24 or len(config['pepper'])<24:
        raise RuntimeError('payment_configuration_invalid')
    alipay=Alipay('/etc/goufayu-payment/alipay',config['alipay_seller_id']) if config.get('alipay_enabled') is True else None
    app=Payments(config,Database(config['dsn']),WeChat('/etc/goufayu-payment/wechat'),alipay)
    app.db.call('pending')
    threading.Thread(target=app.worker,daemon=True).start()
    Server(app).serve_forever()


if __name__=='__main__':main()
