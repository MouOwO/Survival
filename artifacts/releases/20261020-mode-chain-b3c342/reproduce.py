"""Offline integrity/reproduction for this immutable mode-chain release.

Uses only tracked files and Python's standard library. No Git, database,
network, service operations, credentials or running-hash changes.
"""
from __future__ import annotations
import argparse
import ast
import copy
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import tarfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
def need(value,code):
    if not value:raise RuntimeError(code)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def once(source,old,new):
    need(source.count(old)==1,'reproduction_anchor_changed')
    return source.replace(old,new,1)
def safe_name(name):
    path=PurePosixPath(name)
    need(bool(name) and bool(path.parts) and not path.is_absolute() and '..' not in path.parts
         and '\\' not in name and ':' not in name and '\0' not in name and path.as_posix()==name,'unsafe_member')
    return path

def verify():
    proof=json.loads((HERE/'release_proof.json').read_bytes())
    for name,expected in proof['tracked_inputs'].items():
        need(sha((HERE/safe_name(name)).read_bytes())==expected,'tracked_input_changed:'+name)
    raw=(HERE/'mode_chain_release.tar.gz').read_bytes()
    need(sha(raw)==proof['sealed_sha256'],'sealed_tar_changed')
    files={}
    with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as tar:
        members=tar.getmembers();need(sum(x.size for x in members)<128*1024*1024,'expanded_payload_too_large')
        for member in members:
            safe_name(member.name)
            need(member.isfile() and member.name not in files,'unsafe_tar_member')
            files[member.name]=tar.extractfile(member).read()
    review=json.loads(files['package_review.json'])
    need(set(files)==set(review['files'])|{'package_review.json'},'sealed_scope_changed')
    need(all(sha(files[n])==v for n,v in review['files'].items()),'sealed_member_changed')
    need(review['bundle']==proof['bundle'] and review['parent']==proof['parent'],'sealed_identity_changed')
    report=json.loads(files['verification/mode_only.json'])
    need(report['status']=='PASS' and report['cluster_stopped'] is True,'verification_evidence_changed')
    parent=json.loads(files['overlay/addon/server/bundles/'+proof['parent']+'/bundle.json'])
    candidate=json.loads(files['overlay/addon/server/bundles/'+proof['bundle']+'/bundle.json'])
    need(sha(canonical(parent))==proof['parent'],'parent_bundle_changed')
    data=copy.deepcopy(parent)
    data['sources']['systems/archive_welfare_rewards.lua']=once(parent['sources']['systems/archive_welfare_rewards.lua'],
        '    for _, count in pairs((archive or {}).clear_counts or {}) do total = total + nonnegative_integer(count) end',
        '    for _, key in ipairs({"clear_counts", "rich_clear_counts", "cold_clear_counts", "scourge_clear_counts"}) do\n        for _, count in pairs((archive or {})[key] or {}) do total = total + nonnegative_integer(count) end\n    end')
    data['sources']['config/recorded_mode_balance.lua']=(HERE/'inputs/recorded_mode_balance.lua').read_text('utf-8')
    tree=ast.parse(files['overlay/backend/archive_backend/service.py'].decode('utf-8-sig'))
    fields=next(n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FIELDS' for t in n.targets))
    commands={ast.literal_eval(k) for k in fields.keys}|{'lottery_snapshot'}
    data['compatible_config_hashes'][proof['parent']]={'commands':sorted(commands),
        'upgrade_commands':sorted({'clear','standard_clear','rich_clear','cold_clear','scourge_clear','mode_clear','welfare_reconcile'})}
    need(data==candidate and sha(canonical(data))==proof['bundle'],'bundle_reproduction_failed')
    need(candidate['configs']==parent['configs'] and candidate['csv_hashes']==parent['csv_hashes'],'live_rules_changed')
    need(all(candidate['compatible_config_hashes'][k]==v for k,v in parent['compatible_config_hashes'].items()),'historical_compatibility_changed')
    baseline=json.loads((HERE/'inputs/live_release_manifest.json').read_bytes())
    need(sha((HERE/'inputs/live_release_manifest.json').read_bytes())==proof['baseline_manifest_sha256'],'live_manifest_changed')
    match=(HERE/'inputs/match_modes.before.py').read_text('utf-8')
    match=once(match,'''        # Preserve the existing rich entry rule. The shipped mode selector has
        # no predecessor unlock chain for cold/scourge; adding durable identity
        # must not introduce a new gate (cold N10 combat is not available yet).
        if mode == "rich" and not progression(raw)["standard_clear_counts"].get("n10"):''',
        '        if not progression(raw)[PARENT_MODES[mode] + "_clear_counts"].get("n10"):')
    need(match.encode()==files['overlay/backend/archive_backend/match_modes.py'],'mode_gate_reproduction_failed')
    unique=(HERE/'inputs/unique_points.before.py').read_text('utf-8')
    old_pairs={tuple(re.findall(r'[0-9a-f]{64}',m)) for m in re.findall(r"\('[0-9a-f]{64}', '[0-9a-f]{64}'\)",unique)}
    added={(proof['bundle'],proof['parent'])}|{(proof['bundle'],old) for current,old in old_pairs if current==proof['parent']}
    anchor='IDENTICAL_LOTTERY_UPDATES = frozenset({\n'
    unique=once(unique,anchor,anchor+''.join('    '+repr(pair)+',\n' for pair in sorted(added)))
    need(unique.encode()==files['overlay/backend/archive_backend/unique_points.py'],'lottery_pairs_reproduction_failed')
    for name in ('match_modes','unique_points'):
        before=(HERE/('inputs/'+name+'.before.py')).read_bytes()
        need(sha(before)==baseline['files']['backend/archive_backend/'+name+'.py'],'baseline_backend_changed')
    changed_backend={name.removeprefix('overlay/') for name,body in files.items()
        if name.startswith('overlay/backend/') and sha(body)!=baseline['files'].get(name.removeprefix('overlay/'))}
    need(changed_backend==set(proof['changed_backend_files']),'backend_scope_changed')
    migration=files['overlay/database/202610200004_mode_unlock_chain.sql']
    need(sha(migration)==proof['migration004_sha256'],'migration004_changed')
    source004=ROOT/'server/aliyun/database/target/202610200004_mode_unlock_chain.sql'
    if source004.exists():need(source004.read_bytes().replace(b'\r\n',b'\n')==migration,'tracked004_differs_from_release')
    guard=files['database/archive_sync_registration_REVIEW_ONLY.sql']
    need(sha(guard)==proof['new_sync_sha256'],'registration_guard_changed')
    text=guard.decode('utf-8');a=text.index(' -- Reviewed mode-chain004 candidate:');b=text.index(' -- Reviewed daily unique points:',a)
    need(sha((text[:a]+text[b:]).encode())==proof['old_sync_sha256'],'live_sync_logic_changed')
    for signature,entry in report['registration']['post_functions'].items():
        need(sha(entry['definition'].encode())==entry['sha256']==proof['post_function_hashes'][signature],'function_proof_changed')
    need(not any(any(marker in name.lower() for marker in ('.pgpass','.pem','.env','.dump','pg_service.conf')) for name in files),'private_member_refused')
    return proof,files

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,help='Optionally extract the exact incremental overlay under this checkout/output; never overwrite differing files')
    args=parser.parse_args();proof,files=verify()
    extracted=0
    if args.output is not None:
        output=(ROOT/args.output).resolve()
        need(output.is_relative_to(ROOT/'output'),'extraction_must_stay_under_checkout_output')
        allowed=set(proof['changed_backend_files'])|{'addon/server/bundles/current.json','addon/scripts/vscripts/config/generated/archive_http_bundle.lua','database/202610200004_mode_unlock_chain.sql'}
        prefix='addon/server/bundles/'+proof['bundle']+'/'
        selected={name.removeprefix('overlay/'):raw for name,raw in files.items()
            if name.startswith('overlay/') and (name.removeprefix('overlay/') in allowed or name.removeprefix('overlay/').startswith(prefix))}
        selected['database/archive_sync_registration_REVIEW_ONLY.sql']=files['database/archive_sync_registration_REVIEW_ONLY.sql']
        for name,raw in selected.items():
            target=output/safe_name(name);need(not target.is_symlink(),'output_symlink_refused')
            for ancestor in target.parents:
                if ancestor==ROOT:break
                need(not ancestor.is_symlink(),'output_parent_symlink_refused')
            target.parent.mkdir(parents=True,exist_ok=True)
            need(not target.exists() or target.read_bytes()==raw,'existing_output_differs')
            target.write_bytes(raw);extracted+=1
    print(json.dumps({'status':'FROZEN_MODE_RELEASE_REPRODUCED','bundle':proof['bundle'],
        'sealed_sha256':proof['sealed_sha256'],'new_lottery_pairs_preserved':True,'extracted_files':extracted,
        'network_calls':0,'database_connections':0,'running_hash_changes':0}))
if __name__=='__main__':main()
