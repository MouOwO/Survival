"""Exercise Windows Setup with isolated task, bridge and console fixtures."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


HARNESS = r'''
$ErrorActionPreference='Stop'
function Record($Value) { Add-Content -LiteralPath (Join-Path $PSScriptRoot 'events.txt') -Value $Value }
function Get-Command { param($Name,$CommandType,$ErrorAction) [pscustomobject]@{Source='fixture-node.exe'} }
function Get-ScheduledTask {
    param($TaskName,$ErrorAction)
    if ($env:HAMMER_FIXTURE_TASK -eq 'missing' -and -not $global:HammerFixtureRegistered) { return }
    $runner=Join-Path $PSScriptRoot 'tools/run_hammer_backend.ps1'
    $arguments='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'"'
    if ($env:HAMMER_FIXTURE_TASK -eq 'foreign') { $arguments='foreign task' }
    if ($env:HAMMER_FIXTURE_TASK -eq 'foreign_after_stop' -and
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'output/hammer_backend/bridge.stop'))) {
        $arguments='foreign task'
    }
    [pscustomobject]@{State=$env:HAMMER_FIXTURE_TASK_STATE;
      Settings=[pscustomobject]@{Enabled=($env:HAMMER_FIXTURE_TASK_ENABLED -eq '1')};Actions=@([pscustomobject]@{
      Execute=(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe');Arguments=$arguments})}
}
function New-ScheduledTaskAction { param($Execute,$Argument,$WorkingDirectory) @{} }
function New-ScheduledTaskTrigger { param([switch]$AtLogOn,$User) @{} }
function New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel) @{} }
function New-ScheduledTaskSettingsSet {
    param($MultipleInstances,[switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,
      [switch]$DontStopIfGoingOnBatteries,$ExecutionTimeLimit,$RestartCount,$RestartInterval) @{}
}
function Register-ScheduledTask { param($TaskName,$Action,$Trigger,$Principal,$Settings,$Description,[switch]$Force) Record 'register'; $global:HammerFixtureRegistered=$true }
function Start-ScheduledTask { param($TaskName) Record 'start' }
function Enable-ScheduledTask { param($TaskName) Record 'enable' }
function Disable-ScheduledTask { param($TaskName) Record 'disable' }
function Start-Process {
    param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$Wait)
    $expected=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $runner=Join-Path $PSScriptRoot 'tools/run_hammer_backend.ps1'
    $arguments='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'"'
    if ($FilePath -ne $expected -or $ArgumentList -ne $arguments -or
        $WorkingDirectory -ne $PSScriptRoot -or $WindowStyle -ne 'Hidden' -or $Wait) {
        throw 'Unexpected manual runner launch'
    }
    Record 'manual:start'
}
function Stop-Process { throw 'Unexpected process termination' }
function Stop-ScheduledTask { throw 'Unexpected task termination' }
try { & (Join-Path $PSScriptRoot 'tools/setup_hammer_backend.ps1') -Action $env:HAMMER_FIXTURE_ACTION -AsJson:($env:HAMMER_FIXTURE_JSON -eq '1') }
catch { Write-Output $_.Exception.Message; exit 31 }
'''


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell setup behavior')
class SetupTests(unittest.TestCase):
    def run_setup(self, action, task='missing', repair_failure=False, *, as_json=False,
                  task_state='Ready', task_enabled=True, helper_status='waiting_for_party', heartbeat_age=0,
                  stop_confirmed=True, stop_failure=''):
        with tempfile.TemporaryDirectory(prefix='hammer setup ') as folder:
            root=Path(folder)
            (root/'tools').mkdir()
            shutil.copyfile(Path(__file__).with_name('setup_hammer_backend.ps1'),root/'tools/setup_hammer_backend.ps1')
            (root/'tools/backend_python.ps1').write_text(
                'function Resolve-SurvivalBackendPython { param($RepoRoot) $env:HAMMER_FIXTURE_PYTHON }',encoding='utf-8')
            (root/'tools/run_hammer_backend.ps1').write_text('throw "Must not run the real worker"',encoding='utf-8')
            (root/'tools/repair_hammer_console.ps1').write_text(r'''
param($Action)
Record ('console:'+ $Action)
if ($env:HAMMER_FIXTURE_REPAIR_FAIL -eq '1') { throw 'Fixture repair blocked' }
Write-Output '{"ok":true,"status":"console_configuration_ready"}'
''',encoding='utf-8')
            (root/'tools/hammer_backend_bridge.py').write_text('''
import json, os, sys, time
from pathlib import Path
with (Path(__file__).resolve().parents[1]/'events.txt').open('a') as out:
    out.write('bridge:'+sys.argv[1]+'\\n')
status = os.environ['HAMMER_FIXTURE_HELPER_STATUS']
if sys.argv[1] == 'stop':
    marker=Path(__file__).resolve().parents[1]/'output/hammer_backend/bridge.stop'
    marker.parent.mkdir(parents=True,exist_ok=True)
    marker.write_text('stop')
    if os.environ['HAMMER_FIXTURE_STOP_FAILURE'] == 'invalid':
        print('invalid-json')
    else:
        print(json.dumps({'ok':True,'status':'stopped',
            'stop_confirmed':os.environ['HAMMER_FIXTURE_STOP_CONFIRMED'] == '1'}))
    if os.environ['HAMMER_FIXTURE_STOP_FAILURE'] == 'exit':
        raise SystemExit(1)
else:
    print(json.dumps({'ok': status not in {'not_started', 'heartbeat_expired'},
        'status': status, 'updated_at': time.time() - float(os.environ['HAMMER_FIXTURE_HEARTBEAT_AGE']),
        'untrusted_extra': 'STATUS_EXTRA_MUST_NOT_ESCAPE'}))
''',encoding='utf-8')
            (root/'harness.ps1').write_text(HARNESS,encoding='utf-8')
            shell=Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
            env=dict(os.environ,HAMMER_FIXTURE_PYTHON=sys.executable,HAMMER_FIXTURE_ACTION=action,
                HAMMER_FIXTURE_TASK=task,HAMMER_FIXTURE_REPAIR_FAIL='1' if repair_failure else '0',
                HAMMER_FIXTURE_JSON='1' if as_json else '0', HAMMER_FIXTURE_TASK_STATE=task_state,
                HAMMER_FIXTURE_TASK_ENABLED='1' if task_enabled else '0',
                HAMMER_FIXTURE_HELPER_STATUS=helper_status, HAMMER_FIXTURE_HEARTBEAT_AGE=str(heartbeat_age),
                HAMMER_FIXTURE_STOP_CONFIRMED='1' if stop_confirmed else '0',
                HAMMER_FIXTURE_STOP_FAILURE=stop_failure)
            result=subprocess.run([str(shell),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(root/'harness.ps1')],
                capture_output=True,env=env,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
            events=(root/'events.txt').read_text().splitlines() if (root/'events.txt').exists() else []
            result.fixture_stop_exists=(root/'output/hammer_backend/bridge.stop').exists()
            return result,events

    def test_install_repairs_before_stopping_or_registering(self):
        result,events=self.run_setup('Install')
        self.assertEqual(result.returncode,0,(result.stdout+result.stderr).decode(errors='replace'))
        self.assertEqual(events,['console:Repair','bridge:stop','register','start','bridge:status'])

    def test_start_repairs_existing_task_before_restart(self):
        result,events=self.run_setup('Start','owned')
        self.assertEqual(result.returncode,0,(result.stdout+result.stderr).decode(errors='replace'))
        self.assertEqual(events,['console:Repair','bridge:stop','enable','start','bridge:status'])

    def test_repair_failure_preserves_running_helper(self):
        result,events=self.run_setup('Install',repair_failure=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(events,['console:Repair'])

    def test_foreign_task_is_preserved_before_console_changes(self):
        result,events=self.run_setup('Install','foreign')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(events,[])

    def test_status_checks_console_without_repairing_or_restarting(self):
        result,events=self.run_setup('Status','owned')
        self.assertEqual(result.returncode,0,(result.stdout+result.stderr).decode(errors='replace'))
        self.assertEqual(events,['console:Check','bridge:status'])

    def test_json_status_is_one_public_object_without_console_access(self):
        result,events=self.run_setup('Status','owned',as_json=True,task_state='Running')
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
        value=json.loads(result.stdout.decode('utf-8-sig'))
        self.assertEqual(value, {'ok':True, 'task_installed':True, 'task_state':'Running',
            'task_enabled':True, 'helper_running':True, 'helper_status':'waiting_for_party'})
        self.assertEqual(events,['bridge:status'])
        self.assertNotIn(b'STATUS_EXTRA_MUST_NOT_ESCAPE',result.stdout)

    def test_json_status_distinguishes_installed_disabled_and_manual_helper(self):
        for task,state,enabled,installed in (
            ('owned','Disabled',False,True), ('owned','Running',False,True),
            ('missing','Ready',True,False)):
            with self.subTest(task=task,state=state):
                result,events=self.run_setup('Status',task,as_json=True,
                    task_state=state,task_enabled=enabled)
                value=json.loads(result.stdout.decode('utf-8-sig'))
                self.assertTrue(value['helper_running'])
                self.assertEqual(value['task_installed'],installed)
                self.assertEqual(value['task_enabled'],enabled if installed else False)
                self.assertEqual(events,['bridge:status'])

    def test_json_status_rejects_stopped_missing_and_expired_heartbeats(self):
        for status,age in (('stopped',0),('not_started',0),('heartbeat_expired',0),
                           ('waiting_for_party',91)):
            with self.subTest(status=status,age=age):
                result,events=self.run_setup('Status','owned',as_json=True,
                    helper_status=status,heartbeat_age=age)
                value=json.loads(result.stdout.decode('utf-8-sig'))
                self.assertFalse(value['helper_running'])
                self.assertEqual(value['helper_status'],'heartbeat_expired' if age else status)
                self.assertEqual(events,['bridge:status'])

    def test_json_status_preserves_foreign_task_before_inspecting_bridge(self):
        result,events=self.run_setup('Status','foreign',as_json=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(events,[])

    def test_json_mode_rejects_mutating_actions_before_any_effect(self):
        result,events=self.run_setup('Start','owned',as_json=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(events,[])

    def test_json_status_rejects_unknown_helper_output(self):
        result,events=self.run_setup('Status','owned',as_json=True,helper_status='unexpected')
        value=json.loads(result.stdout.decode('utf-8-sig'))
        self.assertFalse(value['ok'])
        self.assertFalse(value['helper_running'])
        self.assertEqual(value['helper_status'],'status_unavailable')
        self.assertEqual(events,['bridge:status'])

    def test_stop_accepts_confirmed_cleanup_while_legacy_task_still_runs(self):
        result,events=self.run_setup('Stop','owned',task_state='Running')
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
        self.assertEqual(events,['disable','bridge:stop'])
        self.assertTrue(result.fixture_stop_exists)

    def test_start_and_install_restore_with_fixed_hidden_legacy_runner(self):
        for action,expected in (
            ('Start',['console:Repair','bridge:stop','enable','manual:start','bridge:status']),
            ('Install',['console:Repair','bridge:stop','register','manual:start','bridge:status'])):
            with self.subTest(action=action):
                result,events=self.run_setup(action,'owned',task_state='Running')
                self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
                self.assertEqual(events,expected)
                self.assertFalse(result.fixture_stop_exists)

    def test_unconfirmed_stop_never_clears_marker_or_starts_a_helper(self):
        for confirmed,failure in ((False,''),(True,'exit'),(True,'invalid')):
            with self.subTest(confirmed=confirmed,failure=failure):
                result,events=self.run_setup('Start','owned',task_state='Running',
                    stop_confirmed=confirmed,stop_failure=failure)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(events,['console:Repair','bridge:stop'])
                self.assertTrue(result.fixture_stop_exists)


if __name__=='__main__':
    unittest.main()
