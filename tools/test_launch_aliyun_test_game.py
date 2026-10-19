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
    event, result = 'tunnel:' + action, scenario.get('tunnel', {'ok': True})
elif name == 'aliyun_game_test_auth.py':
    event, result = 'auth:' + action, {'ok': True}
    if action == 'probe':
        previous = events.read_text() if events.exists() else ''
        index = previous.splitlines().count('auth:probe')
        choices = scenario.get('probes', [{'ok': True}])
        result = choices[min(index, len(choices) - 1)]
    elif action == 'inject':
        result = scenario.get('inject', {'ok': True})
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
    $eventsFile = Join-Path $PSScriptRoot 'events.txt'
    $previous = if (Test-Path -LiteralPath $eventsFile) { @(Get-Content -LiteralPath $eventsFile) } else { @() }
    Record-Event 'process:get'
    if ($global:GoufayuFixtureScenario.game_exited_while_waiting -and $previous -contains 'auth:probe') { return }
    if ($global:GoufayuFixtureScenario.game_running -or $previous -contains 'game:start') { return [pscustomobject]@{Id=12345} }
}
function Start-Process {
    param($FilePath, $WorkingDirectory, $WindowStyle, $ArgumentList)
    if ($WindowStyle -eq 'Hidden' -and ($ArgumentList -join ' ') -like '*run_hammer_backend.ps1*') {
        Record-Event 'helper:start'
        if ($global:GoufayuFixtureScenario.resume_failure) { throw 'Fixture standalone resume failed' }
        $global:GoufayuFixtureStandaloneRestored = $true
        return
    }
    if ($FilePath -notlike '*dota2.exe' -or $WindowStyle -ne 'Normal') { throw 'Unexpected launch' }
    Record-Event 'game:start'
}
function Start-Sleep {
    param($Seconds, $Milliseconds)
    if ($Milliseconds) { Record-Event ('sleep-ms:' + $Milliseconds) }
    else { Record-Event ('sleep:' + $Seconds) }
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
param([string]$Action, [switch]$AsJson)
Record-Event ('bridge:' + $Action)
$stopFile = Join-Path $PSScriptRoot '../output/hammer_backend/bridge.stop'
switch ($Action) {
    'Status' {
        if (-not $AsJson) { throw 'Fixture expects JSON status' }
        if ($global:GoufayuFixtureScenario.status_failure) { throw 'Fixture status failed' }
        if ($global:GoufayuFixtureResumeRequested) {
            $global:GoufayuFixtureResumeStatusChecks++
            if ($global:GoufayuFixtureScenario.resume_status_failure_after_unready -and
                $global:GoufayuFixtureResumeStatusChecks -gt 1) {
                throw 'Fixture restored status unavailable after missing heartbeat'
            }
        }
        $previous = $global:GoufayuFixtureScenario.bridge_status
        $state = [pscustomobject]@{ok=$true; task_installed=$previous.task_installed;
            task_state=$previous.task_state; task_enabled=$previous.task_enabled;
            helper_running=$previous.helper_running; helper_status=$previous.helper_status}
        if ($global:GoufayuFixtureStopped) {
            if ($state.task_installed) { $state.task_enabled=$false; $state.task_state='Disabled' }
            $state.helper_running=$false; $state.helper_status='stopped'
        }
        if ($global:GoufayuFixtureScheduledRestored) {
            $state.task_enabled=$true; $state.task_state='Running'
            $state.helper_running=$true; $state.helper_status='connected'
        }
        if ($global:GoufayuFixtureStandaloneRestored) {
            $state.helper_running=$true; $state.helper_status='connected'
        }
        $state | ConvertTo-Json -Compress
        return
    }
    'Stop' {
        $global:GoufayuFixtureStopped = $true
        New-Item -ItemType Directory -Path (Split-Path -Parent $stopFile) -Force | Out-Null
        $marker = if ($global:GoufayuFixtureScenario.stop_marker_invalid) { 'unrelated-data' } else { 'stop' }
        Set-Content -LiteralPath $stopFile -Value $marker -Encoding Ascii
        if ($global:GoufayuFixtureScenario.stop_failure -eq 'throw') { throw 'Fixture graceful stop failed' }
        if ($global:GoufayuFixtureScenario.stop_failure -eq 'exit') { $global:LASTEXITCODE = 1; return }
        $global:LASTEXITCODE = 0
        Write-Output 'HAMMER_BACKEND_STOPPED: fixture only'
        return
    }
    'Start' {
        if ($global:GoufayuFixtureScenario.resume_failure -eq 'throw') { throw 'Fixture resume failed' }
        if ($global:GoufayuFixtureScenario.resume_failure -eq 'exit') { $global:LASTEXITCODE = 1; return }
        $global:GoufayuFixtureResumeRequested = $true
        $global:GoufayuFixtureScheduledRestored = -not $global:GoufayuFixtureScenario.resume_no_heartbeat
        Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
        Write-Output 'HAMMER_BACKEND_START_REQUESTED: fixture only'
        return
    }
    default { throw 'Unexpected bridge action' }
}
'''

ACTIVE_BRIDGE = dict(task_installed=True, task_state='Running', task_enabled=True,
                     helper_running=True, helper_status='connected')
IDLE_BRIDGE = dict(task_installed=False, task_state='not_installed', task_enabled=False,
                   helper_running=False, helper_status='not_started')


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
                            bridge_status=IDLE_BRIDGE,
                            rosters=[{'ok': True, 'status': 'waiting_players', 'players': 2}])
            defaults.update(scenario)
            (root / 'scenario.json').write_text(json.dumps(defaults), encoding='utf-8')
            (root / 'launch-test.ps1').write_text(HARNESS_FIXTURE, encoding='utf-8')
            (tools / 'setup_hammer_backend.ps1').write_text(BRIDGE_FIXTURE, encoding='utf-8')
            (tools / 'run_hammer_backend.ps1').touch()
            for helper in ('aliyun_test_connection.py', 'aliyun_game_test_auth.py', 'aliyun_lan_probe.py'):
                (tools / helper).write_text(HELPER_FIXTURE, encoding='utf-8')
            run = subprocess.run(
                [str(self.powershell), '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                 '-File', str(root / 'launch-test.ps1')],
                capture_output=True, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
            output = (run.stdout + run.stderr).decode('utf-8', 'replace')
            events = root / 'events.txt'
            if scenario.get('stop_marker_invalid'):
                self.assertTrue((root / 'output/hammer_backend/bridge.stop').exists())
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

    def test_single_player_preserves_idle_disabled_or_uninstalled_helper(self):
        for status in (IDLE_BRIDGE,
                       dict(IDLE_BRIDGE, task_installed=True, task_state='Disabled'),
                       dict(IDLE_BRIDGE, task_installed=True, task_state='Running'),
                       dict(IDLE_BRIDGE, task_installed=True, task_state='Queued'),
                       dict(IDLE_BRIDGE, task_state='Running', task_enabled=True),
                       dict(IDLE_BRIDGE, task_state='Queued', task_enabled=True),
                       dict(IDLE_BRIDGE, task_installed=True, task_state='Ready', task_enabled=True)):
            with self.subTest(status=status):
                code, output, events = self.run_launcher(expected=1, game_running=True, bridge_status=status)
                self.assertEqual(code, 0, output)
                self.assertEqual(events, ['tunnel:connect', 'bridge:Status', 'process:get', 'auth:probe', 'auth:inject'])
                self.assertIn('GAME_AUTH_READY', output)
                self.assertNotIn('HAMMER_BACKEND_PAUSED_FOR_LAN', output)
                self.assertNotIn('bridge:Start', events)

    def test_single_player_pauses_active_owned_task_before_console_and_resumes_after_injection(self):
        for status in (ACTIVE_BRIDGE,
                       dict(ACTIVE_BRIDGE, helper_running=False, helper_status='not_started'),
                       dict(ACTIVE_BRIDGE, task_state='Queued', helper_running=False, helper_status='not_started')):
            with self.subTest(status=status):
                code, output, events = self.run_launcher(expected=1, game_running=True, bridge_status=status)
                self.assertEqual(code, 0, output)
                self.assertEqual(events, ['tunnel:connect', 'bridge:Status', 'bridge:Stop', 'process:get',
                                          'auth:probe', 'auth:inject', 'bridge:Start', 'bridge:Status'])
                self.assertIn('HAMMER_BACKEND_PAUSED_FOR_AUTH', output)
                self.assertIn('HAMMER_BACKEND_RESUMED', output)
                self.assertNotIn('game:start', events)

    def test_single_player_restores_active_helper_after_probe_or_authentication_failure(self):
        for failure in ('probe', 'inject'):
            with self.subTest(failure=failure):
                scenario = {'probes': [{'ok': False, 'error': 'fixture_probe_failed'}]} if failure == 'probe' else {
                    'inject': {'ok': False, 'error': 'tools_auth_recovery_failed'}}
                code, output, events = self.run_launcher(
                    expected=1, game_running=True, bridge_status=ACTIVE_BRIDGE, **scenario)
                self.assertEqual(code, 31, output)
                self.assertEqual(events[-2:], ['bridge:Start', 'bridge:Status'])
                self.assertIn('HAMMER_BACKEND_RESUMED', output)
                self.assertNotIn('GAME_AUTH_READY', output)
                self.assertLessEqual(events.count('auth:inject'), 1)

    def test_single_player_pause_failure_blocks_game_and_credentials_and_restores_partial_stop(self):
        for failure in ('throw', 'exit'):
            with self.subTest(failure=failure):
                code, output, events = self.run_launcher(
                    expected=1, bridge_status=ACTIVE_BRIDGE, stop_failure=failure)
                self.assertEqual(code, 31, output)
                self.assertEqual(events, ['tunnel:connect', 'bridge:Status', 'bridge:Stop', 'bridge:Start', 'bridge:Status'])
                self.assertIn('HAMMER_BACKEND_PAUSE_FAILED', output)
                self.assertIn('HAMMER_BACKEND_RESUMED', output)

    def test_restore_failure_is_explicit_and_preserves_original_authentication_error(self):
        for failure in ('throw', 'exit'):
            with self.subTest(failure=failure):
                code, output, events = self.run_launcher(
                    expected=1, game_running=True, bridge_status=ACTIVE_BRIDGE, resume_failure=failure,
                    inject={'ok': False, 'error': 'tools_auth_verify_failed'})
                self.assertEqual(code, 31, output)
                self.assertEqual(events[-1], 'bridge:Start')
                self.assertIn('HAMMER_BACKEND_RESUME_FAILED', output)
                self.assertIn('FIXTURE_ERROR: Game authentication: tools_auth_verify_failed', output)
                self.assertEqual(events.count('auth:inject'), 1)

    def test_restore_failure_after_success_returns_error_with_manual_resume_instruction(self):
        code, output, events = self.run_launcher(
            expected=1, game_running=True, bridge_status=ACTIVE_BRIDGE, resume_failure='throw')
        self.assertEqual(code, 31, output)
        self.assertEqual(events[-1], 'bridge:Start')
        self.assertIn('GAME_AUTH_READY', output)
        self.assertIn('FIXTURE_ERROR: HAMMER_BACKEND_RESUME_FAILED', output)
        self.assertIn('-Action Start to restore it', output)

    def test_task_start_success_without_live_heartbeat_does_not_confirm_restore(self):
        for auth_failed in (False, True):
            with self.subTest(auth_failed=auth_failed):
                injection = {'ok': False, 'error': 'tools_auth_verify_failed'} if auth_failed else {'ok': True}
                code, output, events = self.run_launcher(
                    expected=1, game_running=True, bridge_status=ACTIVE_BRIDGE,
                    resume_no_heartbeat=True, resume_status_failure_after_unready=True, inject=injection)
                self.assertEqual(code, 31, output)
                self.assertEqual(events[-4:], ['bridge:Start', 'bridge:Status', 'sleep-ms:250', 'bridge:Status'])
                self.assertIn('HAMMER_BACKEND_RESUME_FAILED', output)
                self.assertNotIn('HAMMER_BACKEND_RESUMED:', output)
                if auth_failed:
                    self.assertIn('FIXTURE_ERROR: Game authentication: tools_auth_verify_failed', output)
                else:
                    self.assertIn('FIXTURE_ERROR: HAMMER_BACKEND_RESUME_FAILED', output)
                self.assertEqual(events.count('auth:inject'), 1)

    def test_standalone_helper_is_restored_hidden_without_enabling_disabled_or_missing_task(self):
        for installed in (False, True):
            with self.subTest(installed=installed):
                status = dict(IDLE_BRIDGE, task_installed=installed,
                              task_state='Disabled' if installed else 'not_installed',
                              helper_running=True, helper_status='connected')
                code, output, events = self.run_launcher(expected=1, game_running=True, bridge_status=status)
                self.assertEqual(code, 0, output)
                self.assertEqual(events, ['tunnel:connect', 'bridge:Status', 'bridge:Stop', 'process:get',
                                          'auth:probe', 'auth:inject', 'helper:start', 'bridge:Status'])
                self.assertIn('HAMMER_BACKEND_RESUMED', output)
                self.assertNotIn('bridge:Start', events)

    def test_standalone_restore_preserves_an_invalid_stop_marker_and_reports_failure(self):
        status = dict(IDLE_BRIDGE, helper_running=True, helper_status='connected')
        code, output, events = self.run_launcher(
            expected=1, game_running=True, bridge_status=status, stop_marker_invalid=True)
        self.assertEqual(code, 31, output)
        self.assertIn('HAMMER_BACKEND_RESUME_FAILED', output)
        self.assertIn('run_hammer_backend.ps1 to restore the standalone helper', output)
        self.assertIn('output/hammer_backend/bridge.stop first', output)
        self.assertIn('do not clear an invalid marker blindly', output)
        self.assertNotIn('helper:start', events)

    def test_standalone_restore_failure_reports_manual_action_and_preserves_authentication_error(self):
        status = dict(IDLE_BRIDGE, helper_running=True, helper_status='connected')
        code, output, events = self.run_launcher(
            expected=1, game_running=True, bridge_status=status, resume_failure='throw',
            inject={'ok': False, 'error': 'tools_auth_recovery_failed'})
        self.assertEqual(code, 31, output)
        self.assertEqual(events[-1], 'helper:start')
        self.assertIn('HAMMER_BACKEND_RESUME_FAILED', output)
        self.assertIn('FIXTURE_ERROR: Game authentication: tools_auth_recovery_failed', output)
        self.assertIn('run_hammer_backend.ps1 to restore the standalone helper', output)
        self.assertEqual(events.count('auth:inject'), 1)

    def test_single_player_status_failure_stops_before_game_or_console_operations(self):
        code, output, events = self.run_launcher(expected=1, game_running=True, status_failure=True)
        self.assertEqual(code, 31, output)
        self.assertEqual(events, ['tunnel:connect', 'bridge:Status'])
        self.assertIn('HAMMER_BACKEND_STATUS_FAILED', output)

    def test_backend_failure_reports_reason_before_game_or_authentication(self):
        for result in ({'ok': False, 'status': 'backend_unavailable'},
                       {'ok': False, 'status': 'backend_unavailable', 'error': 'backend_unavailable'}):
            with self.subTest(result=result):
                code, output, events = self.run_launcher(expected=1, tunnel=result)
                self.assertEqual(code, 31, output)
                self.assertEqual(events, ['tunnel:connect'])
                self.assertIn('SSH connection: backend_unavailable', output)
                self.assertIn('existing tunnel and game were preserved', output)
                self.assertNotIn('GAME_AUTH_READY', output)

    def test_ssh_network_failure_reports_next_check_before_starting_game(self):
        hints = {
            'ssh_connection_timeout': 'SSH port 22 did not respond',
            'ssh_connection_refused': 'SSH port 22 refused',
            'ssh_network_unreachable': 'No network route',
            'ssh_connection_reset': 'SSH connection was reset',
            'ssh_connection_closed': 'SSH connection was closed',
        }
        for error, hint in hints.items():
            with self.subTest(error=error):
                code, output, events = self.run_launcher(expected=1, tunnel={'ok': False, 'error': error})
                self.assertEqual(code, 31, output)
                self.assertEqual(events, ['tunnel:connect'])
                self.assertIn('SSH connection: ' + error, output)
                self.assertIn(hint, output)
                self.assertNotIn('GAME_AUTH_READY', output)

    def test_missing_connection_reason_has_nonempty_fallback(self):
        code, output, events = self.run_launcher(expected=1, tunnel={'ok': False})
        self.assertEqual(code, 31, output)
        self.assertEqual(events, ['tunnel:connect'])
        self.assertIn('SSH connection: ssh_tunnel_or_backend_unavailable', output)

    def test_gate_not_ready_does_not_authenticate_even_with_enough_players(self):
        code, output, events = self.run_launcher(game_running=True, rosters=[
            {'ok': True, 'status': 'gate_not_ready', 'players': 2},
            {'ok': True, 'status': 'waiting_players', 'players': 2},
        ])
        self.assertEqual(code, 0, output)
        self.assertEqual(events, ['bridge:Stop', 'tunnel:connect', 'process:get', 'auth:probe',
                                  'roster:2', 'sleep:2', 'roster:2', 'auth:inject'])

    def test_slow_startup_reports_stages_and_authenticates_only_when_ready(self):
        code, output, events = self.run_launcher(expected=1, probes=[
            {'ok': False, 'error': 'tools_console_unavailable'},
            {'ok': False, 'error': 'tools_server_confirmation_missing'},
            {'ok': True},
        ])
        self.assertEqual(code, 0, output)
        self.assertIn('Waiting for the Workshop Tools console', output)
        self.assertIn('test map has not confirmed readiness', output)
        self.assertEqual(events.count('game:start'), 1)
        self.assertEqual(events.count('auth:probe'), 3)
        self.assertEqual(events[-1], 'auth:inject')

    def test_client_exit_stops_waiting_without_authentication_or_relaunch(self):
        code, output, events = self.run_launcher(
            expected=1, game_exited_while_waiting=True,
            probes=[{'ok': False, 'error': 'tools_console_unavailable'}])
        self.assertEqual(code, 31, output)
        self.assertIn('GAME_CLIENT_EXITED', output)
        self.assertEqual(events.count('game:start'), 1)
        self.assertNotIn('auth:inject', events)

    def test_existing_unready_game_times_out_with_actionable_help_and_is_preserved(self):
        code, output, events = self.run_launcher(
            expected=1, game_running=True,
            probes=[{'ok': False, 'error': 'tools_server_confirmation_missing'}])
        self.assertEqual(code, 31, output)
        self.assertIn('GAME_MAP_WAIT_TIMEOUT', output)
        self.assertIn('Dota was already running', output)
        self.assertIn('double-click launch_aliyun_test_game.cmd', output)
        self.assertNotIn('game:start', events)
        self.assertNotIn('auth:inject', events)

    def test_existing_empty_tools_game_gets_one_guarded_launch_before_authentication(self):
        code, output, events = self.run_launcher(expected=1, game_running=True, probes=[
            {'ok': False, 'error': 'tools_server_confirmation_missing'},
            {'ok': False, 'error': 'tools_server_confirmation_missing'},
            {'ok': True},
        ])
        self.assertEqual(code, 0, output)
        self.assertEqual(events.count('auth:start-empty'), 1)
        self.assertNotIn('game:start', events)
        self.assertEqual(events[-1], 'auth:inject')


if __name__ == '__main__':
    unittest.main()
