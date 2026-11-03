"""Process query failure must not authorize close/retirement. No native actions."""
from pathlib import Path
import importlib.util,json,subprocess,tempfile,unittest
from unittest import mock

SPEC=importlib.util.spec_from_file_location('native_probe',Path(__file__).with_name('network50_native_probe_20261103.py'))
m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)

class ProcessQueryTests(unittest.TestCase):
    def test_powershell_errors_are_terminating_and_propagated(self):
        failed=subprocess.CalledProcessError(1,['powershell'],stderr='CIM access denied')
        with mock.patch.object(m.subprocess,'run',side_effect=failed) as call:
            with self.assertRaises(subprocess.CalledProcessError):m.clients()
        argv=call.call_args.args[0]
        self.assertTrue(argv[-1].startswith("$ErrorActionPreference='Stop';"))
        self.assertIn('-ErrorAction Stop',argv[-1])
        self.assertTrue(call.call_args.kwargs['check'])

    def test_explicit_empty_array_is_distinct_from_query_failure(self):
        for stdout in ('','null','{}','{"pid":25552,"created":"x"}'):
            with self.subTest(stdout=stdout),mock.patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,stdout,'')):
                with self.assertRaises(ValueError):m.clients()
        with mock.patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'[]','')):
            self.assertEqual(m.clients(),[])

    def test_owned_identity_is_preserved_exactly(self):
        rows=[{'pid':25552,'created':'2026-11-03T15:27:06.7849590Z'}]
        with mock.patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,json.dumps(rows),'')):
            self.assertEqual(m.clients(),rows)
        for row in ({'pid':True,'created':'x'},{'pid':0,'created':'x'},{'pid':1,'created':None}):
            with self.subTest(row=row),mock.patch.object(m,'ps',return_value=[row]):
                with self.assertRaises(ValueError):m.clients()

    def test_query_failure_blocks_close_before_any_native_window_access(self):
        with tempfile.TemporaryDirectory() as temporary:
            store=Path(temporary)
            (store/'process.json').write_text('{"pid":25552,"created":"2026-11-03T15:27:06.7849590Z"}')
            with mock.patch.object(m,'STORE',store),mock.patch.object(m,'clients',side_effect=ValueError('query failed')),mock.patch.object(m.ctypes,'WinDLL',create=True,side_effect=AssertionError('no window access')):
                with self.assertRaisesRegex(ValueError,'query failed'):m.close()

if __name__=='__main__':unittest.main()
