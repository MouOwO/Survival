"""Metadata-only production plan contracts; no transform, SDK, native or keys."""
from collections import Counter
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock

PATH=Path(__file__).with_name('complete_delivery_release_20261103')/'production_plan.py'
SPEC=importlib.util.spec_from_file_location('complete_production_plan_under_test',PATH)
m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)


class ProductionPlanTests(unittest.TestCase):
    def test_only_exact_dual_immutable_commit_arguments_are_admitted(self):
        for game,content in (('HEAD','b'*40),('a'*40,'HEAD'),('A'*40,'b'*40),('a'*39,'b'*40)):
            with mock.patch.object(m.pending,'_git',side_effect=AssertionError('reject before IO')):
                with self.assertRaisesRegex(ValueError,'explicit_immutable_dual_revision_required'):m.plan(game,content)

    def test_runtime_selection_excludes_test_and_hidden_source(self):
        self.assertTrue(m.lua_runtime('scripts/vscripts/config/generated/a.lua'))
        for path in ('scripts/vscripts/tests/a.lua','scripts/vscripts/.private/a.lua','data/a.lua','scripts/vscripts/a.txt'):
            self.assertFalse(m.lua_runtime(path))

    def fixture_plan(self,missing_new=False):
        policy=json.loads((m.ROOT/'tools/lua_protection_policy.json').read_bytes())
        paths=set(m.OVERRIDES)|set(policy['business_modules'])|set(m.NEW_GENERATED)
        if missing_new:paths.remove(m.NEW_GENERATED[-1])
        tree={path:dict(mode='100644',kind='blob',oid='1'*40,bytes=100) for path in paths}
        baseline=dict(parent_manifest_sha256='a'*64,parent_content_sha256='c'*64,parent_sequence=2026110104,
                      deferred_sources={'game:scripts/vscripts/config/content_id_aliases.lua':dict(status='old')})
        manifest=dict(content_sha256='c'*64,file_count=len(m.OVERRIDES),files=[dict(path=path,bytes=200,sha256='d'*64) for path in m.OVERRIDES])
        def read(path,expected=None):return baseline if path==m.pending.BASELINE else manifest
        def git(repo,*args,counts):return ((('a' if repo==m.ROOT else 'b')*40)+'\n').encode()
        facts={path:dict(hash_state='VERIFIED',sha256='e'*64,bytes=100) for path in paths}
        with (mock.patch.object(m.pending,'_git',side_effect=git),mock.patch.object(m.pending,'git_tree',side_effect=lambda repo,*args:tree if repo==m.ROOT else {}),
              mock.patch.object(m.pending,'_read_json',side_effect=read),mock.patch.object(m.pending,'read_git_facts',return_value=facts),
              mock.patch.object(m.protection,'dependency_identity',return_value={'verified_source_tree_sha256':policy['dependency']['source_tree_sha256']})):
            return m.plan('a'*40,'b'*40)

    def test_only_four_constant_overrides_preserve_parent_bytes(self):
        value=self.fixture_plan()
        self.assertEqual(len(value['production_overrides']),7)
        for row in value['production_overrides']:
            self.assertEqual(row['development_sha256'],'e'*64)
            self.assertEqual(row['authenticated_policy_baseline']['sha256'],'d'*64)
            if row['path'] in m.CONSTANT_OVERRIDES:
                self.assertEqual(row['target']['sha256'],'d'*64)
                self.assertFalse(row['replacing_with_parent_would_discard_new_runtime_logic'])
            else:
                self.assertIsNone(row['target'])
                self.assertTrue(row['replacing_with_parent_would_discard_new_runtime_logic'])
                self.assertEqual(row['required_transform_tool'],'tools/complete_delivery_release_20261103/production.py')
            self.assertFalse(row['production_rules_or_account_limits_relaxed'])
            self.assertEqual(row['changed_source_logic_outside_policy_review'],'NOT_REVIEWED_BLOCKING')

    def test_lobby_entry_and_removed_preview_policy_cannot_be_replaced_by_old_parent(self):
        value=self.fixture_plan()
        merged={r['path']:r for r in value['production_overrides'] if r['target'] is None}
        self.assertEqual(set(merged),{'addoninfo.txt','scripts/vscripts/addon_game_mode_client.lua','scripts/vscripts/core/test_access_policy.lua'})

    def test_all_new_generated_configuration_is_selected_and_proof_is_not_fabricated(self):
        value=self.fixture_plan()
        self.assertEqual(value['counts']['new_network50_configurations'],2)
        self.assertEqual(value['counts']['business_probe_modules'],4)
        self.assertFalse(value['protected_values_verified'])
        self.assertTrue(all(row['transformed_sha256'] is None and row['verification']=='NOT_RUN_BLOCKING' for row in value['protected_inputs']))
        self.assertFalse(value['preparation_recipe']['plaintext_fallback_allowed'])
        self.assertFalse(value['build_ready']);self.assertFalse(value['signature_ready']);self.assertFalse(value['publication_ready'])
        self.assertEqual((value['files_written'],value['git_mutations'],value['sdk_calls'],value['network_calls']),(0,0,0,0))

    def test_source_before_network50_commit_remains_explicitly_blocked(self):
        value=self.fixture_plan(missing_new=True)
        self.assertEqual(value['missing_new_configurations'],[m.NEW_GENERATED[-1]])
        self.assertIn('NEW_NETWORK50_GENERATED_CONFIG_MISSING_FROM_SELECTED_COMMIT',value['blockers'])


if __name__=='__main__':unittest.main()
