"""Pure roll-forward of a mixed, actually delivered Workshop source baseline.

The caller authenticates signatures/receipts and supplies original-byte hashes.
This module checks their complete mutual bindings; it never grants an SDK
capability or performs filesystem, Git, network, journal, or pointer writes.

Cost is O(previous source metadata + manifest rows + deferred metadata), once
after a verified delivery. Only explicitly covered target Git entries advance;
the rest of HEAD is never copied into a mixed baseline. No game loop exists.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re

SDK_STATUS = 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'
DOWNLOAD_STATUS = 'OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED'
CHECKS = ('crc32_verified', 'manifest_dual_hashes_verified', 'section_md5s_verified', 'whole_vpk_md5_verified')
SOURCE_ROOTS = frozenset(('scripts', 'panorama', 'materials', 'models', 'particles', 'sounds',
                          'soundevents', 'resource', 'maps', 'data', 'art'))


def canonical_digest(value):
    """Object binding, distinct from hashes of original serialized file bytes."""
    return hashlib.sha256((json.dumps(value, sort_keys=True, separators=(',', ':'),
                                      ensure_ascii=True, allow_nan=False) + '\n').encode('ascii')).hexdigest()


def _need(ok, code):
    if not ok:
        raise ValueError(code)


def _digest(value, length=64):
    return isinstance(value, str) and re.fullmatch('[a-f0-9]{%d}' % length, value) is not None


def _path(value):
    return (isinstance(value, str) and value and not value.startswith(('/', '\\'))
            and '\\' not in value and ':' not in value and all(p not in ('', '.', '..') for p in value.split('/')))


def _paths(value, name):
    _need(isinstance(value, list) and all(_path(v) for v in value) and len(value) == len(set(value)), name)
    return set(value)


def _manifest_rows(manifest):
    rows = {}
    _need(isinstance(manifest.get('files'), list), 'complete_authenticated_manifest_required')
    for row in manifest['files']:
        _need(isinstance(row, dict) and _path(row.get('path')) and row['path'] not in rows
              and type(row.get('bytes')) is int and row['bytes'] >= 0 and _digest(row.get('sha256')),
              'invalid_or_duplicate_manifest_resource')
        rows[row['path']] = row
    _need(manifest.get('file_count') == len(rows) and rows and _digest(manifest.get('content_sha256')),
          'authenticated_manifest_count_or_content_invalid')
    return rows


def _packages(rows, workshop):
    _need(isinstance(rows, list) and len(rows) == 5, 'exact_five_package_files_required')
    result = {}
    for row in rows:
        _need(isinstance(row, dict) and isinstance(row.get('name'), str) and row['name'] not in result
              and type(row.get('bytes')) is int and row['bytes'] > 0 and _digest(row.get('sha256')),
              'invalid_or_duplicate_package_file')
        result[row['name']] = (row['bytes'], row['sha256'])
    _need(set(result) == {workshop + '.vpk', *(workshop + '_%03d.vpk' % i for i in range(4))},
          'unexpected_package_volume_or_stale_extra')
    return result


def _identity(value):
    return tuple(value.get(k) for k in ('workshop_id', 'release_sequence', 'content_sha256'))


def _source_relevant(path):
    parts = path.split('/')
    return (path == 'addoninfo.txt' or parts[0] in SOURCE_ROOTS) and not any(
        part in {'tests', '__pycache__', 'node_modules'} or part.startswith('.') for part in parts)


def _tree_identity(entry):
    return (entry.get('mode'), entry.get('kind'), entry.get('oid')) if entry else None


def _validate_delivery(manifest, package, evidence):
    """Accept real SDK/download schemas, not a READY/WORKSHOP_SYNCED boolean."""
    _need(isinstance(evidence, dict) and evidence.get('signature_valid') is True
          and evidence.get('signed_manifest_release_sequence') == package.get('release_sequence'),
          'authenticated_target_signature_required')
    _need(_digest(evidence.get('manifest_sha256')) and _digest(evidence.get('package_report_sha256'))
          and _digest(evidence.get('journal_sha256')), 'original_control_byte_digests_required')
    _need(evidence.get('manifest_object_sha256') == canonical_digest(manifest)
          and evidence.get('package_report_object_sha256') == canonical_digest(package),
          'supplied_manifest_or_report_differs_from_authenticated_object')
    workshop = package.get('workshop_id')
    _need(isinstance(workshop, str) and re.fullmatch('[1-9][0-9]{0,19}', workshop)
          and type(package.get('release_sequence')) is int and package['release_sequence'] > 0,
          'target_package_identity_invalid')
    _need(package.get('signature_valid') is True and package.get('full_runtime_validator_passed') is True
          and package.get('dry_run') is False and package.get('payload_changed') is False
          and type(package.get('protected_modules_preserved')) is int and package['protected_modules_preserved'] >= 0,
          'completed_authenticated_runtime_package_required')
    _need(package.get('content_sha256') == manifest['content_sha256']
          and package.get('files') == manifest['file_count'], 'package_manifest_identity_differs')
    files = _packages(package.get('package_files'), workshop)
    index = files[workshop + '.vpk']
    _need(package.get('vpk_sha256') == index[1], 'package_index_digest_differs')
    journal, receipt = evidence.get('journal'), evidence.get('download_receipt')
    _need(isinstance(journal, dict) and isinstance(receipt, dict), 'sdk_and_official_download_receipts_required')
    _need(journal.get('uploaded') is True and journal.get('status') == SDK_STATUS
          and journal.get('app_id') == 570 and type(journal.get('app_id')) is int
          and journal.get('legal_agreement_required') is False and _identity(journal) == _identity(package),
          'same_target_successful_sdk_submission_required')
    _need(_packages(journal.get('package_files'), workshop) == files
          and (journal.get('vpk_bytes'), journal.get('vpk_sha256')) == index,
          'sdk_submission_package_bytes_differ')
    _need(receipt.get('status') == DOWNLOAD_STATUS and _identity(receipt) == _identity(package)
          and receipt.get('package_report_sha256') == evidence['package_report_sha256']
          and receipt.get('canonical_journal_sha256') == evidence['journal_sha256']
          and receipt.get('canonical_journal_unchanged') is True,
          'official_download_not_bound_to_same_report_and_sdk_journal')
    verified = receipt.get('verification', {})
    _need(isinstance(verified, dict) and verified.get('status') == 'UNLISTED_WORKSHOP_DOWNLOAD_FULLY_VERIFIED'
          and verified.get('signature_valid') is True and verified.get('vpk_sha256') == index[1]
          and _packages(verified.get('package_files'), workshop) == files,
          'official_download_mixed_or_incomplete_package')
    checks = verified.get('verification', {})
    _need(isinstance(checks, dict) and checks.get('files') == manifest['file_count']
          and checks.get('archive_count') == 4 and all(checks.get(key) is True for key in CHECKS)
          and receipt.get('signed_resources_verified') == manifest['file_count']
          and receipt.get('protected_modules_verified') == package.get('protected_modules_preserved'),
          'full_download_resource_signature_and_archive_validation_required')
    download = receipt.get('download', {})
    callback = download.get('callback', {}) if isinstance(download, dict) else {}
    _need(isinstance(download, dict) and download.get('download_requested') is True and callback.get('callback_id') == 3406
          and callback.get('result') == 1 and callback.get('app_id') == 570
          and str(callback.get('workshop_id')) == workshop and verified.get('callback') == callback,
          'successful_same_item_native_download_callback_required')
    steam_manifest = receipt.get('steam_manifest')
    _need(isinstance(steam_manifest, str) and re.fullmatch('[1-9][0-9]{0,19}', steam_manifest),
          'official_steam_manifest_string_required')
    acf = receipt.get('acf_installed_entry', {})
    total = sum(value[0] for value in files.values())
    _need(isinstance(acf, dict) and acf.get('manifest') == steam_manifest and str(acf.get('size')) == str(total)
          and verified.get('size_on_disk') == total and verified.get('expected_size_on_disk') == total,
          'official_installed_volume_set_does_not_match_target')
    pre, post = receipt.get('pre_query', {}), receipt.get('post_query', {})
    for query in (pre, post):
        _need(isinstance(query, dict) and str(query.get('id')) == workshop and query.get('result') == 1
              and query.get('cached') is False and query.get('max_cache_age_seconds') == 0
              and query.get('banned') is False and query.get('creator_app_id') == 570
              and query.get('consumer_app_id') == 570 and query.get('total_files_bytes') == total
              and type(query.get('time_updated')) is int and query['time_updated'] > 0,
              'fresh_official_same_item_queries_required')
    _need(all(pre.get(key) == post.get(key) for key in ('id', 'owner', 'time_updated', 'total_files_bytes')),
          'official_item_changed_during_download')
    return steam_manifest


def _target_entry(trees, role, path, *, digest=None, size=None, git_input=False):
    _need(role in trees and _path(path), 'unknown_source_repo_or_path')
    entry = trees[role]['entries'].get(path)
    _need(isinstance(entry, dict) and entry.get('kind') == 'blob'
          and entry.get('mode') in {'100644', '100755'}
          and isinstance(entry.get('oid'), str) and re.fullmatch('[a-f0-9]{40,64}', entry['oid'])
          and type(entry.get('bytes')) is int and entry['bytes'] >= 0,
          'published_source_must_be_known_regular_git_entry')
    actual_hash = entry.get('git_sha256', entry.get('sha256')) if git_input else entry.get('sha256')
    actual_size = entry['bytes'] if git_input else entry.get('content_bytes', entry['bytes'])
    _need(_digest(actual_hash) and (digest is None or actual_hash == digest)
          and (size is None or actual_size == size), 'published_git_input_or_artifact_hash_differs')
    if entry.get('lfs') is True and not git_input:
        _need(entry.get('hash_state') == 'VERIFIED' and entry.get('lfs_declared_sha256') == actual_hash,
              'resolved_verified_lfs_output_required')
    return {key: copy.deepcopy(entry[key]) for key in ('mode', 'kind', 'oid', 'bytes')}, actual_hash


def advance_baseline(previous, authenticated_manifest, package_report, target_git_trees, verified_delivery):
    """Return a new mixed baseline after same-target SDK + complete download.

    target_git_trees = {game:{commit,entries:{path:entry}}, content:...}; each
    actually covered entry additionally needs sha256 of resolved bytes, and for
    LFS git_sha256/raw bytes plus content_bytes/verified LFS metadata. Uncovered
    HEAD entries need no hashes and are never copied. The delivery evidence must
    include journal, original journal/package/manifest byte SHA256s, the actual
    download receipt, signature/release validation, and canonical_digest of the
    supplied manifest/report objects. This is a pure checker of authenticated
    inputs, not a signature verifier for arbitrary caller-supplied JSON.

    Explicit removals require removed_source_bindings={resource:[{repo,path}]},
    including the absent game runtime output. Unknown removal provenance fails.
    """
    manifest, report = authenticated_manifest, package_report
    _need(isinstance(previous, dict) and isinstance(manifest, dict) and isinstance(report, dict), 'baseline_manifest_report_objects_required')
    rows = _manifest_rows(manifest)
    steam_manifest = _validate_delivery(manifest, report, verified_delivery)
    _need(type(previous.get('parent_sequence')) is int and report['release_sequence'] > previous['parent_sequence']
          and report.get('baseline_release_sequence') == previous['parent_sequence']
          and report.get('baseline_content_sha256') == previous.get('parent_content_sha256')
          and report.get('authenticated_parent_manifest_sha256') == previous.get('parent_manifest_sha256'),
          'rollforward_parent_baseline_changed_or_not_newer')
    lineage = report.get('git_runtime_lineage', {})
    _need(isinstance(lineage, dict) and lineage.get('complete') is True and lineage.get('unknown_changes') == []
          and lineage.get('actual_parent_manifest_sha256') == previous['parent_manifest_sha256'],
          'complete_known_runtime_lineage_required')
    _need(lineage.get('full_head_publication_claimed') is not True
          and lineage.get('source_anchor_is_full_published_tree') is not True,
          'mixed_rollforward_cannot_claim_full_head')
    sources = report.get('source_revisions')
    _need(isinstance(sources, dict) and set(sources) == {'game', 'content'}
          and all(_digest(value, 40) for value in sources.values()) and lineage.get('source_revisions') == sources
          and set(target_git_trees) == {'game', 'content'}, 'exact_dual_target_git_revisions_required')
    for role, tree in target_git_trees.items():
        _need(isinstance(tree, dict) and tree.get('commit') == sources[role]
              and isinstance(tree.get('entries'), dict), 'target_tree_commit_differs_from_published_source')
    old_origins, origins = previous.get('resource_origins'), lineage.get('resource_origins')
    _need(isinstance(old_origins, dict) and isinstance(origins, dict) and set(origins) == set(rows),
          'complete_resource_origins_must_match_signed_manifest')
    _need(previous.get('resource_origins_sha256') == canonical_digest(old_origins)
          and report.get('parent_resource_origins_sha256') == canonical_digest(old_origins)
          and lineage.get('parent_resource_origins_sha256') == canonical_digest(old_origins),
          'previous_resource_origin_chain_changed')
    _need(report.get('resource_origins_sha256') == canonical_digest(origins)
          and lineage.get('resource_origins_sha256') == canonical_digest(origins), 'new_resource_origin_digest_differs')
    for path, origin in old_origins.items():
        _need(_path(path) and isinstance(origin, dict) and _digest(origin.get('resource_sha256'))
              and type(origin.get('resource_bytes')) is int and origin['resource_bytes'] >= 0,
              'invalid_previous_resource_origin')
    changed = {path for path, row in rows.items() if path not in old_origins
               or (row['sha256'], row['bytes']) != (old_origins[path]['resource_sha256'], old_origins[path]['resource_bytes'])}
    added, removed = set(rows) - set(old_origins), set(old_origins) - set(rows)
    _need(_paths(report.get('changed_runtime_paths'), 'explicit_runtime_changes_required') == changed
          and _paths(report.get('added_runtime_paths'), 'explicit_runtime_additions_required') == added
          and _paths(report.get('removed_runtime_paths'), 'explicit_runtime_removals_required') == removed,
          'declared_runtime_change_set_differs_from_delivered_bytes')
    _need(_paths(lineage.get('changed_runtime_paths'), 'lineage_change_set_required') == changed,
          'lineage_runtime_changes_differ')
    pins = report.get('target_pins')
    _need(isinstance(pins, dict) and set(pins) == changed and all(
        pins[path].get('sha256') == rows[path]['sha256'] and pins[path].get('bytes') == rows[path]['bytes'] for path in changed),
        'delivered_resource_pins_do_not_match_signed_manifest')
    for path, origin in origins.items():
        _need(origin.get('resource_sha256') == rows[path]['sha256'] and origin.get('resource_bytes') == rows[path]['bytes'],
              'resource_origin_does_not_describe_signed_bytes')
        if path not in changed:
            _need(origin == old_origins[path], 'unpublished_resource_provenance_cannot_be_rebound_to_head')
    compiled_pins = report.get('source_artifact_pins', {})
    _need(isinstance(compiled_pins, dict), 'compiler_source_pin_map_required')
    covered, consumed_compiled = {}, set()
    def cover(role, path, digest, *, size=None, git_input=False, resource=None):
        entry, actual = _target_entry(target_git_trees, role, path, digest=digest, size=size, git_input=git_input)
        key = role + ':' + path
        value = dict(repo=role, path=path, entry=entry, sha256=actual, resource=resource)
        _need(key not in covered or covered[key] == value, 'contradictory_published_source_binding')
        covered[key] = value
    for path in sorted(changed):
        origin, row = origins[path], rows[path]
        _need(origin.get('source_revision') == sources['game']
              and origin.get('parent_content_sha256') == previous['parent_content_sha256'],
              'changed_resource_source_revision_or_parent_differs')
        cover('game', path, row['sha256'], size=row['bytes'], resource=path)
        if origin.get('kind') == 'IMMUTABLE_GIT_RUNTIME_BLOB':
            _need(origin.get('source_path') == path, 'identity_resource_source_path_differs')
        elif origin.get('kind') == 'BOUND_OFFICIAL_COMPILER_ARTIFACT':
            source = origin.get('source_path'); pin = compiled_pins.get(source)
            _need(isinstance(pin, dict) and pin.get('compiled_artifact_sha256') == row['sha256']
                  and origin.get('compilation_binding') == pin
                  and pin.get('normalization') in {'IDENTITY', 'GIT_LF_TO_COMPILER_CRLF_ONLY'},
                  'exact_published_compiler_binding_required')
            git_pin, compiler_pin = pin.get('git_blob', {}), pin.get('compiler_input', {})
            _need(_digest(git_pin.get('sha256')) and _digest(compiler_pin.get('sha256'))
                  and origin.get('source_git_sha256') == git_pin['sha256']
                  and origin.get('compiler_input_sha256') == compiler_pin['sha256'],
                  'compiler_source_or_input_digest_differs')
            cover('game', source, git_pin['sha256'], size=git_pin.get('bytes'), git_input=True, resource=path)
            mirror = pin.get('content_mirror')
            _need(isinstance(mirror, dict) and mirror.get('source_revision') == sources['content']
                  and mirror.get('sha256') == git_pin['sha256'], 'same_published_content_mirror_required')
            cover('content', mirror.get('path'), mirror['sha256'], git_input=True, resource=path)
            consumed_compiled.add(source)
        else:
            raise ValueError('unknown_runtime_origin_requires_explicit_rollforward_mapping')
    _need(consumed_compiled == set(compiled_pins), 'compiler_pin_does_not_belong_to_a_delivered_runtime_change')
    removal_bindings = report.get('removed_source_bindings', {})
    _need(isinstance(removal_bindings, dict) and set(removal_bindings) == removed,
          'runtime_removal_requires_explicit_source_bindings')
    removed_sources = {}
    for resource, inputs in removal_bindings.items():
        _need(isinstance(inputs, list) and inputs and dict(repo='game', path=resource) in inputs,
              'removed_runtime_output_must_be_explicitly_bound')
        for source in inputs:
            role, path = source.get('repo'), source.get('path')
            _need(role in target_git_trees and _path(path) and path not in target_git_trees[role]['entries'],
                  'removed_source_still_exists_or_is_unknown')
            key = role + ':' + path
            _need(key not in covered, 'source_cannot_be_published_and_removed')
            removed_sources[key] = dict(repo=role, path=path, resource=resource)
    baseline = copy.deepcopy(previous)
    inventory = baseline.get('source_inventory')
    _need(isinstance(inventory, dict) and set(inventory) == {'game', 'content'}
          and all(isinstance(v, dict) for v in inventory.values()), 'previous_mixed_source_inventory_required')
    for item in covered.values():
        inventory[item['repo']][item['path']] = copy.deepcopy(item['entry'])
    for item in removed_sources.values():
        _need(item['path'] in inventory[item['repo']], 'removed_source_not_in_previous_inventory')
        del inventory[item['repo']][item['path']]
    deferred = copy.deepcopy(previous.get('deferred_sources', {}))
    _need(isinstance(deferred, dict), 'previous_deferred_history_required')
    for group in (lineage.get('deferred_sources'), lineage.get('deferred_unpublished0201_sources')):
        _need(isinstance(group, dict), 'explicit_deferred_source_maps_required')
        for key, item in group.items():
            _need(isinstance(item, dict) and item.get('repo') in inventory and _path(item.get('path'))
                  and key == item['repo'] + ':' + item['path'], 'invalid_deferred_source_identity')
            _need(key not in deferred or deferred[key] == item or key in covered or key in removed_sources,
                  'unpublished_deferred_history_changed_without_delivery')
            if key not in deferred:
                deferred[key] = copy.deepcopy(item)
    # A selective package cannot silently absorb unrelated target-tree changes.
    # Those changes either remain explicitly deferred or are unknown and refuse
    # roll-forward. The original entries are retained, including pending deletes.
    for role, tree in target_git_trees.items():
        previous_entries = previous['source_inventory'][role]
        for path in set(previous_entries) | set(tree['entries']):
            key = role + ':' + path
            if not _source_relevant(path) or key in covered or key in removed_sources:
                continue
            if _tree_identity(previous_entries.get(path)) != _tree_identity(tree['entries'].get(path)):
                _need(key in deferred, 'unknown_unpublished_source_change_requires_explicit_deferral')
    cleared = []
    history = baseline.setdefault('resolved_deferred_history', [])
    _need(isinstance(history, list), 'resolved_history_must_be_append_only_list')
    for key in sorted(set(covered) | set(removed_sources)):
        if key not in deferred:
            continue
        source = covered.get(key) or removed_sources[key]
        resolution = dict(key=key, entry=deferred.pop(key), release_sequence=report['release_sequence'],
                          resource=source['resource'], resolution='REMOVED_FROM_RUNTIME' if key in removed_sources else 'INPUT_AND_OUTPUT_ACTUALLY_DELIVERED')
        history.append(resolution); cleared.append(key)
    baseline.update(schema=previous.get('schema', 1), kind='AUTHENTICATED_MIXED_PUBLICATION_BASELINE',
        parent_sequence=report['release_sequence'], parent_content_sha256=manifest['content_sha256'],
        parent_manifest_sha256=verified_delivery['manifest_sha256'], official_parent_manifest=steam_manifest,
        resource_origins=copy.deepcopy(origins), resource_origins_sha256=canonical_digest(origins),
        deferred_sources=deferred, source_anchor_is_full_published_tree=False,
        full_head_publication_claimed=False, last_published_source_revisions=copy.deepcopy(sources),
        rollforward=dict(previous_sequence=previous['parent_sequence'], previous_content_sha256=previous['parent_content_sha256'],
            previous_manifest_sha256=previous['parent_manifest_sha256'], package_report_sha256=verified_delivery['package_report_sha256'],
            canonical_journal_sha256=verified_delivery['journal_sha256'],
            updated_source_entries=sorted(covered), removed_source_entries=sorted(removed_sources),
            changed_runtime_paths=sorted(changed), removed_runtime_paths=sorted(removed), cleared_deferred_sources=cleared,
            untouched_source_entries_preserved=True, sdk_and_full_official_download_verified=True,
            filesystem_writes=0, journal_writes=0, sdk_calls=0))
    return baseline
