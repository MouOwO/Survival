"""Offline Windows PowerShell fixtures for the guest's native log collector."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
COLLECTOR = HERE / 'collect_join_network.ps1'
POWERSHELL = shutil.which('powershell.exe')
RUN_ID = '0123456789abcdef0123456789abcdef'
SERVER = '26.34.7.221:27015'
MAX_LOG_BYTES = 4 * 1024 * 1024


def iso(value: datetime) -> str:
    return value.isoformat(timespec='microseconds').replace('+00:00', 'Z')


def powershell_env() -> dict[str, str]:
    environment = os.environ.copy()
    system = Path(environment.get('SystemRoot', r'C:\Windows'))
    # Windows PowerShell must not inherit incompatible PowerShell 7 modules.
    environment['PSModulePath'] = ';'.join((str(system / 'System32/WindowsPowerShell/v1.0/Modules'),
        str(Path(environment.get('ProgramFiles', r'C:\Program Files')) / 'WindowsPowerShell/Modules')))
    return environment


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'Windows PowerShell is required')
class NetworkCaptureChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix='ws4_network_fixture_')
        self.root = Path(self.temporary.name)
        self.game = self.root / 'game'
        self.logs = self.game / 'dota'
        self.logs.mkdir(parents=True)
        self.context_file = self.root / 'join_network_context.json'
        self.started = datetime.now(timezone.utc) - timedelta(seconds=10)
        self.context = dict(schema=1, kind='WS4-NETWORK-CAPTURE', revision='WS4-JOIN-08',
            run_id=RUN_ID, game_path=str(self.game), server=SERVER, started_utc=iso(self.started),
            dedicated_file=f'ws4_join_{RUN_ID}.log', fallback_start_bytes=0,
            fallback_existed=False, fallback_last_write_utc=None)
        self.junctions: list[Path] = []

    def tearDown(self) -> None:
        # Nonrecursive junction removal keeps TemporaryDirectory cleanup within
        # this fixture. All link targets are also verified below to be local.
        for link in reversed(self.junctions):
            if os.path.lexists(link):
                os.rmdir(link)
        self.temporary.cleanup()

    def write_context(self) -> None:
        self.context_file.write_text(json.dumps(self.context), encoding='utf-8')

    def collect(self, *, expected_exit: int = 0, context_file: Path | None = None) -> tuple[dict, str]:
        self.write_context()
        result = subprocess.run([POWERSHELL, '-NoLogo', '-NoProfile', '-NonInteractive',
            '-ExecutionPolicy', 'Bypass', '-File', str(COLLECTOR), '-ContextPath',
            str(context_file or self.context_file)], capture_output=True,
            env=powershell_env(), timeout=30)
        output = result.stdout.decode('utf-8-sig', errors='replace')
        self.assertEqual(result.returncode, expected_exit,
            output + result.stderr.decode('utf-8-sig', errors='replace'))
        lines = [value for value in output.splitlines() if value.startswith('{')]
        self.assertTrue(lines, output)
        return json.loads(lines[-1]), output

    def old_fallback(self, content: bytes) -> Path:
        fallback = self.logs / 'console.log'
        fallback.write_bytes(content)
        previous = self.started - timedelta(seconds=60)
        os.utime(fallback, (previous.timestamp(), previous.timestamp()))
        self.context.update(fallback_start_bytes=len(content), fallback_existed=True,
            fallback_last_write_utc=iso(previous))
        return fallback

    def make_junction(self, link: Path, target: Path) -> None:
        self.assertTrue(target.resolve().is_relative_to(self.root.resolve()))
        quote = lambda value: "'" + str(value).replace("'", "''") + "'"
        command = f"New-Item -ItemType Junction -Path {quote(link)} -Target {quote(target)} | Out-Null"
        result = subprocess.run([POWERSHELL, '-NoLogo', '-NoProfile', '-NonInteractive',
            '-Command', command], capture_output=True, env=powershell_env(), timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        self.junctions.append(link)

    def test_fresh_dedicated_log_extracts_only_fixed_native_evidence(self) -> None:
        private = 'PRIVATE_FIXTURE_MUST_NOT_ESCAPE_76561199999999999'
        raw = '\n'.join((
            f'[Networking] Connecting to {SERVER}',
            '[NetSteamConn] [#123 UDP 26.34.7.221:27015] Connection closed, reason 5003: NETWORK_DISCONNECT_STEAM_AUTHINVALID',
            'CL: Mismatch addon survival_ws4_local CRC date: Client=123 Server=456',
            '[Client] protocol version mismatch',
            '[Client] Connection closed, reason 42: NETWORK_DISCONNECT_DIRECT_CONNECT_RESERVATION',
            '[Client] map template_map: invalid map name',
            '[Client] Connection timed out NETWORK_DISCONNECT_REMOTE_TIMEOUT',
            f'[Client] say {private} NETWORK_DISCONNECT_REJECT_SERVERFULL reason 999',
            json.dumps({'chat': 'NETWORK_DISCONNECT_REJECT_SERVERFULL', 'private': private}),
            f'[Networking] {{"chat":"{private}","text":"NETWORK_DISCONNECT_REJECT_SERVERFULL"}}',
            f'unrelated private content {private}', ''))
        (self.logs / self.context['dedicated_file']).write_text(raw, encoding='utf-8')
        report, output = self.collect()
        self.assertTrue(report['ok'])
        self.assertTrue(report['fresh'])
        self.assertEqual(report['log_source'], 'dedicated')
        self.assertTrue(report['expected_target_seen'])
        self.assertEqual(report['disconnect_codes'], ['NETWORK_DISCONNECT_DIRECT_CONNECT_RESERVATION',
            'NETWORK_DISCONNECT_REMOTE_TIMEOUT', 'NETWORK_DISCONNECT_STEAM_AUTHINVALID'])
        self.assertEqual(report['reason_numbers'], [42, 5003])
        self.assertEqual(set(report['categories']), {'addon_crc_mismatch', 'version_mismatch',
            'steam_authentication', 'lobby_reservation', 'map_missing', 'timeout'})
        saved = (self.root / 'join_network_diagnostic.json').read_text(encoding='utf-8')
        self.assertEqual(json.loads(saved), report)
        for secret in (private, str(self.game), 'NETWORK_DISCONNECT_REJECT_SERVERFULL'):
            self.assertNotIn(secret, saved + output)

    def test_fallback_reads_new_bytes_and_ignores_old_disconnect(self) -> None:
        fallback = self.old_fallback(b'[Client] NETWORK_DISCONNECT_REJECT_SERVERFULL reason 999\n')
        addition = (f'[Networking] Connecting to {SERVER}\n'
            '[Client] Connection closed, reason 4004: NETWORK_DISCONNECT_REMOTE_BADCRYPT\n').encode()
        with fallback.open('ab') as stream:
            stream.write(addition)
        report, _ = self.collect()
        self.assertEqual(report['bytes'], len(addition))
        self.assertTrue(report['fresh'])
        self.assertEqual(report['log_source'], 'console_increment')
        self.assertEqual(report['disconnect_codes'], ['NETWORK_DISCONNECT_REMOTE_BADCRYPT'])
        self.assertEqual(report['reason_numbers'], [4004])
        self.assertNotIn('server_full', report['categories'])

    def test_actual_month_day_native_timestamps_and_parenthesized_reasons(self) -> None:
        raw = '\n'.join((
            '10/23 22:04:06 [Client] Disconnecting from server: NETWORK_DISCONNECT_LOOPSHUTDOWN',
            "10/23 22:04:06 [NetSteamConn] Closing Steam Net Connection on socket 'client' to loopback:1, handle #1126613539 (2054 NETWORK_DISCONNECT_LOOPSHUTDOWN)",
            "10/23 22:04:06 [SteamNetSockets] [#1126613539 pipe 'server'] closed by app, linger requested but not needed (2054) NETWORK_DISCONNECT_LOOPSHUTDOWN",
            '10/23 22:04:06 [Client] say PRIVATE_TIMESTAMP_CHAT NETWORK_DISCONNECT_STEAM_TICKET (999)',
            '10/23 22:04:06 [Client] {"chat":"NETWORK_DISCONNECT_STEAM_TICKET", "reason":777}',
            ''))
        (self.logs / self.context['dedicated_file']).write_text(raw, encoding='utf-8')
        report, output = self.collect()
        self.assertEqual(report['disconnect_codes'], ['NETWORK_DISCONNECT_LOOPSHUTDOWN'])
        self.assertEqual(report['reason_numbers'], [2054])
        self.assertEqual(report['counts']['disconnect_codes'], 3)
        self.assertNotIn('1126613539', output)
        self.assertNotIn('PRIVATE_TIMESTAMP_CHAT', output)

    def test_bom_only_dedicated_log_falls_back_to_new_console_bytes(self) -> None:
        fallback = self.old_fallback(b'OLD PRIVATE FIXTURE\n')
        addition = b'[Client] NETWORK_DISCONNECT_CONNECTION_FAILURE\n'
        with fallback.open('ab') as stream:
            stream.write(addition)
        (self.logs / self.context['dedicated_file']).write_bytes(b'\xef\xbb\xbf')
        report, _ = self.collect()
        self.assertEqual(report['log_source'], 'console_increment')
        self.assertEqual(report['bytes'], len(addition))
        self.assertTrue(report['ok'])
        self.assertEqual(report['disconnect_codes'], ['NETWORK_DISCONNECT_CONNECTION_FAILURE'])

    def test_missing_empty_or_unchanged_logs_keep_reason_unknown(self) -> None:
        report, _ = self.collect()
        self.assertFalse(report['ok'])
        self.assertFalse(report['fresh'])
        self.assertEqual(report['status'], 'log_not_created')
        (self.logs / self.context['dedicated_file']).write_bytes(b'\xef\xbb\xbf')
        report, _ = self.collect()
        self.assertFalse(report['ok'])
        self.assertEqual(report['bytes'], 0)
        fallback = self.old_fallback(b'[Client] NETWORK_DISCONNECT_STEAM_TICKET\n')
        report, _ = self.collect()
        self.assertFalse(report['fresh'])
        self.assertEqual(report['status'], 'no_new_log_bytes')
        self.assertEqual(report['bytes'], 0)
        self.assertEqual(report['disconnect_codes'], [])
        self.assertEqual(fallback.read_bytes(), b'[Client] NETWORK_DISCONNECT_STEAM_TICKET\n')

    def test_truncated_or_stale_fallback_is_not_reinterpreted_as_new(self) -> None:
        fallback = self.old_fallback(b'[Client] NETWORK_DISCONNECT_STEAM_TICKET\n' * 10)
        fallback.write_bytes(b'[Client] NETWORK_DISCONNECT_REJECT_SERVERFULL\n')
        report, _ = self.collect()
        self.assertEqual(report['status'], 'fallback_truncated')
        self.assertTrue(report['truncated'])
        self.assertEqual(report['bytes'], 0)
        self.assertFalse(report['ok'])
        self.assertEqual(report['disconnect_codes'], [])
        fallback = self.old_fallback(b'old\n')
        with fallback.open('ab') as stream:
            stream.write(b'[Client] NETWORK_DISCONNECT_STEAM_TICKET\n')
        stale = self.started - timedelta(seconds=30)
        os.utime(fallback, (stale.timestamp(), stale.timestamp()))
        report, _ = self.collect()
        self.assertEqual(report['status'], 'log_not_fresh')
        self.assertFalse(report['fresh'])
        self.assertEqual(report['bytes'], 0)

    def test_tail_bound_unknown_code_and_oversized_line_are_safe(self) -> None:
        unknown = 'NETWORK_DISCONNECT_PRIVATE_FIXTURE_SECRET'
        raw = b'x' * (MAX_LOG_BYTES + 100) + b'\n'
        raw += ('[Client] ' + 'x' * 20000 + ' NETWORK_DISCONNECT_STEAM_TICKET\n').encode()
        raw += (f'[Client] {unknown}\n'
            f'{{"chat":"NETWORK_DISCONNECT_REJECT_SERVERFULL","server":"{SERVER}"}}\n').encode()
        (self.logs / self.context['dedicated_file']).write_bytes(raw)
        report, output = self.collect()
        self.assertLessEqual(report['bytes'], MAX_LOG_BYTES)
        self.assertTrue(report['truncated'])
        self.assertEqual(report['status'], 'reason_unknown')
        self.assertEqual(report['disconnect_codes'], [])
        self.assertEqual(report['categories'], [])
        self.assertFalse(report['expected_target_seen'])
        self.assertEqual(report['counts']['oversized_lines'], 1)
        self.assertNotIn(unknown, output)

    def test_context_rejects_unknown_fields_traversal_and_oversize(self) -> None:
        for changes in ({'unexpected_secret': 'PRIVATE_CONTEXT_SECRET'},
            {'dedicated_file': '../console.log'}, {'server': SERVER + '\nquit'},
            {'game_path': str(self.game / '..' / 'game')}):
            with self.subTest(changes=tuple(changes)):
                original = dict(self.context)
                self.context.update(changes)
                report, output = self.collect(expected_exit=1)
                self.assertEqual(report['error'], 'network_context_invalid' if 'game_path' not in changes else 'network_path_invalid')
                self.assertNotIn('PRIVATE_CONTEXT_SECRET', output)
                self.context = original
        self.context['unexpected_secret'] = 'x' * 70000
        report, _ = self.collect(expected_exit=1)
        self.assertEqual(report['error'], 'network_context_too_large')

    def test_context_ancestor_and_log_directory_junctions_are_rejected(self) -> None:
        self.write_context()
        context_link = self.root / 'context_link'
        self.make_junction(context_link, self.root)
        report, _ = self.collect(expected_exit=1, context_file=context_link / self.context_file.name)
        self.assertEqual(report['error'], 'network_linked_path')
        real_logs = self.game / 'real_logs'
        real_logs.mkdir()
        self.logs.rmdir()
        self.make_junction(self.logs, real_logs)
        (real_logs / self.context['dedicated_file']).write_text('[Client] NETWORK_DISCONNECT_STEAM_TICKET\n')
        report, _ = self.collect(expected_exit=1)
        self.assertEqual(report['error'], 'network_linked_path')

    def test_cmd_entry_is_ascii_crlf_and_pauses(self) -> None:
        raw = (HERE / 'collect_network.cmd').read_bytes()
        raw.decode('ascii')
        self.assertIn(b'powershell.exe -NoLogo -NoProfile', raw)
        self.assertIn(b'collect_join_network.ps1', raw)
        self.assertIn(b'pause\r\n', raw)
        self.assertEqual(raw.count(b'\n'), raw.count(b'\r\n'))


if __name__ == '__main__':
    unittest.main()
