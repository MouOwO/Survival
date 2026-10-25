"""Reconcile this one failed v08 submission with the existing signed v05 item.

Default: local read-only plan, no Steam initialization or output writes.
--verify: fresh official queries, DownloadItem callback, full signed verification;
          create a new local evidence directory, leave the journal unchanged.
--apply: perform the SAME live verification in this process, then CAS/atomically
         reconcile the local journal under its publication lock. Never publish.

No receipt-import/force flag is provided. A cached installed flag, old JSON report
or a hand-edited successful state cannot authorize reconciliation. No credentials,
Steam configuration, private key, publisher action or game process is accessed.
Manual-dispatch ABI: ValveSoftware/Proton proton_11.0 steamworks_sdk_164/steam_api.h
and steamworks_sdk_165/{steam_api_internal.h,isteamugc.h,isteamutils.h}.
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True

import argparse
import copy
import ctypes as C
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import struct
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import steam_workshop_upload as api

ITEM = '3824360109'
SEQUENCE = 2026102405
CONTENT = 'b4750e433bdd1b1ea2fab0de98d13b3660ed5d3ef80a10c63c46512eab10bc60'
INDEX = '2d363a7d5ee2b96560d11536fa4be508e7b56c440dbbc88f35fcb88a5e99a039'
MANIFEST = '2955439000185399689'  # uint64 IDs remain decimal strings in JSON.
REMOTE_TIME = 1792846304
TOTAL_BYTES = 3767007982
PENDING_SHA = 'fddcd8ecb98cf8b1bfbbe1c4e4335d6a9709d759dbaf8e78db8df38c85adf308'
BASELINE_SHA = '4d830db529a61ed78b9ab132e083d514e0ff1ae67c2fc2500dbbc124de08fb87'
HISTORICAL_SHA = '6008c9050e740a90a51aa1878eacb099436e0ea7c2d23e3e7ae4f4bed7608816'
FAILURE_REPORT_SHA = '29c01d52c754457d4d14a294658f8815bacc472f50acf69696ecf19a12a59f0d'
SDK_LOG_SHA = '54292fe4e6e8919625291fe48cc54dc79b08d3038123fb9a3757f14bdb721693'
CANDIDATE_MANIFEST_SHA = '0db65cb309c64acad9e3ebb73b1b6bd21044f4e15825a1f210333d1345e525ba'
CANDIDATE_SIGNATURE_SHA = '72d832fc32e45ee5ddfbe878e0cdc2173481722bfe301d628e6d11e2cccd760f'
ATTEMPT = ROOT / 'output/ui_qa_20261025/release/v08_upload_20261025T005552732855Z_c2f4b5c9'
STATE = ROOT / 'output/four_accounts_20261022/steam_upload_state.json'
BASELINE = ATTEMPT / 'state_before.json'
HISTORICAL = ROOT / 'publishing/workshop/workshop_entry_release_20261024.json'
FAILURE_REPORT = ATTEMPT / 'report.json'
SDK_LOG = ROOT / 'output/workshop_reconciliation_20261025/v08_sdk_failure/depot_build_570.log'
CANDIDATE = Path('D:/Survival_发布候选/20261024_ws4_workshop_entry_v05')
TRUSTED = CANDIDATE.with_name(CANDIDATE.name + '_trusted_source')
PUBLIC_FILES = ('tools/release_security/protection_policy.json',
                'tools/release_security/trusted_public_key.pem')
TRUST_PINS = {
    'scripts/vscripts/addon_game_mode.lua': '32f371db9fc024710474e67818f360e0c8b0187bdc5189e4f76107871fface5e',
    'scripts/vscripts/addon_game_mode_client.lua': 'db095896002b6f63b47484908285448c9ca2bdae70f2dce718ab2d53b02e3fd8',
    'scripts/vscripts/config/test_access.lua': 'c8b3280e51afa1ffac0f7ed87bdc7823fc18cad190a906970f3a063f6c9e7e06',
    'scripts/vscripts/core/event_bus.lua': '316d424fc50cd86e639eb29c83cda3bcc4cc688fb10ac4954a86cbfd916d8cf9',
    'scripts/vscripts/core/test_access_policy.lua': 'fe6c77e68ef2806c948851c66943d141fc1af5d858eae0b502b4204860d0d681',
    'scripts/vscripts/systems/multiplayer_player_service.lua': '55aef4d45f1a2ad12fce95437547230f398455424c5244c9ae67f386deec0f29',
    'scripts/vscripts/systems/player_profile_service.lua': 'ad2ba8edf96c45f8730df8f1d5289414f8e4f1a3bd05cd95827c9dc690e39a86',
    'scripts/vscripts/systems/startup_loading_service.lua': 'c0293001b2f1c85492b35cf28aff157e5d54ddbdcf00b3cbf7ccead0739d3a0d',
    'scripts/vscripts/systems/workshop_entry.lua': '1afaa3f740a2b3c5c53c8f802ec244f3b20e277f13f20157175088edaecc4fcc',
    'scripts/vscripts/ui/ui_request_router.lua': 'a2a1bba0a329daea539b89285fd93c7f1833a9f30e9b630167c0aafc2eb297fc',
    'tools/release_security/protection_policy.json': '8e8c2e50a6a983dda7336a083377bbf55de8625f89f5633977c8d7901b53da96',
    'tools/release_security/trusted_public_key.pem': '1717c28cb7476e5eb5326b780589c880e86d42cc026b6d4728d95ac95e8873bf',
}
ACF = api.pack.handoff.INSTALL.parents[1] / 'workshop/appworkshop_570.acf'
INSTALLED = ACF.parent / 'content/570' / ITEM
OUTPUT = ROOT / 'output/workshop_reconciliation_20261025'
FACT_FIELDS = ('content_sha256', 'release_sequence', 'vpk_sha256', 'vpk_bytes',
               'verification', 'package', 'package_files')
NATIVE_FIELDS = ('native_test', 'ordinary_workshop_match', 'native_four_archive_reads_verified')
CHECKS = ('crc32_verified', 'manifest_dual_hashes_verified',
          'section_md5s_verified', 'whole_vpk_md5_verified')


class Refused(RuntimeError):
    """All messages are fixed local diagnostic tags, never native/private text."""


def need(condition, tag):
    if not condition:
        raise Refused(tag)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf8')


def read_pinned(path, expected, maximum=1024 * 1024):
    path = api.pack.handoff.regular_path(path)
    with path.open('rb') as stream:
        raw = stream.read(maximum + 1)
    need(len(raw) <= maximum and sha(raw) == expected, 'pinned_input_changed')
    return raw


def local_inputs():
    pending_raw = read_pinned(STATE, PENDING_SHA)
    baseline_raw = read_pinned(BASELINE, BASELINE_SHA)
    read_pinned(HISTORICAL, HISTORICAL_SHA)
    failure_raw = read_pinned(FAILURE_REPORT, FAILURE_REPORT_SHA)
    sdk_raw = read_pinned(SDK_LOG, SDK_LOG_SHA)
    pending = api.pack.handoff.decode_json(pending_raw)
    baseline = api.pack.handoff.decode_json(baseline_raw)
    failure = api.pack.handoff.decode_json(failure_raw)
    for state in (pending, baseline):
        need(state.get('owner') == api.OWNER and state.get('app_id') == api.APP
             and state.get('workshop_id') == ITEM and state.get('visibility_requested') == 3,
             'state_identity_mismatch')
    need(pending.get('status') == 'SUBMIT_REQUEST_PENDING' and pending.get('uploaded') is False,
         'not_the_pinned_pending_submission')
    need(pending.get('release_sequence') == 2026102503
         and baseline.get('uploaded') is True and baseline.get('release_sequence') == SEQUENCE
         and baseline.get('content_sha256') == CONTENT and baseline.get('vpk_sha256') == INDEX,
         'release_identity_mismatch')
    need(failure.get('exit_code') == 1 and failure.get('uploaded') is False
         and failure.get('workshop_id') == ITEM and failure.get('automatic_retry_permitted') is False,
         'failed_attempt_evidence_mismatch')
    need(b'Timeout uploading manifest (size 104842)' in sdk_raw, 'sdk_failure_evidence_mismatch')
    need(len(baseline.get('package_files', [])) == 5
         and sum(row['bytes'] for row in baseline['package_files']) == TOTAL_BYTES,
         'baseline_package_mismatch')
    return {'pending_raw': pending_raw, 'pending': pending, 'baseline': baseline,
            'failure_report': failure, 'sdk_log_raw': sdk_raw}


class CallbackMessage(C.Structure):
    _pack_ = 8
    _fields_ = [('user', C.c_int32), ('callback', C.c_int32),
                ('data', C.c_void_p), ('size', C.c_int32)]


class CallCompleted(C.Structure):
    _pack_ = 8
    _fields_ = [('call', C.c_uint64), ('callback', C.c_int32), ('size', C.c_uint32)]


class DownloadResult(C.Structure):
    _pack_ = 8
    _fields_ = [('app', C.c_uint32), ('item', C.c_uint64), ('result', C.c_int32)]


def validate_abi():
    need(C.sizeof(C.c_void_p) == 8
         and (C.sizeof(CallbackMessage), CallbackMessage.data.offset, CallbackMessage.size.offset) == (24, 8, 16)
         and C.sizeof(CallCompleted) == 16
         and (C.sizeof(DownloadResult), DownloadResult.item.offset, DownloadResult.result.offset) == (24, 8, 16)
         and C.sizeof(api.Queried) == 280, 'unsupported_callback_abi')


class Dispatch:
    """Only this newly initialized process's pipe; never mix RunCallbacks()."""
    def __init__(self, steam):
        validate_abi()
        self.steam = steam
        self.init = steam.fn('SteamAPI_ManualDispatch_Init', None, [])
        self.run = steam.fn('SteamAPI_ManualDispatch_RunFrame', None, [C.c_int32])
        self.next = steam.fn('SteamAPI_ManualDispatch_GetNextCallback', C.c_bool,
                             [C.c_int32, C.POINTER(CallbackMessage)])
        self.free = steam.fn('SteamAPI_ManualDispatch_FreeLastCallback', None, [C.c_int32])
        self.result = steam.fn('SteamAPI_ManualDispatch_GetAPICallResult', C.c_bool,
                               [C.c_int32, C.c_uint64, C.c_void_p, C.c_int32,
                                C.c_int32, C.POINTER(C.c_bool)])
        self.pipe = steam.fn('SteamAPI_GetHSteamPipe', C.c_int32, [])()
        self.user = steam.fn('SteamAPI_GetHSteamUser', C.c_int32, [])()
        need(self.pipe > 0 and self.user > 0, 'invalid_local_steam_pipe')
        self.init()  # All required exports were resolved before enabling manual dispatch.

    def poll(self, handler):
        self.run(self.pipe)
        for _ in range(10000):
            message = CallbackMessage()
            if not self.next(self.pipe, C.byref(message)):
                return
            try:
                need(0 <= message.size <= 1024 * 1024
                     and (message.size == 0 or message.data), 'invalid_callback_buffer')
                if message.user == self.user:
                    handler(message)
            finally:
                self.free(self.pipe)
        raise Refused('callback_queue_exceeded_bound')

    def query(self, call, query, timeout=120):
        need(call not in (0, api.INVALID), 'query_call_not_scheduled')
        answer = []
        def handler(message):
            if message.callback != 703:
                return
            need(message.size == C.sizeof(CallCompleted), 'call_completed_size_mismatch')
            completed = CallCompleted.from_buffer_copy(C.string_at(message.data, message.size))
            if completed.call != call:
                return
            need(not answer and completed.callback == 3401
                 and completed.size == C.sizeof(api.Queried), 'query_callback_identity_mismatch')
            record, failed = api.Queried(), C.c_bool()
            ok = self.result(self.pipe, call, C.byref(record), C.sizeof(record), 3401, C.byref(failed))
            need(ok and not failed.value and record.result == 1
                 and record.handle == query and not record.cached
                 and record.returned == 1 and record.total == 1, 'fresh_query_callback_rejected')
            answer.append(record)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.poll(handler)
            if answer:
                return answer[0]
            time.sleep(0.05)
        raise Refused('fresh_query_timeout')

    def download(self, request, timeout=7200):
        # Drain old events BEFORE requesting; flags are supplementary, never proof.
        self.poll(lambda unused: None)
        started = now()
        need(request(), 'official_download_not_scheduled')
        answer = []
        def handler(message):
            if message.callback != 3406:
                return
            need(message.size == C.sizeof(DownloadResult), 'download_callback_size_mismatch')
            record = DownloadResult.from_buffer_copy(C.string_at(message.data, message.size))
            if record.app != api.APP or str(record.item) != ITEM:
                return
            need(record.result == 1 and not answer, 'official_download_callback_failed')
            answer.append({'callback_id': 3406, 'app_id': record.app,
                           'workshop_id': str(record.item), 'result': record.result,
                           'requested_utc': started, 'received_utc': now()})
        deadline, last = time.monotonic() + timeout, time.monotonic()
        while time.monotonic() < deadline:
            self.poll(handler)
            if answer:
                return answer[0]
            if time.monotonic() - last >= 30:
                api.emit({'status': 'WAITING_FOR_OFFICIAL_DOWNLOAD_CALLBACK', 'workshop_id': ITEM})
                last = time.monotonic()
            time.sleep(0.1)
        raise Refused('official_download_callback_timeout')


