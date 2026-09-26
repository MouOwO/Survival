from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


HELPER_FIXTURE = r'''
import json, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
scenario = json.loads((root / 'scenario.json').read_text())
events = root / 'events.txt'
name = Path(__file__).name
action = sys.argv[1]
if name == 'aliyun_test_connection.py':
    event, result = 'tunnel:' + action, {'ok': True}
elif name == 'aliyun_game_test_auth.py':
    event, result = 'auth:' + action, {'ok': True}
elif name == 'aliyun_lan_probe.py':
    previous = events.read_text() if events.exists() else ''
    index = sum(line.startswith('roster:') for line in previous.splitlines())
    choices = scenario['rosters']
    result = choices[min(index, len(choices) - 1)]
    event = 'roster:' + str(result.get('players', result.get('error', 'unknown')))
else:
    raise SystemExit('Unexpected fixture helper')
with events.open('a', encoding='ascii') as out:
    out.write(event + '\n')
print(json.dumps(result))
raise SystemExit(0 if result.get('ok') else 1)
'''

HARNESS_FIXTURE = r'''
$ErrorActionPreference = 'Stop'
$global:GoufayuFixtureScenario = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'scenario.json') -Raw | ConvertFrom-Json
function Record-Event([string]$Value) {
    Add-Content -LiteralPath (Join-Path $PSScriptRoot 'events.txt') -Value $Value -Encoding Ascii
}
function Get-Process {
    [CmdletBinding()]param([string]$Name)
    if ($Name -ne 'dota2') { throw 'Unexpected process query' }
    Record-Event 'process:get'
    if ($global:GoufayuFixtureScenario.game_running) { return [pscustomobject]@{Id=12345} }
}
function Start-Process {
    param($FilePath, $WorkingDirectory, $WindowStyle, $ArgumentList)
    if ($FilePath -notlike '*dota2.exe' -or $WindowStyle -ne 'Normal') { throw 'Unexpected launch' }
    Record-Event 'game:start'
}
function Start-Sleep {
    param($Seconds)
    Record-Event ('sleep:' + $Seconds)
}
function Stop-Process { throw 'A game or helper was unexpectedly killed' }
function Stop-ScheduledTask { throw 'A task was unexpectedly killed' }
try {
    & (Join-Path $PSScriptRoot 'tools/launch_aliyun_test_game.ps1') -ExpectedPlayers $global:GoufayuFixtureScenario.expected -WaitSeconds 10 -JoinWaitSeconds 10
} catch {
    Write-Output ('FIXTURE_ERROR: ' + $_.Exception.Message)
    exit 31
}
'''

