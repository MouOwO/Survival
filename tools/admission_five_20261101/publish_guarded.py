"""0104 caller guard, retaining the separately approved new cover.

Explicit preflight/apply only. Local parent CAS is checked after the unchanged
SDK publication lock is acquired. An uncached details query must identify the
published3102 runtime plus its exact approved cover-only metadata event before
entering the frozen SDK publisher. No frozen operator is changed or bypassed.
This has no game loops: one fixed item query under the existing bounded callback
pump, O(1) metadata/space and fixed few cover/Git reads per explicit invocation.
"""
from contextlib import contextmanager,redirect_stdout,redirect_stderr
from datetime import datetime,timezone
from pathlib import Path
import argparse,copy,ctypes as C,hashlib,json,re,struct,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/admission_five_20261101'
STATE=ROOT/'output/four_accounts_20261022/steam_upload_state.json'
PARENT_SHA='e650032673e4380a571f90ef1b035f9a5d2732e4ac9234481f41dd70625900c1'
PACKAGE_SHA='70306be7a42962172fddce88bc8c4ac12dc5e73db1119d97839b871115aa01b6'
NATIVE_SHA='2274d2bd04c8b369dd3527d21aa0b72a1dfa3519377d92c27d71498d206481a2'
CONTENT='6ffc0816d040ffe4a4d7a3db472c74dc18b96fad36f5f204cba5b0879ab5489f'
PARENT_CONTENT='318491d5f839653d888c350dcaa7fb639189ec427779004879819d3ac9b45352'
COVER_COMMIT='3638ca600f33f36e819b5c5efa5f73b4f396ffd2'
COVER_PINS={
 'docs/knowledge_base/validation/20261101/workshop_cover.json':'d64d4ee5cba3fbddc7f0e4b1d692dd50a14e5cbbe3a54c5e4dea1d7bdd3ca376',
 'publishing/workshop/gou_fayu_cover_20261101.json':'ef2fa89c6abd28c29337c20736dbbef9308ac81b94115c4339a7d84fe2b96ade',
 'publishing/workshop/test_listing.json':'139567ba8ab8f1b15083b0d12f3412fac3222204d883efe52a9fb7fdd0d15871'}
COVER_SHA='00714bb69b9c400231f88112673b2fd881d50680a0a76ab63a1792256b679aa1'
PREVIEW_URL='https://images.steamusercontent.com/ugc/14913131426160410278/2CBCF2EB49661EE459A235D9CC42F8E6956941E3/'
COVER_KEYS=frozenset(('cover','cover_master','cover_sha256','cover_master_sha256','cover_bytes','cover_width','cover_height'))
EXPECTED_REMOTE={'id':'3824360109','result':1,'file_type':0,'creator_app_id':570,'consumer_app_id':570,
 'owner':'76561198845461206','visibility':3,'time_updated':1793457063,'total_files_bytes':3788092110,
 'content_bytes':3788092110,'content_file':'18446744073709551615',
 'title_description_sha256':'38fbbde9efb0d8019ce8acf0c16fafb0c807d781f2d40c850a5100b85634df91',
 'metadata_sha256':'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
 'preview_url':PREVIEW_URL,'tags':'Custom Game','banned':False,'tags_truncated':False,'cached':False,'max_cache_age_seconds':0}
sha=lambda raw:hashlib.sha256(raw).hexdigest()
def need(value,message):
 if not value:raise RuntimeError(message)

def parent_bytes(raw,expected_sha=PARENT_SHA):
 need(sha(raw)==expected_sha,'Canonical parent changed; do not overwrite another publication')
 state=json.loads(raw)
 need(state.get('uploaded') is True and state.get('release_sequence')==2026103102
  and state.get('content_sha256')==PARENT_CONTENT and state.get('workshop_id')=='3824360109'
  and state.get('owner')=='76561198845461206' and state.get('app_id')==570
  and state.get('visibility_requested')==3,'Exact successful3102 canonical parent required')
 return state

def remote_parent(answer):
 need(all(type(answer.get(k)) is type(v) and answer.get(k)==v for k,v in EXPECTED_REMOTE.items())
  and 'Custom Game' in answer.get('tags','').split(','),'Remote no longer identifies exact3102; do not overwrite')
 return answer