class ReadDownloadSteam(api.Steam):
    ALLOWED = frozenset(('CreateQueryUGCDetailsRequest', 'SetAllowCachedResponse',
                        'SendQueryUGCRequest', 'GetQueryUGCResult', 'ReleaseQueryUGCRequest',
                        'DownloadItem', 'GetItemState', 'GetItemInstallInfo'))

    def ug(self, suffix, result, types, *args):
        need(suffix in self.ALLOWED, 'publication_or_unreviewed_sdk_call_forbidden')
        return super().ug(suffix, result, types, *args)

    def __enter__(self):
        super().__enter__()
        try:
            self.dispatch = Dispatch(self)
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def fresh_item(self):
        ids = (C.c_uint64 * 1)(int(ITEM))
        query = self.ug('CreateQueryUGCDetailsRequest', C.c_uint64,
                        [C.POINTER(C.c_uint64), C.c_uint32], ids, 1)
        need(query not in (0, api.INVALID), 'invalid_details_query')
        try:
            need(self.ug('SetAllowCachedResponse', C.c_bool, [C.c_uint64, C.c_uint32], query, 0),
                 'cannot_require_uncached_query')
            call = self.ug('SendQueryUGCRequest', C.c_uint64, [C.c_uint64], query)
            record = self.dispatch.query(call, query)
            raw = C.create_string_buffer(9784)
            need(self.ug('GetQueryUGCResult', C.c_bool,
                         [C.c_uint64, C.c_uint32, C.c_void_p], query, 0, raw), 'cannot_read_details_query')
            data = raw.raw
            item, result, kind, creator, consumer = struct.unpack_from('<Qiiii', data)
            answer = {'id': str(item), 'result': result, 'file_type': kind,
                      'creator_app_id': creator, 'consumer_app_id': consumer,
                      'owner': str(struct.unpack_from('<Q', data, 8160)[0]),
                      'visibility': struct.unpack_from('<i', data, 8180)[0],
                      'time_updated': struct.unpack_from('<I', data, 8172)[0],
                      'total_files_bytes': struct.unpack_from('<Q', data, 9776)[0],
                      'banned': bool(data[8184]), 'tags_truncated': bool(data[8186]),
                      'tags': data[8187:9212].split(b'\0')[0].decode('utf8', errors='strict'),
                      'cached': bool(record.cached), 'observed_utc': now(), 'max_cache_age_seconds': 0}
            validate_item(answer)
            return answer
        finally:
            self.ug('ReleaseQueryUGCRequest', C.c_bool, [C.c_uint64], query)

    def download_existing(self):
        flags = self.ug('GetItemState', C.c_uint32, [C.c_uint64], int(ITEM))
        need(flags & 4 and not flags & (2 | 8 | 16 | 32 | 64), 'prior_item_not_stable_installed')
        callback = self.dispatch.download(lambda: self.ug('DownloadItem', C.c_bool,
                                              [C.c_uint64, C.c_bool], int(ITEM), True))
        flags = self.ug('GetItemState', C.c_uint32, [C.c_uint64], int(ITEM))
        need(flags & 4 and not flags & (2 | 8 | 16 | 32 | 64), 'download_not_stable_installed')
        size, timestamp = C.c_uint64(), C.c_uint32()
        folder = C.create_string_buffer(4096)
        need(self.ug('GetItemInstallInfo', C.c_bool,
                     [C.c_uint64, C.POINTER(C.c_uint64), C.c_void_p, C.c_uint32, C.POINTER(C.c_uint32)],
                     int(ITEM), C.byref(size), folder, len(folder), C.byref(timestamp)),
             'official_install_info_unavailable')
        actual_folder = api.pack.handoff.regular_path(Path(folder.value.decode('utf8', errors='strict')))
        need(actual_folder == api.pack.handoff.regular_path(INSTALLED)
             and size.value == TOTAL_BYTES, 'install_identity_mismatch')
        return {'callback': callback, 'flags': flags, 'install_folder': str(actual_folder),
                'size_on_disk': size.value, 'installation_timestamp': timestamp.value}


