"""Read-only full production-transform plan for the complete0302 family.

This is not a builder or signing authority. Explicit immutable dual Git sources
are required. All protected inputs and seven production overrides are listed;
missing native/value/compiler evidence remains blocking. No directory, runtime,
VPK, signature, journal, key, Git state, process, SDK or network is changed.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from complete_delivery_pack_2026111201_8c2c6c import parent_pending as pending
import protect_runtime_lua as protection
SEQUENCE = 2026111201
PROMETHEUS = Path('D:/Survival_安全工具/prometheus')
OVERRIDES = ('addoninfo.txt', 'scripts/vscripts/addon_game_mode_client.lua', 'scripts/vscripts/config/commerce_payment_access.lua', 'scripts/vscripts/config/player_web_auth.lua', 'scripts/vscripts/config/release_profile.lua', 'scripts/vscripts/config/workshop_connection.lua', 'scripts/vscripts/core/test_access_policy.lua')
CONSTANT_OVERRIDES = frozenset(OVERRIDES[2:6])
NEW_GENERATED = ('scripts/vscripts/config/generated/ui_compact_wire_budget.lua', 'scripts/vscripts/config/generated/ui_static_catalog_lookup.lua')

def need(value, reason):
    if not value:
        raise ValueError(reason)

def lua_runtime(path):
    parts = path.split('/')
    return path.startswith('scripts/vscripts/') and path.endswith('.lua') and (not any((part in ('tests', '__pycache__', 'node_modules') or part.startswith('.') for part in parts)))

def plan(game_revision, content_revision):
    for role, value in (('game', game_revision), ('content', content_revision)):
        need(re.fullmatch('[a-f0-9]{40}', value or '') is not None, 'explicit_immutable_dual_revision_required:' + role)
    counts = Counter()
    trees = {}
    for role, repo, revision in (('game', ROOT, game_revision), ('content', pending.CONTENT, content_revision)):
        actual = pending._git(repo, 'rev-parse', '--verify', revision + '^{commit}', counts=counts).decode('ascii').strip()
        need(actual == revision, 'explicit_revision_must_be_the_exact_commit:' + role)
        trees[role] = pending.git_tree(repo, counts, revision)
    baseline = pending._read_json(pending.BASELINE, pending.BASELINE_SHA256)
    manifest = pending._read_json(pending.PARENT_MANIFEST, baseline['parent_manifest_sha256'])
    need(manifest['content_sha256'] == baseline['parent_content_sha256'], 'authenticated0104_parent_changed')
    parent = {row['path']: row for row in manifest['files']}
    policy_path = ROOT / 'tools/lua_protection_policy.json'
    policy_raw = policy_path.read_bytes()
    policy = json.loads(policy_raw)
    protection.check_policy(policy)
    dependency = protection.dependency_identity(PROMETHEUS, policy)
    selected = protection.selected_files(sorted((path for path in trees['game'] if lua_runtime(path))), policy)
    historical = baseline['deferred_sources']
    generated = set((path['path'] for path in selected if path['kind'] == 'generated_table'))
    required = set(OVERRIDES) | {row['path'] for row in selected}
    facts = pending.read_git_facts(ROOT, trees['game'], required, pending.HashBudget(total=256 * 1024 * 1024, per_blob=32 * 1024 * 1024), counts)
    protected = []
    for row in selected:
        path = row['path']
        fact = facts.get(path, {})
        need(fact.get('hash_state') == 'VERIFIED' and fact.get('sha256'), 'immutable_protection_input_unavailable:' + path)
        protected.append(dict(path=path, kind=row['kind'], source_revision=game_revision, git_oid=trees['game'][path]['oid'], source_sha256=fact['sha256'], source_bytes=fact['bytes'], historical_deferred='game:' + path in historical, new_network50_configuration=path in NEW_GENERATED, required_check='EXACT_ALL_GENERATED_VALUES_AND_KEY_IDENTITY' if row['kind'] == 'generated_table' else 'EXISTING_BEHAVIOR_PROBES_AND_RNG_INVARIANT', transformed_sha256=None, transformed_bytes=None, verification='NOT_RUN_BLOCKING'))
    overrides = []
    for path in OVERRIDES:
        need(path in parent, 'production_override_missing_from_authenticated_parent:' + path)
        fact = facts.get(path, {})
        need(fact.get('hash_state') == 'VERIFIED', 'production_development_input_unavailable:' + path)
        constant = path in CONSTANT_OVERRIDES
        overrides.append(dict(path=path, development_source_revision=game_revision, development_git_oid=trees['game'][path]['oid'], development_sha256=fact['sha256'], target=dict(bytes=parent[path]['bytes'], sha256=parent[path]['sha256']) if constant else None, authenticated_policy_baseline=dict(bytes=parent[path]['bytes'], sha256=parent[path]['sha256']), target_origin='AUTHENTICATED0104_PRODUCTION_POLICY_BYTES' if constant else 'REQUIRES_REVIEWED_IMMUTABLE_SOURCE_PRODUCTION_TRANSFORM', required_transform_tool=None if constant else 'tools/complete_delivery_pack_2026111201_8c2c6c/production.py', replacing_with_parent_would_discard_new_runtime_logic=not constant, authenticated_parent_manifest_sha256=baseline['parent_manifest_sha256'], preserve_current_source_in_git=True, production_rules_or_account_limits_relaxed=False, changed_source_logic_outside_policy_review='NOT_REVIEWED_BLOCKING'))
    new_missing = sorted(set(NEW_GENERATED) - generated)
    blockers = ['SOURCE_EXPORT_NOT_PREPARED', 'ALL_PROTECTED_OUTPUTS_NOT_BUILT_OR_VALUE_VERIFIED', 'SEVEN_POLICY_OVERRIDES_REQUIRE_EXPLICIT_COMBINED_SOURCE_REVIEW', 'FULL_COMPILED_RESOURCE_AND_GENERATOR_BINDINGS_REQUIRED', 'COMPLETE_RUNTIME_LEDGER_AND_AUTHORITY_NOT_IMPLEMENTED', 'SIGNED_PACKAGE_ORDINARY_CLIENT_NATIVE_ADMISSION_NOT_RUN']
    if new_missing:
        blockers.append('NEW_NETWORK50_GENERATED_CONFIG_MISSING_FROM_SELECTED_COMMIT')
    return dict(schema=1, kind='COMPLETE0302_READ_ONLY_PRODUCTION_TRANSFORM_PLAN_NOT_A_SIGNABLE_RECIPE', release_sequence=SEQUENCE, source_revisions=dict(game=game_revision, content=content_revision), parent=dict(sequence=baseline['parent_sequence'], manifest_sha256=baseline['parent_manifest_sha256'], content_sha256=manifest['content_sha256'], resource_count=manifest['file_count']), policy=dict(path='tools/lua_protection_policy.json', sha256=hashlib.sha256(policy_raw).hexdigest(), dependency=dependency, data_string_obfuscation_required=True), protected_inputs=protected, production_overrides=overrides, counts=dict(protected_total=len(protected), generated_total=len(generated), business_probe_modules=sum((row['kind'] == 'business' for row in protected)), historical_protected_pending=sum((row['historical_deferred'] for row in protected)), new_network50_configurations=sum((row['new_network50_configuration'] for row in protected)), production_overrides=len(overrides)), missing_new_configurations=new_missing, preparation_recipe=dict(tool='tools/protect_runtime_lua.py', production_transform_tool='tools/complete_delivery_pack_2026111201_8c2c6c/production.py', source='NEW_EXTERNAL_IMMUTABLE_PRODUCTION_EXPORT_REQUIRED', destination='NEW_EXTERNAL_PROTECTED_LUA_TREE_REQUIRED', flags=['--data-string-obfuscation'], before_key_use='VERIFY_EVERY_GENERATED_VALUE_AND_BUSINESS_PROBE_AND_SOURCE_HASH', plaintext_fallback_allowed=False, installed_or_frozen_tree_writes_allowed=False), blockers=blockers, build_ready=False, signature_ready=False, publication_ready=False, protected_values_verified=False, ordinary_client_admission_verified=False, call_counts=dict(counts), files_written=0, git_mutations=0, signing_key_read=False, sdk_calls=0, network_calls=0)

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--content-source-revision', required=True)
    args = parser.parse_args(argv)
    print(json.dumps(plan(args.source_revision, args.content_source_revision), ensure_ascii=False, indent=2))
if __name__ == '__main__':
    main()
