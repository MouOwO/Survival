"""Build the smallest mode-chain update on the exact already-live caps release.

No Git, SSH, account updates, compilation, or running hash changes. All configs,
CSV digests, quota reducers and HTTP/catalog/commerce behavior stay live bytes.
"""
from __future__ import annotations
from datetime import datetime,timezone
import hashlib,json,re,copy
from pathlib import Path
import sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'output/mode_spawn_progression_20261020/live_caps/baseline'
PARENT='ecf55dd6ba24d0b391a1640f7e25c06c50d79ec1eb37f0bfcdb86c28afde22f7'
MANIFEST='30b3400ce2389c150290810097919e648beeae79dc96cbd4bd1ea27bb6310668'
SQL_HASH='da1b05ef4398929735e1b08f093bb11f1fef6bbf92a43cd772b2c2d5ccac4ec5'
def sha(x):return hashlib.sha256(x).hexdigest()
def canonical(x):return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def once(s,a,b):
    assert s.count(a)==1,'baseline_anchor_changed:'+a[:60]
    return s.replace(a,b,1)
def write(path,raw):
    path.parent.mkdir(parents=True,exist_ok=True)
    assert not path.exists() or path.read_bytes()==raw,'immutable_candidate_changed'
    path.write_bytes(raw)
def main():
    manifest_raw=(BASE/'release_manifest.json').read_bytes();assert sha(manifest_raw)==MANIFEST
    manifest=json.loads(manifest_raw);assert manifest['release']=='20261020-archive-caps-v1'
    for path in BASE.rglob('*'):
        if path.is_file() and path.name!='release_manifest.json':
            assert sha(path.read_bytes())==manifest['files'][path.relative_to(BASE).as_posix()],str(path)
    pointers={n:(ROOT/n).read_bytes() for n in ['server/bundles/current.json','scripts/vscripts/config/generated/archive_http_bundle.lua']}
    assert json.loads(pointers['server/bundles/current.json'])['hash']==PARENT,'running_parent_changed'
    raw=(BASE/'addon/server/bundles'/PARENT/'bundle.json').read_bytes();assert sha(raw)==PARENT
    parent=json.loads(raw);data=copy.deepcopy(parent)
    welfare=parent['sources']['systems/archive_welfare_rewards.lua']
    welfare=once(welfare,'    for _, count in pairs((archive or {}).clear_counts or {}) do total = total + nonnegative_integer(count) end',
        '    for _, key in ipairs({"clear_counts", "rich_clear_counts", "cold_clear_counts", "scourge_clear_counts"}) do\n        for _, count in pairs((archive or {})[key] or {}) do total = total + nonnegative_integer(count) end\n    end')
    data['sources']['systems/archive_welfare_rewards.lua']=welfare
    recorded=(ROOT/'scripts/vscripts/config/recorded_mode_balance.lua').read_text('utf-8-sig')
    assert 'function M.source_difficulty' in recorded and 'temporary_source_difficulty_id = "N4"' in recorded and 'temporary_source_difficulty_id = "N2"' in recorded
    data['sources']['config/recorded_mode_balance.lua']=recorded
    match=(BASE/'backend/archive_backend/match_modes.py').read_text('utf-8-sig')
    gate='''        # Preserve the existing rich entry rule. The shipped mode selector has
        # no predecessor unlock chain for cold/scourge; adding durable identity
        # must not introduce a new gate (cold N10 combat is not available yet).
        if mode == "rich" and not progression(raw)["standard_clear_counts"].get("n10"):'''
    match=once(match,gate,'        if not progression(raw)[PARENT_MODES[mode] + "_clear_counts"].get("n10"):')
    assert match==(ROOT/'server/archive_backend/match_modes.py').read_text('utf-8-sig'),'working_gate_differs_from_minimal_live_patch'
    # Accept the immediate live parent and preserve every historical rule.
    import ast
    service_ast=ast.parse((BASE/'backend/archive_backend/service.py').read_text('utf-8-sig'))
    fields=next(n.value for n in service_ast.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FIELDS' for t in n.targets))
    commands={ast.literal_eval(k) for k in fields.keys}|{'lottery_snapshot'}
    upgrades={'clear','standard_clear','rich_clear','cold_clear','scourge_clear','mode_clear','welfare_reconcile'}
    data.setdefault('compatible_config_hashes',{})[PARENT]={'commands':sorted(commands),'upgrade_commands':sorted(upgrades)}
    assert data['configs']==parent['configs'] and data['csv_hashes']==parent['csv_hashes']
    assert all(data['compatible_config_hashes'][k]==v for k,v in parent.get('compatible_config_hashes',{}).items())
    changed=sorted(k for k,v in data['sources'].items() if v!=parent['sources'].get(k))
    assert changed==['config/recorded_mode_balance.lua','systems/archive_welfare_rewards.lua']
    raw=canonical(data);version=sha(raw)
    candidate=ROOT/'output/mgate20'/(version[:8]+'_'+datetime.now(timezone.utc).strftime('%H%M%S%f'))
    backend=candidate/'backend'
    # Full frozen backend is for verification. The operator overlays only files
    # whose SHA changes; every other live file is retained from the live release.
    for source in (BASE/'backend').rglob('*.py'):
        if source.relative_to(BASE/'backend').as_posix() in {'archive_backend/match_modes.py','archive_backend/unique_points.py'}:continue
        write(backend/source.relative_to(BASE/'backend'),source.read_bytes())
    write(backend/'archive_backend/match_modes.py',match.encode())
    unique=(BASE/'backend/archive_backend/unique_points.py').read_text('utf-8-sig')
    pairs={tuple(re.findall(r'[0-9a-f]{64}',m)) for m in re.findall(r"\('[0-9a-f]{64}', '[0-9a-f]{64}'\)",unique)}
    new_pairs={(version,PARENT)}|{(version,old) for current,old in pairs if current==PARENT}
    anchor='IDENTICAL_LOTTERY_UPDATES = frozenset({\n'
    unique=once(unique,anchor,anchor+''.join('    '+repr(pair)+',\n' for pair in sorted(new_pairs)))
    write(backend/'archive_backend/unique_points.py',unique.encode())
    bundles=candidate/'addon/server/bundles'
    write(bundles/version/'bundle.json',raw)
    for n,s in data['sources'].items():write(bundles/version/n,s.encode())
    retained=sorted({PARENT,*parent.get('compatible_config_hashes',{})})
    for old in retained:
        directory=ROOT/'server/bundles'/old
        previous=(directory/'bundle.json').read_bytes();assert sha(previous)==old
        write(bundles/old/'bundle.json',previous)
        for n in json.loads(previous)['sources']:write(bundles/old/n,(directory/n).read_bytes())
    write(bundles/'current.json',canonical({'hash':version,'protocol':1}))
    write(candidate/'addon/scripts/vscripts/config/generated/archive_http_bundle.lua',('-- CANDIDATE ONLY\nreturn { protocol=1, hash="'+version+'" }\n').encode())
    sql=(ROOT/'server/aliyun/database/target/202610200004_mode_unlock_chain.sql').read_bytes();assert sha(sql)==SQL_HASH
    write(candidate/'database/202610200004_mode_unlock_chain.sql',sql)
    changed_backend=sorted(p.relative_to(candidate).as_posix() for p in backend.rglob('*.py') if sha(p.read_bytes())!=manifest['files'][p.relative_to(candidate).as_posix()])
    assert changed_backend==['backend/archive_backend/match_modes.py','backend/archive_backend/unique_points.py']
    files={p.relative_to(candidate).as_posix():sha(p.read_bytes()) for p in candidate.rglob('*') if p.is_file()}
    review={'status':'CANDIDATE_NOT_DEPLOYED','scope':'mode predecessor gates, shared win totals and approved temporary tiers; preserve live caps/catalog',
        'candidate':str(candidate.relative_to(ROOT)),'bundle':version,'parent':PARENT,'baseline_release':manifest['release'],
        'baseline_manifest_sha256':MANIFEST,'changed_configs':[],'changed_lua_sources':changed,'changed_backend_files':changed_backend,
        'retained_old_bundles':retained,'historical_compatibility_preserved':len(parent['compatible_config_hashes']),
        'unique_pairs_preserved':sorted(pairs),'unique_pairs_added':sorted(new_pairs),
        'pointer_changed':False,'remote_deployment':False,'files':files,
        'migration_scope':['202610200004_mode_unlock_chain.sql'],'applied_002_sha256':'70a8ddb268ea419431630961653d61e4d2404bc7d1772fb7012e9495d25cf817',
        'applied_003_sha256':'522891724d0d1df7e105f5da4f508a87e4cdd53c4ea21768a1022f26895ce9b2',
        'candidate_only_adjustments':['Exact three-mode predecessor gate in live match_modes login','Four independent maps count towards existing win welfare','User-approved cold N5-N10 to N4 and scourge N3-N10 to N2; selected target retained','Only equivalent new-hash lottery pairs added, all prior pairs retained'],
        'activation_requirements':['Recheck current live release/manifest/ledger/sync guard before publishing','Apply only new004; never rewrite applied002/003 or their ledger','Register exact new config with a guard preserving current daily rules','Keep all old bundle directories and unchanged backend files']}
    write(candidate/'review.json',canonical(review))
    out=ROOT/'output/mode_progression_release_20261020';(out/'gate_fix_candidate.json').write_bytes(canonical({'candidate':review['candidate'],'bundle':version}))
    assert all((ROOT/n).read_bytes()==v for n,v in pointers.items())
    print(json.dumps({'status':review['status'],'candidate':review['candidate'],'bundle':version,'changed_lua_sources':changed,'changed_backend_files':changed_backend}))
if __name__=='__main__':main()