def validate_item(item):
    expected = {'id': ITEM, 'result': 1, 'file_type': 0, 'creator_app_id': api.APP,
                'consumer_app_id': api.APP, 'owner': api.OWNER, 'visibility': 3,
                'time_updated': REMOTE_TIME, 'total_files_bytes': TOTAL_BYTES,
                'cached': False, 'max_cache_age_seconds': 0, 'banned': False,
                'tags_truncated': False}
    need(all(type(item.get(key)) is type(value) and item.get(key) == value
             for key, value in expected.items())
         and 'Custom Game' in item.get('tags', '').split(','), 'remote_item_changed_or_cached')


def installed_manifest():
    raw = api.pack.read_metadata(api.pack.handoff.regular_path(ACF), 16 * 1024 * 1024)
    data = api.pack.handoff.kv(raw.decode('utf-8-sig'))['appworkshop']
    need(data.get('appid') == str(api.APP), 'acf_app_mismatch')
    row = data['workshopitemsinstalled'][ITEM]
    need(row.get('manifest') == MANIFEST and row.get('size') == str(TOTAL_BYTES)
         and row.get('timeupdated') == str(REMOTE_TIME), 'installed_manifest_changed')
    return {'manifest': row['manifest'], 'size': row['size'], 'timeupdated': row['timeupdated']}


