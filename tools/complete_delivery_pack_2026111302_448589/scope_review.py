"""Read-only full pending scope review; optional output is a JSON report only.

Not a build recipe: observed HEAD/working files are not admitted runtime sources.
Indexes current trees once per repository after the existing inventory pass,
and at most 64 local manifest documents / 128MiB. No VPK, SDK, network, Git
mutation, signing, installation, game launch or journal mutation is performed.
"""
from __future__ import annotations
import argparse
from collections import Counter
import contextlib
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from complete_delivery_pack_2026111302_448589 import parent_pending as inventory
ROOT = inventory.ROOT
HISTORICAL = Path('D:/Survival_发布候选')

def author_paths(resource):
    """Candidate source paths only; availability is not a compilation proof."""
    if resource == 'soundevents/survival_background_music.vsndevts_c':
        return [('content', 'soundevents/survival_background_music.vsndevts')]
    keeper_prefix = 'particles/survival/heroes/keeper/'
    if resource in {keeper_prefix + name + '.vpcf_c' for name in ('keeper_of_the_light_base_attack', 'keeper_base_attack')}:
        source = resource[:-2]
        return [('content', source), ('game', 'art/effects/keeper_attack/source/' + source)]
    if resource == inventory.LOADING_COVER_RESOURCE:
        primary = inventory.LOADING_COVER_DESCRIPTOR
        return [('game', inventory.LOADING_COVER_AUTHORS[primary]), ('content', primary)]
    suffix = PurePosixPath(resource).suffix
    endings = {'.vjs_c': '.js', '.vcss_c': '.css', '.vxml_c': '.xml', '.vtex_c': '.vtex', '.vsvg_c': '.svg'}
    if suffix not in endings:
        return []
    source = str(PurePosixPath(resource).with_suffix(endings[suffix]))
    if suffix in ('.vjs_c', '.vcss_c', '.vxml_c'):
        return [('game', source.replace('panorama/', 'panorama/src/', 1)), ('content', source)]
    return [('content', source)]

def read_manifests(paths, pending_resources):
    index = {}
    documents = []
    used = 0
    for path in paths:
        if len(documents) >= 64:
            raise ValueError('manifest_document_budget_exceeded')
        if not path.is_file() or path.is_symlink():
            continue
        size = path.stat().st_size
        if size > 16 * 1024 * 1024 or used + size > 128 * 1024 * 1024:
            raise ValueError('manifest_read_budget_exceeded')
        raw = path.read_bytes()
        used += len(raw)
        value = json.loads(raw)
        if not isinstance(value.get('files'), list):
            continue
        document = dict(path=str(path), sha256=hashlib.sha256(raw).hexdigest(), content_sha256=value.get('content_sha256'), release_sequence=value.get('release_sequence'), files=len(value['files']))
        documents.append(document)
        for row in value['files']:
            resource = row.get('path')
            if resource in pending_resources:
                index.setdefault((resource, row.get('sha256'), row.get('bytes')), []).append(document)
    return (index, documents, used)

