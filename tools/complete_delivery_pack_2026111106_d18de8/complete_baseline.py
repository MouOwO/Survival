"""Advance the complete source checkpoint only after real official delivery.

There is no SDK call, retry, signing, install or game timer here. One explicit
completion owns the canonical item mutex, revalidates signature/full VPK and
ordinary-client evidence, then rechecks the actual official installation. Two
Git metadata indexes plus O(source entries + resource origins) derive a complete
audited checkpoint; this is never a claim that plaintext HEAD was shipped.
"""
from __future__ import annotations
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / 'tools') not in sys.path:
    sys.path.insert(0, str(ROOT / 'tools'))
from release_lineage_20261101 import guard
TOOL = 'tools/complete_delivery_pack_2026111106_d18de8/complete_baseline.py'
PENDING_TOOL = 'tools/complete_delivery_pack_2026111106_d18de8/complete_pending.py'
LOADED_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
KIND = 'COMPLETE_OFFICIALLY_VERIFIED_AUDITED_SOURCE_CHECKPOINT'
BASE = ROOT / 'output/release_baselines/complete'
ACTIVE = ROOT / 'output/release_baselines/complete_active.json'
MAX_DOCUMENT = 32 * 1024 * 1024

def need(value, reason):
    if not value:
        raise ValueError(reason)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False) + '\n').encode('ascii')

def read(path, expected=None):
    value, raw = guard.read_json(path, MAX_DOCUMENT)
    if expected is not None:
        need(sha(raw) == guard.checked_sha(expected), 'complete_baseline_original_document_changed')
    return (value, raw)

def checked_authority(auth):
    """Only the common registered authority can select this completion code."""
    current = guard.load_authority(auth.policy_path, auth.digest)
    path = guard.regular(current.policy.get('baseline_completion_path', ''))
    raw = Path(__file__).read_bytes()
    need(path == (ROOT / TOOL).resolve() and sha(raw) == current.policy.get('baseline_completion_sha256') and (sha(raw.replace(b'\r\n', b'\n')) == LOADED_LF_SHA256), 'registered_exact_complete_baseline_operator_required')
    need(Path(current.policy['recipe_path']).resolve() == ROOT / 'tools/complete_delivery_pack_2026111106_d18de8/pipeline_recipe.py', 'complete_baseline_requires_complete_recipe')
    return current

