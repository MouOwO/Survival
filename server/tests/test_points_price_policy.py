"""Durable rejection of cumulative-point exchanges and stale price confirmations."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_archive_backend as base
from archive_backend.service import ArchiveService


class PointsPolicyTests(unittest.TestCase):
    setUpClass = classmethod(base.ArchiveTests.setUpClass.__func__)
    command = base.ArchiveTests.command
    send = base.ArchiveTests.send

    def setUp(self):
        self.db = base.Database(self.bundle)
        self.app = base.App(self.db)
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.account = self.app._database_account_id('100')
        self.profile = self.db.profile(self.account)
        self.profile['save']['archive']['commerce'] = {'balances': {'shop_points': 200000}}
        self.profile['save']['gameplay_stats'].update(starjoy_points=10000, starjoy_points_earned=25000)
        self.n = 0

    def prepare(self, digest, kind, token, **fields):
        command = self.service.validate(self.command(kind, request_id=token, **fields)['command'])
        result = self.db.rpc('archive_prepare', dict(p_account=self.account, p_id=command['id'],
            p_hash=digest, p_fingerprint=token, p_command=command))
        return command['id'], result

    def test_closed_exchange_survives_lost_commit_reply_without_any_point_debit(self):
        payload = self.command('lottery_exchange', pool_id='map',
            item_id='lottery_attribute_crystal', request_id='closed_exchange_lost_reply')
        before = copy.deepcopy(self.profile)
        self.db.lose_reply = True
        with patch.object(ArchiveService, 'settle', side_effect=AssertionError('No exchange reducer may run')):
            with self.assertRaises(TimeoutError):
                self.service.command(payload)
            result = self.service.command(payload)
        self.assertFalse(result['ok'])
        self.assertTrue(result['terminal'])
        self.assertEqual(result['error'], 'starjoy_exchange_disabled')
        self.assertEqual(self.profile, before)
        self.assertEqual(self.service.command(payload), result)

    def test_old_prepared_exchange_is_closed_before_loading_an_old_bundle(self):
        operation, prepared = self.prepare('b' * 64, 'lottery_exchange', 'old_exchange_closed',
            pool_id='map', item_id='lottery_attribute_crystal')
        before = copy.deepcopy(self.profile)
        with patch('archive_backend.service.Bundle', side_effect=AssertionError('Old exchange cannot run')):
            result = self.service.finish_prepared(self.account, operation, prepared)
        self.assertFalse(result['ok'])
        self.assertEqual(result['error'], 'starjoy_exchange_disabled')
        self.assertTrue(result['terminal'])
        self.assertEqual(self.profile, before)

    def test_completed_exchange_receipt_is_not_rewritten(self):
        operation, _ = self.prepare('b' * 64, 'lottery_exchange', 'completed_old_exchange',
            pool_id='map', item_id='lottery_attribute_crystal')
        self.db.ops[self.account, operation].update(done=True,
            response={'ok': True, 'cost': 188, 'item': {'id': 'lottery_attribute_crystal'},
                      'historical_rule': 'original completed receipt'})
        receipt = self.db.resume(self.account, operation)
        before = copy.deepcopy(self.profile)
        with patch.object(self.db, 'rpc', side_effect=AssertionError('Completed receipt is read-only')):
            self.assertIs(self.service.finish_prepared(self.account, operation, receipt), receipt)
        self.assertEqual(self.profile, before)

    def test_old_price_is_rejected_even_if_compatibility_upgrades_the_purchase(self):
        sku = 'video_p117'
        old = copy.deepcopy(self.bundle)
        old.hash = 'b' * 64
        old.tables['commerce_catalog'][sku]['price'] = 94
        for upgraded in (False, True):
            with self.subTest(upgraded=upgraded):
                operation, prepared = self.prepare(old.hash, 'commerce_purchase',
                    'stale_price_upgrade_' + str(int(upgraded)), sku=sku)
                rules = {old.hash: {'commands': {'commerce_purchase'},
                    'upgrade_commands': {'commerce_purchase'} if upgraded else set()}}
                before = copy.deepcopy(self.profile)
                with patch.object(self.bundle, 'compatible_config_hashes', rules), \
                        patch('archive_backend.service.Bundle', return_value=old), \
                        patch.object(ArchiveService, 'settle', side_effect=AssertionError('Reconfirmation required')):
                    result = self.service.finish_prepared(self.account, operation, prepared)
                self.assertFalse(result['ok'])
                self.assertTrue(result['terminal'])
                self.assertEqual(result['error'], 'commerce_price_changed')
                self.assertEqual(self.profile, before)
                self.assertEqual(self.service.finish_prepared(self.account, operation,
                    self.db.resume(self.account, operation)), result)

    def test_unchanged_recorded_price_can_still_finish_without_spending_starjoy(self):
        sku = 'video_p117'
        old = copy.deepcopy(self.bundle)
        old.hash = 'b' * 64
        price = old.tables['commerce_catalog'][sku]['price']
        operation, prepared = self.prepare(old.hash, 'commerce_purchase', 'unchanged_recorded_price', sku=sku)
        with patch('archive_backend.service.Bundle', return_value=old):
            result = self.service.finish_prepared(self.account, operation, prepared)
        self.assertTrue(result['ok'], result)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'], 200000 - price)
        self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points'], 10000)

    def test_completed_old_price_receipt_remains_at_its_original_cost(self):
        operation, _ = self.prepare('b' * 64, 'commerce_purchase', 'completed_old_purchase', sku='video_p117')
        self.db.ops[self.account, operation].update(done=True,
            response={'ok': True, 'cost': 94, 'sku': 'video_p117'})
        receipt = self.db.resume(self.account, operation)
        before = copy.deepcopy(self.profile)
        with patch('archive_backend.service.Bundle', side_effect=AssertionError('Completed receipt needs no bundle')):
            self.assertIs(self.service.finish_prepared(self.account, operation, receipt), receipt)
        self.assertEqual(receipt['response']['cost'], 94)
        self.assertEqual(self.profile, before)


if __name__ == '__main__':
    unittest.main()
