"""Complete-release official download, using the frozen 1313/3406 ABI.

Static import/plan has no Steam or filesystem effects. Explicit download makes
one subscription refresh and one DownloadItem request under the common journal
lock. Whole candidate and installed VPK sets are hashed and all signed resources
verified; counts come from authenticated metadata. O(package bytes + resources)
per preflight/locked validation, no runtime timer, retry or publication.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import sys
from types import ModuleType
ROOT = Path(__file__).resolve().parents[2]
PROTOCOL_PATH = ROOT / 'tools/arcade_cleanup_20261027/verify_download.py'
PROTOCOL_SHA = '1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f'
REPORT_SHA = None
_protocol = None
_PROTOCOL_EXECUTED_PINS = {}

def need(ok, why):
    if not ok:
        raise ValueError(why)

def recipe():
    from complete_delivery_pack_2026111005_53969b import pipeline_recipe
    return pipeline_recipe

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def protocol():
    global _protocol
    if _protocol is None:
        raw = PROTOCOL_PATH.read_bytes()
        need(len(raw) <= 128 * 1024 and sha(raw.replace(b'\r\n', b'\n')) == PROTOCOL_SHA, 'complete_frozen_download_protocol_changed')
        for path in (ROOT / 'tools', ROOT / 'tools/workshop_test'):
            if str(path) not in sys.path:
                sys.path.insert(0, str(path))
        value = ModuleType('complete_private_official_download')
        value.__file__ = str(PROTOCOL_PATH)
        from complete_delivery_pack_2026111005_53969b import rehearsal
        with rehearsal.capture_operator_imports():
            exec(compile(raw, str(PROTOCOL_PATH), 'exec'), value.__dict__)
        _PROTOCOL_EXECUTED_PINS.update(rehearsal._EXECUTED_OPERATOR_PINS)
        _PROTOCOL_EXECUTED_PINS[PROTOCOL_PATH.relative_to(ROOT).as_posix()] = sha(raw.replace(b'\r\n', b'\n'))
        text = raw.decode('utf-8-sig')
        node = next((n for n in ast.parse(text).body if isinstance(n, ast.FunctionDef) and n.name == 'download_once'))
        part = '\n'.join(text.splitlines()[node.lineno - 1:node.end_lineno])
        replacements = [('== 4\n', '== len(package["package_files"]) - 1\n'), ('archive_count=4, protected_modules_verified=180,', 'archive_count=len(package["package_files"])-1, protected_modules_verified=inputs["protected_modules"],')]
        for old, new in replacements:
            need(part.count(old) == 1, 'complete_download_counter_adaptation_changed')
            part = part.replace(old, new, 1)
        exec(compile(part, str(PROTOCOL_PATH) + '[complete_dynamic_counters]', 'exec'), value.__dict__)
        _protocol = value
    return _protocol

def current_upload(state, report):
    p = protocol()
    b = recipe()
    return state.get('uploaded') is True and state.get('status') == 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST' and (state.get('owner') == p.api.OWNER) and (state.get('app_id') == p.api.APP) and (state.get('workshop_id') == b.ITEM) and (state.get('visibility_requested') == 3) and (state.get('release_sequence') == report['release_sequence']) and (state.get('content_sha256') == report['content_sha256']) and (state.get('vpk_sha256') == report['vpk_sha256']) and (state.get('vpk_bytes') == report['package_files'][0]['bytes']) and (state.get('package_files') == report['package_files']) and (state.get('legal_agreement_required') is False)

def complete_lineage(state, state_raw, report, read):
    b = recipe()
    lineage = json.loads(read(ROOT / 'output/release_lineage_20261101/state.json'))
    head = lineage.get('head', {})
    need(lineage.get('schema') == 1 and type(lineage.get('generation')) is int and (lineage['generation'] > 0) and (lineage.get('pending') is None) and (head.get('sequence') == report['release_sequence']) and (head.get('canonical_journal_sha256') == sha(state_raw)) and (head.get('content_sha256') == report['content_sha256']) and (head.get('manifest_sha256') == report['signed_manifest_sha256']) and (head.get('resource_origins_sha256') == report['resource_origins_sha256']) and (head.get('source_revisions') == report['source_revisions']), 'complete_download_current_lineage_mismatch')
    previous = state.get('previous_release', {})
    parent, _ = b.baseline(full=False, require_current_journal=False)
    need(previous.get('release_sequence') == parent['release_sequence'] and previous.get('content_sha256') == parent['content_sha256'] and isinstance(state.get('release_history'), list), 'complete_download_parent_history_missing')

def local_inputs(require_success=False, *, full=False):
    b = recipe()
    p = protocol()
    need(re.fullmatch('[a-f0-9]{64}', REPORT_SHA or '') is not None, 'complete_download_explicit_report_sha_required')
    snapshots = {}
    read = lambda path: p.read_snapshot(path, p.api.pack.MAX_MANIFEST, snapshots)
    report_raw = read(b.REPORT / 'package.json')
    need(sha(report_raw) == REPORT_SHA, 'complete_download_report_changed')
    report, manifest, signed = b.load_package(REPORT_SHA, full=full)
    b.verify_operator_paths(dict(_PROTOCOL_EXECUTED_PINS), report['operator_revision'])
    read(b.REPORT / 'pipeline_inputs.json')
    manifest_raw = read(b.VIEW / p.api.pack.handoff.MANIFEST)
    read(b.VIEW / p.api.pack.handoff.SIGNATURE)
    need(sha(manifest_raw) == report['signed_manifest_sha256'], 'complete_download_manifest_changed')
    state_raw = read(b.JOURNAL)
    state = json.loads(state_raw)
    success = current_upload(state, report)
    if require_success:
        need(success, 'complete_download_successful_exact_current_upload_required')
    if success:
        complete_lineage(state, state_raw, report, read)
    else:
        parent, _ = b.baseline(full=False, require_current_journal=True)
        need(state.get('uploaded') is True and state.get('release_sequence') == parent['release_sequence'] and (state.get('content_sha256') == parent['content_sha256']), 'complete_download_unknown_current_journal_preserve_pending')
    p.unchanged(snapshots)
    return dict(report=report, manifest=manifest, signature=signed, state=state, snapshots=snapshots, success=success, expected_manifest=p.journal_manifest(state) if success else None, total=sum((row['bytes'] for row in report['package_files'])), report_sha256=REPORT_SHA, state_sha256=sha(state_raw), protected_modules=report['protected_modules_verified'])

def configure(report):
    b = recipe()
    p = protocol()
    evidence = b.baseline_evidence()
    receipt = evidence['receipt']
    parent, _ = b.baseline(full=False, require_current_journal=False)
    updated = receipt.get('post_query', {}).get('time_updated')
    need(receipt.get('status') == 'OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED' and receipt.get('release_sequence') == parent['release_sequence'] and (receipt.get('content_sha256') == parent['content_sha256']) and (type(updated) is int) and (updated > 0), 'complete_download_authenticated_remote_parent_time_required')
    values = dict(ITEM=b.ITEM, SEQUENCE=report['release_sequence'], FILE_COUNT=report['files'], CONTENT=report['content_sha256'], CANDIDATE=b.VIEW, TRUSTED=b.TRUSTED, VPK=b.OUTPUT / (b.ITEM + '.vpk'), REPORT=b.REPORT / 'package.json', STATE=b.JOURNAL, OUTPUT=b.REPORT / 'download_evidence', MINIMUM_REMOTE_UPDATED=updated, EXPECTED_NAMES=[row['name'] for row in report['package_files']], local_inputs=local_inputs)
    for name, value in values.items():
        setattr(p, name, value)

def static_plan():
    return dict(status='STATIC_COMPLETE_OFFICIAL_DOWNLOAD_PLAN_NO_EFFECTS', workshop_id='3824360109', runtime_counts='FROM_AUTHENTICATED_COMPLETE_SIGNED_MANIFEST', frozen_protocol_sha256=PROTOCOL_SHA, sdk_initialized=False, files_written=0, downloads_requested=0, updates_submitted=0, automatic_retry_performed=False)

def main(argv=None):
    global REPORT_SHA
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--preflight', action='store_true')
    group.add_argument('--download', action='store_true')
    parser.add_argument('--report-sha256')
    args = parser.parse_args(argv)
    if not args.preflight and (not args.download):
        need(args.report_sha256 is None, 'complete_download_plan_has_no_action_arguments')
        print(json.dumps(static_plan()))
        return 0
    REPORT_SHA = args.report_sha256
    try:
        inputs = local_inputs(False, full=True)
        configure(inputs['report'])
        if args.preflight:
            protocol().unchanged(inputs['snapshots'])
            print(json.dumps(dict(status='COMPLETE_OFFICIAL_DOWNLOAD_PREFLIGHT_PASS', release_sequence=inputs['report']['release_sequence'], successful_same_release=inputs['success'], files=inputs['report']['files'], protected_modules=inputs['protected_modules'], sdk_initialized=False, files_written=0, downloads_requested=0)))
            return 0
        from complete_delivery_pack_2026111005_53969b import rehearsal
        rehearsal.environment()[1].no_clients()
        with recipe().scene_maps(), recipe().inc.trusted_source(recipe().TRUSTED):
            return protocol().main(['--download'])
    except Exception as error:
        print(json.dumps(dict(status='COMPLETE_OFFICIAL_DOWNLOAD_REFUSED_PRESERVE_HISTORY', error_type=type(error).__name__, sdk_uploads=0, canonical_journal_written=False, automatic_retry_performed=False)))
        return 2
if __name__ == '__main__':
    raise SystemExit(main())
