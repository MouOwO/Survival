"""Module/route tests only. No OS calls, signing, install, launch or Steam."""
from pathlib import Path
import copy
import importlib.util
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
ops=module('hotfix_operations_contract',HERE/'rehearsal.py')
download=module('hotfix_download_contract',HERE/'verify_download.py')


class OperationsTests(unittest.TestCase):
    def setUp(self):
        ops._SOURCE_CONTEXT=None;ops._ROUTE_CONTEXT=None

    def test_static_plan_is_independent_0202_namespace(self):
        with patch.object(ops.p,'no_clients',side_effect=AssertionError('No native query')):
            value=ops.static_plan()
        self.assertEqual(value['original_release_sequence'],2026110104)
        self.assertEqual(value['port'],29062)
        self.assertIn('lottery_hotfix',value['external_store'])
        self.assertFalse(value['ready_for_upload'])

    def test_direct_and_lobby_are_ordinary_cheats_zero_and_fixed_item(self):
        log=Path('D:/fixed/engine.log')
        direct=ops.arguments(log,'direct');lobby=ops.arguments(log,'lobby')
        self.assertEqual(direct[-3:],['+dota_launch_custom_game','3824360109','ws4_entry'])
        self.assertNotIn('+dota_launch_custom_game',lobby)
        self.assertNotIn('-tools',direct)
        self.assertEqual(direct[direct.index('+sv_cheats')+1],'0')
        with self.assertRaises(ValueError):ops.arguments(log,'arbitrary')

    def test_source_binding_requires_both_authenticated_commit_cursors(self):
        package=dict(source_revision='a'*40,source_revisions={'game':'a'*40,'content':'b'*40},content_sha256='c'*64)
        self.assertEqual(ops.source_binding(package,'d'*64),package['source_revisions'])
        changed=copy.deepcopy(package);changed['source_revisions']['content']='e'*40
        with self.assertRaises(ValueError):ops.source_binding(changed,'d'*64)

    def test_same_frozen_close_function_uses_new_code_pins(self):
        self.assertIs(ops.v4.r.own_code_pins,ops.own_code_pins)
        self.assertIs(ops.p.package_auth,ops.package_auth)
        self.assertIs(ops.p.restore,ops.restore)
        self.assertIs(ops.p.arguments,ops.arguments)

    def test_log_must_be_under_exact_new_transaction_store(self):
        self.assertEqual(ops.expected_log_path(ops.STORE/'case01'),ops.LOG_ROOT/'case01/engine.log')
        with self.assertRaises(ValueError):ops.expected_log_path(ops.STORE/'case01/child')

    def test_download_static_and_family_counts_have_no_old0201_scope(self):
        value=download.static_plan();download.require_family_identity()
        self.assertEqual((value['release_sequence'],value['runtime_files'],value['scoped_runtime_paths'],value['trusted_reviews']),
                         (2026110202,6917,4,20))
        self.assertFalse(value['steam_initialized'])
        self.assertEqual(value['downloads_requested'],0)

    def test_native_verified_parent_and_owned_handle_class_remain_in_use(self):
        self.assertIs(ops.OwnedLifetime,ops.v4.OwnedLifetime)
        self.assertEqual(ops.BASE_MANIFEST,'7025356658517360342')
        self.assertEqual(ops.RESTORED_STATUS,'ORIGINAL0104_FIVE_FILES_FULLY_RESTORED')


if __name__=='__main__':unittest.main()
