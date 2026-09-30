"""Alipay production page-pay, RSA2 notices and signed query/close responses.

Protocol references: official alipay/alipay-sdk-python-all and
https://developer.alibaba.com/docs/doc.htm?articleId=105902&docType=1&treeId=193
No credentials, signed forms, request bodies or buyer details are logged.
"""
import base64
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import html
import json
from pathlib import Path
import re
import urllib.error
import urllib.request
from urllib.parse import parse_qs, urlencode

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from .wechat import PaymentError, NoRedirect, ORIGIN, decode_json

APPID = '2021007102660118'
GATEWAY = 'https://openapi.alipay.com/gateway.do'
CHINA = timezone(timedelta(hours=8))


def key_bytes(path, private=False):
    raw = Path(path).read_text(encoding='utf-8-sig').strip().encode('ascii')
    if raw.startswith(b'-----BEGIN '):
        return serialization.load_pem_private_key(raw, None) if private else serialization.load_pem_public_key(raw)
    der = base64.b64decode(b''.join(raw.split()), validate=True)
    return serialization.load_der_private_key(der, None) if private else serialization.load_der_public_key(der)


def canonical(params, notice=False):
    excluded = {'sign', 'sign_type'} if notice else {'sign'}
    return '&'.join(k + '=' + v for k, v in sorted(params.items()) if k not in excluded and v != '').encode('utf-8')


def amount_fen(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]{1,10}(?:\.[0-9]{1,2})?', value):
        raise PaymentError('payment_mismatch')
    return int(Decimal(value) * 100)


def response_content(raw, key):
    """Return the exact top-level JSON value bytes, never reserialize signatures."""
    text = raw.decode('utf-8')
    decoder = json.JSONDecoder()
    pos = text.index('{') + 1
    while True:
        while text[pos].isspace(): pos += 1
        name, pos = decoder.raw_decode(text, pos)
        while text[pos].isspace(): pos += 1
        if text[pos] != ':': raise ValueError('response_colon')
        pos += 1
        while text[pos].isspace(): pos += 1
        start = pos
        _, pos = decoder.raw_decode(text, pos)
        if name == key: return text[start:pos].encode('utf-8')
        while text[pos].isspace(): pos += 1
        if text[pos] != ',': raise ValueError('response_key_missing')
        pos += 1


