"""Verify the hidden task wrapper waits for its helper, not preserved descendants."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell process waiting')
class RunnerTests(unittest.TestCase):
    def test_wrapper_exits_with_helper_code_while_descendant_remains_running(self):
        with tempfile.TemporaryDirectory(prefix='hammer runner ') as folder:
            root=Path(folder)
            tools=root/'tools'
            tools.mkdir()
            shutil.copyfile(Path(__file__).with_name('run_hammer_backend.ps1'),
                            tools/'run_hammer_backend.ps1')
            (tools/'backend_python.ps1').write_text(
                'function Resolve-SurvivalBackendPython { param($RepoRoot) $env:HAMMER_RUNNER_PYTHON }',
                encoding='utf-8')
            (tools/'repair_hammer_console.ps1').write_text('param($Action)',encoding='utf-8')
            (tools/'fixture_child.py').write_text(
                "import time\nfrom pathlib import Path\ntime.sleep(3)\n"
                "(Path(__file__).parent/'descendant_done').write_text('done')\n",encoding='utf-8')
            (tools/'hammer_backend_bridge.py').write_text(
                "import subprocess, sys\nfrom pathlib import Path\n"
                "subprocess.Popen([sys.executable,str(Path(__file__).with_name('fixture_child.py'))],"
                "stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,"
                "creationflags=subprocess.CREATE_NO_WINDOW)\nraise SystemExit(7)\n",encoding='utf-8')
            shell=Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
            result=subprocess.run([str(shell),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
                '-File',str(tools/'run_hammer_backend.ps1')],capture_output=True,
                env=dict(os.environ,HAMMER_RUNNER_PYTHON=sys.executable),timeout=15,
                creationflags=subprocess.CREATE_NO_WINDOW)
            descendant_finished_when_wrapper_returned=(tools/'descendant_done').exists()
            # This owned fixture exits naturally; do not terminate any process.
            deadline=time.monotonic()+10
            while not (tools/'descendant_done').exists() and time.monotonic()<deadline:
                time.sleep(0.05)
            self.assertTrue((tools/'descendant_done').exists(),'fixture descendant did not finish')
            self.assertEqual(result.returncode,7,(result.stdout+result.stderr).decode(errors='replace'))
            self.assertFalse(descendant_finished_when_wrapper_returned,
                             'wrapper waited for the helper\'s preserved descendant')


if __name__=='__main__':
    unittest.main()
