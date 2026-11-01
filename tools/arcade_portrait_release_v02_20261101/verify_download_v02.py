"""Explicit signed1102 adapter for the unchanged official1313/3406 download.

No arguments prints a static plan. --preflight reads/authenticates local files
only; --download requires an exact successful same-release canonical journal.
The historical protocol's terminal180 summary is preserved. Its authoritative
verification.json instead records the actual184 supplied by local_inputs.

Costs: import/static plan reads bounded tool source only; preflight is one full
signed package verification O(package bytes + resource count), plus a fixed set
of metadata snapshots. Download inherits the reviewed pre/locked revalidation
and one refresh/download; no new retry, timer, game loop or native query exists.
"""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import importlib.util
import json
import re
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


# Fresh private instances: never retarget a frozen v01 module in sys.modules.
checks = module('portrait1102_download_private_checks', HERE/'release_checks.py')
b, need = checks.b, checks.b.need
PROTOCOL = b.ROOT/'tools/arcade_cleanup_20261027/verify_download.py'
PROTOCOL_SHA = '1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f'
need(hashlib.sha256(PROTOCOL.read_bytes().replace(b'\r\n', b'\n')).hexdigest() == PROTOCOL_SHA,
     'Frozen official1313/3406 download protocol changed')
protocol = module('portrait1102_download_private_protocol', PROTOCOL)
api = protocol.api
SOURCE_REVISION = '048a2d6b675325cd511abb01c5a122343052b2f7'
SUCCESS_STATUS = 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'
REPORT_SHA = None


def validated_package(expected_sha, *, full=False):
    need(re.fullmatch(r'[a-f0-9]{64}', expected_sha or '') is not None,
         'Explicit completed signed package report SHA required')
    package, manifest, signed = checks.validated_package(expected_sha, full=full)
    names = [b.ITEM+'.vpk', *(b.ITEM+'_%03d.vpk' % i for i in range(4))]
    need(b.SEQUENCE == 2026110102 and b.ITEM == '3824360109' and len(b.PAYLOADS) == 13
         and package.get('source_revision') == SOURCE_REVISION
         and package.get('release_sequence') == b.SEQUENCE
         and package.get('files') == manifest.get('file_count') == 6918
         and package.get('protected_modules_preserved') == 184
         and signed.get('release_sequence') == b.SEQUENCE
         and signed.get('signature_valid') is True
         and package.get('changed_runtime_paths') == sorted(b.PAYLOADS)
         and [row['name'] for row in package.get('package_files', [])] == names,
         'Exact048 signed1102 thirteen-path6918/184 five-volume package required')
    return package, manifest, signed


def successful_same_release(state, package, manifest):
    """Current top-level identity only; historical manifests cannot qualify."""
    return (state.get('uploaded') is True and state.get('status') == SUCCESS_STATUS
        and state.get('owner') == api.OWNER and state.get('app_id') == api.APP
        and state.get('workshop_id') == b.ITEM and state.get('visibility_requested') == 3
        and state.get('release_sequence') == b.SEQUENCE
        and state.get('content_sha256') == manifest['content_sha256']
        and state.get('vpk_sha256') == package['vpk_sha256']
        and state.get('vpk_bytes') == package['package_files'][0]['bytes']
        and state.get('package_files') == package['package_files']
        and state.get('legal_agreement_required') is False)


def local_inputs(require_success=False, *, full=False):
    snapshots = {}
    read = lambda path: protocol.read_snapshot(path, api.pack.MAX_MANIFEST, snapshots)
    read(b.REPORT/'package.json')
    read(b.VIEW/api.pack.handoff.MANIFEST)
    read(b.VIEW/api.pack.handoff.SIGNATURE)
    state_raw = read(b.JOURNAL)
    state = api.pack.handoff.decode_json(state_raw)
    package, manifest, signature = validated_package(REPORT_SHA, full=full)
    need(state.get('uploaded') is True and state.get('status') == SUCCESS_STATUS,
         'Unknown/pending publication must be reconciled separately; journal preserved')
    success = successful_same_release(state, package, manifest)
    if require_success:
        need(success, 'Successful exact1102 original-item publication required')
    elif not success:
        parent_raw = read(b.BASE_REPORT)
        parent = api.pack.handoff.decode_json(parent_raw)
        need(hashlib.sha256(parent_raw).hexdigest() == b.BASE_REPORT_SHA,
             'Frozen3102 parent package report changed')
        b.require_parent_journal(state, parent)
    # Includes the entire raw journal: previous_release and all19 historical
    # entries are preserved, not rewritten or borrowed as a current manifest.
    protocol.unchanged(snapshots)
    return dict(report=package, manifest=manifest, signature=signature, state=state,
        snapshots=snapshots, success=success,
        expected_manifest=protocol.journal_manifest(state) if success else None,
        total=sum(row['bytes'] for row in package['package_files']), report_sha256=REPORT_SHA,
        state_sha256=hashlib.sha256(state_raw).hexdigest(), protected_modules=184)