def committed(commit,name):
 need(re.fullmatch(r'[a-f0-9]{40}',commit or '') is not None,'Explicit immutable guard/source commit required')
 return subprocess.check_output(['git','cat-file','blob',commit+':'+name],cwd=ROOT)

def approved_cover_fields():
 values={name:committed(COVER_COMMIT,name) for name in COVER_PINS}
 need(all(sha(values[n])==pin for n,pin in COVER_PINS.items()),'Committed approved cover metadata changed')
 proof=json.loads(values['docs/knowledge_base/validation/20261101/workshop_cover.json'])
 asset=json.loads(values['publishing/workshop/gou_fayu_cover_20261101.json'])
 listing=json.loads(values['publishing/workshop/test_listing.json'])
 need(proof.get('status')=='PREVIEW_VERIFIED_CDN' and proof.get('workshop_id')=='3824360109'
  and proof.get('mutating_setters')==['SetItemPreview'] and proof.get('content_upload_requested') is False
  and proof.get('protected_fields_changed')==[] and proof.get('content_bytes_before')==proof.get('content_bytes_after')==3788092110
  and proof.get('remote_preview_sha256')==COVER_SHA and proof.get('remote_preview_bytes')==936610
  and proof.get('remote_preview_verified') is True and proof.get('after_preview_url')==PREVIEW_URL,'Exact approved cover-only event required')
 need(asset.get('preview_sha256')==COVER_SHA and asset.get('preview_bytes')==936610
  and asset.get('remote_preview_url')==PREVIEW_URL and asset.get('remote_preview_verified') is True,'Approved cover artifact record mismatch')
 selected={k:listing[k] for k in COVER_KEYS}
 need(selected['cover']=='gou_fayu_workshop.jpg' and selected['cover_master']=='gou_fayu_cover_master.png'
  and selected['cover_sha256']==COVER_SHA and selected['cover_bytes']==936610
  and selected['cover_width']==1672 and selected['cover_height']==941
  and selected['cover_master_sha256']==asset['master_sha256'],'Exact seven approved cover fields required')
 for filename,digest,length in ((selected['cover'],COVER_SHA,936610),(selected['cover_master'],selected['cover_master_sha256'],2722916)):
  path=ROOT/'publishing/workshop'/filename
  need(path.is_file() and not path.is_symlink() and path.stat().st_size==length and sha(path.read_bytes())==digest,'Approved local cover bytes changed')
 selected['cover']=str(ROOT/'publishing/workshop'/selected['cover'])
 selected['cover_master']=str(ROOT/'publishing/workshop'/selected['cover_master'])
 return selected

def project_cover(base,selected):
 need(set(selected)==COVER_KEYS,'Only the seven reviewed cover fields may be projected')
 result=copy.deepcopy(base);result.update(selected)
 need(all(result[k]==v for k,v in base.items() if k not in COVER_KEYS),'Non-cover listing data changed')
 return result