def snapshot_trust(candidate):
    """The historical snapshot cannot redefine the checkout's public trust."""
    gates = (*api.pack.handoff.GATE_FILES, *api.pack.handoff.ENTRY_GATE_FILES,
             api.pack.handoff.ACCESS_FILE)
    need(len(TRUST_PINS) == 12 and set(TRUST_PINS) == set((*gates, *PUBLIC_FILES)),
         'v05_trust_inventory_definition_changed')
    trusted = api.pack.handoff.regular_path(TRUSTED)
    checkout = api.pack.handoff.regular_path(ROOT)
    candidate = api.pack.handoff.regular_path(candidate)
    need(trusted.is_dir(), 'v05_trust_directory_missing')
    found = set()
    for path in trusted.rglob('*'):
        need(not api.pack.protect_data.linked(path), 'v05_trust_link_forbidden')
        if path.is_file():
            found.add(path.relative_to(trusted).as_posix())
    need(found == set(TRUST_PINS), 'v05_trust_inventory_changed')
    snapshots = {}
    for name, expected in TRUST_PINS.items():
        path = api.pack.protect_data.source_path(trusted, name)
        snapshots[path] = read_pinned(path, expected)
    # Public policy/key must additionally match this reviewed checkout. They are
    # never accepted merely because the candidate/snapshot supplied them.
    for name in PUBLIC_FILES:
        path = api.pack.protect_data.source_path(checkout, name)
        snapshots[path] = read_pinned(path, TRUST_PINS[name])
    for name in gates:
        path = api.pack.protect_data.source_path(candidate, name)
        snapshots[path] = read_pinned(path, TRUST_PINS[name])
    return snapshots


