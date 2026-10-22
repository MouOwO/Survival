"""Upload an already reviewed signed test candidate with Valve's installed SDK.

Default is read-only. --apply is an external publication action: it creates or
updates ONE private item, journals its ID before upload, and never makes it public.
Uses the logged-in Steam client, not web cookies, passwords or extracted tokens.
Native game and four-machine tests remain separate from successful transfer.
"""
from __future__ import annotations

import argparse
import ctypes as C
from contextlib import contextmanager, nullcontext
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stream_workshop_vpk as pack

APP = 570
OWNER = '76561198845461206'
BASE = 76561197960265728
INVALID = 2**64 - 1
ROOT = Path(__file__).resolve().parents[1]
DLL = pack.handoff.INSTALL / 'game/bin/win64/steam_api64.dll'
DLL_SHA256 = '2a785780af426dfc5c809087d100db8d4ff41a1e1a2956ad5473689e77e3c863'


class Created(C.Structure):
    _pack_ = 8
    _fields_ = [('result', C.c_int32), ('item', C.c_uint64), ('legal', C.c_bool)]


class Submitted(C.Structure):
    _pack_ = 8
    _fields_ = [('result', C.c_int32), ('legal', C.c_bool), ('item', C.c_uint64)]


class Queried(C.Structure):
    _pack_ = 8
    _fields_ = [('handle', C.c_uint64), ('result', C.c_int32),
                ('returned', C.c_uint32), ('total', C.c_uint32),
                ('cached', C.c_bool), ('cursor', C.c_char * 256)]


