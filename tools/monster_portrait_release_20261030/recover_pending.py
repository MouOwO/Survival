"""Preserve failed portrait 3003 and verify a fresh official 2901 download before CAS.

No publication or automatic retry. Missing full download proof leaves the
canonical pending journal intact, even if the remote metadata still says 2901.
"""
from pathlib import Path
import argparse, copy, hashlib, importlib.util, json, os, sys
sys.dont_write_bytecode = True
import build_release as portrait
build = portrait.base
spec = importlib.util.spec_from_file_location('map2902_prior_download',
    build.ROOT / 'tools/archive_release_20261029/verify_download.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)
api, need = verifier.api, verifier.need
FAILED_SEQUENCE=2026103003
FAILED_REPORT=portrait.ROOT/'output/portrait_transition_publish_20261030'
OUT=portrait.REPORT/'failure_recovery_3003'


def raw_log(path):
    raw = path.read_bytes()
    return raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8-sig')


def exclusive(path, raw):
    with path.open('xb') as stream:
        stream.write(raw)


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf8')


def run(apply=False):
    with api.publication_lock(build.JOURNAL):
        raw = build.JOURNAL.read_bytes()
        pending = json.loads(raw)
        package = build.load(FAILED_REPORT / 'package_v04.json')
        need(pending.get('status') == 'SUBMIT_REQUEST_PENDING' and pending.get('uploaded') is False
             and pending.get('release_sequence') == FAILED_SEQUENCE
             and pending.get('content_sha256') == package['content_sha256']
             and pending.get('package_files') == package['package_files'], 'Unexpected pending portrait 3003 release')
        rows = [json.loads(line) for line in raw_log(FAILED_REPORT / 'upload-preflight-utf8.log').splitlines()
                if line.startswith('{')]
        before = next(row['state'] for row in rows if row.get('status') == 'VERIFIED_NO_PUBLICATION')
        previous = pending.get('previous_release', {})
        need(before.get('uploaded') is True and before.get('release_sequence') == 2026102901
             and before.get('owner') == api.OWNER and before.get('workshop_id') == build.ITEM
             and before.get('content_sha256') == build.BASE_CONTENT
             and before.get('package_files') == previous.get('package_files')
             and previous.get('release_sequence') == 2026102901 and previous.get('uploaded') is True,
             'Original successful baseline upload required')
        failure = FAILED_REPORT / 'upload.log'
        need('Steam API callback 3404 returned EResult=2' in raw_log(failure), 'Actual failed callback required')
        need(not OUT.exists(), 'New recovery evidence directory required')
        if apply:
            import test_entry
            processes = test_entry.process_inventory()
            need(processes.get('steam_running') is True and processes.get('dota_pids') == [],
                 'Close Dota and keep Steam running before recovery download')
        inputs = verifier.local_inputs(False, full=True)
        need(inputs['state_sha256'] == build.sha(raw) and inputs['report']['content_sha256'] == build.BASE_CONTENT,
             'Baseline recovery snapshot changed')
        inputs['state'] = before
        inputs['expected_manifest'] = verifier.protocol.journal_manifest(before)
        if not apply:
            return dict(status='READ_ONLY_RECOVERY_PLAN', failed_sequence=FAILED_SEQUENCE,
                        remote_release_to_verify=2026102901, publisher_calls=0)
        OUT.mkdir(parents=True, exist_ok=False)
        exclusive(OUT / 'pending.original.json', raw)
        exclusive(OUT / 'upload_failure.original.log', failure.read_bytes())
        exclusive(OUT / 'preflight.original.log', (FAILED_REPORT / 'upload-preflight-utf8.log').read_bytes())
        verifier.protocol.OUTPUT = OUT / 'download_evidence'
        result = verifier.download_once(inputs)
        need(result.get('status') == 'OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED'
             and result.get('release_sequence') == 2026102901, 'Previous release not fully verified')
        need(build.JOURNAL.read_bytes() == raw, 'Pending journal changed during verification')
        receipt = Path(result['evidence'])
        state = copy.deepcopy(before)
        state.setdefault('failed_attempts', []).append(dict(release_sequence=FAILED_SEQUENCE,
            status='PORTRAIT_3003_FAILED_3404_ERESULT_2_REMOTE_STILL_2901', uploaded=False,
            pending_sha256=build.sha(raw), pending_backup=str(OUT / 'pending.original.json'),
            failure_log_sha256=build.sha(failure.read_bytes())))
        state.update(status='RECONCILED_2901_VERIFIED_PORTRAIT_3003_FAILURE_PRESERVED', uploaded=True,
            download_verified=True, download_manifest=result['steam_manifest'],
            ready_for_public_release=False,
            reconciliation=dict(from_pending_sha256=build.sha(raw), receipt=str(receipt),
                receipt_sha256=build.sha(receipt.read_bytes()), verified_remote_release_sequence=2026102901,
                verified_remote_manifest=result['steam_manifest'], publisher_calls=0, failure_preserved=True))
        exclusive(OUT / 'reconciliation.json', encoded(state['reconciliation']))
        temp = build.JOURNAL.with_name(build.JOURNAL.name + '.portrait3003-recovery.part')
        exclusive(temp, encoded(state))
        need(build.JOURNAL.read_bytes() == raw, 'Final journal compare-and-swap failed')
        os.replace(temp, build.JOURNAL)
        return dict(status=state['status'], receipt=str(receipt), publisher_calls=0)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.apply), ensure_ascii=False))
    except Exception as error:
        print(json.dumps(dict(status='PORTRAIT_RECOVERY_REFUSED', error=str(error)), ensure_ascii=False))
        raise SystemExit(1)
