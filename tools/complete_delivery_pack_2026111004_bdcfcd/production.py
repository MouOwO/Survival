"""Prepare immutable Lua production inputs; never sign, install, upload or publish.

Four constant configurations retain authenticated0104 bytes. Three files retain
new immutable runtime logic with narrowly reviewed production policy. Optional
protection uses the existing pinned Prometheus recipe and all-value/RNG probes.
An incomplete full-runtime recipe/ledger/authority remains a publication blocker.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from complete_delivery_pack_2026111004_bdcfcd import parent_pending as pending
import protect_runtime_lua as protection
OVERRIDES = ('addoninfo.txt', 'scripts/vscripts/addon_game_mode_client.lua', 'scripts/vscripts/config/commerce_payment_access.lua', 'scripts/vscripts/config/player_web_auth.lua', 'scripts/vscripts/config/release_profile.lua', 'scripts/vscripts/config/workshop_connection.lua', 'scripts/vscripts/core/test_access_policy.lua')
CONSTANTS = OVERRIDES[2:6]
ACCESS = 'scripts/vscripts/config/test_access.lua'
PROFILE = 'scripts/vscripts/core/test_access_policy.lua'
TOOL_INPUTS = ('tools/complete_delivery_pack_2026111004_bdcfcd/production.py', 'tools/complete_delivery_pack_2026111004_bdcfcd/parent_pending.py', 'tools/release_pending_inventory.py', 'tools/protect_runtime_lua.py', 'tools/build_runtime_release.py', 'tools/lua_protection_policy.json', 'tools/admission_five_20261101/test_projected_policy.lua', 'tools/lua_protection/prometheus_offline_driver.lua', 'tools/lua_protection/verify_values.lua')
EXECUTED_SOURCE_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
LOADED_OPERATOR_LF_HASHES = {'tools/complete_delivery_pack_2026111004_bdcfcd/production.py': EXECUTED_SOURCE_LF_SHA256, 'tools/complete_delivery_pack_2026111004_bdcfcd/parent_pending.py': pending.EXECUTED_SOURCE_LF_SHA256, 'tools/release_pending_inventory.py': pending.legacy.EXECUTED_SOURCE_LF_SHA256, 'tools/protect_runtime_lua.py': protection.EXECUTED_SOURCE_LF_SHA256, 'tools/build_runtime_release.py': protection.runtime.EXECUTED_SOURCE_LF_SHA256}
for _path in sorted(set(TOOL_INPUTS) | {path.relative_to(ROOT).as_posix() for path in (ROOT / 'tools/lua_protection').glob('*.lua')}):
    if _path not in LOADED_OPERATOR_LF_HASHES:
        LOADED_OPERATOR_LF_HASHES[_path] = hashlib.sha256((ROOT / _path).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
LEGACY_BLOCKS = ('local offline_onboarding = require("debug/offline_onboarding_test")\n', '    -- Latch the explicit preview choice before an online match can mutate a\n    -- server convar. The helper never loads or enables the offline provider.\n    offline_onboarding.requested()\n', '    if offline_onboarding.requested() then\n        if not offline_onboarding.is_human(player_id) then\n            return false, "test_access_player_invalid"\n        end\n        return true\n    end\n')

def need(value, reason):
    if not value:
        raise ValueError(reason)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def lf(raw):
    return raw.replace(b'\r\n', b'\n')

def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()

def immutable(value):
    need(re.fullmatch('[a-f0-9]{40}', value or '') is not None, 'explicit_immutable_commit_required')
    return value

def transform_overrides(source, parent):
    """Pure, fail-closed transformations. No filesystem or engine access."""
    need(set(OVERRIDES) | {ACCESS} <= set(source) and set(OVERRIDES) | {ACCESS} <= set(parent), 'complete_override_and_roster_inputs_required')
    targets, reviews = ({}, [])
    for path in CONSTANTS:
        targets[path] = parent[path]
        reviews.append(dict(path=path, kind='AUTHENTICATED0104_CONSTANT_BYTES', constant_policy_probe_required=True))
    path = 'addoninfo.txt'
    text = lf(source[path]).decode('utf8')
    original = lf(parent[path]).decode('utf8')
    need(re.search('"maps"\\s+"ws4_entry"', original) is not None, 'authenticated_entry_policy_must_be_ws4_entry')
    need(len(re.findall('"maps"\\s+"(?:template_map|ws4_entry)"', text)) == 1, 'exactly_one_reviewed_primary_map_required')
    text = re.sub('("maps"\\s+)"(?:template_map|ws4_entry)"', '\\1"ws4_entry"', text, count=1)
    for name in ('ws4_entry', 'template_map'):
        expression = '("' + name + '"\\s*\\{\\s*"MaxPlayers"\\s*)"[0-9]+"(\\s*\\})'
        need(len(re.findall(expression, original)) == 1 and re.search(expression, original)[0].find('"4"') >= 0, 'authenticated_four_player_map_policy_required:' + name)
        need(len(re.findall(expression, text)) == 1, 'explicit_map_capacity_anchor_required:' + name)
        text = re.sub(expression, '\\1"4"\\2', text, count=1)
    need(re.search('"ws4_lobby"\\s*\\{\\s*"MaxPlayers"\\s*"1"\\s*\\}', text) is not None, 'current_independent_lobby_must_survive')
    targets[path] = text.encode()
    reviews.append(dict(path=path, kind='CURRENT_SOURCE_WITH_ENTRY_AND_FOUR_PLAYER_POLICY', retained_lobby=True, primary_map='ws4_entry', gameplay_capacity=4, lobby_capacity=1))
    path = 'scripts/vscripts/addon_game_mode_client.lua'
    text, original = (lf(source[path]), lf(parent[path]))
    need(text.endswith(original), 'original_native_entry_handoff_suffix_changed')
    need(b'require("systems/hosted_lobby_client")' in text and b'ActivateClient=Activate' in text, 'current_hosted_lobby_initializer_missing')
    targets[path] = source[path]
    reviews.append(dict(path=path, kind='CURRENT_IMMUTABLE_CLIENT_ENTRY', retained_lobby_initializer=True, original_native_handoff_suffix_identical=True))
    text, original = (lf(source[PROFILE]).decode(), lf(parent[PROFILE]).decode())
    need(not any((block in original for block in LEGACY_BLOCKS)), 'published0804_parent_must_already_remove_preview_dependencies')
    need(original == text, 'admission_logic_changed_outside_reviewed_preview_removal')
    code = re.sub('--[^\\n]*', '', text)
    need(not re.search('offline|preview|onboarding', code, re.I), 'preview_or_offline_admission_bypass_present')
    need('MAX_ALLOWED_ACCOUNTS = 5' in code, 'five_account_limit_must_remain')
    need(lf(source[ACCESS]) == lf(parent[ACCESS]), 'approved_account_roster_changed')
    ids = re.findall(b'"([0-9]{17})"', source[ACCESS])
    need(len(ids) == len(set(ids)) == 5 and re.search(b'enabled\\s*=\\s*true', source[ACCESS]) is not None, 'exact_enabled_five_account_roster_required')
    targets[PROFILE] = source[PROFILE]
    reviews.append(dict(path=PROFILE, kind='CURRENT_SOURCE_WITH_PREVIEW_DEPENDENCY_REMOVED', approved_account_count=5, original_non_preview_logic_identical=True, removed_dependency='scripts/vscripts/debug/offline_onboarding_test.lua'))
    for row in reviews:
        path = row['path']
        row.update(source_sha256=sha(source[path]), parent_sha256=sha(parent[path]), production_sha256=sha(targets[path]), production_bytes=len(targets[path]))
    return (targets, reviews)

def git_blob(repository, revision, path, counts):
    raw = pending._git(repository, 'show', revision + ':' + path, counts=counts)
    need(len(raw) <= 32 * 1024 * 1024, 'bounded_immutable_production_blob_required:' + path)
    return raw

def tool_bindings(operator_revision, counts):
    records = []
    support = pending._git(ROOT, 'ls-tree', '-r', '--name-only', operator_revision, 'tools/lua_protection', counts=counts).decode().splitlines()
    paths = sorted(set(TOOL_INPUTS) | {path for path in support if path.endswith('.lua')})
    need(set(paths) == set(LOADED_OPERATOR_LF_HASHES), 'loaded_operator_helper_scope_changed_after_import')
    for path in paths:
        raw = git_blob(ROOT, operator_revision, path, counts)
        actual = (ROOT / path).read_bytes()
        need(lf(actual) == lf(raw), 'executed_operator_does_not_match_commit:' + path)
        need(sha(lf(raw)) == LOADED_OPERATOR_LF_HASHES[path], 'loaded_operator_does_not_match_commit:' + path)
        records.append(dict(path=path, revision=operator_revision, git_sha256=sha(raw), executed_lf_sha256=LOADED_OPERATOR_LF_HASHES[path], normalization='CRLF_TO_LF'))
    return records

def context(game_revision, content_revision, operator_revision):
    counts = Counter()
    for repo, revision in ((ROOT, game_revision), (pending.CONTENT, content_revision), (ROOT, operator_revision)):
        immutable(revision)
        need(pending._git(repo, 'rev-parse', '--verify', revision + '^{commit}', counts=counts).decode().strip() == revision, 'source_must_be_exact_git_commit')
    tools = tool_bindings(operator_revision, counts)
    baseline = pending._read_json(pending.BASELINE, pending.BASELINE_SHA256)
    manifest = pending._read_json(pending.PARENT_MANIFEST, baseline['parent_manifest_sha256'])
    need(manifest['content_sha256'] == baseline['parent_content_sha256'], 'authenticated0104_content_changed')
    rows = {row['path']: row for row in manifest['files']}
    source, parent = ({}, {})
    for path in (*OVERRIDES, ACCESS):
        source[path] = git_blob(ROOT, game_revision, path, counts)
        need(path in rows, 'authenticated_parent_resource_missing:' + path)
        raw = (pending.PARENT_MANIFEST.parent / path).read_bytes()
        need(len(raw) == rows[path]['bytes'] and sha(raw) == rows[path]['sha256'], 'authenticated_parent_bytes_changed:' + path)
        parent[path] = raw
    targets, reviews = transform_overrides(source, parent)
    policy = json.loads(git_blob(ROOT, operator_revision, 'tools/lua_protection_policy.json', counts))
    protection.check_policy(policy)
    tree = pending.git_tree(ROOT, counts, game_revision)
    paths = sorted((path for path in tree if path.startswith('scripts/vscripts/') and path.endswith('.lua') and (not any((part.startswith('.') or part in ('tests', '__pycache__', 'node_modules') for part in path.split('/'))))))
    selected = protection.selected_files(paths, policy)
    need(all((path not in paths for path in ('scripts/vscripts/debug/offline_onboarding_test.lua',))), 'deleted_preview_dependency_still_in_runtime_source')
    return dict(game=game_revision, content=content_revision, operator=operator_revision, counts=counts, source=source, parent=parent, targets=targets, reviews=reviews, policy=policy, selected=selected, paths=paths, tools=tools, baseline=baseline, tree=tree)

def lua_quote(value):
    return json.dumps(value, ensure_ascii=False)

def run_probes(ctx, destination, lua):
    fixture = git_blob(ROOT, ctx['operator'], 'tools/admission_five_20261101/test_projected_policy.lua', ctx['counts'])
    path = destination / 'five_account_probe.lua'
    path.write_bytes(fixture)
    result = subprocess.run([str(lua), str(path), str(destination / 'source_export' / PROFILE)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    need(result.returncode == 0 and b'PROJECTED_PRODUCTION_FIVE_ADMISSION_PASS' in result.stdout, 'immutable_five_account_behavior_probe_failed')
    source, parent = (ctx['source'], ctx['parent'])
    script = 'local inputs=' + '{' + ','.join(('[' + lua_quote(path) + ']={source=' + lua_quote(source[path].decode()) + ',parent=' + lua_quote(parent[path].decode()) + '}' for path in CONSTANTS)) + '}\n' + "\nlocal function load_constant(text)local fn=assert(loadstring(text));setfenv(fn,{});local value=fn();assert(type(value)=='table');return value end\nfor path,pair in pairs(inputs)do\n local a,b=load_constant(pair.source),load_constant(pair.parent)\n local allowed=path:find('release_profile',1,true) and {channel=true,native_cloud_roster_required=true} or {enabled=true}\n for key,value in pairs(a)do assert(allowed[key] or b[key]==value,'unreviewed new config key')end\n for key,value in pairs(b)do assert(allowed[key] or a[key]==value,'unreviewed lost config key')end\n if allowed.channel then assert(a.channel=='development' and b.channel=='production' and b.native_cloud_roster_required==true)\n else assert(a.enabled==false and b.enabled==true)end\nend\n"
    script += '\nlocal client=' + lua_quote(source['scripts/vscripts/addon_game_mode_client.lua'].decode()) + '\n' + "\nfor _,map in ipairs({'ws4_lobby','maps/ws4_lobby.vpk','ws4_entry','template_map','unknown'})do\n local calls,requires=0,0\n local env={type=type,pcall=pcall,GetMapName=function()return map end,\n  require=function(name)assert(name=='systems/hosted_lobby_client');requires=requires+1;return {init=function()calls=calls+1 end}end}\n local fn=assert(loadstring(client));setfenv(fn,env);local value=fn()\n if map=='ws4_lobby' or map=='maps/ws4_lobby.vpk' then\n  assert(requires==1 and calls==1 and env.Activate==env.ActivateClient);env.Activate();assert(calls==2)\n else assert(requires==0 and calls==0 and type(value)=='table' and env.Activate==nil)end\nend\nio.write('FOUR_CONFIG_POLICY_ONLY_PASS')\n"
    check = subprocess.run([str(lua), '-'], input=script.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    need(check.returncode == 0 and check.stdout == b'FOUR_CONFIG_POLICY_ONLY_PASS', 'config_contains_unreviewed_runtime_change')
    return dict(five_account_engine_io_simulation=True, five_account_probe_stdout_sha256=sha(result.stdout), four_configs_constant_policy_only=True, deleted_preview_dependency_absent=True, hosted_lobby_and_original_entry_engine_io_simulation=True, actual_steam_login=False, native_acceptance=False, http_calls=0, sdk_calls=0)

def export_lua(ctx, destination):
    """Stream one immutable Git archive; no map/VPK or installed-tree writes."""
    source = destination / 'source_export'
    source.mkdir()
    allowed = set(ctx['paths'])
    need(len(allowed) <= 8192, 'immutable_lua_export_count_budget_exceeded')
    command = ['git', '--no-replace-objects', '-c', 'safe.directory=' + ROOT.as_posix(), '-C', str(ROOT), 'archive', '--format=tar', ctx['game'], 'scripts/vscripts']
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    records, total = ({}, 0)
    try:
        with tarfile.open(fileobj=process.stdout, mode='r|') as archive:
            for entry in archive:
                if entry.name not in allowed:
                    continue
                need(entry.isfile() and (not entry.issym()) and (not entry.islnk()), 'unsafe_immutable_lua_archive_entry')
                need(0 <= entry.size <= 32 * 1024 * 1024, 'lua_export_blob_budget_exceeded')
                total += entry.size
                need(total <= 256 * 1024 * 1024, 'lua_export_total_budget_exceeded')
                raw = archive.extractfile(entry).read()
                need(len(raw) == entry.size and (not raw.startswith(b'version https://git-lfs.github.com/spec/v1')), 'plain_immutable_lua_blob_required')
                oid = ctx['tree'][entry.name]['oid']

                def blob_oid(value):
                    return hashlib.new('sha1' if len(oid) == 40 else 'sha256', b'blob ' + str(len(value)).encode() + b'\x00' + value).hexdigest()
                actual_oid = blob_oid(raw)
                normalization = 'EXACT_GIT_BLOB'
                if actual_oid != oid:
                    restored = raw.replace(b'\r\n', b'\n')
                    need(blob_oid(restored) == oid, 'archived_lua_differs_from_immutable_git_blob:' + entry.name)
                    raw, actual_oid = (restored, oid)
                    normalization = 'ARCHIVE_CRLF_REVERSED_WITH_EXACT_GIT_OID_PROOF'
                need(actual_oid == oid, 'archived_lua_differs_from_immutable_git_blob:' + entry.name)
                target = source / entry.name
                need(target.resolve().is_relative_to(source.resolve()), 'lua_export_path_escaped')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
                records[entry.name] = dict(path=entry.name, source_revision=ctx['game'], git_oid=oid, source_sha256=sha(raw), source_bytes=len(raw), archive_normalization=normalization)
        need(process.wait(timeout=30) == 0 and set(records) == allowed, 'immutable_lua_archive_incomplete')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        process.stdout.close()
        process.stderr.close()
    for path, raw in ctx['targets'].items():
        target = source / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    return (source, records)

def prepare(ctx, destination, lua, prometheus, build_protected=False):
    need(destination.is_absolute(), 'new_absolute_external_destination_required')
    destination = destination.resolve()
    need(destination.is_absolute() and (not destination.exists()), 'new_absolute_external_destination_required')
    need(not destination.is_relative_to(ROOT.parents[2]), 'production_export_must_stay_outside_game_content_mounts')
    need(destination.parent.is_dir(), 'explicit_external_parent_must_exist')
    dependency = protection.dependency_identity(prometheus, ctx['policy'])
    lua = lua.resolve(strict=True)
    luac = (lua.parent / 'luac5.1.exe').resolve(strict=True)
    binaries = {'lua': dict(path=str(lua), sha256=sha(lua.read_bytes())), 'luac': dict(path=str(luac), sha256=sha(luac.read_bytes()))}
    destination.mkdir()
    source, inputs = export_lua(ctx, destination)
    probes = run_probes(ctx, destination, lua)
    tool_bindings(ctx['operator'], ctx['counts'])
    report = dict(kind='COMPLETE0302_PRODUCTION_LUA_PREPARATION_NOT_RELEASE_AUTHORITY', schema=1, source_revisions=dict(game=ctx['game'], content=ctx['content'], operator=ctx['operator']), baseline_manifest_sha256=ctx['baseline']['parent_manifest_sha256'], plain_inputs=list(inputs.values()), production_overrides=ctx['reviews'], executed_operator_inputs=ctx['tools'], behavior_probes=probes, pinned_prometheus=dependency, lua_binaries=binaries, protection_selected=ctx['selected'], protection_verified=False, protection_input_scope='LUA_ONLY_PROJECTION', complete_candidate_materialization_verified=False, full_runtime_recipe_ledger_authority_ready=False, signing_ready=False, publication_ready=False, sdk_calls=0, git_mutations=0, installed_tree_writes=0)
    if build_protected:
        policy = destination / 'fixed_protection_policy.json'
        policy.write_bytes(canonical(ctx['policy']))
        command = [sys.executable, '-X', 'utf8', '-B', str(ROOT / 'tools/protect_runtime_lua.py'), '--source', str(source), '--output', str(destination / 'protected_lua'), '--prometheus-root', str(prometheus), '--policy', str(policy), '--lua', str(lua), '--luac', str(luac), '--data-string-obfuscation', '--lua-only-input']
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1800, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        (destination / 'protection.stdout.txt').write_bytes(result.stdout)
        (destination / 'protection.stderr.txt').write_bytes(result.stderr)
        need(result.returncode == 0, 'pinned_protection_or_all_value_rng_verification_failed')
        tool_bindings(ctx['operator'], ctx['counts'])
        proof_path = destination / 'protected_lua/_lua_protection_report.json'
        proof_raw = proof_path.read_bytes()
        proof = json.loads(proof_raw)
        semantic = proof.get('semantic_verification', {})
        need(proof.get('status') == 'PASS_REQUIRES_NATIVE_SMOKE' and proof.get('input_scope') == 'LUA_ONLY_PROJECTION' and (proof.get('critical_runtime_assets_checked') is False) and (proof.get('complete_candidate_materialization_verified') is False) and (proof.get('generated_string_obfuscation', {}).get('enabled') is True) and (semantic.get('status') == 'PASS') and (semantic.get('all_generated_values_exact') is True) and (semantic.get('gameplay_rng_untouched_while_loading') is True), 'all_values_or_rng_protection_proof_incomplete')
        operator_hashes = {row['path']: row['executed_lf_sha256'] for row in ctx['tools']}
        child_tools = proof.get('executed_tool_inputs')
        need(isinstance(child_tools, list) and len(child_tools) == len({row.get('path') for row in child_tools}) and ({row['path'] for row in child_tools} == set(protection.LOADED_TOOL_LF_HASHES)) and all((row.get('loaded_lf_sha256') == operator_hashes.get(row.get('path')) for row in child_tools)), 'protected_child_loaded_operator_binding_incomplete')
        expected = {row['path']: row for row in ctx['selected']}
        actual = {row['path']: row for row in proof.get('files', [])}
        need(set(actual) == set(expected) and len(actual) == len(proof['files']) and (semantic.get('summary', {}).get('files') == len(expected)), 'protection_selected_scope_incomplete')
        bindings = []
        for path, selected in expected.items():
            row = actual[path]
            output = destination / 'protected_lua' / path
            need(row['kind'] == selected['kind'] and row['before']['sha256'] == inputs[path]['source_sha256'] and (row['after']['sha256'] != row['before']['sha256']) and (sha(output.read_bytes()) == row['after']['sha256']), 'protected_binding_mismatch:' + path)
            bindings.append(dict(path=path, kind=selected['kind'], source_revision=ctx['game'], source_sha256=row['before']['sha256'], production_sha256=row['after']['sha256'], production_bytes=row['after']['bytes'], exact_values_and_rng_verified=True))
        report['protection_verified'] = True
        report['protection_stdout_sha256'] = sha(result.stdout)
        report['protection_report_sha256'] = sha(proof_raw)
        report['protected_bindings'] = bindings
    need(sha(lua.read_bytes()) == binaries['lua']['sha256'] and sha(luac.read_bytes()) == binaries['luac']['sha256'], 'lua_binary_changed_during_preparation')
    (destination / 'production_preparation.json').write_bytes(canonical(report))
    return report

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-revision', 'content-source-revision', 'operator-revision'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--output-directory', type=Path)
    parser.add_argument('--lua', type=Path, default=Path('C:/Program Files/lua/bin/lua5.1.exe'))
    parser.add_argument('--prometheus-root', type=Path, default=Path('D:/survival_安全工具/prometheus'))
    parser.add_argument('--build-protected', action='store_true')
    args = parser.parse_args()
    ctx = context(args.source_revision, args.content_source_revision, args.operator_revision)
    if args.output_directory:
        value = prepare(ctx, args.output_directory, args.lua, args.prometheus_root, args.build_protected)
        print(json.dumps(dict(kind=value['kind'], overrides=len(value['production_overrides']), protected=len(value['protection_selected']), protection_verified=value['protection_verified'], publication_ready=False)))
    else:
        need(not args.build_protected, 'protection_requires_explicit_external_preparation_directory')
        print(json.dumps(dict(kind='READ_ONLY_IMMUTABLE_PRODUCTION_REVIEW', source_revisions=dict(game=ctx['game'], content=ctx['content'], operator=ctx['operator']), overrides=ctx['reviews'], protected=len(ctx['selected']), operator_inputs=ctx['tools'], publication_ready=False), ensure_ascii=False, indent=2))
if __name__ == '__main__':
    main()