class Strings(C.Structure):
    _pack_ = 8
    _fields_ = [('values', C.POINTER(C.c_char_p)), ('count', C.c_int32)]


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def journal(path: Path, value: dict):
    """Persist recovery state before an irreversible call; never discard an ID."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.part')
    value['updated_at_utc'] = datetime.now(timezone.utc).isoformat()
    with temporary.open('w', encoding='utf8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def load(path):
    return pack.handoff.load_json(path)


@contextmanager
def publication_lock(state_path):
    """OS lock survives a stale lock file; process exit releases it safely."""
    import msvcrt
    lock_path = state_path.with_name(state_path.name + '.lock')
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open('a+b') as stream:
        if stream.seek(0, 2) == 0:
            stream.write(b'0')
            stream.flush()
        stream.seek(0)
        msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        try:
            yield
        finally:
            stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)


class Steam:
    """Win64 UGC021 flat ABI from Valve's public Steamworks SDK 1.65 headers."""
    def __enter__(self):
        if os.name != 'nt' or C.sizeof(C.c_void_p) != 8:
            raise ValueError('Only the reviewed Windows x64 ABI is supported')
        if pack.runtime.digest(DLL) != DLL_SHA256:
            raise ValueError('Installed Steam API changed; review SDK versions before use')
        self.previous = {key: os.environ.get(key) for key in ('SteamAppId', 'SteamGameId')}
        self.initialized = False
        try:
            for key in self.previous:
                os.environ[key] = str(APP)
            with os.add_dll_directory(str(DLL.parent)):
                self.dll = C.CDLL(str(DLL))
            error = C.create_string_buffer(1024)
            result = self.fn('SteamAPI_InitFlat', C.c_int32, [C.c_void_p])(error)
            if result:
                raise RuntimeError(f'Steam init failed ({result}): ' + error.value.decode('utf8', errors='replace'))
            self.initialized = True
            self.user = self.fn('SteamAPI_SteamUser_v023', C.c_void_p, [])()
            self.utils = self.fn('SteamAPI_SteamUtils_v010', C.c_void_p, [])()
            self.ugc = self.fn('SteamAPI_SteamUGC_v021', C.c_void_p, [])()
            if not all((self.user, self.utils, self.ugc)):
                raise RuntimeError('Required versioned Steam interface unavailable')
            self.owner = str(self.fn('SteamAPI_ISteamUser_GetSteamID', C.c_uint64, [C.c_void_p])(self.user))
            app = self.fn('SteamAPI_ISteamUtils_GetAppID', C.c_uint32, [C.c_void_p])(self.utils)
            logged = self.fn('SteamAPI_ISteamUser_BLoggedOn', C.c_bool, [C.c_void_p])(self.user)
            if app != APP or self.owner != OWNER or not logged:
                raise ValueError('Dota app/current logged-in owner differs from reviewed test account')
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *unused):
        if self.initialized:
            self.fn('SteamAPI_Shutdown', None, [])()
            self.initialized = False
        for key, value in self.previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def fn(self, name, result, args):
        function = getattr(self.dll, name)
        function.restype, function.argtypes = result, args
        return function

    def ug(self, suffix, result, types, *args):
        return self.fn('SteamAPI_ISteamUGC_' + suffix, result, [C.c_void_p, *types])(self.ugc, *args)

    def wait(self, call, record, callback_id, *, timeout=120, progress=None):
        if not call:
            raise RuntimeError('Steam rejected async API call before scheduling')
        deadline, last = time.monotonic() + timeout, 0
        failed = C.c_bool()
        completed = self.fn('SteamAPI_ISteamUtils_IsAPICallCompleted', C.c_bool,
                            [C.c_void_p, C.c_uint64, C.POINTER(C.c_bool)])
        get_result = self.fn('SteamAPI_ISteamUtils_GetAPICallResult', C.c_bool,
                             [C.c_void_p, C.c_uint64, C.c_void_p, C.c_int32, C.c_int32, C.POINTER(C.c_bool)])
        pump = self.fn('SteamAPI_RunCallbacks', None, [])
        while time.monotonic() < deadline:
            pump()
            if completed(self.utils, call, C.byref(failed)):
                if failed.value:
                    raise RuntimeError('Steam async call failed at transport layer')
                response = record()
                if not get_result(self.utils, call, C.byref(response), C.sizeof(response), callback_id, C.byref(failed)) or failed.value:
                    raise RuntimeError('Steam API callback could not be read with the reviewed ABI')
                if response.result != 1:
                    raise RuntimeError(f'Steam API callback {callback_id} returned EResult={response.result}')
                return response
            if progress and time.monotonic() - last >= 10:
                progress()
                last = time.monotonic()
            time.sleep(0.1)
        raise TimeoutError('Steam async timeout; preserve state and query existing item before retrying')

    def owned(self):
        items = []
        for page in range(1, 101):
            query = self.ug('CreateQueryUserUGCRequest', C.c_uint64,
                            [C.c_uint32, C.c_int32, C.c_int32, C.c_int32, C.c_uint32, C.c_uint32, C.c_uint32],
                            int(OWNER) - BASE, 0, -1, 0, APP, APP, page)
            if query in (0, INVALID):
                raise RuntimeError('Steam owner query handle invalid')
            try:
                call = self.ug('SendQueryUGCRequest', C.c_uint64, [C.c_uint64], query)
                response = self.wait(call, Queried, 3401)
                if response.handle != query:
                    raise RuntimeError('Steam owner query response handle differs')
                for index in range(response.returned):
                    # UGC021 adds a uint64 total-files size at 9776. Older
                    # UGC017's 9776-byte buffer would overflow with this DLL.
                    raw = C.create_string_buffer(9784)
                    if not self.ug('GetQueryUGCResult', C.c_bool,
                                   [C.c_uint64, C.c_uint32, C.c_void_p], query, index, raw):
                        raise RuntimeError('Cannot read owned Workshop item')
                    data = raw.raw
                    item, result, file_type, creator, consumer = struct.unpack_from('<Qiiii', data)
                    owner = str(struct.unpack_from('<Q', data, 8160)[0])
                    if result != 1 or creator != APP or consumer != APP or owner != OWNER:
                        raise RuntimeError('Owned item identity/app verification failed')
                    items.append({'id': str(item), 'file_type': file_type,
                                  'title': data[24:153].split(b'\0')[0].decode('utf8'),
                                  'owner': owner, 'visibility': struct.unpack_from('<i', data, 8180)[0],
                                  'tags': data[8187:9212].split(b'\0')[0].decode('utf8', errors='replace')})
                if len(items) >= response.total:
                    return items
                if not response.returned:
                    raise RuntimeError('Steam owner query truncated before total results')
            finally:
                self.ug('ReleaseQueryUGCRequest', C.c_bool, [C.c_uint64], query)
        raise RuntimeError('Steam owner query exceeded bounded page count')