def fresh_details(steam,sdk):
 ids=(C.c_uint64*1)(3824360109)
 query=steam.ug('CreateQueryUGCDetailsRequest',C.c_uint64,[C.POINTER(C.c_uint64),C.c_uint32],ids,1)
 need(query not in (0,sdk.INVALID),'Invalid details query')
 try:
  need(steam.ug('SetAllowCachedResponse',C.c_bool,[C.c_uint64,C.c_uint32],query,0),'Uncached response required')
  for name in ('SetReturnMetadata','SetReturnLongDescription'):
   need(steam.ug(name,C.c_bool,[C.c_uint64,C.c_bool],query,True),'Protected metadata query option rejected')
  call=steam.ug('SendQueryUGCRequest',C.c_uint64,[C.c_uint64],query)
  response=steam.wait(call,sdk.Queried,3401)
  need(response.handle==query and response.returned==1 and not response.cached,'Fresh query response identity/cache mismatch')
  raw=C.create_string_buffer(9784)
  need(steam.ug('GetQueryUGCResult',C.c_bool,[C.c_uint64,C.c_uint32,C.c_void_p],query,0,raw),'Cannot read UGC021 details')
  data=raw.raw;item,result,kind,creator,consumer=struct.unpack_from('<Qiiii',data)
  preview=C.create_string_buffer(4096);metadata=C.create_string_buffer(65536)
  need(steam.ug('GetQueryUGCPreviewURL',C.c_bool,[C.c_uint64,C.c_uint32,C.c_void_p,C.c_uint32],query,0,preview,len(preview)),'Cannot read current preview URL')
  need(steam.ug('GetQueryUGCMetadata',C.c_bool,[C.c_uint64,C.c_uint32,C.c_void_p,C.c_uint32],query,0,metadata,len(metadata)),'Cannot read protected developer metadata')
  return {'id':str(item),'result':result,'file_type':kind,'creator_app_id':creator,'consumer_app_id':consumer,
   'owner':str(struct.unpack_from('<Q',data,8160)[0]),'visibility':struct.unpack_from('<i',data,8180)[0],
   'time_updated':struct.unpack_from('<I',data,8172)[0],'total_files_bytes':struct.unpack_from('<Q',data,9776)[0],
   'content_file':str(struct.unpack_from('<Q',data,9216)[0]),'content_bytes':struct.unpack_from('<I',data,9492)[0],
   'title_description_sha256':sha(data[24:8160]),'metadata_sha256':sha(metadata.value),'preview_url':preview.value.decode('utf8','strict'),
   'banned':bool(data[8184]),'tags_truncated':bool(data[8186]),
   'tags':data[8187:9212].split(b'\0')[0].decode('utf8','strict'),'cached':bool(response.cached),
   'max_cache_age_seconds':0,'observed_utc':datetime.now(timezone.utc).isoformat()}
 finally:steam.ug('ReleaseQueryUGCRequest',C.c_bool,[C.c_uint64],query)

class Guard:
 def __init__(self,locker,fresh,read=None,parent_validator=parent_bytes):
  self.locker,self.fresh=locker,fresh
  self.read=read or STATE.read_bytes
  self.parent_validator=parent_validator
  self.locked=False;self.observations=[]
 @contextmanager
 def lock(self,path):
  need(Path(path).resolve()==STATE.resolve(),'Only canonical publication lock is permitted')
  need(not self.locked,'Unexpected nested publication lock')
  with self.locker(path):
   self.parent_validator(self.read());self.locked=True
   try:yield
   finally:self.locked=False
 def before_publish(self,steam,facts):
  need(self.locked,'Parent guard must execute while canonical SDK lock is held')
  self.parent_validator(self.read())
  need(facts.get('release_sequence')==2026110104 and facts.get('content_sha256')==CONTENT,'Only reviewed0104 target is permitted')
  observation=remote_parent(self.fresh(steam))
  self.parent_validator(self.read())
  self.observations.append(observation)
  return observation

def guarded_publisher(guard,original_publish):
 def adapted(steam,listing,cover,vpk,facts,state_path,*,apply=False,update_existing=False):
  if apply:
   guard.before_publish(steam,facts)
   return original_publish(steam,listing,cover,vpk,facts,state_path,apply=True,update_existing=update_existing)
  with guard.lock(state_path):
   guard.before_publish(steam,facts)
   return original_publish(steam,listing,cover,vpk,facts,state_path,apply=False,update_existing=update_existing)
 return adapted

