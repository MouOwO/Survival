"""Exercise Windows Setup with isolated task, bridge and console fixtures."""
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
    if ($env:HAMMER_FIXTURE_TASK -eq 'missing') { return }
    $runner=Join-Path $PSScriptRoot 'tools/run_hammer_backend.ps1'
    $arguments='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'"'
    if ($env:HAMMER_FIXTURE_TASK -eq 'foreign') { $arguments='foreign task' }
    [pscustomobject]@{State='Ready';Actions=@([pscustomobject]@{
      Execute=(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe');Arguments=$arguments})}
}
function New-ScheduledTaskAction { param($Execute,$Argument,$WorkingDirectory) @{} }
function New-ScheduledTaskTrigger { param([switch]$AtLogOn,$User) @{} }
function New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel) @{} }
function New-ScheduledTaskSettingsSet {
    param($MultipleInstances,[switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,
      [switch]$DontStopIfGoingOnBatteries,$ExecutionTimeLimit,$RestartCount,$RestartInterval) @{}
}
function Register-ScheduledTask { param($TaskName,$Action,$Trigger,$Principal,$Settings,$Description,[switch]$Force) Record 'register' }
function Start-ScheduledTask { param($TaskName) Record 'start' }
function Enable-ScheduledTask { param($TaskName) Record 'enable' }
function Stop-Process { throw 'Unexpected process termination' }
function Stop-ScheduledTask { throw 'Unexpected task termination' }
try { & (Join-Path $PSScriptRoot 'tools/setup_hammer_backend.ps1') -Action $env:HAMMER_FIXTURE_ACTION }
catch { Write-Output $_.Exception.Message; exit 31 }
'''


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell setup behavior')
class SetupTests(unittest.TestCase):
    def run_setup(self, action, task='missing', repair_failure=False):
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
import sys
from pathlib import Path
with (Path(__file__).resolve().parents[1]/'events.txt').open('a') as out:
    out.write('bridge:'+sys.argv[1]+'\\n')
print('{"ok":true,"status":"waiting_for_party"}')
''',encoding='utf-8')
            (root/'harness.ps1').write_text(HARNESS,encoding='utf-8')
            shell=Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
            env=dict(os.environ,HAMMER_FIXTURE_PYTHON=sys.executable,HAMMER_FIXTURE_ACTION=action,
                HAMMER_FIXTURE_TASK=task,HAMMER_FIXTURE_REPAIR_FAIL='1' if repair_failure else '0')
            result=subprocess.run([str(shell),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(root/'harness.ps1')],
                capture_output=True,env=env,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
            events=(root/'events.txt').read_text().splitlines() if (root/'events.txt').exists() else []
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


if __name__=='__main__':
    unittest.main()