def validate_upload(candidate: Path, vpk: Path, listing_path: Path, build_report: Path):
    """Independently recheck signed bytes; a build report alone is insufficient."""
    candidate = pack.handoff.regular_path(candidate)
    vpk = pack.handoff.regular_path(vpk)
    if pack.runtime.within(vpk, pack.handoff.INSTALL) or pack.runtime.within(vpk, candidate):
        raise ValueError('Upload folder must be outside Dota and the signed source')
    if list(vpk.parent.iterdir()) != [vpk] or vpk.suffix != '.vpk':
        raise ValueError('Content folder must contain exactly one verified VPK')
    manifest = load(candidate / pack.handoff.MANIFEST)
    pack.runtime.validate_manifest(manifest)
    document = load(candidate / pack.handoff.SIGNATURE)
    policy, public_path = pack.handoff.trusted_policy()
    signature = pack.verify_signed_snapshot(manifest, document, public_path,
        policy['integrity']['minimum_release_sequence'], policy['integrity']['trusted_key_id'])
    pack.handoff.require_single_map(candidate)
    pack.runtime.require_production(candidate)
    ids = pack.handoff.configured_ids(candidate)
    listing = load(listing_path)
    if (listing['real_money_payments'] is not False or listing['visibility_requested'] != 'private'
            or sorted(listing['tester_steamids64']) != ids or OWNER not in ids
            or listing['map'] != 'template_map' or listing['max_players'] != 4
            or listing['runtime_content_sha256'] != manifest['content_sha256']
            or listing['release_sequence'] != signature['release_sequence']):
        raise ValueError('Reviewed listing does not match the signed four-account production candidate')
    report = load(build_report)
    if (report['dry_run'] is not False or not report['signature_valid']
            or report['payload_changed'] is not False or report['workshop_upload_performed'] is not False
            or report['content_sha256'] != manifest['content_sha256']
            or report['vpk_sha256'] != pack.runtime.digest(vpk)):
        raise ValueError('Built VPK differs from reviewed local package report')
    verification = pack.verify_vpk(vpk, manifest)
    if not pack.runtime.verify(candidate, manifest)['ok']:
        raise ValueError('Candidate changed after signed build')
    cover = pack.handoff.regular_path(listing_path.parent / listing['cover'])
    if cover.stat().st_size >= 1024 * 1024 or pack.runtime.digest(cover) != listing['cover_sha256']:
        raise ValueError('Preview must match reviewed cover and remain under 1 MiB')
    return listing, cover, {'content_sha256': manifest['content_sha256'],
            'release_sequence': signature['release_sequence'], 'vpk_sha256': report['vpk_sha256'],
            'vpk_bytes': vpk.stat().st_size, 'verification': verification}


