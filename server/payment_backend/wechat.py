"""WeChat APIv3 RSA-SHA256 requests, verified responses and AEAD notices.

Reference: https://pay.weixin.qq.com/doc/v3/merchant/4012791877
Keys are read from protected server files; this module never logs payloads.
"""
import base64
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import secrets
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

APPID = 'wx164e25a570fb636a'
MCHID = '1117928493'
PUBLIC_ID = 'PUB_KEY_ID_0111179284932026092700191743000600'
SERIAL = '65884C7F0CD3A17924257A1EFEC6BC786E8FC9E5'
ORIGIN = 'https://pay.xiaofengnet.com'
SKU = 'monkey_test_010_v1'
TITLE = '齐天大圣存档奖励 ×1（测试商品）'


class PaymentError(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status
        super().__init__(code)


def decode_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate_key')
            result[key] = value
        return result
    def constant(value):
        raise ValueError('nonfinite_number')
    try:
        result = json.loads(raw, object_pairs_hook=pairs, parse_constant=constant)
        if not isinstance(result, dict):
            raise ValueError()
        return result
    except (ValueError, UnicodeError, RecursionError):
        raise PaymentError('invalid_json') from None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise PaymentError('gateway_redirect_rejected', 502)


class WeChat:
    def __init__(self, directory):
        directory = Path(directory)
        self.private = serialization.load_pem_private_key((directory/'apiclient_key.pem').read_bytes(), None)
        self.public = serialization.load_pem_public_key((directory/'pub_key.pem').read_bytes())
        self.api_key = (directory/'api_v3_key.txt').read_text(encoding='utf-8-sig').strip().encode('ascii')
        if (len(self.api_key) != 32 or not isinstance(self.private, rsa.RSAPrivateKey)
                or not isinstance(self.public, rsa.RSAPublicKey) or self.private.key_size != 2048):
            raise PaymentError('key_configuration_invalid', 503)
        self.opener = urllib.request.build_opener(NoRedirect())

    def verify(self, headers, raw):
        try:
            names = ('Wechatpay-Timestamp', 'Wechatpay-Nonce', 'Wechatpay-Signature', 'Wechatpay-Serial')
            values = []
            for name in names:
                if hasattr(headers, 'get_all') and len(headers.get_all(name, [])) != 1:
                    raise ValueError()
                values.append(headers.get(name))
            stamp, nonce, signature, serial = values
            if (serial != PUBLIC_ID or not re.fullmatch(r'[0-9]{10,12}', stamp or '')
                    or abs(time.time()-int(stamp)) > 300 or not nonce or len(nonce)>128):
                raise ValueError()
            content = (stamp+'\n'+nonce+'\n').encode()+raw+b'\n'
            self.public.verify(base64.b64decode(signature, validate=True), content, padding.PKCS1v15(), hashes.SHA256())
        except Exception:
            raise PaymentError('wechat_signature_invalid', 401) from None

    def request(self, method, path, payload=None):
        raw = b'' if payload is None else json.dumps(payload, ensure_ascii=False, separators=(',', ':')).encode()
        stamp, nonce = str(int(time.time())), secrets.token_hex(16)
        message = (method+'\n'+path+'\n'+stamp+'\n'+nonce+'\n').encode()+raw+b'\n'
        signature = base64.b64encode(self.private.sign(message,padding.PKCS1v15(),hashes.SHA256())).decode()
        auth = f'WECHATPAY2-SHA256-RSA2048 mchid="{MCHID}",nonce_str="{nonce}",timestamp="{stamp}",serial_no="{SERIAL}",signature="{signature}"'
        req = urllib.request.Request('https://api.mch.weixin.qq.com'+path, data=raw if method=='POST' else None,
            method=method, headers={'Authorization':auth,'Wechatpay-Serial':PUBLIC_ID,
            'Content-Type':'application/json','Accept':'application/json','User-Agent':'SurvivalPayments/1'})
        try:
            try:
                response = self.opener.open(req, timeout=8)
            except urllib.error.HTTPError as exc:
                response = exc
            with response:
                data = response.read(65537)
                if len(data)>65536:
                    raise PaymentError('gateway_response_too_large',502)
                self.verify(response.headers, data)
                value = decode_json(data) if data else {}
                if not 200<=response.status<300:
                    code = value.get('code','gateway_error')
                    if not isinstance(code,str) or not re.fullmatch(r'[A-Z_]{1,60}',code):
                        code='gateway_error'
                    raise PaymentError(code,502)
                return value
        except (OSError, urllib.error.URLError, TimeoutError):
            raise PaymentError('gateway_unavailable',503) from None

    def create(self, order):
        result = self.request('POST','/v3/pay/transactions/native',{
            'appid':APPID,'mchid':MCHID,'description':TITLE,'out_trade_no':order['order_id'],
            'notify_url':ORIGIN+'/v1/payments/wechat/notify',
            'time_expire':datetime.fromisoformat(order['expires_at']).isoformat(timespec='seconds'),
            'amount':{'total':10,'currency':'CNY'}})
        code = result.get('code_url','')
        if not isinstance(code,str) or not code.startswith('weixin://wxpay/bizpayurl?') or len(code)>2048:
            raise PaymentError('wechat_code_invalid',502)
        return code

    def query(self, order_id):
        return self.request('GET','/v3/pay/transactions/out-trade-no/'+order_id+'?mchid='+MCHID)

    def close(self, order_id):
        self.request('POST','/v3/pay/transactions/out-trade-no/'+order_id+'/close',{'mchid':MCHID})

    def notice(self, headers, raw):
        self.verify(headers,raw)
        event = decode_json(raw)
        if event.get('event_type')!='TRANSACTION.SUCCESS' or event.get('resource_type')!='encrypt-resource':
            raise PaymentError('unsupported_notice')
        try:
            resource = event['resource']
            if resource.get('algorithm')!='AEAD_AES_256_GCM' or resource.get('original_type')!='transaction':
                raise ValueError()
            decrypted = AESGCM(self.api_key).decrypt(resource['nonce'].encode(),
                base64.b64decode(resource['ciphertext'],validate=True),resource.get('associated_data','').encode())
        except Exception:
            raise PaymentError('wechat_decryption_failed',400) from None
        return decode_json(decrypted)


def validate_success(value, order):
    amount = value.get('amount',{})
    if (value.get('appid')!=APPID or value.get('mchid')!=MCHID or value.get('out_trade_no')!=order['order_id']
            or value.get('trade_state')!='SUCCESS' or value.get('trade_type')!='NATIVE'
            or not isinstance(amount,dict) or type(amount.get('total')) is not int
            or amount['total']!=10 or amount.get('currency')!='CNY'
            or not re.fullmatch(r'[0-9]{20,64}',str(value.get('transaction_id','')))):
        raise PaymentError('payment_mismatch')
    return value['transaction_id']
