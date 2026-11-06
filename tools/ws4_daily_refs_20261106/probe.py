"""Candidate-only Python / real Lua wire parity; zero HTTP, RPC or database."""
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

WIRE='backend/archive_backend/http_profile_wire.py'


def need(ok,code):
    if not ok:raise RuntimeError(code)


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(),str(path),'exec'),value.__dict__)
    return value


def size(value):return len(json.dumps(value,ensure_ascii=False,separators=(',',':')).encode('utf8'))


def run(old,new,bundle_hash,decoder_source,vector_runner,lua='/usr/bin/lua'):
    old,new=Path(old),Path(new)
    parent=module('daily_probe_parent',old/WIRE)
    candidate=module('daily_probe_candidate',new/WIRE)
    sys.path.insert(0,str(new/'backend'))
    from archive_backend.bundle import Bundle
    from archive_backend.daily_limits import snapshot
    bundle=Bundle(new/'addon/server/bundles'/bundle_hash)
    need(bundle.hash==bundle_hash,'probe_bundle_changed')
    cap1={'response_capabilities':{'archive_profile_refs_v1':True}}
    cap2={'response_capabilities':{'archive_profile_refs_v1':True,'archive_profile_refs_v2':True}}
    vectors=[];sizes=[]
    for mode in ('standard','pure','rich','cold','scourge','ruins','celestial'):
        for monthly in (False,True):
            account={'schema_version':1,'account_id':'100','revision':7,
                     'entitlements':{'archive_pass':{'active':monthly}},'achievements':{},
                     'public':{},'save':{'content_inventory':{'lottery_ticket':12},
                                       'gameplay_stats':{'synthetic_'+str(i):i for i in range(60)}}}
            profile=deepcopy(account)
            profile.update(mode=mode,match_session_id='synthetic-session-001',account_profile=deepcopy(account))
            if mode=='pure':profile['save']={'content_inventory':{'lottery_ticket':1},'gameplay_stats':{'attack':0}}
            daily=snapshot(account,bundle,now=1793961863)
            profile['daily_limits']=deepcopy(daily)
            profile['progression']={'loaded':True,'daily_limits':deepcopy(daily)}
            response={'ok':True,'done':True,'profile':profile,'daily_limits':deepcopy(daily)}
            saved=deepcopy(response)
            need(candidate.pack({},response)==parent.pack({},response),'probe_legacy_full_changed')
            v1=parent.pack(cap1,response)
            need(candidate.pack(cap1,response)==v1,'probe_legacy_v1_changed')
            packed=candidate.pack(cap2,response)
            need(response==saved,'probe_input_mutated')
            need(packed.get('_http_profile_refs',{}).get('v')==2 and size(packed)<size(v1),'probe_v2_reduction_missing')
            vectors.append({'wire':packed,'expected':response})
            sizes.append(dict(mode=mode,synthetic_monthly=monthly,v1_bytes=size(v1),v2_bytes=size(packed)))
    valid=deepcopy(vectors[0]['wire'])
    for change in ('duplicate','overwrite','late_v1','invalid_mask'):
        broken=deepcopy(valid)
        if change=='duplicate':broken['profile']['daily_limits']['rows'].append(deepcopy(broken['profile']['daily_limits']['rows'][0]))
        elif change=='overwrite':broken['profile']['daily_limits']['by_key']={}
        elif change=='late_v1':broken['daily_limits']={}
        else:broken['_http_profile_refs']['m']=1024
        vectors.append({'wire':broken,'invalid':True})
    need(']=====]'not in decoder_source,'probe_decoder_delimiter_changed')
    anchor="package.path='scripts/vscripts/?.lua;'..package.path"
    need(vector_runner.count(anchor)==1,'probe_runner_anchor_changed')
    runner=vector_runner.replace(anchor,'package.path='+json.dumps((bundle.directory/'?.lua').as_posix()+';')+'..package.path',1)
    runner="package.preload['systems/http_profile_wire']=function()return assert(loadstring([=====["+decoder_source+"]=====]))()end\n"+runner
    completed=subprocess.run([lua,'-e',runner],input=json.dumps(vectors,ensure_ascii=False).encode('utf8'),
                             stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
    need(completed.returncode==0 and ('HTTP_PROFILE_WIRE_VECTORS_PASS '+str(len(vectors)))in completed.stdout.decode('utf8'),'probe_real_lua_roundtrip_failed')
    return dict(ok=True,status='ACTUAL_WS4_PREPARED_DAILY_REFS_V2_PARITY_PASS',real_lua_vectors=len(vectors),
                malformed_vectors=4,legacy_unchanged=True,changed_files=[WIRE],bundle_unchanged=True,
                sizes=sizes,rpc_calls=0,database_writes=0,real_player_data_used=False,
                boundary='Real candidate Python/Lua synthetic wire parity; no PostgreSQL/HTTP or latency measurement')
