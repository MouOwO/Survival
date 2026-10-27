"""Synthetic ledgers/generated keys and real loopback HTTP; no gateway or DB IO."""
import base64
from contextlib import contextmanager, redirect_stderr
import hashlib
import hmac
import http.client
from http.server import ThreadingHTTPServer
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlencode, urlsplit

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from . import service
from .alipay import Alipay, canonical
from .endpoints import (DEFAULT_PUBLIC_BASE, WS4_PUBLIC_BASE, LEGACY_CONFIG, WS4_CONFIG,
                        PaymentEndpoints, key_directory, runtime_binding)
from .service import Database, Payments, Server, handler
from .test_alipay import order as alipay_order, paid as alipay_paid, PID
from .test_payments import FakeDB, order as wechat_order, paid as wechat_paid
from .wechat import PUBLIC_ID, PaymentError, WeChat


@contextmanager
def loopback(app):
    server = ThreadingHTTPServer(('127.0.0.1', 0), handler(app))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    def request(method, path, body=None, headers=None, *, strip_prefix=True):
        parsed = urlsplit(path)
        target = parsed.path + ('?' + parsed.query if parsed.query else '')
        # Emulate only the explicitly intended Nginx prefix stripping. The
        # actual HTTP handler and all responses below execute unchanged.
        prefix = app.endpoints.prefix
        if strip_prefix and prefix and target.startswith(prefix + '/'):
            target = target[len(prefix):]
        client = http.client.HTTPConnection(*server.server_address, timeout=3)
        try:
            client.request(method, target, body, headers or {})
            response = client.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            client.close()

    try:
        yield request
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class EndpointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='payment-endpoints-')
        cls.merchant = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.platform = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        private = cls.merchant.private_bytes(serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
        public = cls.platform.public_key().public_bytes(serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo)
        root = Path(cls.directory.name)
        wx, ali = root / 'wechat', root / 'alipay'
        wx.mkdir(); ali.mkdir()
        (wx / 'apiclient_key.pem').write_bytes(private)
        (wx / 'pub_key.pem').write_bytes(public)
        (wx / 'api_v3_key.txt').write_bytes(b'A' * 32)
        (ali / '应用私钥RSA2048-敏感数据，请妥善保管.txt').write_bytes(private)
        (ali / '支付宝公钥RSA2.txt').write_bytes(public)
        cls.old_wx, cls.ws4_wx = WeChat(wx), WeChat(wx, public_base=WS4_PUBLIC_BASE)
        cls.old_ali, cls.ws4_ali = Alipay(ali, PID), Alipay(ali, PID, public_base=WS4_PUBLIC_BASE)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def config(self, isolated=False):
        return dict(allowed_accounts=['123'], pepper='p' * 32, checkout_key='c' * 32,
            game_token=('w' if isolated else 'g') * 32,
            **({'public_base': WS4_PUBLIC_BASE} if isolated else {}))

    def app(self, isolated=False, *, alipay=False):
        db = FakeDB()
        if alipay:
            db.row = alipay_order()
        else:
            db.row.update(state='pending', code_url='weixin://wxpay/bizpayurl?fixture=1')
        app = Payments(self.config(isolated), db,
            self.ws4_wx if isolated else self.old_wx,
            (self.ws4_ali if isolated else self.old_ali) if alipay else None)
        return app, db

    def notice(self):
        params = dict(alipay_paid(), sign_type='RSA2', charset='utf-8')
        params['sign'] = base64.b64encode(self.platform.sign(
            canonical(params, True), padding.PKCS1v15(), hashes.SHA256())).decode()
        return urlencode(params).encode()

    def test_public_bases_are_exact_and_reject_before_reading_keys(self):
        self.assertEqual(PaymentEndpoints().public_base, DEFAULT_PUBLIC_BASE)
        self.assertEqual(PaymentEndpoints(WS4_PUBLIC_BASE).prefix, '/ws4-payments')
        for invalid in (None, True, '', 'http://pay.xiaofengnet.com', DEFAULT_PUBLIC_BASE + '/',
                        WS4_PUBLIC_BASE + '/', WS4_PUBLIC_BASE + '?x=1', DEFAULT_PUBLIC_BASE + '/other',
                        'https://pay.xiaofengnet.com.evil.example', 'https://user@pay.xiaofengnet.com',
                        'https://pay.xiaofengnet.com:443/ws4-payments'):
            with self.subTest(base=invalid), patch.object(Path, 'read_bytes', side_effect=AssertionError('key IO')):
                with self.assertRaises(ValueError): PaymentEndpoints(invalid)
                with self.assertRaises(ValueError): WeChat('not-read', public_base=invalid)
                with self.assertRaises(ValueError): Alipay('not-read', PID, public_base=invalid)
        with self.assertRaises(ValueError): PaymentEndpoints(WS4_PUBLIC_BASE).url('//evil.invalid')
        with self.assertRaises(ValueError): PaymentEndpoints().public_path('/v1/payments/refund')

    def test_fixed_runtime_pairing_and_old_defaults(self):
        args = service.arguments([])
        self.assertEqual((args.config, args.port), (LEGACY_CONFIG, 8766))
        args = service.arguments(['--config=' + WS4_CONFIG, '--port', '18769'])
        self.assertEqual((args.config, args.port), (WS4_CONFIG, 18769))
        self.assertFalse(runtime_binding(LEGACY_CONFIG, 8766, {}).isolated)
        self.assertTrue(runtime_binding(WS4_CONFIG, 18769, {'public_base': WS4_PUBLIC_BASE}).isolated)
        for config, port, values in ((WS4_CONFIG, 8766, {'public_base': WS4_PUBLIC_BASE}),
                (WS4_CONFIG, 18769, {}), (LEGACY_CONFIG, 18769, {}),
                (LEGACY_CONFIG, 8766, {'public_base': WS4_PUBLIC_BASE}),
                (WS4_CONFIG, 18769, {'public_base': WS4_PUBLIC_BASE, 'bind': '0.0.0.0'})):
            with self.subTest(config=config, port=port, values=values), self.assertRaises(ValueError):
                runtime_binding(config, port, values)
        for arguments in (['--port', '18769'], ['--config', WS4_CONFIG],
                          ['--config', '/tmp/payments.json'], ['--port', '80'], ['--bind', '0.0.0.0']):
            with self.subTest(arguments=arguments), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                service.arguments(arguments)

    def test_config_key_directories_are_fixed_server_roots(self):
        for provider in ('wechat', 'alipay'):
            self.assertEqual(key_directory({}, provider), '/etc/goufayu-payment/' + provider)
            path = '/etc/goufayu-ws4-payment/' + provider
            self.assertEqual(key_directory({provider + '_key_directory': path}, provider), path)
            for invalid in ('/tmp/' + provider, path + '/', path + '/../' + provider,
                            '/etc/goufayu-payment/' + ('wechat' if provider == 'alipay' else 'alipay'),
                            None, ['not-a-path']):
                with self.subTest(provider=provider, path=invalid), self.assertRaises(ValueError):
                    key_directory({provider + '_key_directory': invalid}, provider)

    def test_isolated_dsn_cannot_select_legacy_or_other_database(self):
        good = 'host=127.0.0.1 port=15432 dbname=goufayu_ws4 user=goufayu_payment password=synthetic'
        db = Database(good, isolated=True)
        self.assertIn('hostaddr=127.0.0.1', db.dsn)
        self.assertEqual(Database('unchanged legacy DSN').dsn, 'unchanged legacy DSN')
        for invalid in (good.replace('15432', '5432'), good.replace('goufayu_ws4', 'goufayu_test'),
                        good.replace('127.0.0.1', 'example.invalid'), good.replace('goufayu_payment', 'postgres'),
                        good + ' hostaddr=192.0.2.1', good + ' service=legacy', good + ' options=-crole=postgres'):
            with self.subTest(dsn_kind=invalid.split('password=')[0]), self.assertRaisesRegex(ValueError, 'payment_isolated_dsn_invalid'):
                Database(invalid, isolated=True)
        for wrong in (dict(dbname='goufayu_test'), dict(port=5432), dict(host='192.0.2.1'), dict(user='postgres')):
            conn = Mock()
            conn.info = SimpleNamespace(**dict(dict(user='goufayu_payment', dbname='goufayu_ws4',
                host='127.0.0.1', port=15432), **wrong))
            conn.__enter__ = Mock(return_value=conn)
            conn.__exit__ = Mock(return_value=False)
            with self.subTest(connection=wrong), patch.object(service.psycopg, 'connect', return_value=conn), self.assertRaises(PaymentError):
                db.call('pending')
            conn.execute.assert_not_called()

    def test_checkout_url_and_capabilities_are_separate_even_with_same_key_and_order(self):
        old, old_db = self.app()
        isolated, isolated_db = self.app(True)
        order = wechat_order()
        self.assertEqual(old.token(order['order_id']), hmac.new(b'c' * 32,
            ('checkout:' + order['order_id']).encode(), hashlib.sha256).hexdigest())
        self.assertNotEqual(old.token(order['order_id']), isolated.token(order['order_id']))
        for app, base in ((old, DEFAULT_PUBLIC_BASE), (isolated, WS4_PUBLIC_BASE)):
            result = app.public(order)
            self.assertEqual(result['checkout_url'].split('?')[0], base + '/checkout')
            app.checkout(result['checkout_url'].split('?')[1])
        with self.assertRaises(PaymentError): isolated.checkout(old.public(order)['checkout_url'].split('?')[1])
        with self.assertRaises(PaymentError): old.checkout(isolated.public(order)['checkout_url'].split('?')[1])
        self.assertEqual((old_db.deliveries, isolated_db.deliveries), (0, 0))
        with self.assertRaisesRegex(ValueError, 'namespace_mismatch'):
            Payments(self.config(True), FakeDB(), self.old_wx, self.ws4_ali)
        with self.assertRaisesRegex(ValueError, 'namespace_mismatch'):
            Payments(self.config(True), FakeDB(), self.ws4_wx, self.old_ali)

    def test_wechat_native_order_uses_its_instance_notify_only(self):
        for gateway, base in ((self.old_wx, DEFAULT_PUBLIC_BASE), (self.ws4_wx, WS4_PUBLIC_BASE)):
            with self.subTest(base=base), patch.object(gateway, 'request', return_value={
                    'code_url': 'weixin://wxpay/bizpayurl?synthetic=1'}) as request:
                gateway.create(wechat_order())
                method, path, payload = request.call_args.args
                self.assertEqual((method, path), ('POST', '/v3/pay/transactions/native'))
                self.assertEqual(payload['notify_url'], base + '/v1/payments/wechat/notify')
                self.assertEqual(payload['amount'], {'total': 5000, 'currency': 'CNY'})
        self.assertEqual(self.old_wx.endpoints.public_base, DEFAULT_PUBLIC_BASE)

    def test_alipay_precreate_and_signed_page_use_instance_callback_and_return(self):
        for gateway, base in ((self.old_ali, DEFAULT_PUBLIC_BASE), (self.ws4_ali, WS4_PUBLIC_BASE)):
            with self.subTest(base=base), patch.object(gateway, 'request', return_value={
                    'out_trade_no': alipay_order()['order_id'], 'qr_code': 'https://qr.alipay.com/synthetic'}) as request:
                gateway.precreate(alipay_order())
                self.assertEqual(request.call_args.kwargs, {'notify_url': base + '/v1/payments/alipay/notify'})
            params = gateway.page_params(alipay_order())
            self.merchant.public_key().verify(base64.b64decode(params['sign']), canonical(params),
                padding.PKCS1v15(), hashes.SHA256())
            self.assertEqual(params['notify_url'], base + '/v1/payments/alipay/notify')
            self.assertEqual(params['return_url'], base + '/checkout/return')
            self.assertEqual(json.loads(params['biz_content'])['total_amount'], '50.00')
            page = gateway.page(alipay_order())
            prefix = '/ws4-payments' if base == WS4_PUBLIC_BASE else ''
            self.assertIn('href="' + prefix + '/checkout.css"', page)
            self.assertIn('src="' + prefix + '/alipay-redirect.js"', page)
            self.assertIn('https://openapi.alipay.com/gateway.do?charset=utf-8', page)

    def test_real_http_checkout_assets_and_poll_urls_keep_public_prefix(self):
        for isolated in (False, True):
            app, db = self.app(isolated)
            prefix = app.endpoints.prefix
            with self.subTest(isolated=isolated), loopback(app) as request:
                status, headers, page = request('GET', app.public(db.row)['checkout_url'])
                self.assertEqual(status, 200)
                self.assertIn(('href="' + prefix + '/checkout.css"').encode(), page)
                self.assertIn(('src="' + prefix + '/checkout.js"').encode(), page)
                status, _, script = request('GET', prefix + '/checkout.js')
                self.assertEqual(status, 200)
                self.assertIn(('qr.src="' + prefix + '/checkout/qr"').encode(), script)
                self.assertIn(('fetch("' + prefix + '/checkout/status"').encode(), script)
                self.assertEqual(request('GET', prefix + '/checkout.css')[0], 200)
                self.assertIn(('href="' + prefix + '/checkout.css"').encode(), request('GET', prefix + '/checkout/return')[2])
                if isolated:
                    self.assertEqual(request('GET', prefix + '/checkout.js', strip_prefix=False)[0], 404,
                        'the loopback handler expects the reviewed reverse proxy to strip exactly one prefix')
                    self.assertNotIn(b'fetch("/checkout/status"', script)
                self.assertEqual(db.deliveries, 0)

    def test_real_http_alipay_checkout_redirect_and_native_qr_keep_prefix(self):
        app, db = self.app(True, alipay=True)
        url = app.public(db.row)['checkout_url']
        self.assertTrue(url.startswith(WS4_PUBLIC_BASE + '/checkout/alipay?'))
        with loopback(app) as request:
            status, headers, page = request('GET', url)
            self.assertEqual(status, 200)
            self.assertIn(b'src="/ws4-payments/alipay-redirect.js"', page)
            self.assertIn('form-action https://openapi.alipay.com', headers['Content-Security-Policy'])
            self.assertEqual(request('GET', '/ws4-payments/alipay-redirect.js')[2],
                b'document.getElementById("alipay-form").submit();')
            db.row['code_url'] = 'https://qr.alipay.com/synthetic'
            status, headers, page = request('GET', url)
            self.assertEqual(status, 200)
            self.assertIn(b'src="/ws4-payments/checkout.js"', page)
            self.assertIn("form-action 'none'", headers['Content-Security-Policy'])
            query = url.split('?')[1]
            self.assertIn(b'<svg', request('GET', '/ws4-payments/checkout/qr?' + query)[2])
            self.assertEqual(db.deliveries, 0)

    @unittest.skipUnless(shutil.which('node'), 'Node is needed to execute hosted checkout JavaScript')
    def test_hosted_javascript_executes_prefixed_qr_and_status_requests(self):
        runner = r'''const fs=require("node:fs"),vm=require("node:vm");
const i=JSON.parse(fs.readFileSync(0,"utf8")),nodes={},urls=[];
function element(id){return nodes[id]||(nodes[id]={style:{}});}
vm.runInNewContext(i.script,{location:{search:i.query},document:{getElementById:element},
setInterval:()=>0,fetch:url=>{urls.push(url);return Promise.resolve({ok:true,json:()=>Promise.resolve(i.response)});}});
setImmediate(()=>process.stdout.write(JSON.stringify({qr:element("qr").src,urls})));'''
        for isolated in (False, True):
            app, db = self.app(isolated)
            prefix, query = app.endpoints.prefix, '?order=synthetic&token=fixture'
            with loopback(app) as request:
                script = request('GET', prefix + '/checkout.js')[2].decode()
            result = subprocess.run([shutil.which('node'), '-e', runner],
                input=json.dumps(dict(script=script, query=query, response=app.public(db.row))),
                text=True, encoding='utf-8', capture_output=True, timeout=5, check=True)
            values = json.loads(result.stdout)
            self.assertEqual(values['qr'], prefix + '/checkout/qr' + query)
            self.assertEqual(values['urls'], [prefix + '/checkout/status' + query])
            self.assertEqual(db.deliveries, 0)

    def test_ws4_signed_notify_updates_only_its_synthetic_ledger_and_replay_is_idempotent(self):
        old, old_db = self.app(alipay=True)
        isolated, isolated_db = self.app(True, alipay=True)
        with loopback(old) as old_request, loopback(isolated) as request:
            path = '/ws4-payments/v1/payments/alipay/notify'
            notice = self.notice()
            headers = {'Content-Type': 'application/x-www-form-urlencoded'}
            self.assertEqual(request('POST', path, notice, headers)[0], 200)
            self.assertEqual(request('POST', path, notice, headers)[0], 200)
            self.assertEqual((old_db.deliveries, isolated_db.deliveries), (0, 1))
            self.assertEqual(old_request('POST', path, notice, headers, strip_prefix=False)[0], 404)
            self.assertEqual((old_db.deliveries, isolated_db.deliveries), (0, 1))
            self.assertEqual(request('POST', path, notice.replace(b'50.00', b'0.01'), headers)[0], 401)

    def test_ws4_wechat_callback_keeps_signature_decryption_and_amount_validation(self):
        app, db = self.app(True)
        paid = wechat_paid()
        nonce = b'123456789012'
        cipher = AESGCM(b'A' * 32).encrypt(nonce, json.dumps(paid).encode(), b'transaction')
        raw = json.dumps(dict(event_type='TRANSACTION.SUCCESS', resource_type='encrypt-resource', resource=dict(
            algorithm='AEAD_AES_256_GCM', original_type='transaction', nonce=nonce.decode(),
            associated_data='transaction', ciphertext=base64.b64encode(cipher).decode()))).encode()
        stamp = str(int(time.time()))
        signature = base64.b64encode(self.platform.sign((stamp + '\nsynthetic_nonce\n').encode() + raw + b'\n',
            padding.PKCS1v15(), hashes.SHA256())).decode()
        headers = {'Content-Type': 'application/json', 'Wechatpay-Timestamp': stamp,
            'Wechatpay-Nonce': 'synthetic_nonce', 'Wechatpay-Serial': PUBLIC_ID, 'Wechatpay-Signature': signature}
        with loopback(app) as request:
            path = '/ws4-payments/v1/payments/wechat/notify'
            self.assertEqual(request('POST', path, raw, headers)[0], 204)
            self.assertEqual(request('POST', path, raw, headers)[0], 204)
            self.assertEqual(db.deliveries, 1)
            self.assertEqual(request('POST', path, raw + b' ', headers)[0], 401)

    def test_ws4_never_exposes_reset_refund_or_legacy_bearer(self):
        app, db = self.app(True)
        app.config['test_reset_enabled'] = True
        with loopback(app) as request:
            body = json.dumps(dict(account_id='123', match_session_id='synthetic_session')).encode()
            headers = {'Authorization': 'Bearer ' + app.config['game_token'], 'Content-Type': 'application/json'}
            for action in ('reset', 'refund'):
                self.assertEqual(request('POST', '/ws4-payments/v1/payments/' + action, body, headers)[0], 404)
            wrong = dict(headers, Authorization='Bearer ' + 'g' * 32)
            self.assertEqual(request('POST', '/ws4-payments/v1/payments/catalog', body, wrong)[0], 401)
            self.assertEqual(request('POST', '/ws4-payments/v1/payments/catalog', body, headers)[0], 200)
        with self.assertRaises(PaymentError):
            app.game('reset', dict(account_id='123', match_session_id='synthetic_session',
                kind='refreshmoney', request_id='synthetic_reset'))
        self.assertEqual((db.resets, db.deliveries), (0, 0))

    def test_server_port_binds_loopback_and_cannot_cross_instances(self):
        for isolated, port in ((False, 8766), (True, 18769)):
            app, _ = self.app(isolated)
            with patch.object(ThreadingHTTPServer, '__init__', return_value=None) as init:
                Server(app, port=port)
                self.assertEqual(init.call_args.args[0], ('127.0.0.1', port))
            for bad in (18769 if not isolated else 8766, 0, 443, True):
                with self.subTest(isolated=isolated, port=bad), self.assertRaises(ValueError): Server(app, port=bad)


if __name__ == '__main__':
    unittest.main()
