"""v06 evidence adapter: current data-volume users, authenticated retained index.

Only a private, SHA-pinned v05 function's two index-open predicates are replaced.
No raw receipt is mutated, and no SDK/action occurs on import or by default.
"""
from pathlib import Path
from contextvars import ContextVar
import hashlib
import importlib.util
import inspect
import json
import re
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
PARENT=HERE/'publish.py'
PARENT_SHA='089f4867e429eac63ee109b3eb56026ca195bfe7cb749f7976ea13ba16e23060'
POLICY='DATA_VOLUMES_USED_INDEX_AUTHENTICATED_NOT_OPEN'
BANE='monster_boss_rebirth_05_lucid_torment'
_active=ContextVar('v06_readonly_native_volume_proof',default=None)


def require_parent():
    if hashlib.sha256(PARENT.read_bytes()).hexdigest()!=PARENT_SHA:raise ValueError('Frozen1106 publisher changed')


require_parent()
_spec=importlib.util.spec_from_file_location('v06_private_frozen_1106_publisher',PARENT)
p=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(p)
b,c,ops,legacy,sdk,need=p.b,p.c,p.ops,p.legacy,p.sdk,p.need
subprocess=p.subprocess
KIND,STATUS,SCOPE,CASES,REQUIRED_REVIEW=p.KIND,p.STATUS,p.SCOPE,p.CASES,p.REQUIRED_REVIEW
_parent_preflight=p.preflight
_parent_bind=p.bind_review
_parent_native=p.rehearsal_acceptance


def scope_map(package):
    # Full c.validated_package(full=True) has already authenticated all five
    # VPKs. Read/hash the small directory index once to bind this lookup too.
    path=b.OUTPUT/(b.ITEM+'.vpk')
    expected=package['package_files'][0]
    need(expected['name']==b.ITEM+'.vpk' and path.stat().st_size==expected['bytes']
        and b.pack.runtime.digest(path)==expected['sha256'],'Signed index hash/size changed')
    entries=b.inc.read_entries(path);index={row['path']:row for row in entries}
    need(len(index)==len(entries),'Duplicate signed-index paths')
    need(package['changed_runtime_paths']==sorted(b.PAYLOADS) and len(b.PAYLOADS)==14,'Exact fourteen-path payload scope required')
    result={}
    for name in b.PAYLOADS:
        row=index.get(name);pin=package['target_pins'][name]
        need(row is not None and row.get('archive') in range(4) and row.get('bytes')==pin['bytes'],
            'Every tested payload must have an authenticated data-archive mapping')
        result[name]={'archive':row['archive'],'archive_name':b.ITEM+'_%03d.vpk'%row['archive'],
            'offset':row['offset'],'bytes':row['bytes'],'payload_sha256':pin['sha256']}
    need({row['archive'] for row in result.values()}=={0,3},'Reviewed fourteen payloads must occupy archives0 and3')
    return result