@contextmanager
def trusted_root(candidate):
    snapshots = snapshot_trust(candidate)  # All public/gate pins BEFORE globals change.
    trusted = api.pack.handoff.regular_path(TRUSTED)
    old_root, old_policy = api.pack.handoff.ROOT, api.pack.handoff.POLICY
    api.pack.handoff.ROOT = trusted
    api.pack.handoff.POLICY = trusted / PUBLIC_FILES[0]
    try:
        yield snapshots
    finally:
        api.pack.handoff.ROOT, api.pack.handoff.POLICY = old_root, old_policy


def signed_download(inputs, download, candidate=CANDIDATE):
    read_pinned(candidate / api.pack.handoff.MANIFEST, CANDIDATE_MANIFEST_SHA, api.pack.MAX_MANIFEST)
    read_pinned(candidate / api.pack.handoff.SIGNATURE, CANDIDATE_SIGNATURE_SHA, api.pack.MAX_SIGNATURE)
    with trusted_root(candidate) as trust_snapshots:
        _, manifest, signature, snapshots = api.pack.authenticate(candidate)
    need(signature['release_sequence'] == SEQUENCE and signature['content_sha256'] == CONTENT,
         'signed_v05_identity_mismatch')
    folder = api.pack.handoff.regular_path(Path(download['install_folder']))
    need(folder == api.pack.handoff.regular_path(INSTALLED), 'verification_folder_mismatch')
    index = folder / (ITEM + '.vpk')
    need(set(folder.iterdir()) == set(api.pack.package_paths(index)), 'download_has_extra_or_missing_files')
    for entry in folder.iterdir():
        api.pack.handoff.regular_path(entry)
    before = api.pack.package_inventory(index)
    need(before == inputs['baseline']['package_files'] and len(before) == 5,
         'download_package_inventory_mismatch')
    verification = api.pack.verify_vpk(index, manifest)
    need(verification.get('files') == 6630 and verification.get('archive_count') == 4
         and all(verification.get(key) is True for key in CHECKS), 'download_full_verification_failed')
    need(api.pack.package_inventory(index) == before, 'download_changed_during_verification')
    need(set(folder.iterdir()) == set(api.pack.package_paths(index)), 'download_directory_changed_during_verification')
    for entry in folder.iterdir():
        api.pack.handoff.regular_path(entry)
    api.pack.inventory_unchanged(candidate, snapshots)
    for path, raw in trust_snapshots.items():
        read_pinned(path, sha(raw))
    return {'content_sha256': CONTENT, 'release_sequence': SEQUENCE,
            'vpk_sha256': before[0]['sha256'], 'package_files': before,
            'signature_valid': True, 'verification': verification,
            'manifest': installed_manifest(), 'verified_utc': now()}


