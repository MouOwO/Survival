import base64
from copy import deepcopy
from datetime import datetime, timezone, timedelta
from email.message import Message
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .catalog import DEFAULT_SKU
from .service import Payments, qr_matrix
from .wechat import APPID,MCHID,PUBLIC_ID,PaymentError,WeChat,decode_json,validate_success

ID='WX'+'a'*30
def order():
    return {'order_id':ID,'account_id':'b'*64,'amount':5000,'currency':'CNY','sku':DEFAULT_SKU,'reward':{'title':'齐天大圣','item_id':'lottery_monkey_king'},'state':'created','code_url':None,
        'expires_at':(datetime.now(timezone.utc)+timedelta(minutes=30)).isoformat()}
def paid():
    return {'out_trade_no':ID,'appid':APPID,'mchid':MCHID,'trade_state':'SUCCESS','trade_type':'NATIVE',
        'transaction_id':'4200000123456789012345678901','amount':{'total':5000,'currency':'CNY'}}


class CryptoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory=tempfile.TemporaryDirectory()
        cls.private=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        cls.key=b'A'*32
        p=Path(cls.directory.name)
        (p/'apiclient_key.pem').write_bytes(cls.private.private_bytes(serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
        (p/'pub_key.pem').write_bytes(cls.private.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo))
        (p/'api_v3_key.txt').write_bytes(cls.key)
        cls.wechat=WeChat(p)
    @classmethod
    def tearDownClass(cls):cls.directory.cleanup()
    def signed(self,raw,stamp=None):
        stamp=str(stamp or int(time.time()))
        headers=Message()
        headers['Wechatpay-Timestamp']=stamp;headers['Wechatpay-Nonce']='signed_nonce'
        headers['Wechatpay-Serial']=PUBLIC_ID
        headers['Wechatpay-Signature']=base64.b64encode(self.private.sign(
            (stamp+'\nsigned_nonce\n').encode()+raw+b'\n',padding.PKCS1v15(),hashes.SHA256())).decode()
        return headers
    def event(self):
        nonce=b'123456789012'
        ciphertext=AESGCM(self.key).encrypt(nonce,json.dumps(paid()).encode(),b'transaction')
        return json.dumps({'event_type':'TRANSACTION.SUCCESS','resource_type':'encrypt-resource',
            'resource':{'algorithm':'AEAD_AES_256_GCM','original_type':'transaction','nonce':nonce.decode(),
                'associated_data':'transaction','ciphertext':base64.b64encode(ciphertext).decode()}}).encode()
    def test_verified_notice_and_repeated_notice(self):
        raw=self.event();headers=self.signed(raw)
        self.assertEqual(self.wechat.notice(headers,raw),paid())
        self.assertEqual(self.wechat.notice(headers,raw),paid())
    def test_forged_or_modified_notice(self):
        raw=self.event()
        for headers,body in [(Message(),raw),(self.signed(raw),raw+b' '),(self.signed(raw,int(time.time())-301),raw)]:
            with self.subTest(headers=bool(headers)),self.assertRaises(PaymentError):self.wechat.notice(headers,body)
    def test_wrong_key_id_and_duplicate_headers(self):
        raw=self.event();headers=self.signed(raw);headers.replace_header('Wechatpay-Serial','other_key')
        with self.assertRaises(PaymentError):self.wechat.notice(headers,raw)
        headers=self.signed(raw);headers['Wechatpay-Timestamp']=str(int(time.time()))
        with self.assertRaises(PaymentError):self.wechat.notice(headers,raw)
    def test_authenticated_but_wrong_encryption_key(self):
        raw=self.event();original=self.wechat.api_key;self.wechat.api_key=b'B'*32
        try:
            with self.assertRaises(PaymentError) as error:self.wechat.notice(self.signed(raw),raw)
            self.assertEqual(error.exception.code,'wechat_decryption_failed')
        finally:self.wechat.api_key=original
    def test_order_amount_merchant_and_currency_must_match(self):
        self.assertEqual(validate_success(paid(),order()),paid()['transaction_id'])
        changes=[('appid','other'),('mchid','other'),('out_trade_no','WX'+'b'*30),('trade_state','NOTPAY'),
            ('trade_type','JSAPI'),('amount',{'total':1,'currency':'CNY'}),('amount',{'total':10,'currency':'USD'}),
            ('amount',{'total':True,'currency':'CNY'}),('transaction_id','fake')]
        for key,value in changes:
            receipt=paid();receipt[key]=value
            with self.subTest(key=key),self.assertRaises(PaymentError):validate_success(receipt,order())
    def test_ambiguous_json_rejected(self):
        for raw in (b'{"amount":10,"amount":1}',b'{"amount":NaN}',b'[]'):
            with self.assertRaises(PaymentError):decode_json(raw)


class FakeDB:
    def __init__(self):self.row=order();self.deliveries=0;self.resets=0
    def call(self,name,*args):
        if name=='catalog':return {'ok':True,'products':[]}
        if name=='begin_reset':return {'ok':True,'completed':self.resets>0,'orders':[deepcopy(self.row)]}
        if name=='finish_reset':
            if self.row['state'] not in ('closed','delivered','paid_review'):raise PaymentError('pending_payment_unresolved')
            self.resets+=1
            return {'ok':True,'revision':10}
        if name=='create_order':
            if args[3]!=DEFAULT_SKU:raise PaymentError('product_unavailable')
            self.row['account_id']=args[0]
        if name=='update_gateway':
            if args[1]!='checked':self.row['state']=args[1]
            if args[2]:self.row['code_url']=args[2]
        if name=='deliver':
            if self.row['state']!='delivered':self.deliveries+=1
            self.row['state']='delivered'
        return deepcopy(self.row)


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.db=FakeDB();self.wx=Mock()
        self.wx.query.side_effect=PaymentError('ORDER_NOT_EXIST',502)
        self.wx.create.return_value='weixin://wxpay/bizpayurl?test=1'
        self.app=Payments({'allowed_accounts':['123'],'pepper':'p'*32,'checkout_key':'c'*32},self.db,self.wx)
        self.body={'account_id':'123','match_session_id':'session_test','sku':DEFAULT_SKU}
    def test_price_and_account_cannot_be_overridden(self):
        for body in [dict(self.body,amount=1),dict(self.body,sku='other'),dict(self.body,account_id='456')]:
            with self.assertRaises(PaymentError):self.app.game('create',body)
        self.wx.create.assert_not_called()
    def test_retries_reuse_order_and_never_grant_from_checkout(self):
        first=self.app.game('create',self.body);second=self.app.game('create',self.body)
        self.assertEqual(first['order_id'],second['order_id']);self.assertEqual(self.wx.create.call_count,1)
        self.app.checkout(first['checkout_url'].split('?',1)[1])
        self.assertEqual(self.db.deliveries,0)
    def test_in_game_qr_has_square_modules_and_quiet_zone(self):
        result=self.app.game('create',self.body)
        matrix=result['qr_matrix'].split('|')
        self.assertTrue(29<=len(matrix)<=65)
        self.assertTrue(all(len(row)==len(matrix) for row in matrix))
        self.assertTrue(all(set(row)=={'0'} for row in matrix[:4]+matrix[-4:]))
        self.assertTrue(all(row.startswith('0000') and row.endswith('0000') for row in matrix))
        self.assertEqual(qr_matrix(self.wx.create.return_value),result['qr_matrix'])
        self.db.row['state']='delivered'
        self.assertNotIn('qr_matrix',self.app.public(self.db.row))
    def test_gateway_timeout_retries_same_out_trade_no(self):
        self.wx.create.side_effect=[PaymentError('gateway_unavailable',503),self.wx.create.return_value]
        with self.assertRaises(PaymentError):self.app.game('create',self.body)
        self.app.game('create',self.body)
        self.assertEqual([call.args[0]['order_id'] for call in self.wx.create.call_args_list],[ID,ID])
    def test_checkout_cannot_be_guessed(self):
        for query in ('order='+ID+'&token=bad','order='+ID+'&token='+self.app.token(ID)+'&token=again'):
            with self.assertRaises(PaymentError):self.app.checkout(query)
    def test_status_is_bound_to_player(self):
        with self.assertRaises(PaymentError):self.app.game('status',{'account_id':'123','match_session_id':'session_test','order_id':ID})
    def test_mismatch_never_calls_delivery(self):
        bad=paid();bad['amount']['total']=1
        with self.assertRaises(PaymentError):self.app.success(bad)
        self.assertEqual(self.db.deliveries,0)
    def test_query_recovers_missed_notification(self):
        self.wx.query.side_effect=None;self.wx.query.return_value=paid()
        self.assertEqual(self.app.reconcile(order())['state'],'delivered')
        self.assertEqual(self.db.deliveries,1)
    def test_failed_query_keeps_pending(self):
        self.db.row['state']='pending';self.wx.query.side_effect=PaymentError('wechat_signature_invalid',401)
        with self.assertRaises(PaymentError):self.app.reconcile(self.db.row)
        self.assertEqual(self.db.row['state'],'pending');self.assertEqual(self.db.deliveries,0)
    def reset_body(self):
        return {'account_id':'123','match_session_id':'session_test','kind':'refreshmoney','request_id':'reset_test_request'}
    def test_reset_requires_explicit_server_switch(self):
        with self.assertRaises(PaymentError) as error:self.app.game('reset',self.reset_body())
        self.assertEqual(error.exception.code,'test_reset_disabled')
        self.assertEqual(self.db.resets,0);self.wx.close.assert_not_called()
    def test_reset_closes_pending_and_retries_are_idempotent(self):
        self.app.config['test_reset_enabled']=True
        self.assertTrue(self.app.game('reset',self.reset_body())['ok'])
        self.wx.close.assert_called_once_with(ID)
        self.app.game('reset',self.reset_body())
        self.assertEqual(self.db.resets,1)
    def test_failed_close_does_not_clear_reward(self):
        self.app.config['test_reset_enabled']=True
        self.wx.close.side_effect=PaymentError('gateway_unavailable',503)
        with self.assertRaises(PaymentError):self.app.game('reset',self.reset_body())
        self.assertEqual(self.db.resets,0)
    def test_reset_settles_already_paid_before_clear(self):
        self.app.config['test_reset_enabled']=True
        self.wx.query.side_effect=None;self.wx.query.return_value=paid()
        self.assertTrue(self.app.game('reset',self.reset_body())['ok'])
        self.assertEqual(self.db.deliveries,1);self.assertEqual(self.db.resets,1)
        self.wx.close.assert_not_called()
    def test_previous_ten_fen_receipt_still_uses_original_amount(self):
        receipt=paid();receipt['amount']['total']=10
        original=order();original['amount']=10
        self.assertEqual(validate_success(receipt,original),receipt['transaction_id'])
        with self.assertRaises(PaymentError):validate_success(receipt,order())

    def test_public_receipt_exposes_only_recorded_stat_changes(self):
        row=order();row['state']='delivered'
        row['effect_changes']={'initial_wood':{'before':80,'after':180,'delta':100}}
        result=self.app.public(row)
        self.assertEqual(result['effect_changes'],row['effect_changes'])
        self.assertNotIn('account_id',result)


if __name__=='__main__':unittest.main()