class LogSummary:
 def __init__(self,file,console):self.file,self.console,self.tail=file,console,''
 def write(self,text):
  self.file.write(text);self.file.flush();self.tail+=text
  need(len(self.tail)<16*1024*1024,'One output line exceeded bounded log buffer')
  while '\n' in self.tail:
   line,self.tail=self.tail.split('\n',1)
   try:value=json.loads(line)
   except ValueError:continue
   if isinstance(value,dict):
    keys=('status','reason','error','workshop_id','release_sequence','uploaded')
    self.console.write(json.dumps({k:value[k] for k in keys if k in value},ensure_ascii=False)+'\n');self.console.flush()
  return len(text)
 def flush(self):self.file.flush();self.console.flush()

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('action',choices=('preflight','apply'))
 p.add_argument('--package-sha256',required=True);p.add_argument('--native-proof',type=Path,required=True);p.add_argument('--native-proof-sha256',required=True)
 p.add_argument('--server-proof',type=Path,required=True);p.add_argument('--server-proof-sha256',required=True);p.add_argument('--log-name',required=True)
 p.add_argument('--guard-source-revision',required=True);p.add_argument('--guard-sha256',required=True)
 a=p.parse_args()
 self_raw=Path(__file__).read_bytes()
 need(re.fullmatch(r'[a-f0-9]{64}',a.guard_sha256 or '') and sha(self_raw)==a.guard_sha256,'Explicit reviewed guard SHA required')
 need(self_raw.replace(b'\r\n',b'\n')==committed(a.guard_source_revision,'tools/admission_five_20261101/publish_guarded.py'),'Guard must be committed unchanged before use')
 need(a.package_sha256==PACKAGE_SHA and a.native_proof_sha256==NATIVE_SHA,'Exact reviewed package/native SHA required')
 need(re.fullmatch(r'[a-z0-9_]{1,100}\.log',a.log_name) is not None,'Explicit safe NEW log basename required')
 for path,digest in ((OUT/'package.json',PACKAGE_SHA),(a.native_proof,NATIVE_SHA),(a.server_proof,a.server_proof_sha256)):
  need(re.fullmatch(r'[0-9a-f]{64}',digest or '') and sha(path.read_bytes())==digest,'Explicit proof/file SHA mismatch')
 package=json.loads((OUT/'package.json').read_bytes())
 for name,pin in package['auxiliary_input_pins'].items():need(sha((ROOT/name).read_bytes())==pin['sha256'],'Frozen operator changed before import')
 parent_bytes(STATE.read_bytes())
 cover=approved_cover_fields()
 log=OUT/a.log_name;need(not log.exists(),'Refuse log overwrite; inspect the prior attempt')
 summary_path=log.with_suffix('.guard.json');need(not summary_path.exists(),'NEW guard summary required')
 sys.path.insert(0,str(ROOT/'tools/admission_five_20261101'))
 import publish as target
 sdk=target.publisher
 original_lock,original_publish,original_listing=sdk.publication_lock,sdk.publish,target.listing
 guard=Guard(original_lock,lambda steam:fresh_details(steam,sdk))
 sdk.publication_lock,sdk.publish=guard.lock,guarded_publisher(guard,original_publish)
 target.listing=lambda package:project_cover(original_listing(package),cover)
 argv=['publish.py','--report-sha256',PACKAGE_SHA,'--native-proof',str(a.native_proof.resolve()),'--native-proof-sha256',NATIVE_SHA,
  '--server-proof',str(a.server_proof.resolve()),'--server-proof-sha256',a.server_proof_sha256]
 if a.action=='apply':argv.append('--apply')
 old_argv=sys.argv;code=1;error=None
 try:
  with log.open('x',encoding='utf8',newline='\n') as saved:
   stream=LogSummary(saved,sys.stdout)
   with redirect_stdout(stream),redirect_stderr(stream):
    try:sys.argv=argv;code=target.main()
    except Exception as failure:error=type(failure).__name__+': '+str(failure);print(json.dumps({'status':'PARENT_GUARDED_PUBLICATION_REFUSED_PRESERVE_JOURNAL','error':error}));code=1
 finally:
  sys.argv=old_argv;sdk.publication_lock,sdk.publish=original_lock,original_publish;target.listing=original_listing
 result={'schema':1,'action':a.action,'exit_code':code,'parent_sha256_required':PARENT_SHA,'package_sha256':PACKAGE_SHA,
  'native_sha256':NATIVE_SHA,'server_sha256':a.server_proof_sha256,'fresh_parent_observations':guard.observations,
  'error':error,'frozen_files_modified':False,'automatic_retry_performed':False,'raw_log_sha256':sha(log.read_bytes()),
  'guard_source_revision':a.guard_source_revision,'guard_sha256':a.guard_sha256,'cover_source_commit':COVER_COMMIT,
  'cover_fields_projected':sorted(COVER_KEYS),'approved_cover_sha256':COVER_SHA,
  'remote_atomic_CAS_claimed':False}
 with summary_path.open('x',encoding='utf8',newline='\n') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
 print(json.dumps({'action':a.action,'exit_code':code,'raw_log':str(log),'guard_summary':str(summary_path)},ensure_ascii=False))
 return code

if __name__=='__main__':
 try:raise SystemExit(main())
 except Exception as error:print(json.dumps({'status':'PARENT_WRAPPER_REFUSED_BEFORE_SDK','error':str(error)},ensure_ascii=False));raise SystemExit(1)
