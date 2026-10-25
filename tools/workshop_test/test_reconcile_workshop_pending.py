"""Offline reconciliation safety/ABI tests. Never initialize Steam or publish."""
import copy
import ctypes as C
from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import reconcile_workshop_pending as r


def item():
    return {'id': r.ITEM, 'result': 1, 'file_type': 0, 'creator_app_id': r.api.APP,
            'consumer_app_id': r.api.APP, 'owner': r.api.OWNER, 'visibility': 3,
            'time_updated': r.REMOTE_TIME, 'total_files_bytes': r.TOTAL_BYTES,
            'cached': False, 'max_cache_age_seconds': 0, 'banned': False,
            'tags_truncated': False, 'tags': 'Custom Game', 'observed_utc': r.now()}


class Native:
    """Real ctypes buffers and pointers, without any native DLL."""
    def __init__(self):
        self.events, self.references, self.calls = [], [], []
        self.freed = 0
        self.query_record = r.api.Queried()
        self.query_record.handle, self.query_record.result = 123, 1
        self.query_record.returned, self.query_record.total = 1, 1

    def event(self, record, callback, *, user=8, size=None):
        self.references.append(record)
        self.events.append((user, callback, C.addressof(record), C.sizeof(record) if size is None else size))

    def fn(self, name, restype, argtypes):
        self.calls.append(name)
        if name == 'SteamAPI_GetHSteamPipe': return lambda: 7
        if name == 'SteamAPI_GetHSteamUser': return lambda: 8
        if name in ('SteamAPI_ManualDispatch_Init', 'SteamAPI_ManualDispatch_RunFrame'):
            return lambda *unused: None
        if name == 'SteamAPI_ManualDispatch_FreeLastCallback':
            def free(*unused): self.freed += 1
            return free
        if name == 'SteamAPI_ManualDispatch_GetNextCallback':
            def next_callback(pipe, pointer):
                if not self.events: return False
                row = C.cast(pointer, C.POINTER(r.CallbackMessage)).contents
                row.user, row.callback, row.data, row.size = self.events.pop(0)
                return True
            return next_callback
        if name == 'SteamAPI_ManualDispatch_GetAPICallResult':
            def result(pipe, call, pointer, size, callback, failed):
                C.memmove(pointer, C.byref(self.query_record), C.sizeof(self.query_record))
                C.cast(failed, C.POINTER(C.c_bool)).contents.value = False
                return True
            return result
        raise AssertionError(name)


class DispatchTests(unittest.TestCase):
    def test_layout_and_exports_resolved_before_init(self):
        r.validate_abi()
        native = Native()
        dispatch = r.Dispatch(native)
        self.assertEqual((dispatch.pipe, dispatch.user), (7, 8))
        self.assertEqual(C.sizeof(r.DownloadResult), 24)
        self.assertNotIn('SteamAPI_RunCallbacks', native.calls)

    def test_matching_query_is_uncached_and_exact_handle(self):
        native = Native()
        native.event(r.CallCompleted(99, 3401, 280), 703)
        dispatch = r.Dispatch(native)
        self.assertEqual(dispatch.query(99, 123).handle, 123)
        self.assertEqual(native.freed, 1)

    def test_cached_query_callback_is_rejected_and_freed(self):
        native = Native()
        native.query_record.cached = True
        native.event(r.CallCompleted(99, 3401, 280), 703)
        with self.assertRaisesRegex(r.Refused, 'fresh_query_callback_rejected'):
            r.Dispatch(native).query(99, 123)
        self.assertEqual(native.freed, 1)

    def test_bad_callback_size_is_rejected_and_freed(self):
        native = Native()
        native.event(r.CallCompleted(99, 3401, 280), 703, size=8)
        with self.assertRaisesRegex(r.Refused, 'call_completed_size_mismatch'):
            r.Dispatch(native).query(99, 123)
        self.assertEqual(native.freed, 1)

    def test_real_matching_download_event_required_old_event_drained(self):
        native = Native()
        native.event(r.DownloadResult(570, int(r.ITEM), 1), 3406)
        dispatch = r.Dispatch(native)
        def request():
            native.event(r.DownloadResult(1, int(r.ITEM), 1), 3406)
            native.event(r.DownloadResult(570, 1, 1), 3406)
            native.event(r.DownloadResult(570, int(r.ITEM), 1), 3406)
            return True
        result = dispatch.download(request)
        self.assertEqual(result['callback_id'], 3406)
        self.assertEqual(result['workshop_id'], r.ITEM)
        self.assertEqual(native.freed, 4)

    def test_installed_without_new_callback_cannot_succeed(self):
        native = Native()
        native.event(r.DownloadResult(570, int(r.ITEM), 1), 3406)
        with self.assertRaisesRegex(r.Refused, 'official_download_callback_timeout'):
            r.Dispatch(native).download(lambda: True, timeout=0)
        self.assertEqual(native.freed, 1)

    def test_failed_download_does_not_become_success(self):
        native = Native()
        def request():
            native.event(r.DownloadResult(570, int(r.ITEM), 2), 3406)
            return True
        with self.assertRaisesRegex(r.Refused, 'official_download_callback_failed'):
            r.Dispatch(native).download(request)
        self.assertEqual(native.freed, 1)

    def test_missing_manual_export_refuses_before_download(self):
        native = Native()
        original = native.fn
        def missing(name, *args):
            if name == 'SteamAPI_ManualDispatch_GetNextCallback': raise AttributeError(name)
            return original(name, *args)
        native.fn = missing
        with self.assertRaises(AttributeError): r.Dispatch(native)
        self.assertFalse(native.events)

    def test_sdk_publication_and_subscription_methods_are_not_allowed(self):
        steam = r.ReadDownloadSteam()
        for name in ('CreateItem', 'StartItemUpdate', 'SubmitItemUpdate',
                     'SetItemVisibility', 'SubscribeItem', 'SetItemContent', 'DeleteItem'):
            with self.subTest(name=name), self.assertRaisesRegex(r.Refused, 'forbidden'):
                steam.ug(name, C.c_bool, [])


class JournalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        paths = {name: root / name.lower() for name in
                 ('STATE', 'BASELINE', 'HISTORICAL', 'FAILURE_REPORT', 'SDK_LOG', 'ACF', 'INSTALLED', 'OUTPUT', 'TRUSTED')}
        self.paths = paths
        self.installed = paths['INSTALLED']
        self.installed.mkdir()
        paths['TRUSTED'].mkdir()
        self.baseline = {'schema': 1, 'owner': r.api.OWNER, 'app_id': r.api.APP,
                         'workshop_id': r.ITEM, 'visibility_requested': 3, 'uploaded': True,
                         'status': 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST',
                         'content_sha256': r.CONTENT, 'release_sequence': r.SEQUENCE,
                         'vpk_sha256': r.INDEX, 'vpk_bytes': 2, 'package': 'historical-package',
                         'verification': {'files': 6630, 'archive_count': 4},
                         'package_files': [{'name': str(index), 'bytes': 2, 'sha256': str(index) * 64}
                                           for index in range(5)],
                         'native_test': 'OLD_SINGLE_PLAYER_SUCCESS',
                         'ordinary_workshop_match': 'OLD_SINGLE_PLAYER_SUCCESS',
                         'native_four_archive_reads_verified': True,
                         'last_submit_failure': {'reason': 'an_older_failure'},
                         'download_verified': True}
        self.pending = {**self.baseline, 'uploaded': False, 'status': 'SUBMIT_REQUEST_PENDING',
                        'content_sha256': 'v08-content', 'release_sequence': 2026102503}
        failure = {'exit_code': 1, 'uploaded': False, 'workshop_id': r.ITEM,
                   'automatic_retry_permitted': False}
        raw = {'STATE': r.encoded(self.pending), 'BASELINE': r.encoded(self.baseline),
               'HISTORICAL': b'original historical v05 receipt\r\n',
               'FAILURE_REPORT': r.encoded(failure),
               'SDK_LOG': b'ERROR! Timeout uploading manifest (size 104842)\r\n'}
        for name, content in raw.items(): paths[name].write_bytes(content)
        values = {**paths, 'PENDING_SHA': r.sha(raw['STATE']), 'BASELINE_SHA': r.sha(raw['BASELINE']),
                  'HISTORICAL_SHA': r.sha(raw['HISTORICAL']), 'FAILURE_REPORT_SHA': r.sha(raw['FAILURE_REPORT']),
                  'SDK_LOG_SHA': r.sha(raw['SDK_LOG']), 'TOTAL_BYTES': 10}
        self.constants = patch.multiple(r, **values)
        self.constants.start()
        self.original = paths['STATE'].read_bytes()
        self.historical = paths['HISTORICAL'].read_bytes()

    def tearDown(self):
        self.constants.stop()
        self.tmp.cleanup()

    def proof(self):
        return {'schema': 1, 'status': 'FRESH_OFFICIAL_V05_FULLY_VERIFIED',
                'pending_sha256': r.PENDING_SHA, 'verified_utc': r.now(),
                'pre_query': item(), 'post_query': item(),
                'download': {'callback': {'callback_id': 3406, 'app_id': 570,
                                         'workshop_id': r.ITEM, 'result': 1}},
                'signed_download': {'signature_valid': True, 'content_sha256': r.CONTENT,
                                    'release_sequence': r.SEQUENCE, 'vpk_sha256': r.INDEX,
                                    'package_files': self.baseline['package_files'],
                                    'manifest': {'manifest': r.MANIFEST},
                                    'verification': {'files': 6630, 'archive_count': 4,
                                                     **{name: True for name in r.CHECKS}}}}

    def directory(self):
        r.OUTPUT.mkdir(exist_ok=True)
        return r.create_output(r.OUTPUT / 'new-transaction')

    def assert_original(self):
        self.assertEqual(r.STATE.read_bytes(), self.original)
        self.assertEqual(r.HISTORICAL.read_bytes(), self.historical)

    def test_default_plan_does_not_initialize_sdk_or_write_any_file(self):
        before = sorted(str(path) for path in r.STATE.parent.rglob('*'))
        with patch.object(r, 'ReadDownloadSteam', side_effect=AssertionError('Steam called')), patch.object(r.api, 'emit') as emit:
            self.assertEqual(r.main([]), 0)
        self.assertEqual(emit.call_args.args[0]['files_written'], 0)
        self.assertEqual(before, sorted(str(path) for path in r.STATE.parent.rglob('*')))
        self.assert_original()

    def test_default_does_not_allow_output_directory(self):
        with patch.object(r.api, 'emit'):
            self.assertEqual(r.main(['--output-dir', str(r.OUTPUT / 'illegal')]), 1)
        self.assertFalse(r.OUTPUT.exists())
        self.assert_original()

    def test_changed_pending_historical_or_baseline_fails_closed(self):
        for path in (r.STATE, r.BASELINE, r.HISTORICAL):
            with self.subTest(path=path):
                original = path.read_bytes()
                path.write_bytes(original + b' ')
                with self.assertRaisesRegex(r.Refused, 'pinned_input_changed'): r.local_inputs()
                path.write_bytes(original)
        self.assert_original()

    def test_exact_casefolded_acf_and_uint64_manifest_string(self):
        r.ACF.write_text('"AppWorkshop" { "appid" "570" "WorkshopItemsInstalled" { "' + r.ITEM
                         + '" { "manifest" "' + r.MANIFEST + '" "size" "10" "timeupdated" "'
                         + str(r.REMOTE_TIME) + '" } } }', encoding='utf8')
        result = r.installed_manifest()
        self.assertIsInstance(result['manifest'], str)
        self.assertEqual(result['manifest'], r.MANIFEST)
        r.ACF.write_text(r.ACF.read_text().replace(r.MANIFEST, '111'), encoding='utf8')
        with self.assertRaisesRegex(r.Refused, 'installed_manifest_changed'): r.installed_manifest()

    def test_installation_time_is_recorded_without_equating_to_remote_update_time(self):
        steam = r.ReadDownloadSteam()
        class Callbacks:
            def download(self, request):
                self.requested = request()
                return {'callback_id': 3406, 'app_id': 570, 'workshop_id': r.ITEM, 'result': 1}
        steam.dispatch = Callbacks()
        def ug(name, result, types, *args):
            if name == 'GetItemState': return 5
            if name == 'DownloadItem': return True
            if name == 'GetItemInstallInfo':
                C.cast(args[1], C.POINTER(C.c_uint64)).contents.value = r.TOTAL_BYTES
                args[2].value = str(r.INSTALLED.resolve()).encode('utf8')
                C.cast(args[4], C.POINTER(C.c_uint32)).contents.value = r.REMOTE_TIME + 1000
                return True
            raise AssertionError(name)
        steam.ug = ug
        result = steam.download_existing()
        self.assertEqual(result['installation_timestamp'], r.REMOTE_TIME + 1000)
        self.assertTrue(steam.dispatch.requested)

    def test_historical_trust_inventory_and_checkout_public_pins_fail_closed(self):
        checkout = r.STATE.parent / 'checkout'
        fixture = {name: ('historical:' + name).encode() for name in r.TRUST_PINS}
        pins = {name: r.sha(raw) for name, raw in fixture.items()}
        for name, raw in fixture.items():
            target = r.TRUSTED / name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(raw)
            other = (checkout if name in r.PUBLIC_FILES else r.INSTALLED) / name
            other.parent.mkdir(parents=True, exist_ok=True); other.write_bytes(raw)
        new_main = checkout / 'scripts/vscripts/addon_game_mode.lua'
        new_main.parent.mkdir(parents=True, exist_ok=True)
        new_main.write_bytes(b'new current multiplayer wrapper differs from historical main')
        with patch.object(r, 'ROOT', checkout), patch.object(r, 'TRUST_PINS', pins):
            self.assertEqual(len(r.snapshot_trust(r.INSTALLED)), 24)
            for target in (r.TRUSTED / 'scripts/vscripts/addon_game_mode.lua',
                           r.INSTALLED / 'scripts/vscripts/addon_game_mode.lua',
                           checkout / r.PUBLIC_FILES[1]):
                original = target.read_bytes(); target.write_bytes(b'wrong trust')
                with self.subTest(path=target), self.assertRaisesRegex(r.Refused, 'pinned_input_changed'):
                    r.snapshot_trust(r.INSTALLED)
                target.write_bytes(original)
            extra = r.TRUSTED / 'extra'; extra.write_bytes(b'not reviewed')
            with self.assertRaisesRegex(r.Refused, 'trust_inventory_changed'):
                r.snapshot_trust(r.INSTALLED)
        self.assert_original()

    def test_historical_authentication_context_restored_after_exception(self):
        old_root, old_policy = r.api.pack.handoff.ROOT, r.api.pack.handoff.POLICY
        events = []
        def trust(candidate):
            self.assertEqual((r.api.pack.handoff.ROOT, r.api.pack.handoff.POLICY), (old_root, old_policy))
            events.append('pins'); return {}
        def authenticate(candidate):
            self.assertEqual(r.api.pack.handoff.ROOT, r.TRUSTED.resolve())
            self.assertEqual(r.api.pack.handoff.POLICY, r.TRUSTED.resolve() / r.PUBLIC_FILES[0])
            events.append('authenticate'); raise ValueError('fixture full authentication failure')
        with patch.object(r, 'snapshot_trust', side_effect=trust), patch.object(r, 'read_pinned', return_value=b''), \
                patch.object(r.api.pack, 'authenticate', side_effect=authenticate), self.assertRaises(ValueError):
            r.signed_download({'baseline': self.baseline}, {'install_folder': str(r.INSTALLED)}, r.INSTALLED)
        self.assertEqual(events, ['pins', 'authenticate'])
        self.assertEqual((r.api.pack.handoff.ROOT, r.api.pack.handoff.POLICY), (old_root, old_policy))
        self.assert_original()

    def test_cached_wrong_owner_item_visibility_and_size_are_refused(self):
        for key, value in (('cached', True), ('owner', 'wrong'), ('id', 'wrong'),
                           ('visibility', 0), ('total_files_bytes', 11), ('result', 2),
                           ('banned', True), ('creator_app_id', 1), ('consumer_app_id', 1)):
            changed = item(); changed[key] = value
            with self.subTest(key=key), self.assertRaisesRegex(r.Refused, 'remote_item_changed'):
                r.validate_item(changed)

    def test_success_preserves_original_backup_and_historical_acceptance(self):
        directory = self.directory()
        result = r.commit_local(r.local_inputs(), self.proof(), directory)
        state = json.loads(r.STATE.read_bytes())
        self.assertEqual(result['updates_submitted'], 0)
        self.assertTrue(state['uploaded'])
        self.assertEqual(state['content_sha256'], r.CONTENT)
        self.assertEqual(state['release_sequence'], r.SEQUENCE)
        self.assertEqual(state['native_test'], 'HISTORICAL_ONLY_NOT_RUN_DURING_RECONCILIATION')
        self.assertFalse(state['reconciliation']['native_acceptance_promoted'])
        self.assertEqual(state['failed_attempts'][0]['pending_state'], self.pending)
        self.assertEqual((directory / 'pending_v08.original.json').read_bytes(), self.original)
        self.assertEqual(r.HISTORICAL.read_bytes(), self.historical)
        self.assertNotIn('native_four_archive_reads_verified', state)
        self.assertFalse(state['ready_for_public_release'])

    def test_backup_collision_refuses_without_replacing_anything(self):
        directory = self.directory()
        backup = directory / 'pending_v08.original.json'
        backup.write_bytes(b'keep existing evidence')
        with self.assertRaises(FileExistsError):
            r.commit_local(r.local_inputs(), self.proof(), directory)
        self.assertEqual(backup.read_bytes(), b'keep existing evidence')
        self.assert_original()

    def test_incomplete_and_stale_proofs_do_not_create_success(self):
        for variant in ('callback', 'signature', 'crc', 'manifest', 'stale'):
            proof = self.proof()
            if variant == 'callback': proof['download']['callback']['result'] = 2
            if variant == 'signature': proof['signed_download']['signature_valid'] = False
            if variant == 'crc': proof['signed_download']['verification']['crc32_verified'] = False
            if variant == 'manifest': proof['signed_download']['manifest']['manifest'] = 123
            if variant == 'stale': proof['verified_utc'] = (datetime.now(timezone.utc) - timedelta(minutes=6)).isoformat()
            directory = r.STATE.parent / ('proof-' + variant); directory.mkdir()
            with self.subTest(variant=variant), self.assertRaises(r.Refused):
                r.commit_local(r.local_inputs(), proof, directory)
            self.assertEqual(list(directory.iterdir()), [])
            self.assert_original()

    def test_final_cas_failure_keeps_concurrent_journal_and_temp_is_removed(self):
        directory = self.directory()
        original_inputs = r.local_inputs
        calls = 0
        changed = self.original + b'\n'
        def race():
            nonlocal calls
            calls += 1
            if calls == 2: r.STATE.write_bytes(changed)
            return original_inputs()
        inputs = r.local_inputs()
        with patch.object(r, 'local_inputs', side_effect=race), self.assertRaises(r.Refused):
            r.commit_local(inputs, self.proof(), directory)
        self.assertEqual(r.STATE.read_bytes(), changed)
        self.assertFalse(list(r.STATE.parent.glob('*.part')))
        self.assertEqual((directory / 'pending_v08.original.json').read_bytes(), self.original)
        self.assertEqual(r.HISTORICAL.read_bytes(), self.historical)

    def test_apply_uses_publication_lock_and_fresh_live_verification(self):
        events = []
        class Lock:
            def __enter__(self): events.append('lock'); return self
            def __exit__(self, *unused): events.append('unlock')
        class Steam:
            def __enter__(self): events.append('steam'); return self
            def __exit__(self, *unused): events.append('shutdown')
        proof = self.proof()
        def verify(*unused): events.append('verify'); return proof
        with patch.object(r.api, 'publication_lock', return_value=Lock()), \
                patch.object(r, 'ReadDownloadSteam', return_value=Steam()), \
                patch.object(r, 'verify_live', side_effect=verify), patch.object(r.api, 'emit'):
            self.assertEqual(r.main(['--apply', '--output-dir', str(r.OUTPUT / 'apply')]), 0)
        self.assertEqual(events, ['lock', 'steam', 'verify', 'shutdown', 'unlock'])
        self.assertTrue(json.loads(r.STATE.read_bytes())['uploaded'])

    def test_verify_mode_cannot_commit_canonical(self):
        class Steam:
            def __enter__(self): return self
            def __exit__(self, *unused): pass
        with patch.object(r, 'ReadDownloadSteam', return_value=Steam()), \
                patch.object(r, 'verify_live', return_value=self.proof()), \
                patch.object(r, 'commit_local', side_effect=AssertionError('commit called')), patch.object(r.api, 'emit'):
            self.assertEqual(r.main(['--verify', '--output-dir', str(r.OUTPUT / 'verify')]), 0)
        self.assertTrue((r.OUTPUT / 'verify/fresh_verification.json').exists())
        self.assert_original()

    def test_live_failure_preserves_canonical(self):
        class Steam:
            def __enter__(self): raise r.Refused('test_download_failed')
            def __exit__(self, *unused): pass
        with patch.object(r, 'ReadDownloadSteam', return_value=Steam()), patch.object(r.api, 'emit'):
            self.assertEqual(r.main(['--apply', '--output-dir', str(r.OUTPUT / 'failed')]), 1)
        self.assert_original()

    def test_output_outside_owned_root_and_existing_directory_refused(self):
        with self.assertRaisesRegex(r.Refused, 'output_outside'):
            r.create_output(r.STATE.parent / 'not-owned')
        directory = self.directory()
        with self.assertRaisesRegex(r.Refused, 'already_exists'):
            r.create_output(directory)

    def test_live_verification_order_and_failed_evidence_do_not_commit(self):
        for variant in ('ok', 'callback', 'signature', 'post', 'cas'):
            events = []
            download = {'callback': {'callback_id': 3406, 'app_id': 570,
                                     'workshop_id': r.ITEM, 'result': 1}}
            if variant == 'callback': download['callback']['result'] = 2
            class Steam:
                count = 0
                def fresh_item(self):
                    self.count += 1
                    events.append('pre' if self.count == 1 else 'post')
                    answer = item()
                    if variant == 'post' and self.count == 2: answer['tags'] = 'Custom Game,changed'
                    return answer
                def download_existing(self): events.append('download'); return download
            def verify(*unused):
                events.append('signature')
                if variant == 'signature': raise ValueError('unsigned fixture')
                return self.proof()['signed_download']
            def inputs():
                events.append('cas')
                if variant == 'cas': raise r.Refused('pinned_input_changed')
            with self.subTest(variant=variant), patch.object(r, 'signed_download', side_effect=verify), \
                    patch.object(r, 'local_inputs', side_effect=inputs):
                if variant == 'ok':
                    proof = r.verify_live({}, Steam())
                    self.assertEqual(proof['status'], 'FRESH_OFFICIAL_V05_FULLY_VERIFIED')
                    self.assertEqual(events, ['pre', 'download', 'signature', 'post', 'cas'])
                else:
                    with self.assertRaises((ValueError, r.Refused)): r.verify_live({}, Steam())
            self.assert_original()

    def test_signed_download_rejects_signature_inventory_hash_and_directory_tampering(self):
        folder = r.INSTALLED.resolve()
        fixture_files = [folder / (r.ITEM + '.vpk')] + [folder / (r.ITEM + f'_{i:03}.vpk') for i in range(4)]
        for path in fixture_files: path.write_bytes(b'ab')
        for variant in ('ok', 'sequence', 'content', 'inventory', 'hash', 'after_inventory', 'extra'):
            signature = {'release_sequence': r.SEQUENCE, 'content_sha256': r.CONTENT}
            verification = {'files': 6630, 'archive_count': 4, **{key: True for key in r.CHECKS}}
            inventories = [copy.deepcopy(self.baseline['package_files']), copy.deepcopy(self.baseline['package_files'])]
            if variant == 'sequence': signature['release_sequence'] += 1
            if variant == 'content': signature['content_sha256'] = 'wrong'
            if variant == 'inventory': inventories[0][0]['sha256'] = 'wrong'
            if variant == 'after_inventory': inventories[1][0]['sha256'] = 'wrong'
            if variant == 'hash': verification['whole_vpk_md5_verified'] = False
            def check(*unused):
                if variant == 'extra': (r.INSTALLED / 'unexpected.txt').write_bytes(b'not allowed')
                return verification
            def authenticate(candidate):
                self.assertEqual(r.api.pack.handoff.ROOT, r.TRUSTED.resolve())
                self.assertEqual(r.api.pack.handoff.POLICY, r.TRUSTED.resolve() / r.PUBLIC_FILES[0])
                return r.INSTALLED, {}, signature, {}
            original_globals = (r.api.pack.handoff.ROOT, r.api.pack.handoff.POLICY)
            with self.subTest(variant=variant), ExitStack() as stack:
                stack.enter_context(patch.object(r, 'read_pinned', return_value=b''))
                stack.enter_context(patch.object(r, 'snapshot_trust', return_value={}))
                stack.enter_context(patch.object(r.api.pack, 'authenticate', side_effect=authenticate))
                stack.enter_context(patch.object(r.api.pack, 'package_paths', return_value=fixture_files))
                stack.enter_context(patch.object(r.api.pack, 'package_inventory', side_effect=inventories))
                stack.enter_context(patch.object(r.api.pack, 'verify_vpk', side_effect=check))
                stack.enter_context(patch.object(r.api.pack, 'inventory_unchanged'))
                stack.enter_context(patch.object(r, 'installed_manifest', return_value={'manifest': r.MANIFEST}))
                if variant == 'ok':
                    result = r.signed_download({'baseline': self.baseline}, {'install_folder': str(r.INSTALLED)}, r.INSTALLED)
                    self.assertTrue(result['signature_valid'])
                else:
                    with self.assertRaises(r.Refused):
                        r.signed_download({'baseline': self.baseline}, {'install_folder': str(r.INSTALLED)}, r.INSTALLED)
            self.assertEqual((r.api.pack.handoff.ROOT, r.api.pack.handoff.POLICY), original_globals)
            extra = r.INSTALLED / 'unexpected.txt'
            if extra.exists(): extra.unlink()
            self.assert_original()


if __name__ == '__main__':
    unittest.main()
