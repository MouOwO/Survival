"""Fixed SHOP02 download verification; default is a local read-only plan.

--download requires reviewed package pins and the actual successful upload's
Steam manifest. It refreshes the existing subscription once (1313), requests
one download (3406), then verifies all five installed VPK files and 6637 signed
entries between fresh, uncached official queries. Never publish or edit a
canonical journal. A failure never schedules an automatic retry.
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True

import argparse
import ctypes as C
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import re
import shutil
import struct
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import reconcile_workshop_pending as callbacks
import verify_workshop_download as verify

api, need = callbacks.api, callbacks.need
ITEM = '3824360109'
SEQUENCE = 2026102604
CONTENT = 'b38b10b76aaa4674c8a2d0ffc436922723a793f4b71665916956b4323f40b744'
INDEX = '75a90c772844287890f58c156d08aba1680e3fba8ed69d89fc7a638e8c53845b'
TOTAL_BYTES = 3767101843
CANDIDATE = Path('D:/Survival_发布候选/20261026_ws4_native_shop_v04')
TRUSTED = CANDIDATE.with_name(CANDIDATE.name + '_trusted_source')
REPORT = ROOT / 'output/native_shop_qr_20261026/package_build.json'
STATE = ROOT / 'output/four_accounts_20261022/steam_upload_state.json'
OUTPUT = ROOT / 'output/native_shop_qr_20261026/download_evidence'
INSTALLED, ACF = callbacks.INSTALLED, callbacks.ACF
MINIMUM_REMOTE_UPDATED = 1792978097  # Verified SHOP01 v3 publication; new v4 must be newer.
EXPECTED_NAMES = [ITEM + '.vpk', *(f'{ITEM}_{index:03}.vpk' for index in range(4))]

# Fill only from the completed local package report and real SDK upload success.
# There are no caller flags to supply replacement identities or bypass a pin.
REPORT_SHA = 'a80c617b66b1d093ce41f4612f5395f901839b296a975fb9453c5f1d1c69d01e'
EXPECTED_STEAM_MANIFEST = '6642037826174811075'  # v4 SDK3404 + same-item workshop_log, 2026-10-26T04:37:09Z.
METADATA_PINS = {
    '_release_manifest.json': 'b7f6377a80c00684a58abed1a73d10e555b51451216f7bca010e8682abd7d269',
    '_release_signature.json': '948fb302e69654f9e6b6f50eb15d4af04d6617fd7b3eb0b6b7b877a028ea6759',
}
PUBLIC_PINS = {
    'tools/release_security/protection_policy.json': '8e8c2e50a6a983dda7336a083377bbf55de8625f89f5633977c8d7901b53da96',
    'tools/release_security/trusted_public_key.pem': '1717c28cb7476e5eb5326b780589c880e86d42cc026b6d4728d95ac95e8873bf',
}


def sha_pin(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def manifest_pinned():
    return (isinstance(EXPECTED_STEAM_MANIFEST, str) and EXPECTED_STEAM_MANIFEST.isascii()
            and EXPECTED_STEAM_MANIFEST.isdecimal() and 0 < int(EXPECTED_STEAM_MANIFEST) < 2**64)


def require_local_pins():
    # Pending package pins refuse before even opening a release file. A local
    # plan never needs a completed Steam manifest and never initializes Steam.
    need(sha_pin(INDEX) and sha_pin(REPORT_SHA) and type(TOTAL_BYTES) is int and TOTAL_BYTES > 0
         and set(METADATA_PINS) == {'_release_manifest.json', '_release_signature.json'}
         and all(sha_pin(value) for value in METADATA_PINS.values())
         and set(PUBLIC_PINS) == {'tools/release_security/protection_policy.json',
                                  'tools/release_security/trusted_public_key.pem'}
         and all(sha_pin(value) for value in PUBLIC_PINS.values()),
         'shop02_completed_local_release_pins_not_yet_finalized')


def local_inputs(require_success=False):
    require_local_pins()
    for name, expected in METADATA_PINS.items():
        callbacks.read_pinned(CANDIDATE / name, expected, api.pack.MAX_MANIFEST)
    # Trust comes from independently pinned checkout public files, never a key
    # supplied by the candidate. No historical gate or mutable checkout main is
    # substituted for a frozen candidate's own signed inventory.
    for name, expected in PUBLIC_PINS.items():
        callbacks.read_pinned(ROOT / name, expected)
    manifest = api.load(CANDIDATE / api.pack.handoff.MANIFEST)
    document = api.load(CANDIDATE / api.pack.handoff.SIGNATURE)
    api.pack.runtime.validate_manifest(manifest)
    policy, public_path = api.pack.handoff.trusted_policy()
    signature = api.pack.verify_signed_snapshot(manifest, document, public_path,
        policy['integrity']['minimum_release_sequence'], policy['integrity']['trusted_key_id'])
    need(signature['content_sha256'] == CONTENT and signature['release_sequence'] == SEQUENCE
         and len(manifest['files']) == 6637, 'shop02_signed_identity_mismatch')
    need(sha_pin(REPORT_SHA), 'shop02_completed_package_report_not_yet_pinned')
    report = api.pack.handoff.decode_json(callbacks.read_pinned(REPORT, REPORT_SHA))
    rows = report.get('package_files', [])
    need(report.get('content_sha256') == CONTENT and report.get('release_sequence') == SEQUENCE
         and report.get('signature_valid') is True and report.get('dry_run') is False
         and report.get('payload_changed') is False and report.get('workshop_upload_performed') is False
         and isinstance(rows, list) and len(rows) == 5
         and [row.get('name') for row in rows] == EXPECTED_NAMES
         and all(type(row.get('bytes')) is int and row['bytes'] > 0 and sha_pin(row.get('sha256')) for row in rows)
         and report.get('vpk_sha256') == rows[0]['sha256'] == INDEX
         and sum(row['bytes'] for row in rows) == TOTAL_BYTES
         and report.get('files') == 6637 and report.get('full_input_hash_verification') is True,
         'shop02_package_report_mismatch')
    raw = api.pack.read_metadata(api.pack.handoff.regular_path(STATE), 4 * 1024 * 1024)
    state = api.pack.handoff.decode_json(raw)
    success = (state.get('uploaded') is True and state.get('owner') == api.OWNER
               and state.get('app_id') == api.APP and state.get('workshop_id') == ITEM
               and state.get('visibility_requested') == 3 and state.get('release_sequence') == SEQUENCE
               and state.get('content_sha256') == CONTENT and state.get('vpk_sha256') == rows[0]['sha256']
               and state.get('vpk_bytes') == rows[0]['bytes'] and state.get('package_files') == rows)
    if require_success:
        need(success, 'shop02_successful_original_item_upload_journal_required')
    return report, state, raw, success


def validate_remote(item, total):
    expected = {'id': ITEM, 'result': 1, 'file_type': 0, 'creator_app_id': api.APP,
                'consumer_app_id': api.APP, 'owner': api.OWNER, 'visibility': 3,
                'total_files_bytes': total, 'cached': False, 'max_cache_age_seconds': 0,
                'banned': False, 'tags_truncated': False}
    need(all(type(item.get(key)) is type(value) and item.get(key) == value for key, value in expected.items())
         and type(item.get('time_updated')) is int and item['time_updated'] > MINIMUM_REMOTE_UPDATED
         and 'Custom Game' in item.get('tags', '').split(','), 'shop02_remote_identity_or_freshness_mismatch')


class SHOP02Steam(api.Steam):
    # Reuse only the reviewed SDK initialization and ManualDispatch ABI. No
    # historical v05 validator, reconcile/apply operation or RunCallbacks pump.
    ALLOWED = frozenset(('CreateQueryUGCDetailsRequest', 'SetAllowCachedResponse',
                        'SendQueryUGCRequest', 'GetQueryUGCResult', 'ReleaseQueryUGCRequest',
                        'SubscribeItem', 'DownloadItem', 'GetItemState', 'GetItemInstallInfo'))

    def __init__(self, total):
        self.total = total

    def ug(self, suffix, result, types, *args):
        need(suffix in self.ALLOWED, 'shop02_publication_or_unreviewed_sdk_call_forbidden')
        return super().ug(suffix, result, types, *args)

    def __enter__(self):
        super().__enter__()
        try:
            self.dispatch = callbacks.Dispatch(self)
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def fresh_item(self):
        ids = (C.c_uint64 * 1)(int(ITEM))
        query = self.ug('CreateQueryUGCDetailsRequest', C.c_uint64,
                        [C.POINTER(C.c_uint64), C.c_uint32], ids, 1)
        need(query not in (0, api.INVALID), 'shop02_invalid_query')
        try:
            need(self.ug('SetAllowCachedResponse', C.c_bool, [C.c_uint64, C.c_uint32], query, 0),
                 'shop02_uncached_query_required')
            call = self.ug('SendQueryUGCRequest', C.c_uint64, [C.c_uint64], query)
            response = self.dispatch.query(call, query)
            raw = C.create_string_buffer(9784)
            need(self.ug('GetQueryUGCResult', C.c_bool, [C.c_uint64, C.c_uint32, C.c_void_p], query, 0, raw),
                 'shop02_cannot_read_query')
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
                      'cached': bool(response.cached), 'max_cache_age_seconds': 0,
                      'observed_utc': callbacks.now()}
            validate_remote(answer, self.total)
            return answer
        finally:
            self.ug('ReleaseQueryUGCRequest', C.c_bool, [C.c_uint64], query)

    def refresh_subscription_once(self, timeout=120):
        before = self.ug('GetItemState', C.c_uint32, [C.c_uint64], int(ITEM))
        need(before & 1 and not before & (2 | 16 | 32 | 64), 'shop02_subscription_not_stable_for_refresh')
        self.dispatch.poll(lambda unused: None)
        call = self.ug('SubscribeItem', C.c_uint64, [C.c_uint64], int(ITEM))
        need(call not in (0, api.INVALID), 'shop02_subscribe_not_scheduled')
        need(C.sizeof(verify.Subscribed) == 16 and verify.Subscribed.item.offset == 8,
             'shop02_subscribe_abi_mismatch')
        received = []
        started = callbacks.now()

        def handler(message):
            if message.callback != 703:
                return
            need(message.size == C.sizeof(callbacks.CallCompleted), 'shop02_subscribe_completed_size_mismatch')
            completed = callbacks.CallCompleted.from_buffer_copy(C.string_at(message.data, message.size))
            if completed.call != call:
                return
            need(not received and completed.callback == 1313 and completed.size == C.sizeof(verify.Subscribed),
                 'shop02_subscribe_callback_identity_mismatch')
            record, failed = verify.Subscribed(), C.c_bool()
            ok = self.dispatch.result(self.dispatch.pipe, call, C.byref(record), C.sizeof(record), 1313, C.byref(failed))
            need(ok and not failed.value and record.result == 1 and str(record.item) == ITEM,
                 'shop02_subscribe_callback_failed')
            received.append({'callback_id': 1313, 'result': record.result, 'workshop_id': ITEM,
                             'requested_utc': started, 'received_utc': callbacks.now()})

        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.dispatch.poll(handler)
            if received:
                after = self.ug('GetItemState', C.c_uint32, [C.c_uint64], int(ITEM))
                need(after & 1 and not after & (2 | 16 | 32 | 64),
                     'shop02_subscription_refresh_started_automatic_download_no_second_request')
                return {'callback': received[0], 'prior_flags': before, 'flags': after,
                        'subscribe_calls': 1, 'unsubscribe_calls': 0}
            time.sleep(0.05)
        raise callbacks.Refused('shop02_subscribe_callback_timeout_no_retry')

    def download_installed(self):
        before = self.ug('GetItemState', C.c_uint32, [C.c_uint64], int(ITEM))
        need(before & 1 and not before & (2 | 16 | 32 | 64), 'shop02_another_download_or_unsupported_state')
        callback = self.dispatch.download(lambda: self.ug('DownloadItem', C.c_bool,
                                          [C.c_uint64, C.c_bool], int(ITEM), True))
        flags = self.ug('GetItemState', C.c_uint32, [C.c_uint64], int(ITEM))
        need(flags & 1 and flags & 4 and not flags & (2 | 8 | 16 | 32 | 64), 'shop02_install_not_stable_after_3406')
        size, stamp, folder = C.c_uint64(), C.c_uint32(), C.create_string_buffer(4096)
        need(self.ug('GetItemInstallInfo', C.c_bool,
                     [C.c_uint64, C.POINTER(C.c_uint64), C.c_void_p, C.c_uint32, C.POINTER(C.c_uint32)],
                     int(ITEM), C.byref(size), folder, len(folder), C.byref(stamp)), 'shop02_install_info_missing')
        actual = api.pack.handoff.regular_path(Path(folder.value.decode('utf8', errors='strict')))
        self.install_observation = {'callback': callback, 'prior_flags': before, 'flags': flags,
            'install_folder': str(actual), 'size_on_disk': size.value, 'installation_timestamp': stamp.value,
            'expected_folder': str(INSTALLED.resolve()), 'expected_size_on_disk': self.total,
            'expected_manifest': EXPECTED_STEAM_MANIFEST, 'download_requested': True, 'native_test': 'NOT_RUN'}
        need(actual == api.pack.handoff.regular_path(INSTALLED) and size.value == self.total,
             'shop02_install_folder_or_size_mismatch')
        return self.install_observation.copy()


def save_evidence(value):
    directory = OUTPUT / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_') + uuid.uuid4().hex)
    api.pack.handoff.regular_path(directory, must_exist=False)
    directory.mkdir(parents=True, exist_ok=False)
    path = directory / 'verification.json'
    callbacks.write_exclusive(path, callbacks.encoded(value))
    return path


def download_once(package, state, state_raw):
    import test_entry  # Its process inventory is read-only; never launch/relay.
    processes = test_entry.process_inventory()
    need(processes.get('steam_running') is True and processes.get('dota_pids') == [],
         'shop02_close_dota_keep_steam_before_download')
    total = sum(row['bytes'] for row in package['package_files'])
    with SHOP02Steam(total) as steam:
        pre = steam.fresh_item()
        subscribed = steam.refresh_subscription_once()
        try:
            downloaded = steam.download_installed()
        except callbacks.Refused:
            observation = getattr(steam, 'install_observation', None)
            if observation is not None:
                path = save_evidence({'schema': 1, 'status': 'SHOP02_INSTALL_IDENTITY_REFUSED',
                    'observed_utc': callbacks.now(), 'pre_query': pre, 'subscription_refresh': subscribed,
                    'install_observation': observation, 'canonical_journal_written': False,
                    'automatic_retry_performed': False, 'full_verification': 'NOT_RUN_IDENTITY_MISMATCH'})
                api.emit({'status': 'SHOP02_INSTALL_DIAGNOSIS_SAVED', 'evidence': str(path)})
            raise
        installed = api.pack.handoff.regular_path(Path(downloaded['install_folder']))
        need(set(installed.iterdir()) == {installed / name for name in EXPECTED_NAMES},
             'shop02_installed_exact_five_files_required')
        for path in installed.iterdir():
            api.pack.handoff.regular_path(path)  # Reject links before reading VPK bytes.
        verified = verify.verify_installed(downloaded.copy(), CANDIDATE, state)
        need(verified['signature_valid'] is True and verified['vpk_sha256'] == package['vpk_sha256']
             and verified['package_files'] == package['package_files']
             and verified['verification'].get('files') == 6637
             and verified['verification'].get('archive_count') == 4
             and all(verified['verification'].get(key) is True for key in callbacks.CHECKS),
             'shop02_full_installed_verification_incomplete')
        folder, index = Path(verified['install_folder']), Path(verified['vpk'])
        need(set(folder.iterdir()) == set(api.pack.package_paths(index)), 'shop02_installed_directory_changed')
        for path in folder.iterdir():
            api.pack.handoff.regular_path(path)
        need(api.pack.package_inventory(index) == package['package_files'], 'shop02_installed_bytes_changed')
        post = steam.fresh_item()
    need({key: value for key, value in pre.items() if key != 'observed_utc'}
         == {key: value for key, value in post.items() if key != 'observed_utc'}, 'shop02_remote_changed_during_verification')
    acf_raw = api.pack.read_metadata(api.pack.handoff.regular_path(ACF), 16 * 1024 * 1024)
    acf = api.pack.handoff.kv(acf_raw.decode('utf-8-sig'))['appworkshop']
    row = acf['workshopitemsinstalled'][ITEM]
    need(acf.get('appid') == str(api.APP) and row.get('manifest') == EXPECTED_STEAM_MANIFEST
         and row.get('size') == str(total) and row.get('timeupdated') == str(post['time_updated']),
         'shop02_installed_manifest_not_fresh')
    _, _, current_raw, _ = local_inputs(True)
    need(current_raw == state_raw, 'shop02_canonical_journal_changed_during_download')
    receipt = {'schema': 1, 'status': 'OFFICIAL_SHOP02_DOWNLOAD_FULLY_VERIFIED',
        'observed_utc': callbacks.now(), 'workshop_id': ITEM, 'release_sequence': SEQUENCE,
        'content_sha256': CONTENT, 'vpk_sha256': package['vpk_sha256'],
        'steam_manifest': EXPECTED_STEAM_MANIFEST, 'manifest_is_string': True,
        'pre_query': pre, 'subscription_refresh': subscribed, 'download': downloaded,
        'verification': verified, 'post_query': post, 'acf_installed_entry': row,
        'package_report_sha256': REPORT_SHA, 'canonical_journal_sha256': hashlib.sha256(state_raw).hexdigest(),
        'canonical_journal_unchanged': True, 'items_created': 0, 'updates_submitted': 0,
        'native_test': 'NOT_RUN', 'multiplayer_acceptance': 'NOT_RUN', 'ready_for_public_release': False}
    path = save_evidence(receipt)
    return {'status': receipt['status'], 'workshop_id': ITEM, 'release_sequence': SEQUENCE,
            'steam_manifest': EXPECTED_STEAM_MANIFEST, 'files': 6637, 'archive_count': 4,
            'canonical_journal_unchanged': True, 'evidence': str(path)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    args = parser.parse_args(argv)
    try:
        package, state, state_raw, success = local_inputs(args.download)
        required = sum(row['bytes'] for row in package['package_files']) + 1024**3
        free = shutil.disk_usage(INSTALLED.anchor).free
        if not args.download:
            api.emit({'status': 'READ_ONLY_SHOP02_DOWNLOAD_PLAN', 'workshop_id': ITEM,
                      'release_sequence': SEQUENCE, 'successful_shop02_upload_journal': success,
                      'free_bytes': free, 'conservative_required_free_bytes': required,
                      'space_admitted': free >= required, 'steam_manifest_pinned': manifest_pinned(),
                      'will_refresh_existing_subscription_once': True, 'steam_initialized': False, 'files_written': 0})
            return 0
        need(manifest_pinned(), 'shop02_real_sdk_success_manifest_not_yet_pinned')
        need(free >= required, 'shop02_insufficient_full_package_plus_one_gib_staging_space')
        with api.publication_lock(STATE):
            # Recheck while serialized with the normal publisher, without ever
            # editing its state. Only a download evidence directory is created.
            package, state, locked_raw, _ = local_inputs(True)
            need(locked_raw == state_raw, 'shop02_canonical_journal_changed_before_download')
            api.emit(download_once(package, state, state_raw))
        return 0
    except Exception as error:
        api.emit({'status': 'SHOP02_DOWNLOAD_VERIFICATION_REFUSED',
                  'reason': str(error) if isinstance(error, callbacks.Refused) else type(error).__name__,
                  'updates_submitted': 0, 'canonical_journal_written': False, 'automatic_retry_performed': False})
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
