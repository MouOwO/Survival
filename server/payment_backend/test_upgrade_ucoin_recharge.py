"""Operator failure boundaries with fake services/filesystem, never SSH or payments."""
import contextlib
import io
import json
import sys
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock,patch
from . import upgrade_ucoin_recharge as operator


class FakeLink:
    def __init__(self,target):self.target=target;self.removed=False
    def is_symlink(self):return not self.removed
    def resolve(self):return self.target
    def unlink(self):self.removed=True


class Base:
    def __init__(self,state):self.state=state
    def __truediv__(self,name):
        assert name=='current'
        return SimpleNamespace(resolve=lambda:self.state['current'])


class OperatorFailureTests(unittest.TestCase):
    def setUp(self):
        self.old=Path('/reviewed/20261016-shop-functional-v2');self.state={'current':self.old};self.events=[]
        self.conn=Mock();self.connection=Mock();self.connection.__enter__=Mock(return_value=self.conn)
        self.connection.__exit__=Mock(return_value=False)
        self.release=SimpleNamespace(BASE=Base(self.state),health=Mock(return_value='123'),backup=Mock(),
            prepare_environment=Mock(),verify_release=Mock(return_value=self.old),
            connection=Mock(return_value=self.connection),temporary_link=Mock(side_effect=lambda prefix,target:FakeLink(target)),
            run=Mock(side_effect=lambda args:self.events.append(args)),wait_healthy=Mock())
        self.patches=[patch.object(operator,'verify_scope',return_value={'database_function_sha256':{}}),
            patch.object(operator,'preserved_state',return_value={'keep':'same'}),
            patch.object(operator,'old_products_hash',return_value='same'),
            patch.object(operator,'migrate'),patch.object(operator,'append_product',return_value={'added':True}),
            patch.object(operator,'verify_addition'),patch.object(operator,'verify_archive_baseline'),
            patch.object(operator,'verify_database_baseline'),patch.object(operator,'verify_catalog_baseline')]
        self.mocks=[p.start() for p in self.patches]
        self.addCleanup(lambda:[p.stop() for p in reversed(self.patches)])

    def move(self,link,current):self.state['current']=link.resolve()

    def activate(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return operator.activate(self.release,self.old,str(self.old),{'validated':True})

    def test_success_backs_up_stops_only_payment_and_retains_new_reader(self):
        with patch.object(operator.os,'replace',side_effect=self.move):result=self.activate()
        self.assertEqual(self.state['current'],operator.ROOT)
        self.assertEqual(self.events,[['systemctl','stop','goufayu-payment.service'],['systemctl','start','goufayu-payment.service']])
        self.release.backup.assert_called_once();self.assertFalse(result['sql_downgraded'])
        self.assertEqual(result['gateway_orders_created'],0)

    def test_failed_sql_restarts_old_service_without_publishing_or_switching(self):
        self.mocks[3].side_effect=RuntimeError('ddl_failed')
        with patch.object(operator.os,'replace') as move,self.assertRaisesRegex(RuntimeError,'ddl_failed'):self.activate()
        self.assertEqual(self.state['current'],self.old);move.assert_not_called();self.mocks[4].assert_not_called()
        self.assertEqual(self.events[-1],['systemctl','start','goufayu-payment.service'])

    def test_after_commit_swap_failure_recovers_compatible_new_reader(self):
        count=0
        def move(link,current):
            nonlocal count
            count+=1
            if count==1:raise OSError('atomic_swap_failed')
            self.move(link,current)
        with patch.object(operator.os,'replace',side_effect=move),self.assertRaisesRegex(OSError,'atomic_swap_failed'):self.activate()
        self.assertEqual(self.state['current'],operator.ROOT)
        self.assertEqual(self.events[-1],['systemctl','start','goufayu-payment.service'])

    def test_another_operator_changed_current_recovery_does_not_overwrite(self):
        other=Path('/reviewed/another_release')
        def move(link,current):self.state['current']=other;raise OSError('concurrent_change')
        with patch.object(operator.os,'replace',side_effect=move) as replace,self.assertRaisesRegex(RuntimeError,'recharge_recovery_current_changed'):self.activate()
        self.assertEqual(replace.call_count,1);self.assertEqual(self.state['current'],other)

    def test_backup_failure_never_stops_service_or_opens_transaction(self):
        self.release.backup.side_effect=RuntimeError('backup_failed')
        with self.assertRaisesRegex(RuntimeError,'backup_failed'):self.activate()
        self.release.run.assert_not_called();self.release.connection.assert_not_called()

    def test_commit_ack_loss_conservatively_starts_compatible_reader(self):
        self.connection.__exit__.side_effect=OSError('commit_ack_lost')
        with patch.object(operator.os,'replace',side_effect=self.move),self.assertRaisesRegex(OSError,'commit_ack_lost'):self.activate()
        self.assertEqual(self.state['current'],operator.ROOT)
        self.assertEqual(self.events[-1],['systemctl','start','goufayu-payment.service'])

    def test_stop_timeout_still_restores_the_old_payment_service(self):
        calls=0
        def run(args):
            nonlocal calls
            self.events.append(args);calls+=1
            if calls==1:raise TimeoutError('stop_ack_lost')
        self.release.run.side_effect=run
        with self.assertRaisesRegex(TimeoutError,'stop_ack_lost'):self.activate()
        self.assertEqual(self.state['current'],self.old)
        self.assertEqual(self.events[-1],['systemctl','start','goufayu-payment.service'])


class ArchiveGuardTests(unittest.TestCase):
    def test_archive_guard_uses_actual_current_pointer_without_helper_game_attribute(self):
        class Archive:
            name=operator.ARCHIVE_RELEASE
            def __truediv__(self,name):
                self_name='addon/server/bundles/current.json'
                assert name==self_name
                return SimpleNamespace(read_bytes=lambda:json.dumps({'hash':operator.ARCHIVE_BUNDLE}).encode())
        pointer=SimpleNamespace(resolve=lambda strict:Archive())
        with patch.dict(sys.modules,{'deploy':SimpleNamespace(GAME=pointer)}):
            operator.verify_archive_baseline(SimpleNamespace())