def native_data_volume_use(value,process,package):
    context=_active.get();need(context is not None,'Native-volume proof requires an explicit preflight context')
    if context['map'] is None:context['map']=scope_map(package)
    names=list(ops.p.NAMES);rows=value.get('file_use',[])
    need(isinstance(rows,list) and len(rows)==5 and [row.get('name') for row in rows]==names,
        'Exact five RM resource rows required; missing/unknown/duplicate row')
    need(type(process.get('native_created_filetime')) is int
        and process['native_created_filetime']//10==ops.p.utc_ticks(process['created_utc'])//10,
        'Same owned native process FILETIME required')
    if 'native_created_filetime' in value.get('process',{}):
        need(value['process']['native_created_filetime']==process['native_created_filetime'],'Inspection native process FILETIME changed')
    need(p.timestamp(process['created_utc'])>=p.timestamp(process['started_utc']),
        'Fresh owned process must be created after its recorded launch start')
    held=process['held_files']
    need(value.get('held_files')==held and len(held)==5
        and len({(row['volume_serial'],row['file_index']) for row in held})==5
        and [row['name'] for row in held]==names
        and all(row['bytes']==expected['bytes'] for row,expected in zip(held,package['package_files'])),
        'All five locked FileIDs and signed sizes must remain unchanged')
    need(all(type(row.get('owned_keeper_uses_file')) is bool and row['owned_keeper_uses_file'] is True
        and type(row.get('owned_dota_uses_file')) is bool for row in rows),
        'Keeper must own all five resources with explicit unchanged observations')
    need(all(row['owned_dota_uses_file'] is True for row in rows[1:]),
        'All four data volumes must be used by the same owned Dota generation')
    need(value.get('index_owned_dota_use_observed') is rows[0]['owned_dota_uses_file'],
        'Raw index observation must remain unchanged and consistent')
    observed_all=all(row['owned_dota_uses_file'] and row['owned_keeper_uses_file'] for row in rows)
    need(value.get('all_five_open_verified') is observed_all
        and value.get('all_five_owned_dota_file_uses_observed') is observed_all,
        'Raw all-five-open observations must not be rewritten')
    need(value.get('external_signed_manifest_binding') is True
        and value.get('external_signed_resources_verified')==6918
        and value.get('external_protected_modules_verified')==184,
        'Full signed inventory authentication binding required')
    used={row['name'] for row in rows[1:]}
    need(all(row['archive_name'] in used for row in context['map'].values()),'A tested payload archive is not an owned native resource')
    # The frozen inspection's file_use_result compares RM PID AND the complete
    # native100ns creation time from process.json. It did not export raw RM
    # process lists. Do not invent them or claim that such raw lists were saved.
    context['observations'].append(dict(observed_utc=value['observed_utc'],
        pid=process['pid'],native_created_filetime=process['native_created_filetime'],
        exact_generation_source='FROZEN_INSPECTION_FILE_USE_RESULT_PID_AND_NATIVE_FILETIME',
        raw_rm_pid_lists_saved=False,data_volumes=[row['name'] for row in rows[1:]],
        keeper_all_five=True,index_owned_dota_use_observed=rows[0]['owned_dota_uses_file'],
        all_five_open_verified=value['all_five_open_verified'],held_files=held))
    return True


def unique_log_fingerprint(review,origin,reader):
    path=reader.file(review['rehearsal']['engine_log_final'],origin)
    text=path.read_text(encoding='utf8',errors='replace')
    anchors=[]
    for line in text.splitlines():
        prefix='[SURVIVAL_PORTRAIT] QUERY_ANCHOR '
        if prefix not in line:continue
        try:row=json.loads(line.split(prefix,1)[1])
        except ValueError:continue
        if (row.get('binding')=='shared_main' and row.get('sharedMainReason')=='native_portrait_identity_matches'
            and row.get('mainRejection') is None and type(row.get('entity')) is int
            and row['entity']==row.get('expectedDisplayUnit')==row.get('nativePortraitUnit')):anchors.append(row['entity'])
    need(bool(anchors),'Unique current shared_main native identity fingerprint required')
    ready=re.search(r'\[SURVIVAL_MONSTER_PORTRAIT\] READY asset=\s*'+re.escape(BANE)
        +r'\s+map=\s*[A-Za-z0-9_./-]+\s+ms=\s*\d+\s+components=\s*4\b',text)
    selected=re.search(r'\[SURVIVAL_PORTRAIT\] SCENE_SET[^\r\n]*\basset=\s*'+re.escape(BANE)+r'\b',text)
    need(ready is not None and selected is not None and re.search(
        r'\[SURVIVAL_PORTRAIT\] SHOW mode=\s*monster_scene\b',text[selected.end():]) is not None,
        'Unique Bane four-component READY, SCENE_SET and subsequent SHOW required')
    return dict(shared_main_entities=sorted(set(anchors)),bane_ready_components=4,
        bane_scene_set=True,subsequent_monster_scene_show=True,raw_log_exported=False)


