"""Deployment boundary checks; no SSH, network, services or databases touched."""
import base64
from contextlib import redirect_stdout, redirect_stderr
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import deploy_web_auth as driver
import remote_web_auth as operator


def fixture_sources(marker=b'# reviewed runtime\n', names=None):
    return {name: marker for name in (operator.RUNTIME_SOURCES if names is None else names)}


class DeploymentBoundaryChecks(unittest.TestCase):
    def test_appending_pin_preserves_original_pins_and_metadata(self):
        before = {'workshop_id': '3824360109', 'sha256': ['a' * 64],
                  'local_host_sha256': 'a' * 64, 'local_host_name': 'original'}
        result = json.loads(operator.append_pin(json.dumps(before).encode(), 'b' * 64))
        self.assertEqual(result['sha256'], ['a' * 64, 'b' * 64])
        self.assertEqual(result['local_host_sha256'], before['local_host_sha256'])
        self.assertEqual(result['local_host_name'], before['local_host_name'])

    def test_pin_overflow_duplicate_or_wrong_workshop_fails_closed(self):
        for document in (
            {'workshop_id': '3824360109', 'sha256': [c * 64 for c in 'abcd']},
            {'workshop_id': '3824360109', 'sha256': ['e' * 64]},
            {'workshop_id': 'wrong', 'sha256': []},
            {'workshop_id': '3824360109', 'sha256': [{}]},
        ):
            with self.assertRaises(RuntimeError):
                operator.append_pin(json.dumps(document).encode(), 'e' * 64)

    def test_allowlist_is_read_from_existing_env_and_requires_four_accounts(self):
        accounts = '76561198424163156,76561198845461206,76561198104787442,76561198974301984'
        self.assertEqual(operator.accounts(('POSTGRES_DSN="private"\nSURVIVAL_TEST_STEAM_IDS64=' + json.dumps(accounts)).encode()), accounts)
        for value in ('', accounts.split(',')[0], ','.join([accounts.split(',')[0]] * 4)):
            with self.assertRaises(RuntimeError):
                operator.accounts(('SURVIVAL_TEST_STEAM_IDS64=' + json.dumps(value)).encode())

    def test_only_one_correct_tls_server_is_selected(self):
        text = '''server { listen 80; server_name pay.xiaofengnet.com; }
server { listen 443 ssl; server_name other.example; }
server { listen 443 ssl; server_name pay.xiaofengnet.com;
 location /existing/ { proxy_pass http://127.0.0.1:8766; }
 # comment with brace }
 set $example "quoted } brace";
}
'''
        path, raw, close = operator.tls_candidates([(Path('/etc/nginx/a.conf'), text)])
        self.assertEqual(raw[close], '}')
        changed = raw[:close] + '\n include /etc/nginx/goufayu-ws4-web.locations;\n' + raw[close:]
        self.assertEqual(changed.replace('\n include /etc/nginx/goufayu-ws4-web.locations;\n', ''), text)
        with self.assertRaisesRegex(RuntimeError, 'unique_tls'):
            operator.tls_candidates([(path, text), (Path('/etc/nginx/b.conf'), text)])

    def test_unit_and_proxy_are_isolated_without_existing_routes(self):
        unit, rules = operator.unit_source().decode(), operator.proxy_rules().decode()
        self.assertIn('User=goufayu-ws4-web\n', unit)
        self.assertIn('ReadWritePaths=/var/lib/goufayu-ws4-web\n', unit)
        self.assertIn('/usr/bin/python3.11 -B -m player_web_auth.run', unit)
        self.assertNotIn('ReadWritePaths=/var/lib/goufayu-ws4\n', unit)
        self.assertIn('location ^~ /ws4-web/', rules)
        self.assertIn('proxy_pass http://127.0.0.1:18767/;', rules)
        self.assertIn('limit_except GET POST', rules)
        self.assertIn('client_max_body_size 64k;', rules)
        self.assertIn('access_log off;', rules)
        self.assertNotIn('location /ws4/', rules)
        self.assertNotIn('location /payment', rules)

    def test_anonymous_probe_does_not_contain_an_account_or_secret(self):
        def inspect(request, timeout):
            self.assertEqual(request.data, b'{}')
            self.assertEqual(request.get_method(), 'POST')
            self.assertIsNone(request.get_header('Authorization'))
            import io
            raise operator.urllib.error.HTTPError(request.full_url, 403, 'denied', {},
                io.BytesIO(b'{"ok":false,"error":"player_session_required"}'))
        with patch.object(operator.urllib.request, 'urlopen', side_effect=inspect):
            operator.reject_anonymous('http://127.0.0.1:18767')

    def test_prepared_files_have_not_changed_before_activation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ops, release, config = root/'ops', root/'release', root/'config'
            for path in (ops, release, config):
                path.mkdir()
            source = b'# reviewed source\n'
            for name in operator.RUNTIME_SOURCES:
                target = release/name
                target.parent.mkdir(exist_ok=True)
                target.write_bytes(source)
            (config/'auth.env').write_bytes(b'private')
            plan = {'release': str(release), 'env_sha256': operator.sha(b'private'),
                    'files': {name: operator.sha(source) for name in operator.RUNTIME_SOURCES}}
            for kind in ('nginx', 'pins'):
                for state in ('before', 'after'):
                    raw = (kind + state).encode()
                    (ops/(kind+'.'+state)).write_bytes(raw)
                    plan[kind+'_'+state+'_sha256'] = operator.sha(raw)
            (ops/'unit.candidate').write_bytes(operator.unit_source())
            (ops/'locations.candidate').write_bytes(operator.proxy_rules())
            (ops/'prepared.json').write_text(json.dumps(plan))
            with patch.object(operator, 'OPS', ops), patch.object(operator, 'RELEASE', release), patch.object(operator, 'CONFIG', config), patch.object(operator, 'unit_source', return_value=(ops/'unit.candidate').read_bytes()):
                operator.prepared()
                (release/'player_web_auth/run.py').write_bytes(b'# changed source')
                with self.assertRaisesRegex(RuntimeError, 'prepared_source_changed'):
                    operator.prepared()

    def test_driver_only_packages_python_sources(self):
        payload = driver.overlay()
        self.assertEqual(set(payload), operator.RUNTIME_SOURCES)
        for name, encoded in payload.items():
            self.assertTrue(name.startswith(('player_web_auth/', 'lobby_backend/')))
            self.assertTrue(name.endswith('.py'))
            self.assertNotIn('test_', Path(name).name)
            compile(base64.b64decode(encoded), name, 'exec')

    def test_rollback_removes_only_new_pin_and_stops_only_new_service(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ops = root/'ops'
            ops.mkdir()
            nginx, pins, unit, locations = (root/name for name in ('nginx.conf', 'pins.json', 'new.service', 'locations'))
            before, after = b'original routes', b'original routes plus web route'
            nginx.write_bytes(after)
            original = {'workshop_id': '3824360109', 'sha256': ['a'*64], 'local_host_sha256': 'a'*64}
            current = {**original, 'sha256': ['a'*64, 'b'*64, 'c'*64]}
            pins.write_text(json.dumps(current))
            (ops/'nginx.before').write_bytes(before)
            (ops/'pins.before').write_text(json.dumps(original))
            (ops/'activation.json').write_text('{}')
            unit.write_bytes(operator.unit_source())
            locations.write_bytes(operator.proxy_rules())
            plan = {'nginx_path': str(nginx), 'nginx_before_sha256': operator.sha(before),
                    'nginx_after_sha256': operator.sha(after), 'nginx_gid': 0, 'nginx_mode': 0o644,
                    'new_bearer_sha256': 'b'*64}
            commands = []
            def local_replace(path, raw, **kwargs):
                path.write_bytes(raw)
            fake_pwd = SimpleNamespace(getpwnam=lambda name: SimpleNamespace(pw_gid=123))
            with patch.dict(sys.modules, {'pwd': fake_pwd}), patch.object(operator, 'OPS', ops), \
                 patch.object(operator, 'PINS', pins), patch.object(operator, 'UNIT', unit), \
                 patch.object(operator, 'LOCATIONS', locations), patch.object(operator, 'prepared', return_value=plan), \
                 patch.object(operator, 'unchanged') as unchanged, patch.object(operator, 'replace', side_effect=local_replace), \
                 patch.object(operator, 'run', side_effect=lambda args: commands.append(args) or b''):
                result = operator.rollback()
            self.assertTrue(result['private_state_preserved'])
            self.assertEqual(nginx.read_bytes(), before)
            self.assertEqual(json.loads(pins.read_bytes())['sha256'], ['a'*64, 'c'*64])
            self.assertEqual(json.loads(pins.read_bytes())['local_host_sha256'], 'a'*64)
            self.assertIn(['systemctl', 'disable', '--now', 'new.service'], commands)
            self.assertEqual(unchanged.call_count, 2)
            for command in commands:
                self.assertFalse(set(operator.SERVICES) & set(command))

    def test_rollback_preserves_external_nginx_edit_without_stopping_any_service(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            nginx = root/'nginx.conf'
            nginx.write_bytes(b'concurrent administrator edit')
            (root/'activation.json').write_text('{}')
            plan = {'nginx_path': str(nginx), 'nginx_before_sha256': operator.sha(b'before'),
                    'nginx_after_sha256': operator.sha(b'after')}
            with patch.dict(sys.modules, {'pwd': SimpleNamespace()}), patch.object(operator, 'OPS', root), \
                 patch.object(operator, 'prepared', return_value=plan), patch.object(operator, 'unchanged'), \
                 patch.object(operator, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'nginx_external_change_preserved'):
                    operator.rollback()
            run.assert_not_called()
            self.assertEqual(nginx.read_bytes(), b'concurrent administrator edit')

    def test_failed_activation_emits_only_fixed_code_stage_and_rollback_result(self):
        failure = operator.ActivationFailure(RuntimeError('health_contract_invalid'), 'wait_loopback_health', True,
            health_error=OSError('private credential /host/path must not be printed'))
        stream = io.StringIO()
        with patch.object(operator, 'activate', side_effect=failure), redirect_stdout(stream):
            with self.assertRaises(SystemExit) as exit_code:
                operator.main('activate')
        self.assertEqual(exit_code.exception.code, 1)
        result = json.loads(stream.getvalue())
        self.assertEqual(result['error'], 'health_contract_invalid')
        self.assertEqual(result['stage'], 'wait_loopback_health')
        self.assertTrue(result['rollback_ok'])
        self.assertEqual(result['loopback_health_error'], 'host_io_failed')
        self.assertNotIn('credential', stream.getvalue())
        self.assertNotIn('/host/path', stream.getvalue())

    def test_reactivation_requires_successful_rollback_and_unchanged_semantic_pins(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            nginx, pins, unit, locations = (root/name for name in ('nginx', 'pins', 'unit', 'locations'))
            raw = b'original nginx'
            nginx.write_bytes(raw)
            original = {'workshop_id': '3824360109', 'sha256': ['a'*64]}
            pins.write_text(json.dumps(original, sort_keys=True, indent=2))
            (root/'pins.before').write_text(json.dumps(original))
            (root/'activation.json').write_text('{}')
            plan = {'nginx_path': str(nginx), 'nginx_before_sha256': operator.sha(raw)}
            fake_socket = SimpleNamespace(connect_ex=lambda target: 1)
            # MagicMock supplies the context-manager special methods on its type.
            from unittest.mock import MagicMock
            context = MagicMock()
            context.__enter__.return_value = fake_socket
            with patch.object(operator, 'OPS', root), patch.object(operator, 'PINS', pins), \
                 patch.object(operator, 'UNIT', unit), patch.object(operator, 'LOCATIONS', locations), \
                 patch.object(operator.socket, 'socket', return_value=context):
                with self.assertRaisesRegex(RuntimeError, 'successful_rollback_required'):
                    operator.activation_ready(plan)
                (root/'rolled-back.json').write_text('{"ok":true}')
                operator.activation_ready(plan)
                pins.write_text(json.dumps({**original, 'sha256': ['a'*64, 'c'*64]}))
                with self.assertRaisesRegex(RuntimeError, 'activation_pin_baseline_changed'):
                    operator.activation_ready(plan)

    def test_identical_prepared_source_is_a_read_only_noop(self):
        sources = {'player_web_auth/run.py': b'# unchanged candidate\n'}
        plan = {'files': {name: operator.sha(raw) for name, raw in sources.items()}}
        with patch.dict(sys.modules, {'pwd': SimpleNamespace()}), \
             patch.object(operator, 'prepared', return_value=plan), patch.object(operator, 'unchanged'), \
             patch.object(operator, 'decoded_sources', return_value=sources), \
             patch.object(operator, 'replace') as replace, patch.object(operator, 'private') as private, \
             patch.object(operator, 'activation_ready') as ready:
            result = operator.refresh_prepared()
        self.assertFalse(result['candidate_updated'])
        replace.assert_not_called()
        private.assert_not_called()
        ready.assert_not_called()

    def test_source_refresh_requires_rollback_before_any_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            sources = fixture_sources(b'# revised candidate\n')
            plan = {'files': {name: operator.sha(b'# original candidate\n') for name in sources}}
            with patch.dict(sys.modules, {'pwd': SimpleNamespace()}), \
                 patch.object(operator, 'OPS', Path(temporary)), patch.object(operator, 'prepared', return_value=plan), \
                 patch.object(operator, 'unchanged'), patch.object(operator, 'decoded_sources', return_value=sources), \
                 patch.object(operator, 'replace') as replace, patch.object(operator, 'private') as private:
                with self.assertRaisesRegex(RuntimeError, 'successful_rollback_required_before_refresh'):
                    operator.refresh_prepared()
            replace.assert_not_called()
            private.assert_not_called()

    def test_relay_setting_is_explicit_and_not_accepted_by_other_commands(self):
        for mode in ('audit', 'prepare', 'activate', 'verify', 'rollback'):
            self.assertIsNone(driver.arguments([mode]).steam_tls_relay)
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                driver.arguments([mode, '--steam-tls-relay', '1'])
        for value in ('0', '1'):
            self.assertEqual(driver.arguments(['configure-transport', '--steam-tls-relay', value]).steam_tls_relay, value)
        for arguments in (['configure-transport'], ['configure-transport', '--steam-tls-relay', 'true']):
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                driver.arguments(arguments)

    def test_transport_environment_changes_only_one_assignment(self):
        raw = (b'PLAYER_WEB_AUTH_SECRET="retained-secret-test"\r\n'
               b'PLAYER_WEB_AUTH_UPSTREAM_BEARER="retained-upstream-test"\r\n'
               b'PLAYER_WEB_AUTH_STEAM_TLS_RELAY="0"\r\nPYTHONUNBUFFERED="1"\r\n')
        result, changed = operator.transport_environment(raw, '1')
        self.assertTrue(changed)
        self.assertEqual(result, raw.replace(b'PLAYER_WEB_AUTH_STEAM_TLS_RELAY="0"',
                                            b'PLAYER_WEB_AUTH_STEAM_TLS_RELAY="1"'))
        self.assertEqual(operator.transport_environment(result, '1'), (result, False))
        original = b'PLAYER_WEB_AUTH_SECRET="retained-secret-test"'
        self.assertEqual(operator.transport_environment(original, '0'), (original, False))
        appended, changed = operator.transport_environment(original, '1')
        self.assertEqual(appended, original + b'\nPLAYER_WEB_AUTH_STEAM_TLS_RELAY="1"\n')
        self.assertTrue(changed)

    def test_transport_environment_rejects_duplicates_invalid_existing_or_nonexplicit_input(self):
        cases = ((b'PLAYER_WEB_AUTH_STEAM_TLS_RELAY="0"\nPLAYER_WEB_AUTH_STEAM_TLS_RELAY="0"\n', '1'),
                 (b'PLAYER_WEB_AUTH_STEAM_TLS_RELAY="yes"\n', '1'), (b'', None), (b'', True), (b'', '2'))
        for raw, setting in cases:
            with self.assertRaises(RuntimeError):
                operator.transport_environment(raw, setting)

    def test_transport_configuration_requires_successful_rollback_before_any_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.dict(sys.modules, {'pwd': SimpleNamespace()}), patch.object(operator, 'OPS', Path(temporary)), \
                 patch.object(operator, 'STEAM_TLS_RELAY', '1'), patch.object(operator, 'prepared', return_value={}), \
                 patch.object(operator, 'unchanged'), patch.object(operator, 'activation_ready') as ready, \
                 patch.object(operator, 'replace') as replace, patch.object(operator, 'private') as private:
                with self.assertRaisesRegex(RuntimeError, 'successful_rollback_required_before_transport_change'):
                    operator.configure_transport()
            ready.assert_not_called()
            replace.assert_not_called()
            private.assert_not_called()

    def test_transport_environment_requires_private_root_group_permissions(self):
        for mode, uid, gid, valid in ((0o100640, 0, 123, True), (0o100644, 0, 123, False),
                                      (0o100640, 456, 123, False), (0o100640, 0, 456, False)):
            path = SimpleNamespace(stat=lambda: SimpleNamespace(st_mode=mode, st_uid=uid, st_gid=gid))
            if valid:
                operator.transport_environment_permissions(path, 123)
            else:
                with self.assertRaisesRegex(RuntimeError, 'transport_environment_permissions_invalid'):
                    operator.transport_environment_permissions(path, 123)

    def transport_candidate(self, *, fail_after_write=False, requested='1'):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        ops, config = root/'ops', root/'config'
        ops.mkdir();config.mkdir()
        before_env = b'PLAYER_WEB_AUTH_SECRET="retained-secret-test"\nPLAYER_WEB_AUTH_UPSTREAM_BEARER="retained-upstream-test"\n'
        (config/'auth.env').write_bytes(before_env)
        state = root/'auth.sqlite3'
        state.write_bytes(b'private-state-preserved')
        plan = {'env_sha256': operator.sha(before_env), 'files': {'player_web_auth/run.py': 'a'*64}}
        before_plan = json.dumps(plan).encode()
        (ops/'prepared.json').write_bytes(before_plan)
        (ops/'activation.json').write_text('{}')
        (ops/'rolled-back.json').write_text('{"ok":true}')
        count = [0]
        def check_prepared():
            count[0] += 1
            if fail_after_write and count[0] > 1:
                raise RuntimeError('prepared_source_changed')
            current = json.loads((ops/'prepared.json').read_bytes())
            self.assertEqual(current['env_sha256'], operator.sha((config/'auth.env').read_bytes()))
            return current
        def local_write(path, raw, **kwargs):
            path.write_bytes(raw)
        fake_pwd = SimpleNamespace(getpwnam=lambda name: SimpleNamespace(pw_gid=123))
        with patch.dict(sys.modules, {'pwd': fake_pwd}), patch.object(operator, 'OPS', ops), \
             patch.object(operator, 'CONFIG', config), patch.object(operator, 'STEAM_TLS_RELAY', requested), \
             patch.object(operator, 'prepared', side_effect=check_prepared), patch.object(operator, 'unchanged'), \
             patch.object(operator, 'transport_environment_permissions'), patch.object(operator, 'activation_ready') as ready, \
             patch.object(operator, 'private', side_effect=local_write), patch.object(operator, 'replace', side_effect=local_write) as replace, \
             patch.object(operator, 'run') as run:
            if fail_after_write:
                with self.assertRaises(operator.ConfigurationFailure) as caught:
                    operator.configure_transport()
                self.assertTrue(caught.exception.summary['configuration_restored'])
                result = caught.exception.summary
            else:
                result = operator.configure_transport()
        self.assertEqual(state.read_bytes(), b'private-state-preserved')
        run.assert_not_called()
        return ops, config, before_env, before_plan, result, replace.call_count, ready.call_count

    def test_transport_configuration_preserves_secrets_state_and_private_backup(self):
        ops, config, before_env, before_plan, result, writes, guards = self.transport_candidate()
        self.assertEqual(result['phase'], 'WEB_AUTH_TRANSPORT_CONFIGURED_NOT_STARTED')
        self.assertTrue(result['steam_tls_relay'])
        self.assertEqual((config/'auth.env').read_bytes(), before_env + b'PLAYER_WEB_AUTH_STEAM_TLS_RELAY="1"\n')
        backups = list(ops.glob('env-before-transport-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0]/'auth.env').read_bytes(), before_env)
        self.assertEqual((backups[0]/'prepared.json').read_bytes(), before_plan)
        self.assertEqual(guards, 2)
        self.assertEqual(writes, 2)
        self.assertNotIn('retained-secret-test', json.dumps(result))

    def test_transport_configuration_restores_both_files_after_failed_verification(self):
        ops, config, before_env, before_plan, result, writes, guards = self.transport_candidate(fail_after_write=True)
        self.assertEqual((config/'auth.env').read_bytes(), before_env)
        self.assertEqual((ops/'prepared.json').read_bytes(), before_plan)
        self.assertEqual(result['error'], 'prepared_source_changed')
        self.assertTrue(result['configuration_restored'])
        self.assertEqual(writes, 4)

    def test_default_direct_transport_noop_writes_nothing(self):
        ops, config, before_env, before_plan, result, writes, guards = self.transport_candidate(requested='0')
        self.assertEqual(result['phase'], 'WEB_AUTH_TRANSPORT_UNCHANGED')
        self.assertFalse(result['steam_tls_relay'])
        self.assertEqual(writes, 0)
        self.assertEqual(list(ops.glob('env-before-transport-*')), [])
        self.assertEqual((config/'auth.env').read_bytes(), before_env)
        self.assertEqual((ops/'prepared.json').read_bytes(), before_plan)


class RuntimeBundleChecks(unittest.TestCase):
    def payload(self):
        return {name: base64.b64encode(raw).decode('ascii') for name, raw in fixture_sources().items()}

    def test_fixed_runtime_lists_match_and_exclude_standalone_runner(self):
        self.assertEqual(driver.RUNTIME_SOURCES, operator.RUNTIME_SOURCES)
        self.assertEqual(len(operator.RUNTIME_SOURCES), 7)
        self.assertEqual(len(operator.LEGACY_SOURCES), 4)
        self.assertNotIn('lobby_backend/run.py', operator.RUNTIME_SOURCES)

    def test_collection_excludes_tests_private_files_and_unknown_directories(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, raw in fixture_sources().items():
                path = root/'server'/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            for name in ('lobby_backend/test_service.py', 'lobby_backend/private.py',
                         'lobby_backend/run.py', 'player_web_auth/private.env', 'unknown/server.py'):
                path = root/'server'/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'private fixture must never enter payload')
            with patch.object(driver, 'ROOT', root):
                self.assertEqual(set(driver.collect_sources()), operator.RUNTIME_SOURCES)

    def test_collection_rejects_each_missing_lobby_dependency(self):
        for missing in (operator.RUNTIME_SOURCES - operator.LEGACY_SOURCES):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                for name, raw in fixture_sources().items():
                    if name == missing:
                        continue
                    path = root/'server'/name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(raw)
                with patch.object(driver, 'ROOT', root), self.assertRaisesRegex(RuntimeError, 'source_incomplete'):
                    driver.collect_sources()

    def test_remote_requires_every_runtime_dependency(self):
        for missing in operator.RUNTIME_SOURCES:
            payload = self.payload()
            del payload[missing]
            with self.subTest(missing=missing), patch.object(operator, 'OVERLAY', payload, create=True), self.assertRaisesRegex(RuntimeError, 'web_source_incomplete'):
                operator.decoded_sources()

    def test_remote_rejects_unknown_paths_traversal_tests_and_private_sources(self):
        for name in ('other/run.py', 'lobby_backend/private.py', 'lobby_backend/run.py',
                     'lobby_backend/test_service.py', 'player_web_auth/subdir/run.py',
                     'player_web_auth/../lobby_backend/service.py', '../player_web_auth/run.py',
                     '/player_web_auth/run.py', 'player_web_auth\\run.py', 'lobby_backend/service.py/../x.py',
                     'player_web_auth//run.py', 'lobby_backend/README.md', ''):
            payload = self.payload()
            payload[name] = base64.b64encode(b'# not a runtime source\n').decode('ascii')
            with self.subTest(name=name), patch.object(operator, 'OVERLAY', payload, create=True), self.assertRaisesRegex(RuntimeError, 'web_source_path_invalid'):
                operator.decoded_sources()

    def test_exact_real_bundle_imports_with_lobby_default_off(self):
        payload = driver.collect_sources()
        with patch.object(operator, 'OVERLAY', payload, create=True):
            sources = operator.decoded_sources()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, raw in sources.items():
                path = root/name
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(raw)
            code = ('import sys;sys.path.insert(0,sys.argv[1]);'
                    'from player_web_auth.run import lobby_from_environment;'
                    'from player_web_auth.http_api import handler;'
                    'from lobby_backend.http_api import ROUTES;'
                    'from lobby_backend import LobbyService;'
                    'assert lobby_from_environment(None,{}) is None;'
                    'assert lobby_from_environment(None,{"PLAYER_WEB_AUTH_LOBBY_ENABLED":"0"}) is None;'
                    'assert "/v1/lobby/join" in ROUTES')
            result = subprocess.run([sys.executable, '-I', '-B', '-c', code, str(root)],
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr.decode('utf8', 'replace'))
            self.assertFalse(list(root.rglob('__pycache__')))

    def candidate(self, names):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        ops, release, config = root/'ops', root/'release', root/'config'
        for directory in (ops, release, config): directory.mkdir()
        sources = fixture_sources(b'# original runtime\n', names)
        for name, raw in sources.items():
            target = release/name
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(raw)
        env = b'PLAYER_WEB_AUTH_LOBBY_ENABLED="0"\nPRIVATE_TEST_VALUE="retained"\n'
        (config/'auth.env').write_bytes(env)
        (root/'private-state.sqlite3').write_bytes(b'unchanged private fixture')
        plan = {'release': str(release), 'files': {name: operator.sha(raw) for name, raw in sources.items()},
                'env_sha256': operator.sha(env)}
        for kind in ('nginx', 'pins'):
            for state in ('before', 'after'):
                raw = (kind+state).encode()
                (ops/(kind+'.'+state)).write_bytes(raw)
                plan[kind+'_'+state+'_sha256'] = operator.sha(raw)
        with patch.object(operator, 'RELEASE', release), patch.object(operator, 'CONFIG', config):
            (ops/'unit.candidate').write_bytes(operator.unit_source())
        (ops/'locations.candidate').write_bytes(operator.proxy_rules())
        before_plan = json.dumps(plan).encode()
        (ops/'prepared.json').write_bytes(before_plan)
        (ops/'activation.json').write_bytes(b'{}')
        (ops/'rolled-back.json').write_bytes(b'{"ok":true}')
        return SimpleNamespace(root=root, ops=ops, release=release, config=config, plan=plan,
                               env=env, sources=sources, before_plan=before_plan)

    def refresh(self, candidate, *, fail_after_write=False, concurrent_after_write=False, concurrent_before_write=False, concurrent_plan=False):
        original_prepared = operator.prepared
        calls = [0]
        def check_prepared():
            calls[0] += 1
            if calls[0] > 1 and fail_after_write:
                if concurrent_after_write:
                    (candidate.release/'player_web_auth/run.py').write_bytes(b'# administrator edit\n')
                raise RuntimeError('prepared_source_changed')
            return original_prepared()
        def private(path, raw, **kwargs):
            self.assertFalse(path.exists())
            path.write_bytes(raw)
            if concurrent_plan and path.name == 'prepared.json' and path.parent.name.startswith('source-before-refresh-'):
                (candidate.ops/'prepared.json').write_text(json.dumps({**candidate.plan, 'administrator_edit': True}))
        def ready(plan):
            if concurrent_before_write:
                (candidate.release/'player_web_auth/run.py').write_bytes(b'# administrator edit\n')
        fake_pwd = SimpleNamespace(getpwnam=lambda name: SimpleNamespace(pw_gid=123))
        with patch.dict(sys.modules, {'pwd': fake_pwd}), patch.object(operator, 'OPS', candidate.ops), \
             patch.object(operator, 'RELEASE', candidate.release), patch.object(operator, 'CONFIG', candidate.config), \
             patch.object(operator, 'prepared', side_effect=check_prepared), patch.object(operator, 'unchanged'), \
             patch.object(operator, 'decoded_sources', return_value=fixture_sources(b'# new runtime\n')), \
             patch.object(operator, 'activation_ready', side_effect=ready), patch.object(operator, 'private', side_effect=private), \
             patch.object(operator, 'replace', side_effect=lambda path, raw, **kwargs: path.write_bytes(raw)), \
             patch.object(operator.os, 'chown', create=True), patch.object(operator, 'run') as run:
            try:
                return operator.refresh_prepared()
            finally:
                run.assert_not_called()

    def test_stopped_legacy_migration_adds_exactly_three_files_and_preserves_backup(self):
        candidate = self.candidate(operator.LEGACY_SOURCES)
        result = self.refresh(candidate)
        self.assertTrue(result['previous_candidate_backup_preserved'])
        self.assertEqual(set(json.loads((candidate.ops/'prepared.json').read_bytes())['files']), operator.RUNTIME_SOURCES)
        self.assertEqual(set(p.relative_to(candidate.release).as_posix() for p in candidate.release.rglob('*.py')), operator.RUNTIME_SOURCES)
        backup, = candidate.ops.glob('source-before-refresh-*')
        self.assertEqual((backup/'prepared.json').read_bytes(), candidate.before_plan)
        for name, raw in candidate.sources.items(): self.assertEqual((backup/name).read_bytes(), raw)
        self.assertEqual((candidate.config/'auth.env').read_bytes(), candidate.env)
        self.assertEqual((candidate.root/'private-state.sqlite3').read_bytes(), b'unchanged private fixture')

    def test_failed_migration_restores_old_plan_code_and_removes_only_own_additions(self):
        candidate = self.candidate(operator.LEGACY_SOURCES)
        with self.assertRaisesRegex(RuntimeError, 'prepared_source_changed'):
            self.refresh(candidate, fail_after_write=True)
        self.assertEqual((candidate.ops/'prepared.json').read_bytes(), candidate.before_plan)
        for name, raw in candidate.sources.items(): self.assertEqual((candidate.release/name).read_bytes(), raw)
        self.assertFalse((candidate.release/'lobby_backend').exists())
        self.assertEqual((candidate.config/'auth.env').read_bytes(), candidate.env)

    def test_unknown_added_namespace_is_preserved_before_any_migration_write(self):
        candidate = self.candidate(operator.LEGACY_SOURCES)
        package = candidate.release/'lobby_backend'
        package.mkdir()
        (package/'private.txt').write_bytes(b'external fixture')
        with self.assertRaisesRegex(RuntimeError, 'source_added_namespace_exists'):
            self.refresh(candidate)
        self.assertEqual((package/'private.txt').read_bytes(), b'external fixture')
        self.assertEqual(list(candidate.ops.glob('source-before-refresh-*')), [])

    def test_compare_and_swap_rejects_concurrent_source_before_first_write(self):
        candidate = self.candidate(operator.LEGACY_SOURCES)
        with self.assertRaisesRegex(RuntimeError, 'prepared_source_changed'):
            self.refresh(candidate, concurrent_before_write=True)
        self.assertEqual((candidate.release/'player_web_auth/run.py').read_bytes(), b'# administrator edit\n')
        self.assertFalse((candidate.release/'lobby_backend').exists())
        self.assertEqual((candidate.ops/'prepared.json').read_bytes(), candidate.before_plan)

    def test_failed_refresh_never_overwrites_external_edit_during_restore(self):
        candidate = self.candidate(operator.RUNTIME_SOURCES)
        with self.assertRaisesRegex(RuntimeError, 'source_refresh_restore_conflict'):
            self.refresh(candidate, fail_after_write=True, concurrent_after_write=True)
        self.assertEqual((candidate.release/'player_web_auth/run.py').read_bytes(), b'# administrator edit\n')
        self.assertEqual((candidate.ops/'prepared.json').read_bytes(), candidate.before_plan)
        self.assertEqual((candidate.config/'auth.env').read_bytes(), candidate.env)

    def test_legacy_activation_requires_complete_new_runtime_before_any_action(self):
        with patch.dict(sys.modules, {'pwd': SimpleNamespace()}), \
             patch.object(operator, 'prepared', return_value={'files': fixture_sources(names=operator.LEGACY_SOURCES)}), \
             patch.object(operator, 'unchanged') as unchanged, patch.object(operator, 'run') as run, \
             patch.object(operator, 'private') as private, patch.object(operator, 'replace') as replace:
            with self.assertRaisesRegex(RuntimeError, 'prepared_source_incomplete'):
                operator.activate()
        for operation in (unchanged, run, private, replace): operation.assert_not_called()

    def test_prepared_plan_rejects_unknown_files_and_partial_new_package(self):
        candidate = self.candidate(operator.RUNTIME_SOURCES)
        for name in ('../private.py', 'lobby_backend/private.py', 'unknown/service.py', 'player_web_auth\\run.py'):
            changed = {**candidate.plan, 'files': {**candidate.plan['files'], name: 'a'*64}}
            (candidate.ops/'prepared.json').write_text(json.dumps(changed))
            with patch.object(operator, 'OPS', candidate.ops), patch.object(operator, 'RELEASE', candidate.release), \
                 patch.object(operator, 'CONFIG', candidate.config), self.assertRaisesRegex(RuntimeError, 'prepared_source_path_invalid'):
                operator.prepared()
        files = dict(candidate.plan['files'])
        del files['lobby_backend/service.py']
        (candidate.ops/'prepared.json').write_text(json.dumps({**candidate.plan, 'files': files}))
        with patch.object(operator, 'OPS', candidate.ops), patch.object(operator, 'RELEASE', candidate.release), \
             patch.object(operator, 'CONFIG', candidate.config), self.assertRaisesRegex(RuntimeError, 'prepared_source_incomplete'):
            operator.prepared()

    def test_prepared_runtime_hash_covers_lobby_dependencies(self):
        candidate = self.candidate(operator.RUNTIME_SOURCES)
        (candidate.release/'lobby_backend/service.py').write_bytes(b'# external dependency edit\n')
        with patch.object(operator, 'OPS', candidate.ops), patch.object(operator, 'RELEASE', candidate.release), \
             patch.object(operator, 'CONFIG', candidate.config), self.assertRaisesRegex(RuntimeError, 'prepared_source_changed'):
            operator.prepared()

    def test_plan_compare_and_swap_preserves_concurrent_administrator_plan(self):
        candidate = self.candidate(operator.LEGACY_SOURCES)
        with self.assertRaisesRegex(RuntimeError, 'prepared_plan_changed'):
            self.refresh(candidate, concurrent_plan=True)
        self.assertTrue(json.loads((candidate.ops/'prepared.json').read_bytes())['administrator_edit'])
        self.assertFalse((candidate.release/'lobby_backend').exists())
        for name, raw in candidate.sources.items(): self.assertEqual((candidate.release/name).read_bytes(), raw)

    def test_collector_rejects_a_symlink_in_fixed_runtime_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, raw in fixture_sources().items():
                path = root/'server'/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            target = root/'private_fixture.py'
            target.write_bytes(b'# never package this alias\n')
            link = root/'server/lobby_backend/service.py'
            link.unlink()
            try:
                link.symlink_to(target)
            except OSError:
                self.skipTest('symlink creation unavailable')
            with patch.object(driver, 'ROOT', root), self.assertRaisesRegex(RuntimeError, 'source_path_invalid'):
                driver.collect_sources()


if __name__ == '__main__':
    unittest.main()
