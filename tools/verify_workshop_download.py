"""Download the journaled private/unlisted test item and verify signed VPK entries.

Default only inspects. --download subscribes the current authorized owner to
the existing item and requests its Steam-managed download. No publication,
server changes, credential injection or native play result is performed.
"""
import argparse
import ctypes as C
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import steam_workshop_upload as api


class Subscribed(C.Structure):
    _pack_ = 8
    _fields_ = [('result', C.c_int32), ('item', C.c_uint64)]


def check(steam, state, *, download=False):
    if (state.get('uploaded') is not True or state.get('owner') != api.OWNER
            or state.get('app_id') != api.APP or not state.get('workshop_id')):
        raise ValueError('A successful reviewed upload journal is required')
    owned = [row for row in steam.owned() if row['id'] == state['workshop_id']]
    visibility = state.get('visibility_requested', 2)
    if visibility not in (2, 3):
        raise ValueError('Only private or explicitly approved unlisted journals are supported')
    if (len(owned) != 1 or owned[0]['owner'] != api.OWNER
            or owned[0]['visibility'] != visibility or 'Custom Game' not in owned[0]['tags'].split(',')):
        raise ValueError('Current Steam item differs from its reviewed owner/visibility/custom-game tags')
    item = int(state['workshop_id'])
    if not download:
        return {'status': 'PRIVATE_ITEM_READ_ONLY_VERIFIED' if visibility == 2 else 'UNLISTED_ITEM_READ_ONLY_VERIFIED', 'item': owned[0],
                'native_test': 'NOT_RUN', 'download_requested': False}
    subscribed = steam.wait(steam.ug('SubscribeItem', C.c_uint64, [C.c_uint64], item), Subscribed, 1313)
    if subscribed.item != item:
        raise RuntimeError('Subscribe result differs from reviewed item')
    if not steam.ug('DownloadItem', C.c_bool, [C.c_uint64, C.c_bool], item, True):
        raise RuntimeError('Steam declined download request; subscription may still have succeeded')
    deadline, last = time.monotonic() + 2 * 3600, 0
    while time.monotonic() < deadline:
        steam.fn('SteamAPI_RunCallbacks', None, [])()
        flags = steam.ug('GetItemState', C.c_uint32, [C.c_uint64], item)
        if flags & 4 and not flags & (8 | 16 | 32):
            size, timestamp = C.c_uint64(), C.c_uint32()
            folder = C.create_string_buffer(4096)
            if not steam.ug('GetItemInstallInfo', C.c_bool,
                    [C.c_uint64, C.POINTER(C.c_uint64), C.c_void_p, C.c_uint32, C.POINTER(C.c_uint32)],
                    item, C.byref(size), folder, len(folder), C.byref(timestamp)):
                raise RuntimeError('Steam installed item but install folder is unavailable')
            return {'status': 'STEAM_DOWNLOAD_INSTALLED_PENDING_HASH_CHECK', 'item': owned[0],
                    'install_folder': folder.value.decode('utf8'), 'size_on_disk': size.value,
                    'timestamp': timestamp.value, 'native_test': 'NOT_RUN', 'download_requested': True}
        if time.monotonic() - last >= 10:
            done, total = C.c_uint64(), C.c_uint64()
            steam.ug('GetItemDownloadInfo', C.c_bool,
                [C.c_uint64, C.POINTER(C.c_uint64), C.POINTER(C.c_uint64)], item, C.byref(done), C.byref(total))
            api.emit({'status': 'DOWNLOAD_PROGRESS', 'workshop_id': str(item), 'flags': flags,
                      'downloaded_bytes': done.value, 'total_bytes': total.value})
            last = time.monotonic()
        time.sleep(0.1)
    raise TimeoutError('Steam download timed out; do not substitute the local upload source for a downloaded copy')


def verify_installed(result, candidate, state):
    folder = api.pack.handoff.regular_path(Path(result['install_folder']))
    files = list(folder.iterdir())
    target = folder / (state['workshop_id'] + '.vpk')
    if set(files) != set(api.pack.package_paths(target)):
        raise ValueError('Downloaded folder differs from the submitted VPK and numbered archives')
    manifest = api.load(candidate / api.pack.handoff.MANIFEST)
    document = api.load(candidate / api.pack.handoff.SIGNATURE)
    policy, public_path = api.pack.handoff.trusted_policy()
    signature = api.pack.verify_signed_snapshot(manifest, document, public_path,
            policy['integrity']['minimum_release_sequence'], policy['integrity']['trusted_key_id'])
    if signature['content_sha256'] != state['content_sha256']:
        raise ValueError('Signed candidate differs from successful upload journal')
    sha = api.pack.runtime.digest(target)
    if sha != state['vpk_sha256'] or target.stat().st_size != state['vpk_bytes']:
        raise ValueError('Downloaded VPK differs from submitted bytes')
    inventory = api.pack.package_inventory(target)
    if (len(inventory) > 1 or 'package_files' in state) and state.get('package_files') != inventory:
        raise ValueError('Downloaded archives differ from submitted bytes')
    result.update(status=('PRIVATE_WORKSHOP_DOWNLOAD_FULLY_VERIFIED' if state.get('visibility_requested', 2) == 2
                          else 'UNLISTED_WORKSHOP_DOWNLOAD_FULLY_VERIFIED'), vpk=str(target),
                  vpk_sha256=sha, verification=api.pack.verify_vpk(target, manifest),
                  signature_valid=True, package_files=inventory, ready_for_public_release=False)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-file', type=Path,
                        default=api.ROOT / 'output/four_accounts_20261022/steam_upload_state.json')
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    try:
        state = api.load(args.state_file)
        with api.Steam() as steam:
            result = check(steam, state, download=args.download)
        if args.download:
            result = verify_installed(result, args.candidate, state)
        if args.report:
            if args.report.exists():
                raise ValueError('Refusing to overwrite an existing verification report')
            with args.report.open('x', encoding='utf8') as stream:
                json.dump(result, stream, ensure_ascii=False, indent=2)
        api.emit(result)
        return 0
    except Exception as error:
        api.emit({'status': 'DOWNLOAD_OR_VERIFICATION_BLOCKED', 'error': type(error).__name__ + ': ' + str(error),
                  'native_test': 'NOT_RUN', 'ready_for_public_release': False})
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