class Alipay:
    def __init__(self, directory, seller_id=None):
        directory = Path(directory)
        self.app_id, self.seller_id = APPID, seller_id
        if seller_id is not None and not re.fullmatch(r'2088[0-9]{12}', seller_id):
            raise PaymentError('alipay_seller_invalid', 503)
        self.private = key_bytes(directory/'应用私钥RSA2048-敏感数据，请妥善保管.txt', True)
        self.public = key_bytes(directory/'支付宝公钥RSA2.txt')
        if not isinstance(self.private, rsa.RSAPrivateKey) or self.private.key_size != 2048 or not isinstance(self.public, rsa.RSAPublicKey) or self.public.key_size != 2048:
            raise PaymentError('alipay_key_invalid', 503)
        self.opener = urllib.request.build_opener(NoRedirect())

    def params(self, method, business, **extra):
        params = dict(app_id=self.app_id, method=method, format='JSON', charset='utf-8', sign_type='RSA2',
                      timestamp=datetime.now(CHINA).strftime('%Y-%m-%d %H:%M:%S'), version='1.0',
                      biz_content=json.dumps(business, ensure_ascii=False, separators=(',', ':')), **extra)
        params['sign'] = base64.b64encode(self.private.sign(canonical(params), padding.PKCS1v15(), hashes.SHA256())).decode()
        return params

    def verify(self, content, signature):
        try:
            self.public.verify(base64.b64decode(signature, validate=True), content, padding.PKCS1v15(), hashes.SHA256())
        except Exception:
            raise PaymentError('alipay_signature_invalid', 401) from None

    def verified_response(self, method, raw):
        value = decode_json(raw)
        key = method.replace('.', '_') + '_response'
        if key not in value: key = 'error_response'
        if not isinstance(value.get(key), dict) or not isinstance(value.get('sign'), str):
            raise PaymentError('alipay_signature_invalid', 502)
        try: content = response_content(raw, key)
        except (ValueError, IndexError, UnicodeError): raise PaymentError('alipay_response_invalid', 502) from None
        self.verify(content, value['sign'])
        result = value[key]
        if result.get('code') != '10000':
            code = result.get('sub_code', 'alipay_gateway_error')
            if not isinstance(code, str) or not re.fullmatch(r'[A-Za-z0-9_.-]{1,100}', code): code = 'alipay_gateway_error'
            raise PaymentError(code, 502)
        return result

    def request(self, method, business):
        req = urllib.request.Request(GATEWAY, data=urlencode(self.params(method, business)).encode(),
            headers={'Content-Type':'application/x-www-form-urlencoded; charset=utf-8', 'Accept':'application/json'})
        try:
            with self.opener.open(req, timeout=8) as response:
                raw = response.read(65537)
                if len(raw) > 65536: raise PaymentError('gateway_response_too_large', 502)
                return self.verified_response(method, raw)
        except (urllib.error.URLError, OSError, TimeoutError):
            raise PaymentError('alipay_gateway_unavailable', 503) from None

    def query(self, order_id): return self.request('alipay.trade.query', {'out_trade_no':order_id})
    def close(self, order_id):
        result = self.request('alipay.trade.close', {'out_trade_no':order_id})
        if result.get('out_trade_no') != order_id: raise PaymentError('payment_mismatch')
        return result

    def page_params(self, order):
        if not self.seller_id or order.get('provider') != 'alipay' or order['appid'] != self.app_id or order['mchid'] != self.seller_id:
            raise PaymentError('payment_mismatch')
        return self.params('alipay.trade.page.pay', dict(out_trade_no=order['order_id'], seller_id=self.seller_id,
            total_amount=f"{order['amount']//100}.{order['amount']%100:02d}", subject=order['reward']['title'],
            product_code='FAST_INSTANT_TRADE_PAY', qr_pay_mode='4', qrcode_width=256,
            time_expire=datetime.fromisoformat(order['expires_at']).astimezone(CHINA).strftime('%Y-%m-%d %H:%M:%S')),
            notify_url=ORIGIN+'/v1/payments/alipay/notify', return_url=ORIGIN+'/checkout/return')

    def page(self, order):
        fields = ''.join('<input type="hidden" name="'+html.escape(k, quote=True)+'" value="'+html.escape(v, quote=True)+'">' for k,v in self.page_params(order).items())
        return ('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>支付宝收银台</title>'
            '<link rel="stylesheet" href="/checkout.css"><main><h1>正在打开支付宝</h1><p>请在支付宝页面核对商品和金额后付款。</p>'
            # HTML form POSTs omit charset in Content-Type. Alipay requires the
            # decoding charset in the URL before it can verify Chinese fields.
            '<form id="alipay-form" method="post" accept-charset="UTF-8" action="'+GATEWAY+'?charset=utf-8">'+fields+
            '<button type="submit">继续到支付宝</button></form></main><script src="/alipay-redirect.js"></script></html>')

    def notice(self, raw):
        try:
            params = parse_qs(raw.decode('utf-8'), keep_blank_values=True, strict_parsing=True, encoding='utf-8', errors='strict', max_num_fields=100)
            if any(len(v) != 1 for v in params.values()): raise ValueError()
            params = {k:v[0] for k,v in params.items()}
            if params.get('sign_type') != 'RSA2' or params.get('charset', 'utf-8').lower() != 'utf-8': raise ValueError()
        except (ValueError, UnicodeError): raise PaymentError('alipay_notice_invalid') from None
        self.verify(canonical(params, True), params.get('sign', ''))
        if params.get('app_id') != self.app_id or params.get('seller_id') != self.seller_id:
            raise PaymentError('payment_mismatch')
        return params

    def validate(self, value, order, notice=False):
        if order.get('provider') != 'alipay' or order['appid'] != self.app_id or order['mchid'] != self.seller_id:
            raise PaymentError('payment_mismatch')
        if value.get('out_trade_no') != order['order_id'] or amount_fen(value.get('total_amount')) != order['amount'] or order['currency'] != 'CNY':
            raise PaymentError('payment_mismatch')
        for key, expected in (('app_id', self.app_id), ('seller_id', self.seller_id)):
            if (notice or key in value) and value.get(key) != expected: raise PaymentError('payment_mismatch')
        if not isinstance(value.get('trade_no'),str) or not re.fullmatch(r'[0-9]{20,64}', value['trade_no']): raise PaymentError('payment_mismatch')
        return value['trade_no']