def verify_live(inputs, steam, candidate=CANDIDATE):
    pre = steam.fresh_item()
    download = steam.download_existing()
    need(download['callback']['app_id'] == api.APP and download['callback']['workshop_id'] == ITEM
         and download['callback']['result'] == 1 and download['callback']['callback_id'] == 3406,
         'official_callback_proof_missing')
    verified = signed_download(inputs, download, candidate)
    post = steam.fresh_item()
    validate_item(pre)
    validate_item(post)
    need({key: value for key, value in pre.items() if key != 'observed_utc'}
         == {key: value for key, value in post.items() if key != 'observed_utc'},
         'remote_changed_during_full_verification')
    local_inputs()  # All pinned inputs, original receipt and canonical still intact.
    return {'schema': 1, 'status': 'FRESH_OFFICIAL_V05_FULLY_VERIFIED',
            'verified_utc': now(), 'pending_sha256': PENDING_SHA, 'baseline_sha256': BASELINE_SHA,
            'historical_receipt_sha256': HISTORICAL_SHA, 'pre_query': pre,
            'download': download, 'signed_download': verified, 'post_query': post,
            'publisher_calls': 0, 'items_created': 0, 'updates_submitted': 0,
            'native_test': 'NOT_RUN', 'multiplayer_acceptance': 'NOT_RUN',
            'ready_for_public_release': False}


