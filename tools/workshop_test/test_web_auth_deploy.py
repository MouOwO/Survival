"""Deployment boundary checks; no SSH, network, services or databases touched."""
import base64
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import deploy_web_auth as driver
import remote_web_auth as operator


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
            (release/'player_web_auth').mkdir()
            source = b'# reviewed source\n'
            (release/'player_web_auth/run.py').write_bytes(source)
            (config/'auth.env').write_bytes(b'private')
            plan = {'release': str(release), 'env_sha256': operator.sha(b'private'),
                    'files': {'player_web_auth/run.py': operator.sha(source)}}
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
        self.assertIn('player_web_auth/run.py', payload)
        for name, encoded in payload.items():
            self.assertTrue(name.startswith('player_web_auth/'))
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
            sources = {'player_web_auth/run.py': b'# revised candidate\n'}
            plan = {'files': {'player_web_auth/run.py': operator.sha(b'# original candidate\n')}}
            with patch.dict(sys.modules, {'pwd': SimpleNamespace()}), \
                 patch.object(operator, 'OPS', Path(temporary)), patch.object(operator, 'prepared', return_value=plan), \
                 patch.object(operator, 'unchanged'), patch.object(operator, 'decoded_sources', return_value=sources), \
                 patch.object(operator, 'replace') as replace, patch.object(operator, 'private') as private:
                with self.assertRaisesRegex(RuntimeError, 'successful_rollback_required_before_refresh'):
                    operator.refresh_prepared()
            replace.assert_not_called()
            private.assert_not_called()


if __name__ == '__main__':
    unittest.main()