BRIDGE_FIXTURE = r'''
param([string]$Action)
if ($Action -ne 'Stop') { throw 'Unexpected bridge action' }
Record-Event ('bridge:' + $Action)
if ($global:GoufayuFixtureScenario.stop_failure -eq 'throw') { throw 'Fixture graceful stop failed' }
if ($global:GoufayuFixtureScenario.stop_failure -eq 'exit') { $global:LASTEXITCODE = 1; return }
$global:LASTEXITCODE = 0
Write-Output 'HAMMER_BACKEND_STOPPED: fixture only'
'''


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell launcher behavior')
class LaunchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runtime = tempfile.TemporaryDirectory(prefix='goufayu launcher Python ')
        cls.venv = Path(cls.runtime.name) / 'venv'
        created = subprocess.run(
            [sys._base_executable, '-m', 'venv', '--without-pip', str(cls.venv)],
            capture_output=True, timeout=60, creationflags=subprocess.CREATE_NO_WINDOW)
        if created.returncode:
            cls.runtime.cleanup()
            raise AssertionError(created.stderr.decode('utf-8', 'replace'))
        cls.powershell = Path(os.environ.get('SystemRoot', 'C:/Windows')) / 'System32/WindowsPowerShell/v1.0/powershell.exe'

    @classmethod
    def tearDownClass(cls):
        cls.runtime.cleanup()

    def run_launcher(self, **scenario):
        source = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(prefix='goufayu LAN fixture ') as folder:
            # Match the real game/dota_addons/survival layout and space-bearing paths.
            engine = Path(folder) / 'game'
            root = engine / 'dota_addons/survival'
            tools = root / 'tools'
            tools.mkdir(parents=True)
            shutil.copyfile(source / 'launch_aliyun_test_game.ps1', tools / 'launch_aliyun_test_game.ps1')
            shutil.copyfile(source / 'backend_python.ps1', tools / 'backend_python.ps1')
            shutil.copytree(self.venv, root / 'output/ecs_backend_work/.venv')
            (root / 'maps').mkdir()
            (root / 'maps/template_map.vpk').touch()
            (engine / 'bin/win64').mkdir(parents=True)
            (engine / 'bin/win64/dota2.exe').touch()
            (engine / 'dota').mkdir()
            defaults = dict(expected=2, game_running=False, stop_failure='',
                            rosters=[{'ok': True, 'status': 'waiting_players', 'players': 2}])
            defaults.update(scenario)
            (root / 'scenario.json').write_text(json.dumps(defaults), encoding='utf-8')
            (root / 'launch-test.ps1').write_text(HARNESS_FIXTURE, encoding='utf-8')
            (tools / 'setup_hammer_backend.ps1').write_text(BRIDGE_FIXTURE, encoding='utf-8')
            for helper in ('aliyun_test_connection.py', 'aliyun_game_test_auth.py', 'aliyun_lan_probe.py'):
                (tools / helper).write_text(HELPER_FIXTURE, encoding='utf-8')
            run = subprocess.run(
                [str(self.powershell), '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                 '-File', str(root / 'launch-test.ps1')],
                capture_output=True, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
            output = (run.stdout + run.stderr).decode('utf-8', 'replace')
            events = root / 'events.txt'
            return run.returncode, output, events.read_text().splitlines() if events.exists() else []

    def test_bridge_stops_before_tunnel_and_game_and_waits_for_all_players(self):
        code, output, events = self.run_launcher(rosters=[
            {'ok': True, 'status': 'waiting_players', 'players': 1},
            {'ok': True, 'status': 'waiting_players', 'players': 2},
        ])
        self.assertEqual(code, 0, output)
        self.assertEqual(events, ['bridge:Stop', 'tunnel:connect', 'process:get', 'game:start',
                                  'auth:probe', 'roster:1', 'sleep:2', 'roster:2', 'auth:inject'])
        self.assertIn('HAMMER_BACKEND_PAUSED_FOR_LAN', output)
        self.assertIn('-Action Start', output)
        self.assertIn('LAN_PLAYERS: 1/2', output)
        self.assertIn('LAN_PLAYERS: 2/2', output)
        self.assertIn('GAME_AUTH_READY', output)

    def test_stop_failure_aborts_before_network_game_and_credentials(self):
        for failure in ('throw', 'exit'):
            with self.subTest(failure=failure):
                code, output, events = self.run_launcher(stop_failure=failure)
                self.assertEqual(code, 31, output)
                self.assertEqual(events, ['bridge:Stop'])
                self.assertIn('HAMMER_BACKEND_PAUSE_FAILED', output)
                self.assertNotIn('GAME_AUTH_READY', output)

    def test_already_authenticated_or_released_session_is_preserved(self):
        error = 'lan_session_already_authenticated_restart_without_bridge'
        for reason, message in (
                ('credential_already_present', 'backend credential configured'),
                ('admission_already_released', 'loading/admission gate'),
                ('session_already_configured_or_released', 'configured or released')):
            with self.subTest(reason=reason):
                code, output, events = self.run_launcher(game_running=True, rosters=[
                    {'ok': False, 'error': error, 'reason': reason},
                ])
                self.assertEqual(code, 31, output)
                self.assertEqual(events, ['bridge:Stop', 'tunnel:connect', 'process:get',
                                          'auth:probe', 'roster:' + error])
                self.assertIn(message, output)
                self.assertIn('Fully exit the current Dota 2 game', output)
                self.assertIn('launch_aliyun_lan_host.cmd', output)
                self.assertNotIn('GAME_AUTH_READY', output)

    def test_single_player_does_not_pause_bridge_or_check_lan_roster(self):
        code, output, events = self.run_launcher(expected=1, game_running=True)
        self.assertEqual(code, 0, output)
        self.assertEqual(events, ['tunnel:connect', 'process:get', 'auth:probe', 'auth:inject'])
        self.assertIn('GAME_AUTH_READY', output)
        self.assertNotIn('HAMMER_BACKEND_PAUSED_FOR_LAN', output)

    def test_gate_not_ready_does_not_authenticate_even_with_enough_players(self):
        code, output, events = self.run_launcher(game_running=True, rosters=[
            {'ok': True, 'status': 'gate_not_ready', 'players': 2},
            {'ok': True, 'status': 'waiting_players', 'players': 2},
        ])
        self.assertEqual(code, 0, output)
        self.assertEqual(events, ['bridge:Stop', 'tunnel:connect', 'process:get', 'auth:probe',
                                  'roster:2', 'sleep:2', 'roster:2', 'auth:inject'])


if __name__ == '__main__':
    unittest.main()