def review():
    capture = io.StringIO()
    with contextlib.redirect_stdout(capture):
        inventory.main([])
    initial = json.loads(capture.getvalue())
    counts = Counter()
    trees = {}
    for role, repo in (('game', ROOT), ('content', inventory.CONTENT)):
        trees[role] = inventory.git_tree(repo, counts, initial['target_commits'][role])
    resource_paths = {row['resource'] for row in initial['rows'] if row.get('resource')}
    paths = [inventory.PARENT_MANIFEST]
    paths.extend(sorted((p / '_release_manifest.json' for p in HISTORICAL.iterdir() if p.is_dir() and p.name.endswith('_view') and (p / '_release_manifest.json' != inventory.PARENT_MANIFEST))))
    manifest_index, documents, bytes_read = read_manifests(paths, resource_paths)
    parent_documents = [row for row in documents if row['path'] == str(inventory.PARENT_MANIFEST)]
    if len(parent_documents) != 1 or parent_documents[0]['sha256'] != initial['recorded_parent_manifest_sha256']:
        raise ValueError('authenticated_parent_manifest_changed_during_scope_review')
    dirty = {(r['repo'], r['path']) for r in initial['dirty'] if r['runtime_related']}
    decisions = []
    for row in initial['rows']:
        source = row['source']
        resource = row.get('resource') or source['path']
        item = dict(source=source, resource=resource, inventory_status=row['status'], history=row['history'], working_tree_dirty=(source['repo'], source['path']) in dirty, candidate=row['candidate'], parent_sha256=row.get('parent_sha256'))
        candidates = []
        for role, path in author_paths(resource):
            value = trees[role].get(path)
            candidates.append(dict(repo=role, path=path, exists_in_observed_commit=value is not None, oid=value.get('oid') if value else None, bytes=value.get('bytes') if value else None, source_commit=initial['target_commits'][role], working_copy_dirty=(role, path) in dirty))
        item['candidate_authors'] = candidates
        digest = row['candidate'].get('sha256')
        size = row['candidate'].get('bytes')
        matches = manifest_index.get((resource, digest, size), [])
        item['local_manifest_byte_matches'] = [dict(**match, proof='AUTHENTICATED_PARENT_DIGEST' if match['path'] == str(inventory.PARENT_MANIFEST) else 'HISTORICAL_MANIFEST_DECLARATION_ONLY_NOT_SOURCE_BINDING') for match in matches]
        compiled = PurePosixPath(resource).suffix in inventory.COMPILED_SUFFIXES | {'.vsvg_c'}
        if source.get('head_oid') is None:
            decision = 'EXPLICIT_RUNTIME_REMOVAL_REVIEW_REQUIRED'
        elif compiled and digest and (digest == row.get('parent_sha256')):
            decision = 'EXACT_PARENT_RESOURCE_BYTES_REVIEW_PRESERVE_NO_RECOMPILATION_CLAIM'
        elif compiled and matches:
            decision = 'LOCAL_HISTORICAL_MANIFEST_BYTES_MATCH_INPUT_BINDING_STILL_REQUIRED'
        elif compiled and candidates and all((author['exists_in_observed_commit'] for author in candidates)):
            decision = 'IMMUTABLE_AUTHORS_AVAILABLE_RECOMPILE_OR_VALIDATE_EMBEDDED_BINDING'
        elif compiled:
            decision = 'MISSING_IMMUTABLE_AUTHOR_MAPPING_BLOCKING'
        elif row['status'] == 'PRODUCTION_TRANSFORM_REQUIRED':
            decision = 'EXPLICIT_PRODUCTION_POLICY_OR_PROTECTION_TRANSFORM_REQUIRED'
        elif row['status'] == 'GENERATED_BINDING_REQUIRED':
            decision = 'GENERATOR_INPUT_OUTPUT_BINDING_REQUIRED'
        elif row['blocking']:
            decision = 'UNRESOLVED_MAPPING_OR_REVIEW_REQUIRED'
        else:
            decision = 'IDENTITY_BYTES_AVAILABLE_STILL_REQUIRES_COMBINED_REVIEW'
        item['review_decision'] = decision
        decisions.append(item)
    return dict(schema=1, kind='ALL_PENDING_AND_CURRENT_WORKTREE_SCOPE_REVIEW_NOT_A_BUILD_RECIPE', publication_status='LOCAL_REVIEW_ONLY_NO_PUBLICATION_CLAIM', observed_commits=initial['target_commits'], immutable_release_sources_selected=False, baseline=dict(sequence=initial['recorded_parent_sequence'], manifest_sha256=initial['recorded_parent_manifest_sha256'], content_sha256=initial['recorded_parent_content_sha256']), initial_counts=initial['counts'], decisions=decisions, current_worktree_runtime=[row for row in initial['dirty'] if row['runtime_related']], other_worktree_changes=[row for row in initial['dirty'] if not row['runtime_related']], decision_counts=dict(sorted(Counter((row['review_decision'] for row in decisions)).items())), local_manifests=documents, read_costs=dict(inventory_calls=initial['call_counts'], extra_tree_calls=dict(counts), manifest_bytes=bytes_read), unresolved_current_source_bindings=True, build_ready=False, publication_ready=False, sdk_calls=0, network_calls=0, git_mutations=0, package_or_journal_writes=0)

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    value = review()
    raw = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
    if args.output:
        target = args.output.resolve()
        if not target.is_relative_to((ROOT / 'output').resolve()) or target.suffix != '.json':
            raise ValueError('review_report_must_be_output_json')
        if target.exists():
            raise ValueError('new_scope_review_report_required_preserve_previous_evidence')
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(raw)
        print(json.dumps(dict(kind=value['kind'], report=str(target), sha256=hashlib.sha256(raw).hexdigest(), initial_counts=value['initial_counts'], decision_counts=value['decision_counts'], build_ready=False), ensure_ascii=False))
    else:
        print(raw.decode())
if __name__ == '__main__':
    main()
