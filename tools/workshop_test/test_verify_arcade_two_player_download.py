"""Offline safety regressions; never initialize Steam or access release inputs."""
import ctypes as C
import io
from contextlib import redirect_stdout
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import verify_arcade_two_player_download as subject


class SafetyTests(unittest.TestCase):
    def test_default_plan_cannot_initialize_steam_or_write(self):
        package = {'package_files': [{'bytes': 10}]}
        with patch.object(subject, 'local_inputs', return_value=(package, {}, b'unchanged', False)), \
             patch.object(subject.shutil, 'disk_usage', return_value=SimpleNamespace(free=2**40)), \
             patch.object(subject.api.Steam, '__enter__', side_effect=AssertionError('Steam forbidden')), \
             patch.object(subject.api, 'publication_lock', side_effect=AssertionError('lock write forbidden')), \
             patch.object(subject.callbacks, 'write_exclusive', side_effect=AssertionError('write forbidden')), \
             redirect_stdout(io.StringIO()) as output:
            self.assertEqual(subject.main([]), 0)
        self.assertIn('READ_ONLY_MP10_DOWNLOAD_PLAN', output.getvalue())
        self.assertIn('"steam_initialized": false', output.getvalue())

    def test_unpinned_manifest_blocks_before_steam_and_lock(self):
        package = {'package_files': [{'bytes': 10}]}
        with patch.object(subject, 'local_inputs', return_value=(package, {}, b'unchanged', True)), \
             patch.object(subject, 'EXPECTED_STEAM_MANIFEST', None), \
             patch.object(subject.shutil, 'disk_usage', return_value=SimpleNamespace(free=2**40)), \
             patch.object(subject.api.Steam, '__enter__', side_effect=AssertionError('Steam forbidden')), \
             patch.object(subject.api, 'publication_lock', side_effect=AssertionError('lock forbidden')), \
             redirect_stdout(io.StringIO()) as output:
            self.assertEqual(subject.main(['--download']), 1)
        self.assertIn('real_sdk_success_manifest_not_yet_pinned', output.getvalue())

    def test_manifest_must_remain_a_positive_uint64_ascii_string(self):
        for value in (None, 123, '', '0', '-1', str(2**64), '１２３'):
            with self.subTest(value=value), patch.object(subject, 'EXPECTED_STEAM_MANIFEST', value):
                self.assertFalse(subject.manifest_pinned())
        with patch.object(subject, 'EXPECTED_STEAM_MANIFEST', '123'):
            self.assertTrue(subject.manifest_pinned())

    def test_remote_identity_and_freshness_fail_closed(self):
        item = {'id': subject.ITEM, 'result': 1, 'file_type': 0, 'creator_app_id': 570,
                'consumer_app_id': 570, 'owner': subject.api.OWNER, 'visibility': 3,
                'total_files_bytes': 1000, 'cached': False, 'max_cache_age_seconds': 0,
                'banned': False, 'tags_truncated': False, 'time_updated': subject.MINIMUM_REMOTE_UPDATED + 1,
                'tags': 'Custom Game'}
        subject.validate_remote(item, 1000)
        for key, value in {'id': '1', 'owner': '1', 'result': True, 'consumer_app_id': 571,
                           'visibility': 0, 'cached': True, 'banned': True, 'tags_truncated': True,
                           'total_files_bytes': 999, 'max_cache_age_seconds': 1,
                           'time_updated': subject.MINIMUM_REMOTE_UPDATED, 'tags': 'Other'}.items():
            with self.subTest(field=key), self.assertRaises(subject.callbacks.Refused):
                subject.validate_remote({**item, key: value}, 1000)

    def subscription(self, *, result=1, item=None, after=13):
        steam = subject.MP10Steam(1000)
        calls = []
        scheduled = [False]
        completed = subject.callbacks.CallCompleted(99, 1313, C.sizeof(subject.verify.Subscribed))
        message = SimpleNamespace(callback=703, size=C.sizeof(completed), data=C.addressof(completed))

        def ug(name, unused_result, unused_types, *unused_args):
            calls.append(name)
            if name == 'GetItemState':
                return after if scheduled[0] else 5
            self.assertEqual(name, 'SubscribeItem')
            scheduled[0] = True
            return 99

        def poll(handler):
            if scheduled[0]:
                handler(message)

        def read_result(pipe, call, pointer, size, callback, failed):
            self.assertEqual((call, size, callback), (99, 16, 1313))
            record = C.cast(pointer, C.POINTER(subject.verify.Subscribed)).contents
            record.result, record.item = result, int(subject.ITEM if item is None else item)
            return True

        steam.ug = ug
        steam.dispatch = SimpleNamespace(pipe=7, poll=poll, result=read_result)
        return steam, calls

    def test_existing_subscription_requires_real_matching_1313(self):
        steam, calls = self.subscription()
        receipt = steam.refresh_subscription_once()
        self.assertEqual(receipt['callback']['callback_id'], 1313)
        self.assertEqual(receipt['flags'], 13)
        self.assertEqual(calls.count('SubscribeItem'), 1)
        self.assertNotIn('DownloadItem', calls)

    def test_failed_or_wrong_item_subscribe_cannot_authorize_download(self):
        for options in ({'result': 2}, {'item': '1'}, {'after': 29}):
            with self.subTest(options=options):
                steam, calls = self.subscription(**options)
                with self.assertRaises(subject.callbacks.Refused):
                    steam.refresh_subscription_once()
                self.assertNotIn('DownloadItem', calls)

    def test_publication_methods_remain_outside_sdk_allowlist(self):
        steam = subject.MP10Steam(1000)
        for name in ('CreateItem', 'StartItemUpdate', 'SubmitItemUpdate', 'SetItemVisibility', 'UnsubscribeItem'):
            with self.subTest(method=name), self.assertRaises(subject.callbacks.Refused):
                steam.ug(name, C.c_bool, [])


if __name__ == '__main__':
    unittest.main()
