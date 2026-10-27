"""Readback tests are local temporary/memory fixtures, never actual grants."""
import copy
from decimal import InvalidOperation
import json
import sqlite3
import unittest
from unittest.mock import patch

import live_readback as local
import live_readback_remote as remote


class ReadbackTests(unittest.TestCase):
    def fixture(self):
        return {'kind':'WS4_REAL_SESSION_READONLY_SNAPSHOT','ok':True,'account_id':'123','match_session_id':'real-match-123',
                'control_account_id':'456','observed_at':2000,'real_player_grant':True,'server_snapshot_ready':True,
                'cloud_profile_readback':False,'grant':{'approved_at':1900},
                'wallet':{'profile_exists':True,'profile_revision':3,'u_coin':0,'wallet_field_absent':False},
                'control_wallet':{'profile_exists':True,'profile_revision':4,'u_coin':80,'wallet_field_absent':False}}

    def test_default_plan_does_not_read_remote_or_create_success_evidence(self):
        with patch.object(local,'remote') as call,patch('builtins.print') as output:
            local.main([])
        call.assert_not_called()
        value=json.loads(output.call_args.args[0])['result']
        self.assertFalse(value['real_player_grant']);self.assertFalse(value['cloud_profile_readback'])

    def test_no_grant_or_expired_revoked_wrong_steam_never_counts_as_real_session(self):
        db=sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.execute('CREATE TABLE challenges(created,approved_at,token_expires,revoked,approved_steam,token_hash,account,match_id)')
        self.assertFalse(remote.session_evidence(db,'123','real-match-123',2000)['approved'])
        steam=str(remote.STEAM_BASE+123)
        rows=[(1800,None,None,0,None,None,'123','real-match-123'),
              (1800,1900,1999,0,steam,'never-export','123','real-match-123'),
              (1800,1900,3000,1,steam,'never-export','123','real-match-123'),
              (1800,1900,3000,0,str(remote.STEAM_BASE+999),'never-export','123','real-match-123')]
        db.executemany('INSERT INTO challenges VALUES(?,?,?,?,?,?,?,?)',rows)
        result=remote.session_evidence(db,'123','real-match-123',2000)
        self.assertFalse(result['approved']);self.assertNotIn('never-export',json.dumps(result))
        db.execute('INSERT INTO challenges VALUES(?,?,?,?,?,?,?,?)',(1950,1960,3000,0,steam,'never-export','123','real-match-123'))
        result=remote.session_evidence(db,'123','real-match-123',2000)
        self.assertTrue(result['approved']);self.assertEqual(result['approved_at'],1960)
        self.assertNotIn('never-export',json.dumps(result));self.assertNotIn(steam,json.dumps(result))
        self.assertFalse(remote.session_evidence(db,'456','real-match-123',2000)['approved'])

    def test_wallet_rejects_malformed_types_fraction_negative_overflow_and_missing_profile(self):
        base={'profile_exists':True,'profile_revision':7,'wallet_kind':'number','wallet_text':'100'}
        self.assertEqual(remote.wallet(base)['u_coin'],100)
        self.assertEqual(remote.wallet({**base,'wallet_kind':None,'wallet_text':None})['u_coin'],0)
        for edit in ({'wallet_kind':'string'},{'wallet_text':'-1'},{'wallet_text':'1.1'},{'wallet_text':'9007199254740992'},
                     {'wallet_text':'NaN'},{'profile_revision':True},{'commerce_kind':'array'},{'balances_kind':'string'}):
            with self.assertRaises(RuntimeError):remote.wallet({**base,**edit})
        self.assertIsNone(remote.wallet({'profile_exists':False})['u_coin'])

    def test_compare_exact_credit_and_control_without_requiring_fake_client_fields(self):
        before=self.fixture();after=copy.deepcopy(before);after['observed_at']+=5
        after['wallet']['u_coin']=100;after['wallet']['profile_revision']+=1
        result=local.compare(before,after)
        self.assertTrue(result['ok']);self.assertTrue(result['wallet_credit_verified'])
        self.assertFalse(result['client_readback_verified']);self.assertFalse(result['cloud_profile_readback'])
        after['control_wallet']['u_coin']+=100
        self.assertFalse(local.compare(before,after)['ok'])
        after['control_wallet']=copy.deepcopy(before['control_wallet']);after['wallet']['u_coin']=200
        self.assertFalse(local.compare(before,after)['wallet_credit_verified'])
        after['account_id']='999'
        with self.assertRaisesRegex(ValueError,'identity_mismatch'):local.compare(before,after)

    def test_optional_real_client_receipt_cannot_cross_session_or_fake_unknown_fields(self):
        snapshot=self.fixture()
        receipt={'kind':'WS4_HELPER_LIVE_READBACK','account_id':'123','match_session_id':'real-match-123',
                 'observed_at':1999,'authenticated':True,'loaded':True,'profile_revision':3,'u_coin':0,'wallet_scope':'account'}
        value=local.attach_client(snapshot,receipt)
        self.assertTrue(value['cloud_profile_readback']);self.assertFalse(value['api_proxy_receipt_available'])
        for edit in ({'match_session_id':'other-session'},{'u_coin':100},{'loaded':False},{'observed_at':100},
                     {'token':'must-not-export'},{'http_profile_status':403}):
            with self.assertRaises(ValueError):local.attach_client(snapshot,{**receipt,**edit})
        with self.assertRaisesRegex(ValueError,'real_server_session_required'):
            local.attach_client({**snapshot,'real_player_grant':False},receipt)

    def test_query_is_scalar_select_without_rpcs_full_archive_or_unbounded_identity(self):
        query=remote.profile_query('a'*64)
        self.assertTrue(query.lstrip().startswith('SELECT '))
        self.assertNotIn('to_jsonb(',query);self.assertNotIn('fishing_profile_json',query)
        self.assertIn('p.account_id=',query)
        for value in ('x'*64,"' OR true --",'a'*65):
            with self.assertRaises(RuntimeError):remote.profile_query(value)

if __name__=='__main__':unittest.main()