def current_head(auth, report, report_sha, request):
    """Read-only CAS snapshot; never opens a second publication lease."""
    journal, journal_raw = read(auth.policy['canonical_journal'])
    state, state_raw = read(auth.policy['lineage_state'])
    head = state.get('head', {})
    need(state.get('schema') == 1 and state.get('pending') is None and (type(state.get('generation')) is int) and (state['generation'] == request.get('generation')), 'complete_baseline_pending_or_changed_generation')
    need(head.get('sequence') == journal.get('release_sequence') == report.get('release_sequence') and head.get('canonical_journal_sha256') == sha(journal_raw) and (head.get('content_sha256') == journal.get('content_sha256') == report.get('content_sha256')) and (head.get('manifest_sha256') == request.get('signed_manifest_sha256') == report.get('signed_manifest_sha256')) and (head.get('resource_origins_sha256') == report.get('resource_origins_sha256')) and (head.get('source_revisions') == request.get('source_revisions') == report.get('source_revisions')) and (request.get('report_sha256') == report_sha), 'complete_baseline_uploaded_head_or_request_mismatch')
    need(journal.get('uploaded') is True and journal.get('status') == 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST' and (journal.get('app_id') == auth.policy['app_id'] == report.get('app_id')) and (journal.get('workshop_id') == auth.policy['workshop_id'] == report.get('workshop_id')) and (journal.get('owner') == auth.policy['owner'] == report.get('owner')) and (journal.get('package_files') == report.get('package_files')) and (journal.get('vpk_sha256') == report.get('vpk_sha256')) and (journal.get('legal_agreement_required') is False), 'complete_baseline_exact_successful_sdk_submission_required')
    return (journal, journal_raw, state, state_raw)

def verified_delivery(report, manifest, report_sha, journal, journal_sha, receipt):
    """Check the real SDK/3406/fresh-query schema, with dynamic volume counts."""
    import release_delivery_state as delivery
    status = delivery.report(dict(local_package=report, local_package_report_sha256=report_sha, expected_source_revisions=report['source_revisions'], journal=journal, journal_sha256=journal_sha, download_receipt=receipt, local_resources=manifest['files'], published_resources=manifest['files'], pending_source_changes=[]))
    need(status['upload_evidence_matches_target'] and status['official_download_evidence_matches_target'], 'complete_baseline_same_target_real_sdk_and_official_download_required:' + ','.join(status['blockers']))
    need(receipt.get('protected_modules_verified') == report.get('protected_modules_verified') and receipt.get('critical_resources_verified') is True and (receipt.get('download', {}).get('callback', {}).get('callback_id') == 3406) and (receipt.get('verification', {}).get('callback') == receipt.get('download', {}).get('callback')), 'complete_baseline_actual_protection_and_native_callback_required')
    steam = receipt.get('steam_manifest')
    acf = receipt.get('acf_installed_entry', {})
    total = sum((row['bytes'] for row in report['package_files']))
    need(acf.get('manifest') == steam and acf.get('size') == str(total) and (acf.get('timeupdated') == str(receipt['post_query']['time_updated'])) and (receipt['verification'].get('size_on_disk') == total) and (receipt['verification'].get('expected_size_on_disk') == total), 'complete_baseline_official_manifest_and_exact_installed_size_required')
    return status

def advance(previous, report, manifest, projection, inventory, trees, delivery):
    """Pure full-checkpoint derivation; callers authenticate original bytes."""
    from complete_delivery_pack_2026111106_d18de8 import parent_pending as pending
    need(set(trees) == set(report['source_revisions']) == {'game', 'content'}, 'complete_baseline_two_exact_target_trees_required')
    for role, tree in trees.items():
        need(tree.get('commit') == report['source_revisions'][role] and isinstance(tree.get('entries'), dict) and (len(tree['entries']) <= 100000), 'complete_baseline_target_git_tree_changed')
    need(report['release_sequence'] > previous['parent_sequence'] and report.get('authenticated_parent_manifest_sha256') == previous['parent_manifest_sha256'] and (report.get('authenticated_parent_content_sha256') == previous['parent_content_sha256']) and (projection.get('parent_manifest_sha256') == previous['parent_manifest_sha256']), 'complete_baseline_wrong_original_parent')
    ledger = projection['coverage_ledger']
    need(ledger.get('coverage_complete') is True and ledger.get('unknown_sources') == [] and (ledger.get('deferred_sources') == []), 'complete_baseline_unreviewed_or_deferred_sources_remain')
    covered = ledger.get('covered_sources')
    need(isinstance(covered, list) and len(covered) == len(set(covered)) and (set(ledger.get('pending_sources', [])) == set(covered)), 'complete_baseline_all_pending_source_coverage_required')
    target = {role: value['entries'] for role, value in trees.items()}
    wanted = {role + ':' + name for role, name in pending.pending_source_keys(previous['source_inventory'], target, previous['deferred_sources'])}
    inventory_keys = {row['source']['repo'] + ':' + row['source']['path'] for row in inventory['rows']}
    need(wanted <= set(covered) and inventory_keys == set(covered) and (inventory.get('counts', {}).get('dirty_runtime') == 0), 'complete_baseline_source_checkpoint_contains_uncovered_changes')
    rows = {row['path']: row for row in manifest['files']}
    need(len(rows) == manifest['file_count'] == report['files'] and sorted(rows) == [row['path'] for row in projection['projected_rows']] and (manifest['files'] == projection['projected_rows']), 'complete_baseline_exact_projected_signed_resources_required')
    origins = report['resource_origins']
    need(set(origins) == set(rows) and sha(canonical(origins)) == report['resource_origins_sha256'] and (report['parent_resource_origins_sha256'] == previous['resource_origins_sha256']), 'complete_baseline_exact_resource_origin_chain_required')
    old = previous['resource_origins']
    changed = {name for name, row in rows.items() if name not in old or (row['sha256'], row['bytes']) != (old[name]['resource_sha256'], old[name]['resource_bytes'])}
    removed = set(old) - set(rows)
    bindings = {row['resource']: row for row in ledger['resource_bindings']}
    need(set(projection['changed_runtime_paths']) == set(report['changed_runtime_paths']) == changed and set(projection['removed_runtime_paths']) == set(report['removed_runtime_paths']) == removed, 'complete_baseline_actual_changed_removed_set_required')
    for name, origin in origins.items():
        row = rows[name]
        need((origin.get('resource_sha256'), origin.get('resource_bytes')) == (row['sha256'], row['bytes']), 'complete_baseline_origin_does_not_describe_signed_bytes')
        if name in changed:
            need(origin.get('kind') == 'COMPLETE_IMMUTABLE_TYPED_RUNTIME_BINDING' and origin.get('binding') == bindings.get(name) and (origin.get('source_revisions') == report['source_revisions']) and (origin.get('projection_sha256') == projection['projection_sha256']), 'complete_baseline_changed_origin_requires_actual_typed_binding')
        else:
            need(origin == old[name], 'complete_baseline_unaffected_parent_origins_changed')
    online_test = delivery.get('publication_mode') == 'EXPLICIT_UNLISTED_ONLINE_TEST_NATIVE_PENDING' and delivery.get('online_test_release_authorized') is True and (delivery.get('ordinary_production_acceptance') is False) and (delivery.get('native_acceptance_status') == 'PENDING_USER_ONLINE_TEST') and isinstance(delivery.get('online_test_authorization_sha256'), str) and (len(delivery['online_test_authorization_sha256']) == 64)
    if online_test:
        guard.checked_sha(delivery['online_test_authorization_sha256'])
    need((delivery.get('ordinary_production_acceptance') is True or online_test) and delivery.get('official_full_installation_reverified') is True and (delivery.get('signature_valid') is True), 'complete_baseline_actual_ordinary_and_full_official_evidence_required')
    return dict(schema=1, kind=KIND, source_anchor_is_full_published_tree=False, source_inventory_purpose='COMPLETE_AUDITED_SOURCE_CHECKPOINT_NOT_PLAINTEXT_RUNTIME_EXPORT', parent_sequence=report['release_sequence'], parent_content_sha256=manifest['content_sha256'], parent_manifest_sha256=report['signed_manifest_sha256'], official_parent_manifest=delivery['steam_manifest'], source_anchors=copy.deepcopy(report['source_revisions']), source_inventory=copy.deepcopy(target), source_inventory_sha256=sha(canonical(target)), resource_origins=copy.deepcopy(origins), resource_origins_sha256=report['resource_origins_sha256'], deferred_sources={}, audited_covered_sources=sorted(covered), cleared_historical_sources=sorted(ledger.get('historical_sources', [])), non_runtime_reviews=sorted(ledger.get('non_runtime_reviews', [])), projection_sha256=projection['projection_sha256'], previous_manifest_sha256=previous['parent_manifest_sha256'], complete_delivery=copy.deepcopy(delivery), full_head_publication_claimed=False)

def target_trees(builder, report):
    from complete_delivery_pack_2026111106_d18de8 import parent_pending as pending
    counts = Counter()
    trees = {role: dict(commit=revision, entries=pending.git_tree(root, counts, revision)) for role, revision, root in (('game', report['source_revisions']['game'], ROOT), ('content', report['source_revisions']['content'], pending.CONTENT))}
    return (trees, dict(counts))

def reverify_online_test_installation(auth, builder, report, expected, journal, receipt, snapshots):
    """Verify actual official bytes while leaving native gameplay acceptance pending."""
    import release_pipeline as pipeline
    downloaded = pipeline.pinned_module(auth, 'download')
    downloaded.REPORT_SHA = expected
    downloaded.configure(report)
    protocol = downloaded.protocol()
    installed = guard.regular(Path(receipt['download']['install_folder']))
    need(installed == guard.regular(protocol.INSTALLED), 'online_test_fixed_official_installation_required')
    with builder.scene_maps(), builder.inc.trusted_source(builder.TRUSTED):
        actual = protocol.verify.verify_installed(copy.deepcopy(receipt['download']), builder.VIEW, journal)
        need(actual.get('signature_valid') is True and actual.get('package_files') == report['package_files'] and (actual.get('vpk_sha256') == report['vpk_sha256']) and (actual.get('verification', {}).get('files') == report['files']) and (actual['verification'].get('archive_count') == len(report['package_files']) - 1) and all((actual['verification'].get(key) is True for key in protocol.callbacks.CHECKS)), 'online_test_actual_official_full_installation_failed')
        raw = protocol.api.pack.read_metadata(protocol.ACF, protocol.api.pack.MAX_MANIFEST)
        steam, row = protocol.acf_manifest(raw, receipt['post_query'], sum((v['bytes'] for v in report['package_files'])), receipt['steam_manifest'])
        need(steam == receipt['steam_manifest'] and row == receipt['acf_installed_entry'], 'online_test_official_manifest_changed')
        snapshots[Path(protocol.ACF)] = raw
    builder.verify_operator_paths(dict(downloaded._PROTOCOL_EXECUTED_PINS), report['operator_revision'])
    protocol.unchanged(snapshots)

def collect_verified(auth, builder, request, receipt_path, *, full):
    """Recheck original inputs; full completion additionally rehashes official VPK."""
    auth = checked_authority(auth)
    expected = guard.checked_sha(request.get('report_sha256'))
    report, manifest, signed = builder.load_package(expected, full=full)
    from complete_delivery_pack_2026111106_d18de8 import publication_validator as publication
    online_test = request.get('publication_mode') == publication.ONLINE_TEST_MODE
    policy_operator = publication.publication_operator(request, report) if online_test else report['operator_revision']
    builder.verify_operator_paths({TOOL: LOADED_LF_SHA256}, policy_operator)
    ctx = builder.context(report['operator_revision'])
    path = guard.regular(receipt_path)
    need(path.resolve().is_relative_to((builder.REPORT / 'download_evidence').resolve()) and path.name == 'verification.json', 'complete_baseline_original_official_receipt_path_required')
    receipt, receipt_raw = read(path)
    journal, journal_raw, state, state_raw = current_head(auth, report, expected, request)
    verified_delivery(report, manifest, expected, journal, sha(journal_raw), receipt)
    official_snapshots = {}
    if online_test:
        native_summary = publication.online_test_admission(request, report)
        publication._operator_file(TOOL, Path(__file__).read_bytes(), native_summary['publication_operator_revision'])
        if full:
            reverify_online_test_installation(auth, builder, report, expected, journal, receipt, official_snapshots)
        native_summary.update(official_full_installation_reverified=True, official_receipt_sha256=sha(receipt_raw))
    elif full:
        native = publication._native_policy(ctx.config, report['operator_revision'])
        native_summary = native.validate_post_download_native_release(request, report, manifest, signed, receipt_ref={'path': str(path), 'sha256': sha(receipt_raw)})
        need(native_summary.get('ordinary_production_acceptance') is True and native_summary.get('official_full_installation_reverified') is True and (native_summary.get('official_receipt_sha256') == sha(receipt_raw)), 'complete_baseline_real_ordinary_and_official_admission_required')
    else:
        native_summary = {'ordinary_production_acceptance': True}
    previous = builder.dependencies().package.pending._read_json(builder.dependencies().package.pending.BASELINE, builder.dependencies().package.pending.BASELINE_SHA256)
    inventory = json.loads(ctx.inputs['inventory_raw'])
    trees, costs = target_trees(builder, report)
    evidence = dict(authority_sha256=auth.digest, source_revisions=report['source_revisions'], report_sha256=expected, report_path=str(builder.REPORT / 'package.json'), receipt_path=str(path), receipt_sha256=sha(receipt_raw), canonical_journal_sha256=sha(journal_raw), lineage_state_sha256=sha(state_raw), generation=state['generation'], steam_manifest=receipt['steam_manifest'], signed_manifest_sha256=report['signed_manifest_sha256'], signature_valid=signed.get('release_sequence') == report['release_sequence'], ordinary_production_acceptance=native_summary.get('ordinary_production_acceptance') is True, official_full_installation_reverified=True, publication_request=copy.deepcopy(request), package_operator_revision=report['operator_revision'], collection_operator_revision=report['collection_source_revisions']['operator'], projection_document_sha256=sha(ctx.projection_raw), git_metadata_costs=costs, no_additional_sdk_calls=True, canonical_journal_written=False)
    if online_test:
        evidence.update({key: native_summary[key] for key in ('publication_mode', 'online_test_release_authorized', 'native_acceptance_status', 'online_test_authorization_sha256', 'publication_operator_revision')})
    result = advance(previous, report, manifest, ctx.projection, inventory, trees, evidence)
    return dict(baseline=result, report=report, manifest=manifest, receipt=receipt, snapshots={Path(auth.policy['canonical_journal']): journal_raw, Path(auth.policy['lineage_state']): state_raw, path: receipt_raw, builder.INPUT_FILE: ctx.config_raw, builder.REPORT / 'package.json': (builder.REPORT / 'package.json').read_bytes(), **official_snapshots})

def unchanged(snapshots):
    for path, raw in snapshots.items():
        need(guard.regular(path).read_bytes() == raw, 'complete_baseline_inputs_changed_before_commit')

def record_verified_delivery(auth, builder, request, receipt_path):
    """One post-download CAS transaction; never resubmits or edits SDK journal."""
    auth = checked_authority(auth)
    with guard.exclusive_lock(auth.policy['publication_lock']):
        before = ACTIVE.read_bytes() if ACTIVE.exists() else None
        result = collect_verified(auth, builder, request, receipt_path, full=True)
        baseline = result['baseline']
        raw = canonical(baseline)
        need(len(raw) <= MAX_DOCUMENT, 'complete_baseline_checkpoint_byte_budget')
        name = str(baseline['parent_sequence']) + '_' + sha(raw) + '.json'
        destination = guard.regular(BASE / name)
        need(destination.parent == BASE.resolve(), 'complete_baseline_immutable_destination_required')
        cursor = dict(schema=1, kind=KIND, baseline=destination.relative_to(ROOT).as_posix(), baseline_sha256=sha(raw), authority_sha256=auth.digest, release_sequence=baseline['parent_sequence'], content_sha256=baseline['parent_content_sha256'], official_steam_manifest=baseline['official_parent_manifest'])
        unchanged(result['snapshots'])
        need((ACTIVE.read_bytes() if ACTIVE.exists() else None) == before, 'complete_baseline_active_cursor_changed')
        if destination.exists():
            need(destination.read_bytes() == raw, 'complete_baseline_immutable_history_changed')
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open('xb') as stream:
                stream.write(raw)
                stream.flush()
                import os
                os.fsync(stream.fileno())
        unchanged(result['snapshots'])
        if before is not None:
            old = json.loads(before)
            from complete_delivery_pack_2026111106_d18de8 import parent_pending
            need(old == cursor or (old.get('baseline_sha256') == parent_pending.BASELINE_SHA256 and old.get('release_sequence') == 2026111102 and (old.get('authority_sha256') == parent_pending.PARENT_AUTHORITY_SHA256)), 'complete_baseline_existing_checkpoint_requires_explicit_new_generation')
        guard.atomic_json(ACTIVE, cursor)
    return dict(status='COMPLETE_DELIVERY_BASELINE_RECORDED', baseline=cursor['baseline'], baseline_sha256=cursor['baseline_sha256'], release_sequence=baseline['parent_sequence'], steam_manifest=baseline['official_parent_manifest'], cleared_source_count=len(baseline['audited_covered_sources']), canonical_journal_written=False, sdk_calls=0, publication_performed=False)

def load_active():
    """Authenticate a recorded checkpoint against the current fixed authority."""
    import release_pipeline as pipeline
    auth = checked_authority(pipeline.authority())
    cursor, cursor_raw = read(ACTIVE)
    expected_fields = {'schema', 'kind', 'baseline', 'baseline_sha256', 'authority_sha256', 'release_sequence', 'content_sha256', 'official_steam_manifest'}
    need(set(cursor) == expected_fields and cursor['schema'] == 1 and (cursor['kind'] == KIND) and (cursor['authority_sha256'] == auth.digest), 'registered_complete_baseline_cursor_required')
    destination = guard.regular(ROOT / cursor['baseline'])
    need(destination.parent == BASE.resolve(), 'complete_baseline_cursor_outside_immutable_history')
    saved, raw = read(destination, cursor['baseline_sha256'])
    need(saved.get('kind') == KIND, 'complete_baseline_kind_required')
    evidence = saved['complete_delivery']
    builder = pipeline.recipe(auth)
    current = collect_verified(auth, builder, evidence['publication_request'], evidence['receipt_path'], full=False)
    need(canonical(current['baseline']) == raw and ACTIVE.read_bytes() == cursor_raw, 'complete_baseline_checkpoint_differs_from_actual_delivery')
    need((cursor['release_sequence'], cursor['content_sha256'], cursor['official_steam_manifest']) == (saved['parent_sequence'], saved['parent_content_sha256'], saved['official_parent_manifest']), 'complete_baseline_cursor_identity_changed')
    unchanged(current['snapshots'])
    return (saved, current['manifest'], cursor)
