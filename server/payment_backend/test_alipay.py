"""Protocol, ownership and HTTP callback regression tests using generated keys."""
import base64
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import http.client
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import Mock, MagicMock, patch
from urllib.parse import urlencode, parse_qs
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from .alipay import Alipay, APPID, canonical
from .service import Payments, handler
from .wechat import PaymentError
from .test_payments import FakeDB

PID='2088000000000001'
ID='AL'+'b'*30
def order():
    return dict(order_id=ID,account_id=hmac.new(b'p'*32,b'123',hashlib.sha256).hexdigest(),sku='ticket_test',
        amount=5000,currency='CNY',provider='alipay',appid=APPID,mchid=PID,state='pending',
        code_url='alipay:page_pay',reward={'title':'礼包 <测试> & "一"'},
        expires_at=(datetime.now(timezone.utc)+timedelta(minutes=30)).isoformat())
def paid():
    return dict(out_trade_no=ID,app_id=APPID,seller_id=PID,total_amount='50.00',
        trade_no='2026093000000000000001234567',trade_status='TRADE_SUCCESS',buyer_pay_amount='49.00')

class AlipayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory=tempfile.TemporaryDirectory()
        cls.merchant=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        cls.platform=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        root=Path(cls.directory.name)
        (root/'应用私钥RSA2048-敏感数据，请妥善保管.txt').write_bytes(base64.b64encode(cls.merchant.private_bytes(
            serialization.Encoding.DER,serialization.PrivateFormat.PKCS8,serialization.NoEncryption())))
        (root/'支付宝公钥RSA2.txt').write_bytes(base64.b64encode(cls.platform.public_key().public_bytes(
            serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo)))
        cls.ali=Alipay(root,PID)
    @classmethod
    def tearDownClass(cls):cls.directory.cleanup()
    def signature(self,raw):return base64.b64encode(self.platform.sign(raw,padding.PKCS1v15(),hashes.SHA256())).decode()
    def notice(self,params=None):
        params=dict(params or paid(),sign_type='RSA2',charset='utf-8',subject='礼包 & + 中文')
        params['sign']=self.signature(canonical(params,True))
        return urlencode(params).encode()
    def response(self,value,method='alipay.trade.query'):
        # Preserve whitespace and escaped non-ASCII characters inside the signed object.
        raw=json.dumps(value,ensure_ascii=True,indent=2).encode()
        return b'{'+json.dumps(method.replace('.','_')+'_response').encode()+b': '+raw+b',"sign":'+json.dumps(self.signature(raw)).encode()+b'}'
    def setUp(self):
        self.db=FakeDB();self.db.row=order()
        self.app=Payments(dict(allowed_accounts=['123'],pepper='p'*32,checkout_key='c'*32,game_token='g'*32),self.db,Mock(),self.ali)
    def test_page_signed_identity_fixed_expiry_and_escaping(self):
        original=order();params=self.ali.page_params(original)
        self.merchant.public_key().verify(base64.b64decode(params['sign']),canonical(params),padding.PKCS1v15(),hashes.SHA256())
        business=json.loads(params['biz_content'])
        self.assertEqual(business['total_amount'],'50.00');self.assertEqual(business['seller_id'],PID)
        self.assertEqual(business['product_code'],'FAST_INSTANT_TRADE_PAY')
        self.assertEqual(business['time_expire'],json.loads(self.ali.page_params(original)['biz_content'])['time_expire'])
        self.assertIn('&lt;测试&gt;',self.ali.page(original));self.assertNotIn('<测试>',self.ali.page(original))
        self.assertNotIn('PRIVATE KEY',self.ali.page(original))
        self.assertIn('action="https://openapi.alipay.com/gateway.do?charset=utf-8"',self.ali.page(original))
        self.assertIn('accept-charset="UTF-8"',self.ali.page(original))
    def test_response_signs_exact_bytes_including_business_errors(self):
        value=dict(paid(),code='10000',msg='成功')
        raw=self.response(value)
        self.assertEqual(self.ali.verified_response('alipay.trade.query',raw),value)
        with self.assertRaises(PaymentError):self.ali.verified_response('alipay.trade.query',raw.replace(b'50.00',b'0.01'))
        with self.assertRaises(PaymentError) as error:
            self.ali.verified_response('alipay.trade.query',self.response({'code':'40004','sub_code':'ACQ.TRADE_NOT_EXIST'}))
        self.assertEqual(error.exception.code,'ACQ.TRADE_NOT_EXIST')
        with self.assertRaises(PaymentError):self.ali.verified_response('alipay.trade.query',b'{"alipay_trade_query_response":{"code":"40004","sub_code":"ACQ.TRADE_NOT_EXIST"}}')
        with self.assertRaises(PaymentError):self.ali.verified_response('alipay.trade.query',raw[:-1]+b',"sign":"fake"}')
    def test_precreate_signed_qr_price_identity_expiry_and_notify(self):
        code='https://qr.alipay.com/bax1234567890'
        response=MagicMock();response.__enter__.return_value=response
        response.read.return_value=self.response(dict(code='10000',out_trade_no=ID,qr_code=code),'alipay.trade.precreate')
        with patch.object(self.ali,'opener') as opener:
            opener.open.return_value=response
            self.assertEqual(self.ali.precreate(order()),code)
            request=opener.open.call_args.args[0]
        params={k:v[0] for k,v in parse_qs(request.data.decode()).items()}
        self.merchant.public_key().verify(base64.b64decode(params['sign']),canonical(params),padding.PKCS1v15(),hashes.SHA256())
        self.assertEqual(params['method'],'alipay.trade.precreate')
        self.assertEqual(params['notify_url'],'https://pay.xiaofengnet.com/v1/payments/alipay/notify')
        business=json.loads(params['biz_content'])
        self.assertEqual(business['out_trade_no'],ID);self.assertEqual(business['seller_id'],PID)
        self.assertEqual(business['total_amount'],'50.00');self.assertIn('time_expire',business)
        self.assertNotIn('return_url',params);self.assertNotIn('product_code',business)
    def test_precreate_rejects_untrusted_qr_and_preserves_permission_error(self):
        base=dict(code='10000',out_trade_no=ID,qr_code='https://qr.alipay.com/abc123')
        for change in ({'out_trade_no':'another'}, {'qr_code':'https://qr.alipay.com.evil.example/abc'},
                       {'qr_code':'https://evil.example/abc'}, {'qr_code':'https://qr.alipay.com/abc?next=bad'},
                       {'qr_code':'alipay:page_pay'}, {'qr_code':None}):
            with self.subTest(change=change),patch.object(self.ali,'request',return_value=dict(base,**change)),self.assertRaises(PaymentError):
                self.ali.precreate(order())
        raw=self.response({'code':'40004','sub_code':'ACQ.ACCESS_FORBIDDEN'},'alipay.trade.precreate')
        with self.assertRaises(PaymentError) as error:self.ali.verified_response('alipay.trade.precreate',raw)
        self.assertEqual(error.exception.code,'ACQ.ACCESS_FORBIDDEN')
        with self.assertRaises(PaymentError):self.ali.verified_response('alipay.trade.precreate',raw.replace(b'40004',b'10000'))
    def test_native_creation_retries_same_order_and_keeps_legacy_pending_order(self):
        self.app.alipay_mode='precreate'
        gateway=Mock(wraps=self.ali);gateway.app_id=APPID;gateway.seller_id=PID;self.app.alipay=gateway
        gateway.query.side_effect=PaymentError('ACQ.TRADE_NOT_EXIST',502)
        gateway.precreate.side_effect=[PaymentError('alipay_gateway_unavailable',503),'https://qr.alipay.com/testqr123']
        self.db.row.update(state='created',code_url=None)
        body=dict(account_id='123',match_session_id='test_session',sku='ticket_test',provider='alipay')
        with self.assertRaises(PaymentError):self.app.game('create',body)
        public=self.app.game('create',body)
        self.assertEqual(public['checkout_mode'],'qr');self.assertIn('qr_matrix',public)
        self.assertEqual([x.args[0]['order_id'] for x in gateway.precreate.call_args_list],[ID,ID])
        self.assertEqual(self.app.game('create',body)['order_id'],ID)
        self.assertEqual(gateway.precreate.call_count,2);self.assertEqual(self.db.deliveries,0)
        matrix=public['qr_matrix'].split('|');self.assertTrue(29<=len(matrix)<=65)
        self.assertTrue(all(len(row)==len(matrix) for row in matrix))
        self.assertTrue(all(set(row)=={'0'} for row in matrix[:4]+matrix[-4:]))
        self.db.row=order()
        legacy=self.app.game('create',body)
        self.assertEqual(legacy['checkout_mode'],'page_pay');self.assertNotIn('qr_matrix',legacy)
        self.assertEqual(gateway.precreate.call_count,2)
        self.db.row.update(code_url='https://qr.alipay.com/testqr123',state='delivered')
        self.assertNotIn('qr_matrix',self.app.public(self.db.row))
        self.db.row.update(state='pending',expires_at=(datetime.now(timezone.utc)-timedelta(seconds=1)).isoformat())
        self.assertNotIn('qr_matrix',self.app.public(self.db.row))
    def test_native_permission_failure_never_falls_back_to_web_checkout(self):
        self.app.alipay_mode='precreate'
        gateway=Mock(wraps=self.ali);gateway.app_id=APPID;gateway.seller_id=PID;self.app.alipay=gateway
        gateway.query.side_effect=PaymentError('ACQ.TRADE_NOT_EXIST',502)
        gateway.precreate.side_effect=PaymentError('ACQ.ACCESS_FORBIDDEN',502)
        self.db.row.update(state='created',code_url=None)
        with self.assertRaises(PaymentError) as error:
            self.app.game('create',dict(account_id='123',match_session_id='test_session',sku='ticket_test',provider='alipay'))
        self.assertEqual(error.exception.code,'ACQ.ACCESS_FORBIDDEN')
        self.assertIsNone(self.db.row['code_url']);self.assertEqual(self.db.row['state'],'created')
        gateway.page.assert_not_called();self.assertEqual(self.db.deliveries,0)
    def test_notice_identity_amount_and_repeated_delivery(self):
        raw=self.notice();self.app.alipay_notice(raw);self.app.alipay_notice(raw)
        self.assertEqual(self.db.deliveries,1)
        for key,value in [('seller_id','2088000000000002'),('app_id','other'),('total_amount','0.10'),('out_trade_no','AL'+'c'*30)]:
            params=paid();params[key]=value
            with self.subTest(key=key),self.assertRaises(PaymentError):self.app.alipay_notice(self.notice(params))
        self.assertEqual(self.db.deliveries,1)
    def test_forged_ambiguous_notice_and_unpaid_do_not_grant(self):
        raw=self.notice()
        for body in (raw.replace(b'50.00',b'0.01'),raw+b'&seller_id='+PID.encode(),b'sign_type=RSA2&sign=invalid'):
            with self.assertRaises(PaymentError):self.app.alipay_notice(body)
        params=paid();params['trade_status']='WAIT_BUYER_PAY';self.app.alipay_notice(self.notice(params))
        self.assertEqual(self.db.deliveries,0)
        self.db.row['provider']='wechat'
        with self.assertRaises(PaymentError):self.app.alipay_notice(raw)
    def test_query_recovery_close_failure_and_owner(self):
        gateway=Mock(wraps=self.ali);gateway.app_id=APPID;gateway.seller_id=PID;self.app.alipay=gateway
        gateway.query.return_value=paid()
        self.assertEqual(self.app.reconcile(self.db.row)['state'],'delivered');self.assertEqual(self.db.deliveries,1)
        self.db.row=order();gateway.query.side_effect=PaymentError('alipay_signature_invalid',401)
        with self.assertRaises(PaymentError):self.app.close_order(self.db.row)
        self.assertEqual(self.db.row['state'],'pending');gateway.close.assert_not_called()
        gateway.query.side_effect=PaymentError('ACQ.TRADE_NOT_EXIST',502)
        gateway.close.side_effect=PaymentError('ACQ.TRADE_NOT_EXIST',502)
        with self.assertRaises(PaymentError) as error:self.app.close_order(self.db.row)
        self.assertEqual(error.exception.code,'payment_close_pending')
        self.db.row['expires_at']=(datetime.now(timezone.utc)-timedelta(seconds=1)).isoformat()
        self.assertEqual(self.app.close_order(self.db.row)['state'],'closed')
        self.db.row=order();self.db.row['account_id']='other'
        with self.assertRaises(PaymentError):self.app.game('cancel',dict(account_id='123',match_session_id='test_session',order_id=ID))
    def test_public_alipay_no_qr_and_no_browser_delivery(self):
        public=self.app.public(self.db.row)
        self.assertEqual(public['provider'],'alipay');self.assertNotIn('qr_matrix',public)
        self.assertIn('/checkout/alipay?',public['checkout_url'])
        self.app.checkout(public['checkout_url'].split('?',1)[1]);self.assertEqual(self.db.deliveries,0)
        for value in ('1e2','NaN','50.001',50,True):
            params=paid();params['total_amount']=value
            with self.assertRaises(PaymentError):self.ali.validate(params,self.db.row)
    def test_http_callback_ack_and_form_csp(self):
        server=ThreadingHTTPServer(('127.0.0.1',0),handler(self.app))
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        def request(method,path,body=None,headers=None):
            client=http.client.HTTPConnection(*server.server_address,timeout=3)
            client.request(method,path,body,headers or {});response=client.getresponse()
            result=response.status,dict(response.getheaders()),response.read();client.close();return result
        try:
            url='/checkout/alipay?order='+ID+'&token='+self.app.token(ID)
            status,headers,body=request('GET',url)
            self.assertEqual(status,200);self.assertIn('form-action https://openapi.alipay.com',headers['Content-Security-Policy'])
            self.assertIn('https://excashier.alipay.com',headers['Content-Security-Policy'])
            self.assertIn('https://unitradeprod.alipay.com',headers['Content-Security-Policy'])
            self.assertNotIn(b'PRIVATE KEY',body)
            self.assertEqual(request('GET','/checkout/qr?order='+ID+'&token='+self.app.token(ID))[0],409)
            self.db.row['code_url']='https://qr.alipay.com/native123'
            status,headers,body=request('GET',url)
            self.assertEqual(status,200);self.assertNotIn(b'alipay-form',body)
            self.assertIn("form-action 'none'",headers['Content-Security-Policy'])
            result=request('GET','/checkout/qr?order='+ID+'&token='+self.app.token(ID))
            self.assertEqual(result[0],200);self.assertIn(b'<svg',result[2])
            self.assertEqual(request('GET','/checkout/qr?order='+ID+'&token=invalid')[0],404)
            self.db.row.update(state='created',code_url=None)
            self.assertNotIn(b'alipay-form',request('GET',url)[2])
            self.db.row.update(state='pending',code_url='https://qr.alipay.com/native123')
            self.assertEqual(request('GET','/checkout/return?trade_status=TRADE_SUCCESS')[0],200)
            self.assertEqual(self.db.deliveries,0)
            self.assertEqual(request('POST','/v1/payments/alipay/notify',b'sign=x',{'Content-Type':'application/x-www-form-urlencoded'})[0],400)
            result=request('POST','/v1/payments/alipay/notify',self.notice(),{'Content-Type':'application/x-www-form-urlencoded'})
            self.assertEqual((result[0],result[2]),(200,b'success'));self.assertEqual(self.db.deliveries,1)
            self.assertEqual(request('POST','/v1/payments/cancel',b'{}')[0],401)
        finally:server.shutdown();server.server_close();thread.join()

if __name__=='__main__':unittest.main()
