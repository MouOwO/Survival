"""Read-only pending audit from the authenticated complete delivery checkpoint.

One invocation rechecks original control evidence, indexes two current Git
trees, then streams only new/changed source blobs. Stable game refresh cost is
zero: this tool has no watcher, native, SDK, timer, mutation or network call.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
ROOT = Path(__file__).resolve().parents[2]
TOOL = 'tools/complete_delivery_pack_2026111007_314dcb/complete_pending.py'
LOADED_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()

def inventory():
    from complete_delivery_pack_2026111007_314dcb import parent_pending as pending
    from complete_delivery_pack_2026111007_314dcb import complete_baseline as baseline
    from complete_delivery_pack_2026111007_314dcb import pipeline_recipe as recipe
    checkpoint, manifest, cursor = baseline.load_active()
    evidence = checkpoint['complete_delivery']
    policy_operator = evidence['publication_operator_revision'] if evidence.get('publication_mode') == 'EXPLICIT_UNLISTED_ONLINE_TEST_NATIVE_PENDING' else evidence['package_operator_revision']
    recipe.verify_operator_paths({TOOL: LOADED_LF_SHA256}, policy_operator)
    counts = Counter()
    trees, commits, dirty = ({}, {}, [])
    roots = {'game': ROOT, 'content': pending.CONTENT}
    for role, root in roots.items():
        commits[role] = pending._git(root, 'rev-parse', 'HEAD', counts=counts).decode('ascii').strip()
        trees[role] = pending.git_tree(root, counts, commits[role])
        dirty.extend(pending.git_dirty(root, role, counts))
    keys = pending.pending_source_keys(checkpoint['source_inventory'], trees, checkpoint['deferred_sources'])
    budget = pending.HashBudget()
    facts = {}
    for role, root in roots.items():
        changed = {path for selected_role, path in keys if selected_role == role}
        if changed:
            facts.update(((role + ':' + path, fact) for path, fact in pending.read_git_facts(root, trees[role], changed, budget, counts).items()))
    policy = pending._read_json(ROOT / 'tools/lua_protection_policy.json')
    production = set(policy['business_modules'])
    for name in set(checkpoint['source_inventory']['game']) | set(trees['game']):
        if name.startswith(policy['generated_prefix']) and PurePosixPath(name).name not in policy['generated_exclusions']:
            production.add(name)
    result = pending.classify_inventory(baseline_inventory=checkpoint['source_inventory'], head_inventory=trees, parent_manifest=manifest, deferred_sources=checkpoint['deferred_sources'], blob_facts=facts, dirty=dirty, production_resources=production)
    mode = 'COMPLETE_SDK_NATIVE_AND_OFFICIAL_DOWNLOAD_VERIFIED_CHECKPOINT' if checkpoint.get('complete_delivery', {}).get('ordinary_production_acceptance') is True else 'COMPLETE_SDK_AND_OFFICIAL_DOWNLOAD_VERIFIED_NATIVE_PENDING_CHECKPOINT'
    result.update(target_commits=commits, baseline_mode=mode, baseline_control=cursor, recorded_parent_sequence=checkpoint['parent_sequence'], recorded_parent_manifest_sha256=checkpoint['parent_manifest_sha256'], recorded_parent_content_sha256=checkpoint['parent_content_sha256'], recorded_parent_steam_manifest=checkpoint['official_parent_manifest'], call_counts=dict(counts), hash_budget=dict(max_total=budget.total, max_blob=budget.per_blob, reserved=budget.used), official_remote_queried=False, bytes_written=0, git_mutations=0, sdk_calls=0, network_calls=0, complete_checkpoint_does_not_claim_plaintext_runtime_export=True)
    return result
