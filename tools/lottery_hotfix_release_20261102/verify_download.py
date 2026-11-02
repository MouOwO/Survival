"""Explicit signed0202 adapter for the unchanged official1313/3406 download.

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
checks = module('portrait0202_download_private_checks', HERE/'release_checks.py')
b, need = checks.b, checks.b.need
PROTOCOL = b.ROOT/'tools/arcade_cleanup_20261027/verify_download.py'
PROTOCOL_SHA = '1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f'
need(hashlib.sha256(PROTOCOL.read_bytes().replace(b'\r\n', b'\n')).hexdigest() == PROTOCOL_SHA,
     'Frozen official1313/3406 download protocol changed')
protocol = module('portrait0202_download_private_protocol', PROTOCOL)
api = protocol.api
LINEAGE = b.ROOT/'output/release_lineage_20261101/state.json'
SUCCESS_STATUS = 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'
REPORT_SHA = None


def require_family_identity():
    need(b.SEQUENCE == 2026110202 and b.ITEM == '3824360109' and len(b.PAYLOADS) == 4,
         'Exact0202 reviewed release family required')


def source_revisions(package):
    values=package.get('source_revisions')
    need(isinstance(values,dict) and set(values)=={'game','content'}
         and all(isinstance(value,str) and re.fullmatch('[a-f0-9]{40}',value) for value in values.values())
         and package.get('source_revision')==values['game']
         and isinstance(package.get('operator_revision'),str)
         and re.fullmatch('[a-f0-9]{40}',package['operator_revision']) is not None,
         'Authenticated immutable game/content/operator revisions required')
    return dict(values)


def validated_package(expected_sha, *, full=False):
    require_family_identity()
    need(re.fullmatch(r'[a-f0-9]{64}', expected_sha or '') is not None,
         'Explicit completed signed package report SHA required')
    package, manifest, signed = checks.validated_package(expected_sha, full=full)
    sources=source_revisions(package)
    names = [b.ITEM+'.vpk', *(b.ITEM+'_%03d.vpk' % i for i in range(4))]
    need(b.SEQUENCE == 2026110202 and b.ITEM == '3824360109' and len(b.PAYLOADS) == 4
         and package.get('source_revisions') == sources
         and package.get('release_sequence') == b.SEQUENCE
         and package.get('files') == manifest.get('file_count') == 6917
         and package.get('protected_modules_preserved') == 184
         and len(package.get('trusted_review_pins', {})) == 19
         and package.get('approved_steamids64') == list(b.APPROVED)
         and len(b.APPROVED) == 5 and package.get('max_players') == 4
         and set(package.get('preserved_admission_rows', {})) == set(b.ADMISSION_PATHS)
         and signed.get('release_sequence') == b.SEQUENCE
         and signed.get('signature_valid') is True
         and package.get('changed_runtime_paths') == sorted(b.PAYLOADS)
         and package.get('added_runtime_paths') == list(b.ADDED_RUNTIME_PATHS)
         and package.get('removed_runtime_paths') == []
         and [row['name'] for row in package.get('package_files', [])] == names,
         'Exact immutable v09 signed0202 four-path6917/184 five-volume package required')
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


def completed_lineage(state,state_raw,package,manifest_raw,read):
    lineage=api.pack.handoff.decode_json(read(LINEAGE));head=lineage.get('head',{})
    need(lineage.get('schema')==1 and type(lineage.get('generation')) is int
         and lineage['generation']==1 and lineage.get('pending') is None
         and head.get('sequence')==b.SEQUENCE
         and head.get('canonical_journal_sha256')==hashlib.sha256(state_raw).hexdigest()
         and head.get('content_sha256')==package['content_sha256']
         and head.get('manifest_sha256')==hashlib.sha256(manifest_raw).hexdigest()
         and head.get('resource_origins_sha256')==package['resource_origins_sha256']
         and head.get('source_revisions')==source_revisions(package),
         'Completed exact0202 publication lineage required; preserve unknown pending')
    need(len(state.get('release_history',[]))==21
         and state.get('previous_release',{}).get('release_sequence')==b.BASE_SEQUENCE
         and state['previous_release'].get('content_sha256')==b.BASE_CONTENT,
         'Twenty parent history entries plus previous0104 must remain preserved')


def local_inputs(require_success=False, *, full=False):
    require_family_identity()
    snapshots = {}
    read = lambda path: protocol.read_snapshot(path, api.pack.MAX_MANIFEST, snapshots)
    read(b.REPORT/'package.json')
    manifest_raw=read(b.VIEW/api.pack.handoff.MANIFEST)
    read(b.VIEW/api.pack.handoff.SIGNATURE)
    state_raw = read(b.JOURNAL)
    state = api.pack.handoff.decode_json(state_raw)
    package, manifest, signature = validated_package(REPORT_SHA, full=full)
    need(state.get('uploaded') is True and state.get('status') == SUCCESS_STATUS,
         'Unknown/pending publication must be reconciled separately; journal preserved')
    success = successful_same_release(state, package, manifest)
    if require_success:
        need(success, 'Successful exact0202 original-item publication required')
    if success:
        completed_lineage(state,state_raw,package,manifest_raw,read)
    else:
        parent_raw = read(b.BASE_REPORT)
        parent = api.pack.handoff.decode_json(parent_raw)
        need(hashlib.sha256(parent_raw).hexdigest() == b.BASE_REPORT_SHA,
             'Frozen0104 parent package report changed')
        b.require_parent_journal(state, parent)
    # Includes the entire raw journal: previous_release and all parent historical
    # entries are preserved, not rewritten or borrowed as a current manifest.
    protocol.unchanged(snapshots)
    return dict(report=package, manifest=manifest, signature=signature, state=state,
        snapshots=snapshots, success=success,
        expected_manifest=protocol.journal_manifest(state) if success else None,
        total=sum(row['bytes'] for row in package['package_files']), report_sha256=REPORT_SHA,
        state_sha256=hashlib.sha256(state_raw).hexdigest(), protected_modules=184)


def configure(package):
    need(b.pack.runtime.digest(b.BASE_RECORD) == b.BASE_RECORD_SHA,
         'Frozen0104 delivery record changed')
    record = b.load(b.BASE_RECORD)
    reference = record['download_receipt']
    receipt_path = b.ROOT/reference['path']
    receipt_raw = api.pack.read_metadata(api.pack.handoff.regular_path(receipt_path), api.pack.MAX_MANIFEST)
    need(hashlib.sha256(receipt_raw).hexdigest() == reference['sha256'],
         'Frozen0104 official download receipt changed')
    receipt = api.pack.handoff.decode_json(receipt_raw)
    updated = receipt.get('post_query', {}).get('time_updated')
    need(receipt.get('status') == 'OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED'
         and receipt.get('release_sequence') == b.BASE_SEQUENCE == 2026110104
         and receipt.get('content_sha256') == b.BASE_CONTENT
         and receipt.get('signed_resources_verified') == 6917
         and receipt.get('protected_modules_verified') == 184
         and type(updated) is int and updated > 0,
         'Actual0104 official receipt remote-update bound required')
    values = dict(ITEM=b.ITEM, SEQUENCE=b.SEQUENCE, FILE_COUNT=6917,
        CONTENT=package['content_sha256'], CANDIDATE=b.VIEW, TRUSTED=b.TRUSTED,
        VPK=b.OUTPUT/(b.ITEM+'.vpk'), REPORT=b.REPORT/'package.json', STATE=b.JOURNAL,
        OUTPUT=b.REPORT/'download_evidence', MINIMUM_REMOTE_UPDATED=updated,
        local_inputs=local_inputs)
    for name, value in values.items():
        setattr(protocol, name, value)


def static_plan():
    return dict(status='STATIC_V09_OFFICIAL_DOWNLOAD_PLAN_NO_EFFECTS',
        workshop_id=b.ITEM, release_sequence=2026110202, runtime_source_revisions='FROM_AUTHENTICATED_COMPLETED_REPORT',
        runtime_files=6917, protected_modules=184, scoped_runtime_paths=4,
        approved_account_count=5, max_players=4, trusted_reviews=19,
        parent_release_sequence=2026110104, immutable_source_revisions_required=True,
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
    require_family_identity()
    if args.preflight:
        inputs = local_inputs(False, full=True)
        configure(inputs['report'])
        protocol.unchanged(inputs['snapshots'])
        print(json.dumps(dict(status='LOCAL_V09_OFFICIAL_DOWNLOAD_PREFLIGHT_PASS',
            release_sequence=b.SEQUENCE, content_sha256=inputs['manifest']['content_sha256'],
            runtime_source_revisions=source_revisions(inputs['report']), signed_resources=6917, protected_modules=184,
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
        print(json.dumps(dict(status='REFUSED_V09_DOWNLOAD_PRESERVE_CANONICAL_JOURNAL',
            error_type=type(error).__name__, canonical_journal_written=False,
            automatic_retry_performed=False, updates_submitted=0)))
        raise SystemExit(2)
