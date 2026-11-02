import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock,patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from archive_backend.lottery_receipt_snapshot import attach


class ReceiptProjectionTests(unittest.TestCase):
    def setUp(self):
        self.service=Mock();self.service.bundle.hash='a'*64
        self.service.settle.return_value={'ok':True,'snapshots':[{'selected_pool_id':'map','tickets':10}]}
        self.reply={'ok':True,'done':True,'profile':{'account_id':'synthetic','revision':2,'save':{'content_inventory':{'lottery_ticket':10}}},'response':{'results':[{'id':'reward'}]}}
        self.command={'kind':'lottery_draw','count':10}

    def test_one_readonly_worker_zero_rpc_and_original_receipt_unchanged(self):
        before=copy.deepcopy(self.reply)
        with patch('archive_backend.unique_points.limit_snapshot_ownership',side_effect=lambda result,bundle:result):
            out=attach(self.service,self.reply,self.command,'a'*64)
        self.assertEqual(out['lottery_snapshots'][0]['tickets'],10)
        self.assertEqual(out['snapshot_config_hash'],'a'*64)
        self.assertEqual(out['response'],before['response']);self.assertEqual(out['profile'],before['profile'])
        self.service.settle.assert_called_once_with(out['profile'],{'id':'lottery_snapshot','kind':'lottery_snapshot'},False)
        self.service.app.rpc_client.rpc.assert_not_called()

    def test_projection_failure_preserves_success_for_normal_query_fallback(self):
        self.service.settle.side_effect=RuntimeError('synthetic projection failure');before=copy.deepcopy(self.reply)
        self.assertEqual(attach(self.service,self.reply,self.command,'a'*64),before)

    def test_no_projection_for_failed_incomplete_or_non_draw(self):
        for reply,command in (({'ok':False},self.command),({'ok':True,'profile':{}},self.command),(self.reply,{'kind':'lottery_read'})):
            before=copy.deepcopy(reply);self.assertEqual(attach(self.service,reply,command,'a'*64),before)
        self.service.settle.assert_not_called()


if __name__=='__main__':unittest.main()
