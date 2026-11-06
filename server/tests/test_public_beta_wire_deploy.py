"""Actual composed controller/gate bodies; no SSH, systemctl or real database."""
from pathlib import Path
import hashlib
import importlib.util
import io
import json
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server/tests'))
import test_ws4_compact_deploy_safety as previous_safety
import test_ws4_compact_drain_gate as previous_gate

spec = importlib.util.spec_from_file_location('joint_ws4_deploy_test', ROOT / 'tools/public_beta_wire_release_20261106/deploy.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class JointDeploymentSafety(previous_safety.DeploymentSafety):
    def setUp(self):
        with patch.object(previous_safety, 'deploy', deploy):
            super().setUp()
        self.target_unit = self.env['unit_pair']()[1]
        self.unit.write_bytes(self.target_unit)
        (self.records / 'candidate-addon.env').write_bytes(self.env['addon_environment']())

    def probe(self):
        value = dict(ok=True, status='ACTUAL_WS4_PREPARED_PUBLIC_BETA_WIRE_PARITY_PASS',
                     binding=self.env['control_binding'](self.original), rpc_calls=0,
                     database_writes=0, real_player_data_used=False,
                     checks=dict(beta=dict(exact_two=True, replay_unchanged=True, second_claim_rejected=True, wrong_session_rejected=True),
                                 ordinary=dict(old_hash_success=True, replay_unchanged=True),
                                 lottery=[dict(equal=True, **{key: {'real_rpc_calls': 0} for key in ('parent','legacy','compact')}) for _ in range(3)],
                                 wire=dict(real_lua_vectors=4, legacy_unchanged=True)))
        (self.records / 'probe.json').write_text(json.dumps(value))
        return value

    def test_receipt_failure_preserves_explicit_recovered_state(self):
        self.env['save'] = Mock(side_effect=OSError('private path'))
        result = self.env['record_recovery'](self.recover())
        self.assertFalse(result['ok'])
        self.assertFalse(result['receipt_persisted'])
        self.assertEqual(result['status'], 'OWN_WS4_PUBLIC_BETA_WIRE_ROLLED_BACK')
        self.assertEqual(self.unit.read_bytes(), self.original_unit)

    def test_only_one_path_override_and_original_unit_retained(self):
        env = self.env['addon_environment']()
        self.assertEqual(env, ('SURVIVAL_ADDON_ROOT=' + str(self.new / 'addon') + '\n').encode())
        self.assertEqual(self.target_unit.count(b'EnvironmentFile='), 1)
        self.assertEqual((self.records / 'unit.original').read_bytes(), self.original_unit)
        binding = self.env['control_binding'](self.original)
        self.assertEqual(binding['candidate_addon_environment_sha256'], hashlib.sha256(env).hexdigest())
        self.env['manifest']['archive_bundle'] = deploy.recipe.PARENT_BUNDLE
        candidate = self.env['candidate_manifest'](self.original)
        self.assertEqual(candidate['archive_bundle'], deploy.recipe.NEW_BUNDLE)
        self.assertEqual(candidate['public_beta_wire_parent_bundle'], deploy.recipe.PARENT_BUNDLE)
        self.assertIsNone(candidate['database_changed'])
        self.assertTrue(candidate['config_registration_expected'])

    def test_candidate_environment_drift_rejected_but_restore_independent(self):
        self.candidate()
        (self.records / 'candidate-addon.env').write_text('SURVIVAL_ADDON_ROOT=/wrong\n')
        self.assert_rejected(self.env['validate_candidate'], 'candidate_addon_environment_changed', self.original)
        self.assertTrue(self.recover()['ok'], 'Rollback must use independent original unit despite bad candidate env')

    def test_parent_unknown_addon_file_is_retained_and_audit_bound(self):
        (self.old / 'addon/extra.lua').write_text('old parent-only runtime')
        observed = self.env['parent_inventory']()
        self.assertIn('addon/extra.lua', observed)
        self.assert_rejected(self.env['validate_parent_inventory'], 'audited_parent_inventory_changed', observed)

    def test_prior_addon_root_requires_exact_inventory_before_switch(self):
        import shutil
        prior = self.old.parent / 'earlier' / 'addon'
        shutil.copytree(self.old / 'addon', prior)
        self.env.update(base=self.old.parent, AUDITED_ADDON_ROOT=str(prior))
        result = self.env['verify_audited_addon'](self.original)
        self.assertTrue(result['identical_to_parent'])
        (prior / 'entry.lua').write_bytes(b'unreviewed older behavior')
        self.assert_rejected(self.env['verify_audited_addon'], 'release_file_hash_changed', self.original)
        (prior / 'extra.lua').write_bytes(b'untracked prior source')
        self.assert_rejected(self.env['verify_audited_addon'], 'actual_addon_file_set_differs_from_parent', self.original)
        self.env['AUDITED_ADDON_ROOT'] = str(self.root / 'unrelated')
        self.assert_rejected(self.env['verify_audited_addon'], 'audited_addon_root_outside_release_tree', self.original)

    def test_joint_probe_requires_beta_and_wire_not_only_lottery(self):
        value = self.probe()
        del value['checks']['beta']
        (self.records / 'probe.json').write_text(json.dumps(value))
        self.assert_rejected(self.env['validate_probe'], 'beta_probe_missing', self.original)

    def test_health_checks_parent_or_candidate_hash_and_actual_addon_root(self):
        namespace = {}
        import ast
        tree = ast.parse(deploy.REMOTE)
        code = ast.Module(body=[node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'health'], type_ignores=[])
        values = dict(self.env, current_gate=None, PARENT_BUNDLE='a'*64, bundle_hash='b'*64,
                      AUDITED_ADDON_ROOT=str(self.old / 'addon'))
        active = [self.old]
        response_hash = ['a'*64]
        values['observed'] = lambda: (active[0], {'pid': 88})
        values['actual_addon_root'] = lambda pid: active[0] / 'addon'
        values['state'] = lambda name: {'pid': 99}
        values['urllib'] = SimpleNamespace(request=SimpleNamespace(
            Request=lambda *a, **k: object(),
            urlopen=lambda *a, **k: io.BytesIO(json.dumps({'ok':True,'config_hash':response_hash[0]}).encode())))
        exec(compile(code, '<actual-joint-health>', 'exec'), values)
        token = 'synthetic-test-only'
        read = Path.read_bytes
        def fake_read(path):
            if path.as_posix() == '/proc/99/environ':
                return ('PLAYER_WEB_AUTH_UPSTREAM_BEARER='+token+'\0').encode()
            if path.as_posix() == '/etc/goufayu-ws4/pins.json':
                return json.dumps({'workshop_id':'3824360109','sha256':[hashlib.sha256(token.encode()).hexdigest()]}).encode()
            return read(path)
        with patch.object(Path, 'read_bytes', fake_read):
            values['health']()
            active[0] = self.new
            with self.assertRaisesRegex(RuntimeError, 'ws4_published_config_unhealthy'):
                values['health']()
            response_hash[0] = 'b'*64
            values['health']()
            values['actual_addon_root'] = lambda pid: self.old / 'addon'
            with self.assertRaisesRegex(RuntimeError, 'active_addon_root_mismatch'):
                values['health']()

    def configuration_records(self):
        folder = self.records.parent / '20261106-public-beta-config-f8ab7087c042'
        folder.mkdir()
        binding = {'source_bundle': deploy.recipe.NEW_BUNDLE, 'candidate_function_sha256': 'a' * 64,
                   'source_revision': 'b' * 40, 'operator_revision': 'c' * 40,
                   'record_name': folder.name}
        sql = 'DO $check$ BEGIN NULL; END; $check$;\n'
        proof = dict(ok=True, binding=binding, status='PUBLIC_BETA_CONFIG_ACTIVE_VERIFIED',
                     config_registration_verified=True, read_only=True, database_writes=0)
        (folder / 'binding.json').write_text(json.dumps(binding))
        (folder / 'verify.json').write_text(json.dumps(proof))
        (folder / 'verify.sql').write_bytes(sql.encode())
        execute = Mock(return_value=SimpleNamespace(returncode=0, stdout=json.dumps(
            {'ok': True, 'status': 'JOINT_CONFIG_ADMISSION_VERIFIED'}).encode()))
        self.env.update(CONFIG_BINDING=binding, CONFIG_VERIFY_SQL=sql,
                        subprocess=SimpleNamespace(run=execute, PIPE=-1))
        return folder, execute

    def test_configuration_gate_requires_bound_receipt_then_readonly_actual_database(self):
        folder, execute = self.configuration_records()
        result = self.env['verify_config_admission']()
        self.assertTrue(result['verified'])
        self.assertEqual(result['database_writes'], 0)
        args, kwargs = execute.call_args
        self.assertIn('goufayu-ws4-db', args[0])
        self.assertEqual(args[0][-1], 'goufayu_ws4')
        self.assertIn(b'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;', kwargs['input'])
        self.assertIn(b'ROLLBACK;', kwargs['input'])
        self.assertNotIn(b'COMMIT;', kwargs['input'])
        self.assertEqual(self.commands, [])

    def test_configuration_gate_rejects_stale_proof_without_invoking_database(self):
        folder, execute = self.configuration_records()
        proof = json.loads((folder / 'verify.json').read_text())
        proof['binding']['source_revision'] = 'd' * 40
        (folder / 'verify.json').write_text(json.dumps(proof))
        self.assert_rejected(self.env['verify_config_admission'], 'verified_config_admission_required')
        execute.assert_not_called()
        self.assertEqual(self.commands, [])

    def test_configuration_gate_rejects_actual_function_or_config_drift(self):
        folder, execute = self.configuration_records()
        execute.return_value = SimpleNamespace(returncode=1, stdout=b'')
        self.assert_rejected(self.env['verify_config_admission'], 'joint_config_admission_readonly_check_failed')
        self.assertEqual(self.commands, [])


class JointControllers(previous_gate.ControllerTests):
    def setUp(self):
        with patch.object(previous_gate, 'deploy', deploy):
            super().setUp()


class JointActivation(previous_gate.ActivationTests):
    def setUp(self):
        with patch.object(previous_gate, 'deploy', deploy):
            super().setUp()


class UnchangedGate(previous_gate.GateTests):
    pass


class UnchangedWatchdog(previous_gate.WatchdogTests):
    pass


class ExactMatchModesPatch(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'server/archive_backend/match_modes.py').read_bytes().replace(b'\r\n', b'\n')
        self.parent = self.source.replace(b'        from .http_profile_wire import pack\n', b'', 1).replace(
            b'return pack(payload, _daily_projection(application, response, result))',
            b'return _daily_projection(application, response, result)')

    def test_preserves_unknown_live_code_outside_project(self):
        unknown = b'\n# Retained live-only behavior outside the projection wrapper.\nLIVE_ONLY_VERSION = 42\n'
        parent = self.parent + unknown
        changed, binding = deploy.recipe.derive_match_modes(parent, self.source, hashlib.sha256(parent).hexdigest())
        self.assertEqual(changed, self.source + unknown)
        self.assertTrue(binding['outside_project_unchanged'])
        self.assertEqual(binding['changed_returns'], 2)

    def test_rejects_parent_drift_and_unreviewed_project_changes(self):
        digest = hashlib.sha256(self.parent).hexdigest()
        with self.assertRaisesRegex(RuntimeError, 'audited_match_modes_changed'):
            deploy.recipe.derive_match_modes(self.parent + b'\n', self.source, digest)
        changed = self.parent.replace(b'    def project(application, payload, response, match_context, *, login=False):\n',
                                      b'    def project(application, payload, response, match_context, *, login=False):\n        unknown = True\n', 1)
        with self.assertRaisesRegex(RuntimeError, 'unreviewed_match_projection_change'):
            deploy.recipe.derive_match_modes(changed, self.source, hashlib.sha256(changed).hexdigest())

    def test_full_seven_file_recipe_and_client_bundle_pair(self):
        # Git transport is replaced only for this uncommitted-input unit test;
        # production source_inputs separately requires immutable Git blobs.
        parent = ROOT / 'tools/public_beta_wire_release_20261106/parent_sources'
        read_source = lambda revision, name: (ROOT / name).read_bytes().replace(b'\r\n', b'\n')
        modes = (parent / 'match_modes.py').read_bytes()
        with patch.object(deploy.recipe, 'git_blob', side_effect=read_source):
            values, binding = deploy.recipe.payloads('b4c2d904b6e520c2e1c62656cd2c05772b38e3f6',
                (parent / 'service.py').read_bytes(), modes, hashlib.sha256(modes).hexdigest(),
                (parent / 'server.py').read_bytes(), (parent / 'postgres.py').read_bytes())
        self.assertEqual({key for key in values if key.startswith('backend/')}, {
            'backend/archive_backend/service.py', 'backend/archive_backend/public_beta_gift.py',
            'backend/archive_backend/match_modes.py', 'backend/archive_backend/http_profile_wire.py',
            'backend/archive_backend/http_request_timing.py', 'backend/fishing_api/server.py',
            'backend/fishing_api/postgres.py'})
        document = json.loads(values['addon/server/bundles/' + deploy.recipe.NEW_BUNDLE + '/bundle.json'])
        self.assertEqual(len(values), len(document['sources']) + 10)
        self.assertEqual(json.loads(values['addon/server/bundles/current.json']),
                         {'hash': deploy.recipe.NEW_BUNDLE, 'protocol': 1})
        self.assertIn(deploy.recipe.NEW_BUNDLE.encode(), values['addon/scripts/vscripts/config/generated/archive_http_bundle.lua'])
        self.assertEqual(binding['payload_sha256'], {name: hashlib.sha256(raw).hexdigest() for name, raw in values.items()})
        self.assertTrue(binding['http_timing']['permission_sql_retry_and_connection_policy_unchanged'])


class SourceInputsAuditBinding(unittest.TestCase):
    """Exercise the actual full input path, replacing only Git transport.

    Temporary audit fixtures reproduce the live CRLF supabase source. A
    source-bound CLI plan is still required after the operator is committed.
    """
    revision = 'c' * 40
    supabase_key = 'backend/fishing_api/supabase.py'
    supabase_raw_sha = 'fb8279e6a76c0394f1e10585f09e1b862a0e5dd8567382718fa7556086207bf9'
    supabase_lf_sha = '78f4cbfbcc2a2aa4b72a6c4087f147d0ed871c3222e0b5ffbe6001281151f8c8'

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.audit = self.root / 'audit'
        self.parent = self.root / 'parent_sources'
        self.parent.mkdir()
        source_files = {}
        for name in ('service.py', 'match_modes.py', 'server.py', 'postgres.py', 'supabase.py'):
            raw = (deploy.PARENT_SOURCE / name).read_bytes().replace(b'\r\n', b'\n')
            (self.parent / name).write_bytes(raw)
            if name == 'service.py':
                continue
            key = ('backend/archive_backend/' if name == 'match_modes.py' else 'backend/fishing_api/') + name
            audited_raw = raw.replace(b'\n', b'\r\n') if name == 'supabase.py' else raw
            destination = self.audit / key
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(audited_raw)
            source_files[key] = {'sha256': deploy.sha(audited_raw)}
        self.assertEqual(source_files[self.supabase_key]['sha256'], self.supabase_raw_sha)
        (self.audit / 'audit.json').write_text(json.dumps(dict(
            release=deploy.recipe.PARENT_RELEASE, manifest_sha256=deploy.recipe.PARENT_MANIFEST,
            source_files=source_files)), encoding='utf8')
        self.addon = self.root / 'addon.json'
        self.addon.write_text(json.dumps(dict(ok=True, release=deploy.recipe.PARENT_RELEASE,
            addon_root_present=True, execstart_contains_addon_root_override=False,
            addon_root_resolved='/opt/goufayu-ws4/releases/test-parent/addon')), encoding='utf8')
        for name, value in (('SOURCE_AUDIT', self.audit), ('PARENT_SOURCE', self.parent), ('ADDON_AUDIT', self.addon)):
            self.enterContext(patch.object(deploy, name, value))
        self.git = self.enterContext(patch('subprocess.check_output', side_effect=self.git_blob_transport))

    def git_blob_transport(self, args, **kwargs):
        self.assertEqual(args[:5], ['git', '--no-replace-objects', '-C', str(ROOT), 'show'])
        self.assertEqual(len(args), 6)
        revision, name = args[5].split(':', 1)
        self.assertEqual(revision, self.revision)
        self.assertNotIn('..', Path(name).parts)
        return (ROOT / name).read_bytes().replace(b'\r\n', b'\n')

    def test_full_source_inputs_preserves_audited_raw_and_git_lf_identities(self):
        values = deploy.source_inputs(self.revision, self.revision)
        payloads, binding, source_pins, operator_pins = values[:4]
        evidence = binding['audited_parent_sources'][self.supabase_key]
        self.assertEqual(evidence, dict(audited_raw_sha256=self.supabase_raw_sha,
            git_lf_sha256=self.supabase_lf_sha, normalization='crlf_to_lf'))
        self.assertNotIn(self.supabase_key, payloads)
        self.assertEqual(len(payloads), 44)
        self.assertEqual(binding['payload_sha256'], {name: deploy.sha(raw) for name, raw in payloads.items()})
        self.assertEqual(binding['config_admission'], values[-1])
        self.assertEqual(set(operator_pins), set(deploy.OPERATOR_FILES))
        self.assertEqual(len(source_pins), 8)
        self.assertIn('verify.sql', values[-2])

    def test_source_inputs_rejects_audited_raw_drift_even_if_normalized_equal(self):
        path = self.audit / self.supabase_key
        path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
        with self.assertRaisesRegex(RuntimeError, 'audited_parent_source_raw_mismatch'):
            deploy.source_inputs(self.revision, self.revision)

    def test_source_inputs_rejects_audit_hash_replaced_with_normalized_hash(self):
        path = self.audit / 'audit.json'
        value = json.loads(path.read_bytes())
        value['source_files'][self.supabase_key]['sha256'] = self.supabase_lf_sha
        path.write_text(json.dumps(value), encoding='utf8')
        with self.assertRaisesRegex(RuntimeError, 'audited_parent_source_raw_mismatch'):
            deploy.source_inputs(self.revision, self.revision)

    def test_source_inputs_rejects_actual_fixture_body_change(self):
        path = self.parent / 'supabase.py'
        path.write_bytes(path.read_bytes() + b'\nUNREVIEWED_CHANGE = True\n')
        with self.assertRaisesRegex(RuntimeError, 'frozen_parent_source_audit_mismatch'):
            deploy.source_inputs(self.revision, self.revision)


class ComposedRemoteBindings(unittest.TestCase):
    def test_top_level_parent_and_bundle_match_actual_audited_release(self):
        import ast
        tree = ast.parse(deploy.REMOTE)
        wanted = {'base', 'old', 'unit', 'expected_manifest', 'expected_service', 'bundle_hash'}
        selected = [node for node in tree.body if isinstance(node, ast.Assign)
                    and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
                    and node.targets[0].id in wanted]
        self.assertEqual(len(selected), len(wanted))
        scope = {'Path': Path}
        exec(compile(ast.Module(body=selected, type_ignores=[]), '<actual-remote-bindings>', 'exec'), scope)
        self.assertEqual(scope['old'], scope['base'] / deploy.recipe.PARENT_RELEASE)
        self.assertEqual(scope['expected_manifest'], deploy.recipe.PARENT_MANIFEST)
        self.assertEqual(scope['expected_service'], deploy.recipe.PARENT_SERVICE)
        self.assertEqual(scope['bundle_hash'], deploy.recipe.NEW_BUNDLE)
        self.assertNotIn('20261106-ws4-public-beta-wire-d15b405cfb16', deploy.REMOTE)

    def test_config_admission_is_checked_before_activation_mutations(self):
        self.assertIn("if MODE=='activate':\n    config_admission=verify_config_admission()\n    result=activate_candidate", deploy.REMOTE)
        self.assertIn("elif MODE=='verify':\n    config_admission=verify_config_admission()", deploy.REMOTE)
        self.assertNotIn('CREATE OR REPLACE FUNCTION public.archive_sync_config', deploy.REMOTE)


if __name__ == '__main__':
    unittest.main()
