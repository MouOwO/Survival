from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(os.name == "nt", "Real Windows PowerShell bootstrap")
class BootstrapTests(unittest.TestCase):
    def test_broken_copied_venv_is_preserved_rebuilt_and_then_reused(self):
        source = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(prefix="goufayu bootstrap ") as folder:
            root = Path(folder)
            (root / "tools").mkdir()
            shutil.copyfile(source / "setup_aliyun_test_host.ps1", root / "tools/setup_aliyun_test_host.ps1")
            # Isolate bootstrap from credentials, SSH, real tasks, and preflight.
            (root / "tools/aliyun_test_host.py").write_text(
                "import json\nprint(json.dumps({'ok': True, 'fixture': True}))\n", encoding="utf-8")
            venv = root / "output/ecs_backend_work/.venv"
            scripts = venv / "Scripts"
            scripts.mkdir(parents=True)
            shutil.copyfile(sys.executable, scripts / "python.exe")
            (venv / "pyvenv.cfg").write_text(
                "home = " + str(root / "old computer missing Python") + "\n", encoding="utf-8")
            marker = venv / "copied-environment.txt"
            marker.write_text("keep this backup", encoding="utf-8")
            harness = root / "bootstrap-test.ps1"
            harness.write_text("""
$ErrorActionPreference='Stop'
function Get-ScheduledTask { param([string]$TaskName) return $null }
& (Join-Path $PSScriptRoot 'tools/setup_aliyun_test_host.ps1') -Action Setup -PythonExe $env:GOUFAYU_TEST_BASE_PYTHON
""", encoding="utf-8")
            powershell = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
            command = [str(powershell), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(harness)]
            env = dict(os.environ, GOUFAYU_TEST_BASE_PYTHON=sys._base_executable)
            first = subprocess.run(command, capture_output=True, env=env, timeout=60,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
            self.assertEqual(first.returncode, 0, (first.stdout + first.stderr).decode("utf-8", "replace"))
            self.assertIn(b"LOCAL_PYTHON_CREATED", first.stdout)
            backups = list(venv.parent.glob(".venv.old.*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / marker.name).read_text(), "keep this backup")
            ready = subprocess.run([str(scripts / "python.exe"), "-c", "import sys; assert sys.version_info >= (3,10)"],
                                   capture_output=True, timeout=15)
            self.assertEqual(ready.returncode, 0, ready.stderr)
            second = subprocess.run(command, capture_output=True, env=env, timeout=60,
                                    creationflags=subprocess.CREATE_NO_WINDOW)
            self.assertEqual(second.returncode, 0, (second.stdout + second.stderr).decode("utf-8", "replace"))
            self.assertIn(b"LOCAL_PYTHON_READY", second.stdout)
            self.assertNotIn(b"LOCAL_PYTHON_CREATED", second.stdout)
            self.assertEqual(list(venv.parent.glob(".venv.old.*")), backups)


if __name__ == "__main__":
    unittest.main()