def write_exclusive(path, raw):
    api.pack.handoff.regular_path(path, must_exist=False)
    with path.open('xb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def create_output(path):
    path = api.pack.handoff.regular_path(path, must_exist=False)
    root = api.pack.handoff.regular_path(OUTPUT, must_exist=False)
    need(api.pack.runtime.within(path, root) and path != root, 'output_outside_reconciliation_root')
    need(not path.exists(), 'output_directory_already_exists')
    path.mkdir(parents=True, exist_ok=False)
    return path


def commit_local(inputs, proof, directory):
    """Caller holds publication_lock. The only replace is the canonical journal."""
    local_inputs()  # CAS before creating any immutable transaction records.
    need(proof.get('status') == 'FRESH_OFFICIAL_V05_FULLY_VERIFIED'
         and proof.get('pending_sha256') == PENDING_SHA, 'live_proof_missing')
    validate_item(proof.get('pre_query', {}))
    validate_item(proof.get('post_query', {}))
    callback = proof.get('download', {}).get('callback', {})
    verified = proof.get('signed_download', {})
    need(callback.get('callback_id') == 3406 and callback.get('app_id') == api.APP
         and callback.get('workshop_id') == ITEM and callback.get('result') == 1
         and verified.get('signature_valid') is True and verified.get('release_sequence') == SEQUENCE
         and verified.get('content_sha256') == CONTENT and verified.get('vpk_sha256') == INDEX
         and verified.get('package_files') == inputs['baseline']['package_files']
         and verified.get('manifest', {}).get('manifest') == MANIFEST
         and all(verified.get('verification', {}).get(key) is True for key in CHECKS)
         and verified.get('verification', {}).get('files') == 6630
         and verified.get('verification', {}).get('archive_count') == 4,
         'full_live_proof_incomplete')
    observed = datetime.fromisoformat(proof['verified_utc'])
    age = (datetime.now(timezone.utc) - observed).total_seconds()
    need(0 <= age <= 300, 'live_proof_not_fresh')
    backup = directory / 'pending_v08.original.json'
    failed = directory / 'failed_attempt_v08.json'
    receipt = directory / 'fresh_verification.json'
    failed_attempt = {'schema': 1, 'status': 'FAILED_V08_NOT_PUBLISHED',
                      'historical_only': True, 'callback_id': 3404, 'result': 2,
                      'diagnosis': 'manifest_upload_timeout', 'manifest_bytes': 104842,
                      'sdk_failure_log_sha256': SDK_LOG_SHA, 'pending_sha256': PENDING_SHA,
                      'pending_state': inputs['pending'], 'upload_report': inputs['failure_report'],
                      'prior_native_acceptance': {name: inputs['pending'].get(name) for name in NATIVE_FIELDS},
                      'v08_official_download_verified': False, 'v08_multiplayer_acceptance': 'NOT_RUN'}
    receipt_raw = encoded(proof)
    write_exclusive(backup, inputs['pending_raw'])
    write_exclusive(failed, encoded(failed_attempt))
    write_exclusive(receipt, receipt_raw)
    write_exclusive(directory / 'v08_sdk_failure.log', inputs['sdk_log_raw'])
    state = copy.deepcopy(inputs['baseline'])
    for name in list(state):
        if name.startswith('download_') or name in NATIVE_FIELDS or name == 'last_submit_failure':
            state.pop(name)
    state.update(status='RECONCILED_UNLISTED_V05_REMOTE_VERIFIED', uploaded=True,
                 native_test='HISTORICAL_ONLY_NOT_RUN_DURING_RECONCILIATION',
                 ordinary_workshop_match='HISTORICAL_ONLY_SEE_RECONCILIATION',
                 ready_for_public_release=False, download_verified=True, download_manifest=MANIFEST,
                 historical_acceptance={name: inputs['baseline'].get(name) for name in NATIVE_FIELDS},
                 failed_attempts=[failed_attempt],
                 reconciliation={'schema': 1, 'performed_utc': now(), 'from_pending_sha256': PENDING_SHA,
                                 'baseline_state_sha256': BASELINE_SHA, 'original_pending_backup': str(backup),
                                 'fresh_verification': str(receipt), 'fresh_verification_sha256': sha(receipt_raw),
                                 'failed_attempt': str(failed), 'historical_receipt_sha256': HISTORICAL_SHA,
                                 'verified_remote_release_sequence': SEQUENCE, 'verified_remote_manifest': MANIFEST,
                                 'publisher_calls': 0, 'native_acceptance_promoted': False})
    need(all(state[field] == inputs['baseline'][field] for field in FACT_FIELDS), 'reconciled_facts_changed')
    raw = encoded(state)
    temporary = STATE.with_name(STATE.name + '.reconcile-' + uuid.uuid4().hex + '.part')
    try:
        write_exclusive(temporary, raw)
        local_inputs()  # CAS immediately before atomic replace; no external work after this.
        os.replace(temporary, STATE)
    finally:
        if temporary.exists():
            temporary.unlink()
    return {'status': 'LOCAL_JOURNAL_RECONCILED_TO_VERIFIED_V05', 'journal_sha256': sha(raw),
            'original_pending_sha256': PENDING_SHA, 'workshop_id': ITEM,
            'release_sequence': SEQUENCE, 'uploaded': True, 'updates_submitted': 0,
            'native_test': 'NOT_RUN', 'ready_for_public_release': False, 'evidence_directory': str(directory)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--verify', action='store_true', help='Request official download and write new verification evidence')
    modes.add_argument('--apply', action='store_true', help='Fresh verification then local-only atomic journal reconciliation')
    parser.add_argument('--output-dir', type=Path, help='New directory beneath output/workshop_reconciliation_20261025')
    args = parser.parse_args(argv)
    try:
        inputs = local_inputs()
        if not args.verify and not args.apply:
            need(args.output_dir is None, 'output_requires_explicit_verify_or_apply')
            api.emit({'status': 'READ_ONLY_RECONCILIATION_PLAN', 'journal_unchanged': True,
                      'expected_pending_sha256': PENDING_SHA, 'baseline_release_sequence': SEQUENCE,
                      'baseline_manifest': MANIFEST, 'workshop_id': ITEM, 'steam_initialized': False,
                      'files_written': 0, 'publisher_calls': 0, 'ready_for_public_release': False})
            return 0
        proposed = args.output_dir or OUTPUT / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_') + uuid.uuid4().hex)
        directory = create_output(proposed)
        if args.apply:
            with api.publication_lock(STATE):
                inputs = local_inputs()
                with ReadDownloadSteam() as steam:
                    proof = verify_live(inputs, steam)
                result = commit_local(inputs, proof, directory)
        else:
            with ReadDownloadSteam() as steam:
                proof = verify_live(inputs, steam)
            write_exclusive(directory / 'fresh_verification.json', encoded(proof))
            result = {'status': 'VERIFIED_V05_JOURNAL_UNCHANGED', 'journal_unchanged': True,
                      'evidence_directory': str(directory), 'updates_submitted': 0,
                      'ready_for_public_release': False}
        api.emit(result)
        return 0
    except Exception as error:
        # Do not echo arbitrary native exception strings, payloads or SDK messages.
        api.emit({'status': 'RECONCILIATION_REFUSED_JOURNAL_PRESERVED',
                  'reason': str(error) if isinstance(error, Refused) else type(error).__name__,
                  'publisher_calls': 0, 'ready_for_public_release': False})
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