# Compile only a SHA-pinned local function, never user text. This preserves all
# original chronology, signed-source, held-file, exit, restore and fatal-log
# guards. Exactly two index-open predicates and their explanatory text differ.
_original_source=inspect.getsource(_parent_native)
_old_a="and value.get('held_files')==process['held_files'] and value.get('index_owned_dota_use_observed') is True"
_new_a="and value.get('held_files')==process['held_files']"
_old_b="and any(row.get('name')==b.ITEM+'.vpk' and row.get('owned_dota_uses_file') is True\n                 and row.get('owned_keeper_uses_file') is True for row in value.get('file_use',[]))"
_new_b="and native_data_volume_use(value,process,package)"
for fragment in (_old_a,_old_b):need(_original_source.count(fragment)==1,'Frozen index predicate shape changed')
_adapted_source=_original_source.replace(_old_a,_new_a).replace(_old_b,_new_b).replace(
    'Owned Dota/keeper candidate index observation required','Authenticated signed index and complete native data-volume use required')
p.native_data_volume_use=native_data_volume_use
exec(compile(_adapted_source,str(Path(__file__))+'[fixed_parent_index_predicates]','exec'),p.__dict__)
_adapted_native=p.rehearsal_acceptance


def rehearsal_acceptance(review,origin,package,package_sha,reader):
    result=_adapted_native(review,origin,package,package_sha,reader)
    context=_active.get();need(context is not None and len(context['observations'])>=2,'Before/after data-volume observations required')
    context['fingerprint']=unique_log_fingerprint(review,origin,reader)
    return result


def bind_review(review,package,package_sha):
    _parent_bind(review,package,package_sha)
    need(review.get('native_file_use_policy')==POLICY,'Root must explicitly review the corrected native-volume evidence policy')


def preflight(package_sha,review_path,review_sha):
    require_parent();context={'map':None,'observations':[],'fingerprint':None};token=_active.set(context)
    try:
        result=_parent_preflight(package_sha,review_path,review_sha)
        proof=dict(status=POLICY,parent_publisher_sha256=PARENT_SHA,
            adapter_sha256=b.pack.runtime.digest(Path(__file__)),
            mapping=context['map'],observations=context['observations'],fingerprint=context['fingerprint'],
            authenticated_signed_index_preserved=True,index_open_not_required=True,
            raw_receipts_modified=False,all_gameplay_paths_verified=False)
        result['native_volume_evidence']=proof
        result['summary'].update(native_volume_evidence_status=POLICY,
            index_owned_dota_original_observations=[row['index_owned_dota_use_observed'] for row in context['observations']],
            all_five_open_original_observations=[row['all_five_open_verified'] for row in context['observations']],
            tested_runtime_path_count=len(context['map']),required_native_data_volumes=4,
            corrected_native_policy_reviewed=True,raw_receipts_modified=False)
        return result
    finally:_active.reset(token)


p.rehearsal_acceptance=rehearsal_acceptance;p.bind_review=bind_review;p.preflight=preflight
apply=p.apply

def main(argv=None):
    supplied=sys.argv[1:] if argv is None else argv
    if not supplied:
        print(json.dumps(dict(status='STATIC_V06_NATIVE_DATA_VOLUME_PLAN_NO_EFFECTS',policy=POLICY,
            parent_sha256=PARENT_SHA,files_written=0,sdk_initialized=False,ready_for_upload=False)))
        return 0
    return p.main(supplied)


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        print(json.dumps(dict(status='REFUSED_V06_PRESERVE_RAW_EVIDENCE_AND_JOURNAL',
            error_type=type(error).__name__,reason=str(error) if isinstance(error,ValueError) else 'External validation failed',
            updates_submitted=0,raw_receipts_modified=False)),flush=True)
        raise SystemExit(2)
