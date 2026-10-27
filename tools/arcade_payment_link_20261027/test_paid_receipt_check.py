"""Local scope checks; no actual grant, order, player or gateway mutation."""
import sqlite3
import unittest
from unittest.mock import patch
import paid_receipt_check as local
import paid_receipt_remote as remote

class PaidReceiptTests(unittest.TestCase):
    def test_bindings_are_exact_account_and_match(self):
        db=sqlite3.connect(':memory:');self.addCleanup(db.close)
        db.execute('CREATE TABLE payment_order_bindings(order_id,account,match_id,created)')
        rows=[('WX'+'a'*30,'123','session-a',1),('WX'+'b'*30,'456','session-a',2),('AL'+'c'*30,'123','session-b',3)]
        db.executemany('INSERT INTO payment_order_bindings VALUES(?,?,?,?)',rows)
        self.assertEqual(remote.bindings(db,'123','session-a'),[{'order_id':'WX'+'a'*30,'bound_at':1}])
        self.assertEqual(remote.bindings(db,'999','session-a'),[])

    def test_query_is_bound_scalar_select_without_transaction_data_or_gateway_payloads(self):
        query=remote.orders_query('a'*64,['WX'+'b'*30])
        self.assertTrue(query.lstrip().startswith('SELECT '))
        self.assertIn('WHERE o.account_id=',query);self.assertIn('o.order_id IN (',query)
        self.assertNotIn('to_jsonb(o)',query);self.assertNotIn('code_url',query)
        self.assertNotIn('mchid',query);self.assertNotIn('appid',query)
        self.assertNotIn("'transaction_id'",query)
        for ids in ([],['evil'],['WX'+'a'*30]*51):
            with self.assertRaises(RuntimeError):remote.orders_query('a'*64,ids)

    def test_default_never_connects(self):
        with patch.object(local,'remote') as call,patch('builtins.print'):
            local.main([])
        call.assert_not_called()

if __name__=='__main__':unittest.main()
