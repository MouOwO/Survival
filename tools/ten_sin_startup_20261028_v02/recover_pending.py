"""One pinned 2805 failure recovery: fully verify remote 2804 before journal CAS.

Never uploads. Preserves the original pending journal and failure log. The
download uses the existing immutable 2804 verifier, with its successful prior
upload proved by both the pending previous-release record and preflight log.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import os
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/ten_sin_startup_20261028_v02/recovery_02'
STATE = ROOT / 'output/four_accounts_20261022/steam_upload_state.json'
PENDING_SHA = 'e05dca1890bfd5179f03dfb6abede3d750796568314351dabf3f9e23e13dbd35'
spec = importlib.util.spec_from_file_location('ten_sin_2804_recovery_verifier',
    ROOT / 'tools/ten_sin_startup_20261028/verify_download.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)
protocol = verifier.protocol
api, need = protocol.api, protocol.need


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf8')


def exclusive(path, raw):
    with path.open('xb') as stream:
        stream.write(raw)


def run(apply=False):
    with api.publication_lock(STATE):
        raw = STATE.read_bytes()
        need(sha(raw) == PENDING_SHA, 'pending journal changed; refuse recovery')
        pending = json.loads(raw)
        need(pending['status'] == 'SUBMIT_REQUEST_PENDING' and pending['uploaded'] is False
             and pending['release_sequence'] == 2026102805, 'unexpected pending release')
        previous = pending['previous_release']
        need(previous['uploaded'] is True and previous['release_sequence'] == 2026102804
             and previous['content_sha256'] == verifier.CONTENT, 'previous upload identity missing')
        log = ROOT / 'output/ten_sin_startup_20261028_v02/upload_preflight.log'
        rows = [json.loads(line) for line in log.read_text(encoding='utf-8-sig').splitlines()
                if line.startswith('{')]
        before = next(row['state'] for row in rows if row['status'] == 'VERIFIED_NO_PUBLICATION')
        need(before['uploaded'] is True and before['release_sequence'] == 2026102804
             and before['package_files'] == previous['package_files']
             and before['owner'] == api.OWNER and before['workshop_id'] == '3824360109',
             'original preflight state does not prove the prior upload')
        failure = ROOT / 'output/ten_sin_startup_20261028_v02/upload.log'
        need('Steam API callback 3404 returned EResult=2' in failure.read_text(encoding='utf8'),
             'original failure receipt missing')
        need(not OUT.exists(), 'new recovery evidence directory required')
        # Full 2804 signed candidate/VPK validation, preserving the pending 2805
        # state as the snapshot. No success flag for 2805 is ever fabricated.
        inputs = verifier.local_inputs(False, full=True)
        need(inputs['state_sha256'] == PENDING_SHA and inputs['total'] == 3767365890,
             'recovery snapshot mismatch')
        # Installed bytes must match the proved successful 2804 record, while
        # snapshots and the receipt still identify the unchanged pending 2805
        # journal. Never present the failed 2805 attempt as uploaded.
        inputs['state'] = before
        if not apply:
            return dict(status='READ_ONLY_RECOVERY_PLAN', pending_sequence=2026102805,
                        remote_release_to_verify=2026102804, publisher_calls=0)
        OUT.mkdir(parents=True, exist_ok=False)
        exclusive(OUT / 'pending_2805.original.json', raw)
        exclusive(OUT / 'upload_failure.original.log', failure.read_bytes())
        exclusive(OUT / 'preflight_2804.original.log', log.read_bytes())
        result = protocol.download_once(inputs)
        need(result['status'] == 'OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED'
             and result['release_sequence'] == 2026102804, 'previous release not fully verified')
        receipt = Path(result['evidence'])
        need(STATE.read_bytes() == raw, 'pending journal changed during live verification')
        state = copy.deepcopy(before)
        failed = dict(release_sequence=2026102805, status='FAILED_3404_ERESULT_2_REMOTE_STILL_2804',
                      pending_sha256=PENDING_SHA, pending_backup=str(OUT / 'pending_2805.original.json'),
                      failure_log=str(OUT / 'upload_failure.original.log'),
                      failure_log_sha256=sha(failure.read_bytes()), uploaded=False)
        state.setdefault('failed_attempts', []).append(failed)
        state.update(status='RECONCILED_UNLISTED_2804_VERIFIED_2805_FAILURE_PRESERVED',
                     uploaded=True, download_verified=True, download_manifest=result['steam_manifest'],
                     native_test='NOT_RUN', ready_for_public_release=False,
                     reconciliation=dict(from_pending_sha256=PENDING_SHA,
                         verified_remote_release_sequence=2026102804,
                         verified_remote_manifest=result['steam_manifest'],
                         receipt=str(receipt), receipt_sha256=sha(receipt.read_bytes()),
                         failure_preserved=True, publisher_calls=0))
        for key in ['content_sha256', 'release_sequence', 'vpk_sha256', 'package_files']:
            need(state[key] == before[key], 'recovery changed verified prior-release facts')
        exclusive(OUT / 'reconciliation.json', encoded(state['reconciliation']))
        temp = STATE.with_name(STATE.name + '.ten-sin-recovery.part')
        exclusive(temp, encoded(state))
        need(STATE.read_bytes() == raw, 'final journal compare-and-swap failed')
        os.replace(temp, STATE)
        return dict(status=state['status'], steam_manifest=result['steam_manifest'],
                    receipt=str(receipt), publisher_calls=0, pending_backup_preserved=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.apply), ensure_ascii=False))
    except Exception as error:
        print(json.dumps(dict(status='RECOVERY_REFUSED', error=str(error)), ensure_ascii=False))
        raise SystemExit(1)