def publish(steam: Steam, listing, cover, vpk, facts, state_path, *, apply=False):
    if pack.runtime.within(state_path.resolve(), vpk.parent.resolve()):
        raise ValueError('Recovery journal must stay outside the uploaded content directory')
    owned = steam.owned()
    emit({'status': 'OWNER_ITEMS_VERIFIED', 'owner': steam.owner, 'app_id': APP, 'items': owned})
    state = load(state_path) if state_path.exists() else None
    if not apply:
        return {'status': 'VERIFIED_NO_PUBLICATION', 'facts': facts, 'state': state,
                'native_test': 'NOT_RUN', 'ready_for_public_release': False}
    if state is None:
        if owned:
            raise ValueError('Existing owned items found; choose/recover the intended item before creating another')
        state = {'schema': 1, 'owner': OWNER, 'app_id': APP, **facts,
                 'visibility_requested': 2, 'workshop_id': None, 'status': 'CREATE_REQUEST_PENDING'}
        journal(state_path, state)
        call = steam.ug('CreateItem', C.c_uint64, [C.c_uint32, C.c_int32], APP, 0)
        response = steam.wait(call, Created, 3403)
        if not 0 < response.item < INVALID:
            raise RuntimeError('Steam created response has invalid published ID; recover pending state manually')
        state.update(workshop_id=str(response.item), status='PRIVATE_ITEM_CREATED',
                     legal_agreement_required=bool(response.legal))
        journal(state_path, state)  # Persist the ID BEFORE any follow-up action.
        emit({'status': state['status'], 'workshop_id': state['workshop_id'], 'legal_agreement_required': bool(response.legal)})
    elif (state.get('owner') != OWNER or state.get('app_id') != APP
          or state.get('content_sha256') != facts['content_sha256'] or not state.get('workshop_id')):
        raise ValueError('Recovery journal has no confirmed ID or differs from current reviewed candidate; do not create again')
    else:
        matching = [item for item in owned if item['id'] == state['workshop_id']]
        if len(matching) != 1 or matching[0]['owner'] != OWNER:
            raise ValueError('Journal ID is not uniquely present in the current owner list; recover it before updating')
        if state.get('uploaded') is True:
            return state
        if state.get('status') == 'SUBMIT_REQUEST_PENDING':
            raise ValueError('Prior submit result is unknown; query/download the confirmed item before explicitly retrying')
    if state.get('legal_agreement_required'):
        raise ValueError('Steam requires the owner to accept its Workshop agreement; no automatic acceptance performed')
    item = int(state['workshop_id'])
    # Set the official package basename only after a genuine ID was persisted.
    target = vpk.with_name(str(item) + '.vpk')
    if target != vpk:
        if target.exists():
            raise ValueError('Refusing to replace an existing ID-named package')
        vpk.rename(target)
        vpk = target
    if pack.runtime.digest(vpk) != facts['vpk_sha256']:
        raise ValueError('Package changed before SubmitItemUpdate')
    handle = steam.ug('StartItemUpdate', C.c_uint64, [C.c_uint32, C.c_uint64], APP, item)
    if handle in (0, INVALID):
        raise RuntimeError('Steam update handle is invalid')
    def setter(suffix, types, *args):
        if not steam.ug(suffix, C.c_bool, [C.c_uint64, *types], handle, *args):
            raise RuntimeError('Steam rejected ' + suffix)
    setter('SetItemUpdateLanguage', [C.c_char_p], b'schinese')
    setter('SetItemTitle', [C.c_char_p], listing['title'].encode('utf8'))
    setter('SetItemDescription', [C.c_char_p], listing['description'].encode('utf8'))
    setter('SetItemVisibility', [C.c_int32], 2)
    values = (C.c_char_p * 1)(b'Custom Game')
    tags = Strings(values, 1)
    setter('SetItemTags', [C.POINTER(Strings), C.c_bool], C.byref(tags), False)
    setter('SetItemContent', [C.c_char_p], str(vpk.parent).encode('utf8'))
    setter('SetItemPreview', [C.c_char_p], str(cover).encode('utf8'))
    state.update(status='SUBMIT_REQUEST_PENDING', package=str(vpk), uploaded=False)
    journal(state_path, state)
    call = steam.ug('SubmitItemUpdate', C.c_uint64, [C.c_uint64, C.c_char_p], handle,
                    b'Private four-account noncommercial test; signed runtime sequence 2026102202.')
    def progress():
        done, total = C.c_uint64(), C.c_uint64()
        stage = steam.ug('GetItemUpdateProgress', C.c_int32,
                         [C.c_uint64, C.POINTER(C.c_uint64), C.POINTER(C.c_uint64)],
                         handle, C.byref(done), C.byref(total))
        emit({'status': 'TRANSFER_PROGRESS', 'workshop_id': str(item), 'stage': stage,
              'bytes_processed': done.value, 'bytes_total': total.value})
    response = steam.wait(call, Submitted, 3404, timeout=4 * 3600, progress=progress)
    if response.item != item:
        raise RuntimeError('Steam submitted item ID differs from journal')
    state.update(status='SUBMITTED_PRIVATE_PENDING_DOWNLOAD_AND_NATIVE_TEST', uploaded=True,
                 legal_agreement_required=bool(response.legal), native_test='NOT_RUN',
                 ready_for_public_release=False)
    journal(state_path, state)
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inspect', action='store_true', help='Only read current owner/app/published list')
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--vpk', type=Path)
    parser.add_argument('--listing', type=Path, default=ROOT / 'publishing/workshop/test_listing.json')
    parser.add_argument('--build-report', type=Path)
    parser.add_argument('--state-file', type=Path, default=ROOT / 'output/four_accounts_20261022/steam_upload_state.json')
    parser.add_argument('--apply', action='store_true', help='Authorized external action: create/update ONE PRIVATE test item')
    args = parser.parse_args()
    try:
        if args.inspect:
            if args.apply:
                raise ValueError('Read-only inspect cannot be combined with apply')
            with Steam() as steam:
                emit({'status': 'READ_ONLY_STEAM_INSPECTION', 'owner': steam.owner,
                      'app_id': APP, 'items': steam.owned(), 'items_created': 0, 'updates_submitted': 0})
            return 0
        if not all((args.candidate, args.vpk, args.build_report)):
            raise ValueError('Supply signed candidate, single external VPK and verified build report')
        listing, cover, facts = validate_upload(args.candidate, args.vpk, args.listing, args.build_report)
        if pack.runtime.within(args.state_file.resolve(), args.vpk.parent.resolve()):
            raise ValueError('Recovery journal must remain outside upload content')
        with publication_lock(args.state_file) if args.apply else nullcontext():
            with Steam() as steam:
                emit(publish(steam, listing, cover, args.vpk, facts, args.state_file, apply=args.apply))
        return 0
    except Exception as error:
        emit({'status': 'BLOCKED_PRESERVE_RECOVERY_JOURNAL', 'error': type(error).__name__ + ': ' + str(error),
              'ready_for_public_release': False})
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