def configure(package):
    need(b.pack.runtime.digest(b.BASE_RECORD) == b.BASE_RECORD_SHA,
         'Frozen3102 delivery record changed')
    observed = datetime.fromisoformat(b.load(b.BASE_RECORD)['observed_utc'])
    need(observed.tzinfo is not None, 'Parent delivery timestamp must include timezone')
    values = dict(ITEM=b.ITEM, SEQUENCE=b.SEQUENCE, FILE_COUNT=6918,
        CONTENT=package['content_sha256'], CANDIDATE=b.VIEW, TRUSTED=b.TRUSTED,
        VPK=b.OUTPUT/(b.ITEM+'.vpk'), REPORT=b.REPORT/'package.json', STATE=b.JOURNAL,
        OUTPUT=b.REPORT/'download_evidence', MINIMUM_REMOTE_UPDATED=int(observed.timestamp()),
        local_inputs=local_inputs)
    for name, value in values.items():
        setattr(protocol, name, value)


def static_plan():
    return dict(status='STATIC_V02_OFFICIAL_DOWNLOAD_PLAN_NO_EFFECTS',
        workshop_id=b.ITEM, release_sequence=2026110102, runtime_source_revision=SOURCE_REVISION,
        runtime_files=6918, protected_modules=184, scoped_runtime_paths=13,
        explicit_signed_report_sha_required=True, exact_successful_current_journal_required_for_download=True,
        frozen_protocol_sha256=PROTOCOL_SHA, historical_terminal_protected_summary=180,
        authoritative_receipt_protected_modules=184, steam_initialized=False, files_written=0,
        downloads_requested=0, canonical_journal_written=False, acf_written=False,
        automatic_retry_performed=False)


def main(argv=None):
    global REPORT_SHA
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--preflight', action='store_true')
    mode.add_argument('--download', action='store_true')
    parser.add_argument('--report-sha256')
    args = parser.parse_args(argv)
    if not args.preflight and not args.download:
        need(args.report_sha256 is None, 'Static plan takes no action inputs')
        print(json.dumps(static_plan(), ensure_ascii=True))
        return 0
    REPORT_SHA = args.report_sha256
    need(re.fullmatch(r'[a-f0-9]{64}', REPORT_SHA or '') is not None,
         'Explicit completed signed package report SHA required')
    if args.preflight:
        inputs = local_inputs(False, full=True)
        configure(inputs['report'])
        protocol.unchanged(inputs['snapshots'])
        print(json.dumps(dict(status='LOCAL_V02_OFFICIAL_DOWNLOAD_PREFLIGHT_PASS',
            release_sequence=b.SEQUENCE, content_sha256=inputs['manifest']['content_sha256'],
            runtime_source_revision=SOURCE_REVISION, signed_resources=6918, protected_modules=184,
            full_local_signed_validation=True, successful_same_release=inputs['success'],
            expected_current_steam_manifest=inputs['expected_manifest'],
            release_history_entries=len(inputs['state'].get('release_history', [])),
            canonical_journal_unchanged=True, steam_initialized=False, files_written=0,
            downloads_requested=0, canonical_journal_written=False, acf_written=False)))
        return 0
    package, _, _ = validated_package(REPORT_SHA)
    configure(package)
    # The exact frozen implementation acquires the canonical publication lock,
    # rechecks snapshots and performs full=True admission before any SDK use.
    with b.scene_maps(), b.inc.trusted_source(b.TRUSTED):
        return protocol.main(['--download'])


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps(dict(status='REFUSED_V02_DOWNLOAD_PRESERVE_CANONICAL_JOURNAL',
            error_type=type(error).__name__, canonical_journal_written=False,
            automatic_retry_performed=False, updates_submitted=0)))
        raise SystemExit(2)
