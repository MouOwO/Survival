"""Isolated local/mock download admission; never invoke a real SDK or API."""
from contextlib import ExitStack, nullcontext, redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch
import copy
import hashlib
import importlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('isolated_download_v03_under_test', HERE/'verify_download_v03.py')
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.output = (d.b.ROOT/'output/download_v03_isolated_tests').resolve()
        self.assertTrue(self.output.is_relative_to((d.b.ROOT/'output').resolve()))
        self.output.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='case_', dir=self.output)
        self.folder = Path(self.temporary.name).resolve()
        self.assertEqual(self.folder.parent, self.output)
        self.addCleanup(self.cleanup)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        for key, value in dict(REPORT=self.folder/'report', VIEW=self.folder/'view',
                JOURNAL=self.folder/'journal.json', BASE_REPORT=self.folder/'parent.json',
                BASE_RECORD=self.folder/'delivery.json', OUTPUT=self.folder/'candidate',
                TRUSTED=self.folder/'trusted').items():
            self.stack.enter_context(patch.object(d.b, key, value))
        self.stack.enter_context(patch.object(d,'SOURCE_REVISION','c'*40))
        self.report_sha = 'a'*64
        self.package = dict(source_revision=d.SOURCE_REVISION, release_sequence=d.b.SEQUENCE,
            files=6918, protected_modules_preserved=184, content_sha256='b'*64,
            vpk_sha256='c'*64, changed_runtime_paths=sorted(d.b.PAYLOADS),
            package_files=[dict(name=name, bytes=i+1, sha256='c'*64) for i, name in enumerate(
                [d.b.ITEM+'.vpk', *(d.b.ITEM+'_%03d.vpk' % j for j in range(4))])])
        self.manifest = dict(content_sha256='b'*64, file_count=6918)
        self.signed = dict(signature_valid=True, release_sequence=d.b.SEQUENCE)
        self.parent = dict(vpk_sha256='d'*64, package_files=[dict(row, sha256='d'*64) for row in self.package['package_files']])
        self.journal = dict(uploaded=True, status=d.SUCCESS_STATUS, owner=d.api.OWNER, app_id=d.api.APP,
            workshop_id=d.b.ITEM, visibility_requested=3, release_sequence=d.b.SEQUENCE,
            content_sha256=self.manifest['content_sha256'], vpk_sha256=self.package['vpk_sha256'],
            vpk_bytes=1, package_files=copy.deepcopy(self.package['package_files']), legal_agreement_required=False,
            release_history=[{'synthetic_history': i} for i in range(19)],
            previous_release={'synthetic': True, 'steam_manifest': '1234567'})
        self.write(d.b.REPORT/'package.json', self.package)
        self.write(d.b.VIEW/d.api.pack.handoff.MANIFEST, self.manifest)
        self.write(d.b.VIEW/d.api.pack.handoff.SIGNATURE, self.signed)
        self.write(d.b.JOURNAL, self.journal)
        parent_sha = self.write(d.b.BASE_REPORT, self.parent)
        delivery_sha = self.write(d.b.BASE_RECORD, {'observed_utc':'2026-10-31T14:08:37.921875+00:00'})
        self.stack.enter_context(patch.object(d.b, 'BASE_REPORT_SHA', parent_sha))
        self.stack.enter_context(patch.object(d.b, 'BASE_RECORD_SHA', delivery_sha))
        self.stack.enter_context(patch.object(d, 'REPORT_SHA', self.report_sha))
        self.auth = self.stack.enter_context(patch.object(d.checks, 'validated_package',
            return_value=(self.package, self.manifest, self.signed)))
        self.steam = self.stack.enter_context(patch.object(d.protocol, 'RefreshSteam',
            side_effect=AssertionError('No real Steam')))

    def cleanup(self):
        # Windows recursive cleanup stays inside this exact controlled output.
        self.assertEqual(Path(self.temporary.name).resolve().parent, self.output)
        self.temporary.cleanup()

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        raw = (json.dumps(value, sort_keys=True)+'\n').encode()
        path.write_bytes(raw)
        return hashlib.sha256(raw).hexdigest()

    def test_static_no_args_has_no_local_admission_sdk_writes_or_download(self):
        with patch.object(d, 'validated_package', side_effect=AssertionError('No package admission')),\
                patch.object(d, 'local_inputs', side_effect=AssertionError('No input reads')),\
                patch.object(d.protocol, 'main', side_effect=AssertionError('No protocol action')),\
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(d.main([]), 0)
        value = json.loads(output.getvalue())
        self.assertFalse(value['steam_initialized'])
        self.assertEqual((value['files_written'], value['downloads_requested']), (0, 0))
        self.assertEqual(value['release_sequence'], 2026110103)
        self.steam.assert_not_called()

    def test_action_needs_explicit_exact_signed_report_sha(self):
        for args in (['--preflight'], ['--download'], ['--preflight','--report-sha256','wrong'],
                ['--report-sha256', self.report_sha]):
            with self.subTest(args=args), self.assertRaises(ValueError):
                d.main(args)
        self.auth.assert_not_called()
        self.steam.assert_not_called()

    def test_signed_source_sequence_scope_and_inventory_are_fixed(self):
        d.validated_package(self.report_sha, full=True)
        for field, value in [('source_revision','f'*40), ('release_sequence',2026110101),
                ('files',6917), ('protected_modules_preserved',180),
                ('changed_runtime_paths',self.package['changed_runtime_paths'][:-1]),
                ('package_files',self.package['package_files'][:-1])]:
            package = dict(self.package, **{field:value})
            with self.subTest(field=field), patch.object(d.checks, 'validated_package',
                    return_value=(package,self.manifest,self.signed)), self.assertRaises(ValueError):
                d.validated_package(self.report_sha)
        self.steam.assert_not_called()

    def test_preflight_full_local_validation_zero_sdk_and_preserves19_history(self):
        before = d.b.JOURNAL.read_bytes()
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(d.main(['--preflight','--report-sha256',self.report_sha]),0)
        value = json.loads(output.getvalue())
        self.assertTrue(value['full_local_signed_validation'])
        self.assertTrue(value['successful_same_release'])
        self.assertEqual(value['release_history_entries'],19)
        self.assertEqual(value['protected_modules'],184)
        self.assertFalse(value['steam_initialized'])
        self.auth.assert_called_once_with(self.report_sha,full=True)
        self.assertEqual(d.b.JOURNAL.read_bytes(), before)
        self.steam.assert_not_called()

    def test_parent3102_only_preflight_and_exact_same_release_only_download(self):
        state = dict(self.journal,release_sequence=d.b.BASE_SEQUENCE,content_sha256=d.b.BASE_CONTENT,
            vpk_sha256=self.parent['vpk_sha256'],package_files=self.parent['package_files'])
        self.write(d.b.JOURNAL,state)
        result = d.local_inputs(False,full=True)
        self.assertFalse(result['success'])
        self.assertIsNone(result['expected_manifest'])
        with self.assertRaisesRegex(ValueError,'exact1103'):
            d.local_inputs(True)
        self.steam.assert_not_called()

    def test_unknown_pending_wrong_package_never_reconciles_or_overwrites(self):
        for field,value in [('status','SUBMIT_REQUEST_PENDING'),('uploaded',False),
                ('content_sha256','f'*64),('vpk_bytes',99),('visibility_requested',2),
                ('package_files',[])]:
            state=dict(self.journal,**{field:value});self.write(d.b.JOURNAL,state)
            before=d.b.JOURNAL.read_bytes()
            with self.subTest(field=field),self.assertRaises(ValueError):d.local_inputs(True)
            self.assertEqual(d.b.JOURNAL.read_bytes(),before)
        self.steam.assert_not_called()

    def test_only_current_manifest_and_conflicts_fail_closed(self):
        result=d.local_inputs(True)
        self.assertIsNone(result['expected_manifest']) # previous_release manifest is ignored.
        self.write(d.b.JOURNAL,dict(self.journal,steam_manifest='99887766'))
        self.assertEqual(d.local_inputs(True)['expected_manifest'],'99887766')
        self.write(d.b.JOURNAL,dict(self.journal,steam_manifest='99887766',download_manifest='11223344'))
        with self.assertRaises(Exception):d.local_inputs(True)

    def test_external_history_change_detected_without_reset(self):
        changed=dict(self.journal,release_history=[])
        def change(*args,**kwargs):
            self.write(d.b.JOURNAL,changed)
            return self.package,self.manifest,self.signed
        with patch.object(d,'validated_package',side_effect=change),self.assertRaisesRegex(Exception,'local_input_changed'):
            d.local_inputs(True)
        self.assertEqual(json.loads(d.b.JOURNAL.read_text()),changed)
        self.steam.assert_not_called()

    def test_adapter_config_is_private_and_does_not_retarget_frozen_peer(self):
        peer=d.module('isolated_frozen_download_peer',d.PROTOCOL)
        old=(peer.SEQUENCE,peer.CONTENT,peer.local_inputs)
        d.configure(self.package)
        self.assertEqual((peer.SEQUENCE,peer.CONTENT,peer.local_inputs),old)
        self.assertEqual(d.protocol.SEQUENCE,2026110103)
        self.assertIs(d.protocol.local_inputs,d.local_inputs)
        self.assertEqual(d.protocol.FILE_COUNT,6918)

    def test_explicit_download_delegates_only_to_frozen_protocol(self):
        with patch.object(d.b,'scene_maps',side_effect=nullcontext),\
                patch.object(d.b.inc,'trusted_source',side_effect=lambda path:nullcontext()),\
                patch.object(d.protocol,'main',return_value=0) as run:
            self.assertEqual(d.main(['--download','--report-sha256',self.report_sha]),0)
        run.assert_called_once_with(['--download'])
        self.steam.assert_not_called()

    def test_frozen_download_lock_revalidates_full_before_sdk_delegate(self):
        d.configure(self.package);inputs=d.local_inputs(True)
        with patch.object(d.protocol,'local_inputs',return_value=inputs) as admission,\
                patch.object(d.protocol.shutil,'disk_usage',return_value=Mock(free=3*1024**3)),\
                patch.object(d.api,'publication_lock',side_effect=lambda path:nullcontext()),\
                patch.object(d.protocol,'download_once',return_value={'status':'MOCK_ONLY'}) as download,\
                patch.object(d.api,'emit'):
            self.assertEqual(d.protocol.main(['--download']),0)
        self.assertEqual(admission.call_args_list[0].args,(True,))
        self.assertEqual(admission.call_args_list[1].args,(True,))
        self.assertEqual(admission.call_args_list[1].kwargs,{'full':True})
        download.assert_called_once_with(inputs)
        self.steam.assert_not_called()

    def test_frozen_callback_protocol_and_terminal180_receipt184_remain_distinct(self):
        raw=d.PROTOCOL.read_bytes().replace(b'\r\n',b'\n')
        self.assertEqual(hashlib.sha256(raw).hexdigest(),d.PROTOCOL_SHA)
        self.assertIn(b'self.dispatch.download(',raw)
        self.assertIn(b'protected_modules_verified=180',raw)
        self.assertIn(b'protected_modules_verified=inputs["protected_modules"]',raw)
        self.assertEqual(d.local_inputs(True)['protected_modules'],184)
        self.assertEqual(d.local_inputs(True)['total'],15)

    def test_frozen_download_once_mocked_authoritative_receipt_is184(self):
        # Exercise the unchanged receipt constructor with every native boundary
        # mocked, retaining real temporary-file membership and ACF parsing.
        d.configure(self.package)
        inputs=d.local_inputs(True)
        installed=self.folder/'installed';installed.mkdir()
        paths=[installed/row['name'] for row in self.package['package_files']]
        for path in paths:path.write_bytes(b'synthetic')
        acf=self.folder/'synthetic.acf'
        acf.write_text('"appworkshop" { "appid" "570" "workshopitemsinstalled" { "'+d.b.ITEM+
            '" { "manifest" "99887766" "size" "15" "timeupdated" "1793480000" } } }',encoding='utf8')
        steam=Mock()
        steam.fresh_item.return_value={'time_updated':1793480000}
        steam.refresh_subscription_once.return_value={'synthetic_callback':'1313'}
        steam.download_installed.return_value={'install_folder':str(installed),'synthetic_callback':'3406'}
        verification=dict(files=6918,archive_count=4,**{key:True for key in d.protocol.callbacks.CHECKS})
        verified=dict(signature_valid=True,vpk_sha256=self.package['vpk_sha256'],
            package_files=self.package['package_files'],verification=verification,vpk=str(paths[0]))
        saved=[]
        def save(value):saved.append(value);return self.folder/'mock_receipt.json'
        entry=importlib.import_module('test_entry')
        with patch.object(entry,'process_inventory',return_value={'steam_running':True,'dota_pids':[]}),\
                patch.object(d.protocol,'RefreshSteam') as native,\
                patch.object(d.protocol,'verify') as verify,\
                patch.object(d.protocol,'ACF',acf),\
                patch.object(d.api.pack,'package_paths',return_value=paths),\
                patch.object(d.api.pack,'package_inventory',return_value=self.package['package_files']),\
                patch.object(d.protocol,'save_evidence',side_effect=save):
            native.return_value.__enter__.return_value=steam
            verify.verify_installed.return_value=verified
            result=d.protocol.download_once(inputs)
        self.assertEqual(len(saved),1)
        self.assertEqual(saved[0]['protected_modules_verified'],184)
        self.assertEqual(saved[0]['signed_resources_verified'],6918)
        self.assertEqual(result['protected_modules_verified'],180) # Frozen legacy terminal only.
        self.assertEqual(saved[0]['steam_manifest'],'99887766')
        self.assertEqual(saved[0]['native_test'],'NOT_RUN')
        self.assertFalse(saved[0]['ready_for_public_release'])
        self.steam.assert_not_called()


    def test_missing_source_pin_refuses_before_package_or_sdk(self):
        with patch.object(d,'SOURCE_REVISION',None):
            with self.assertRaisesRegex(ValueError,'PENDING_IMMUTABLE_V03'):d.validated_package(self.report_sha,full=True)
        self.auth.assert_not_called();self.steam.assert_not_called()


if __name__ == '__main__':
    unittest.main()
