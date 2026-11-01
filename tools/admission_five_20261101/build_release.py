"""Six-path five-account admission release over verified3102; no implicit action.

Default is static. --scope is an unsigned worktree comparison only. --plan and
--build require an immutable source commit; signing additionally requires the
reviewed plan SHA and existing external key. Nothing here deploys or uploads.
One-shot planning O(N+K), N=6917, K=6. Full integrity phases stream3.79GB;
there are no gameplay timers, scene queries or recurring native/network calls.
"""
from contextlib import contextmanager
from pathlib import Path
import argparse,copy,difflib,hashlib,importlib.util,json,re,sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path)
 value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
legacy=module('five_accounts_verified3102',ROOT/'tools/arcade_portrait_release_v03_20261101/build_release.py')
inc,pack,need=legacy.inc,legacy.pack,legacy.need
BASE,BASE_TRUSTED,BASE_VPK=legacy.BASE,legacy.BASE_TRUSTED,legacy.BASE_VPK
BASE_REPORT,BASE_REPORT_SHA,BASE_RECORD=legacy.BASE_REPORT,legacy.BASE_REPORT_SHA,legacy.BASE_RECORD
BASE_CONTENT,BASE_SEQUENCE=legacy.BASE_CONTENT,2026103102
JOURNAL=legacy.JOURNAL
ITEM,SEQUENCE,REVISION='3824360109',2026110104,'WS4-FIVE-ACCOUNT-ADMISSION-01'
PREFIX='20261101_ws4_five_account_admission_v01'
OVERLAY=Path('D:/Survival_发布候选')/(PREFIX+'_overlay')
VIEW=Path('D:/Survival_发布候选')/(PREFIX+'_view')
TRUSTED=Path('D:/Survival_发布候选')/(PREFIX+'_trusted_source')
OUTPUT=Path('D:/Survival_工坊输出')/PREFIX
REPORT=ROOT/'output/admission_five_20261101'
ADDON='svt_f1104'
ORIGINAL=('76561198424163156','76561198845461206','76561198104787442','76561198974301984')
ADDED='76561198296534615'
APPROVED=(*ORIGINAL,ADDED)
POLICY='scripts/vscripts/core/test_access_policy.lua'
ACCESS='scripts/vscripts/config/test_access.lua'
HANDOFF='scripts/vscripts/systems/native_cloud_handoff.lua'
ROSTER='scripts/vscripts/systems/native_cloud_roster.lua'
COMMERCE='scripts/vscripts/core/commerce_release_policy.lua'
PROBE='scripts/vscripts/systems/native_transport_probe.lua'
PAYLOADS=(ACCESS,POLICY,COMMERCE,HANDOFF,ROSTER,PROBE)
EXTRA_REVIEWS=(COMMERCE,PROBE)
BUNDLE=legacy.BUNDLE
EXPECTED_BUNDLE=legacy.EXPECTED_BUNDLE
scene_maps=legacy.scene_maps
sha=lambda raw:hashlib.sha256(raw).hexdigest()
load=legacy.load
checks=legacy.checks
blob=legacy.blob
FROZEN_ADMISSION=(pack.handoff.steamids,pack.handoff.NATIVE_CLOUD_TESTERS,pack.handoff.NATIVE_CLOUD_ENTRY_PINS)

OLD_ROSTER='"76561198424163156", "76561198845461206", "76561198104787442", "76561198974301984"'
NEW_ROSTER=OLD_ROSTER+', "76561198296534615"'
OLD_ACCOUNTS="['463897428'] = true, ['885195478'] = true, ['144521714'] = true, ['1014036256'] = true"
NEW_ACCOUNTS=OLD_ACCOUNTS+", ['336268887'] = true"
LEGACY_BLOCKS=(
 'local offline_onboarding = require("debug/offline_onboarding_test")\n',
 '    -- Latch the explicit preview choice before an online match can mutate a\n    -- server convar. The helper never loads or enables the offline provider.\n    offline_onboarding.requested()\n',
 '    if offline_onboarding.requested() then\n        if not offline_onboarding.is_human(player_id) then\n            return false, "test_access_player_invalid"\n        end\n        return true\n    end\n')

def once(raw,old,new):
 need(raw.count(old)==1,'Exactly one reviewed source anchor required: '+old[:70])
 return raw.replace(old,new,1)

def admission_patch(name,raw):
 """Apply only reviewed admission deltas to3102, preserving unrelated bytes."""
 raw=raw.replace(b'\r\n',b'\n').decode('utf8')
 if name==ACCESS:
  raw=once(raw,'-- Restricted Workshop test accounts confirmed by the owner on 2026-10-22.',
   '-- Restricted Workshop accounts; the owner added a fifth account on 2026-11-01.')
  raw=once(raw,'        "76561198974301984",\n','        "76561198974301984",\n        "76561198296534615",\n')
 elif name==POLICY:
  raw=once(raw,'local MAX_ACCOUNT = 4294967295\n','local MAX_ACCOUNT = 4294967295\nlocal MAX_ALLOWED_ACCOUNTS = 5 -- Approved roster size, not simultaneous player capacity.\n')
  raw=once(raw,'    local count = 0\n    for key, steam','    local count, highest_index = 0, 0\n    for key, steam')
  raw=once(raw,'key > 4 or key ~= math.floor(key)','key > MAX_ALLOWED_ACCOUNTS or key ~= math.floor(key)')
  need(raw.count('test_access_requires_four_accounts')==2,'Original policy cardinality anchors differ')
  raw=raw.replace('test_access_requires_four_accounts','test_access_requires_four_or_five_accounts')
  raw=once(raw,'        count = count + 1\n    end\n    if count ~= 4 then return fail("test_access_requires_four_or_five_accounts") end',
   '        count = count + 1\n        highest_index = math.max(highest_index, key)\n    end\n    if (count ~= 4 and count ~= MAX_ALLOWED_ACCOUNTS) or highest_index ~= count then\n        return fail("test_access_requires_four_or_five_accounts")\n    end')
 elif name==COMMERCE:
  raw=once(raw,'local count,seen,ids=0,{},{}','local count,seen,ids,highest_index=0,{},{},0')
  raw=once(raw,'index<1 or index>4','index<1 or index>5')
  raw=once(raw,'            count,seen[steam],ids[index]=count+1,true,steam\n','            count,seen[steam],ids[index]=count+1,true,steam\n            highest_index=math.max(highest_index,index)\n')
  raw=once(raw,'        if count~=4 then return false end','        if (count~=4 and count~=5) or highest_index~=count then return false end')
 elif name in (HANDOFF,ROSTER,PROBE):
  raw=once(raw,OLD_ROSTER,NEW_ROSTER);raw=once(raw,OLD_ACCOUNTS,NEW_ACCOUNTS)
  raw=once(raw,'        local count = 0\n','        local count, highest_index = 0, 0\n')
  if name==HANDOFF:
   raw=once(raw,'integer(index, 1, CAPACITY)','integer(index, 1, #ROSTER)')
   raw=once(raw,'        if count ~= CAPACITY or type(policy)','        if (count ~= 4 and count ~= #ROSTER) or highest_index ~= count\n            or type(policy)')
   key='index'
  elif name==ROSTER:
   raw=once(raw,'integer(index, 1, 4)','integer(index, 1, #STEAMIDS)')
   raw=once(raw,'        if count ~= 4 or type(policy)','        if (count ~= 4 and count ~= #STEAMIDS) or highest_index ~= count\n            or type(policy)')
   key='index'
  else:
   raw=once(raw,'key < 1 or key > 4','key < 1 or key > #ROSTER')
   raw=once(raw,'        return count == 4 and access.enabled() == true and access.init() == true and access.allowed(id) == true',
    '        return (count == 4 or count == #ROSTER) and highest_index == count\n            and access.enabled() == true and access.init() == true and access.allowed(id) == true')
   key='key'
  raw=once(raw,'            count = count + 1\n','            count = count + 1\n            highest_index = math.max(highest_index, '+key+')\n')
 else:raise ValueError('Unapproved runtime path')
 return raw.encode('utf8')

def committed_projection(name,candidate):
 text=candidate.decode('utf8')
 if name==POLICY:
  for old in LEGACY_BLOCKS:text=once(text,old,'')
 return text.encode('utf8')

def exact_ids(values,expected=APPROVED):
 need(isinstance(values,list) and len(values)==len(expected),'Exact approved account count required')
 need(all(isinstance(v,str) and re.fullmatch(r'[0-9]{17}',v) and pack.handoff.STEAM_BASE<int(v)<=pack.handoff.STEAM_BASE+0xFFFFFFFF for v in values),'Invalid individual SteamID64 literal')
 need(len(set(values))==len(values) and sorted(values)==sorted(expected),'Exact approved accounts required; no extra/replaced identity')
 return sorted(values)

def parsed_ids(path,expected):
 previous=pack.handoff.steamids
 try:
  pack.handoff.steamids=lambda value:exact_ids(value,expected)
  return pack.handoff.configured_ids(path)
 finally:pack.handoff.steamids=previous

@contextmanager
def original_admission_context():
 h=pack.handoff;previous=(h.steamids,h.NATIVE_CLOUD_TESTERS,h.NATIVE_CLOUD_ENTRY_PINS)
 try:
  h.steamids,h.NATIVE_CLOUD_TESTERS,h.NATIVE_CLOUD_ENTRY_PINS=FROZEN_ADMISSION
  yield
 finally:h.steamids,h.NATIVE_CLOUD_TESTERS,h.NATIVE_CLOUD_ENTRY_PINS=previous

def baseline(*,full=False,require_current_journal=True):
 with original_admission_context(),scene_maps():
  return legacy.baseline(full=full,require_current_journal=require_current_journal)

@contextmanager
def admission_context(values):
 """Only this new candidate: exact5 list and two newly reviewed source pins."""
 h=pack.handoff
 previous=(h.steamids,h.NATIVE_CLOUD_TESTERS,h.NATIVE_CLOUD_ENTRY_PINS)
 try:
  h.steamids=exact_ids;h.NATIVE_CLOUD_TESTERS=sorted(APPROVED)
  h.NATIVE_CLOUD_ENTRY_PINS={**previous[2],HANDOFF:sha(values[HANDOFF]),ROSTER:sha(values[ROSTER])}
  yield
 finally:h.steamids,h.NATIVE_CLOUD_TESTERS,h.NATIVE_CLOUD_ENTRY_PINS=previous

AUXILIARY_INPUTS=(
 'tools/admission_five_20261101/build_release.py','tools/admission_five_20261101/release_checks.py',
 'tools/admission_five_20261101/publish.py','tools/admission_five_20261101/verify_download.py',
 'tools/admission_five_20261101/native.py','tools/admission_five_20261101/native_query.cjs',
 'tools/arcade_portrait_release_v03_20261101/build_release.py',*legacy.AUXILIARY_INPUTS)

def payloads(revision,*,worktree=False):
 if not worktree:legacy.immutable_revision(revision)
 result,bindings,diffs={},{},{}
 for name in PAYLOADS:
  old=(BASE/name).read_bytes();target=admission_patch(name,old)
  source=(ROOT/name).read_bytes().replace(b'\r\n',b'\n') if worktree else blob(revision,name)
  need(b'\r' not in source and committed_projection(name,target)==source,'Source differs from exact reviewed admission-only projection: '+name)
  result[name]=target
  bindings[name]={'candidate':checks(target),'git_source':checks(source),
   'source_projection':'RETAIN_EXACT_THREE_BASELINE_OFFLINE_ONBOARDING_BLOCKS' if name==POLICY else 'IDENTITY_GIT_LF',
   'baseline':checks(old),'all_other_source_bytes_equal':True}
  diffs[name]=''.join(difflib.unified_diff(old.replace(b'\r\n',b'\n').decode().splitlines(True),target.decode().splitlines(True),fromfile='3102/'+name,tofile='five-account/'+name))
 return result,bindings,diffs

def trusted_reviews(base_report,values):
 original=legacy.base_trusted_review(base_report)
 changed=set(original)&set(values)
 need(changed=={ACCESS,POLICY,HANDOFF,ROSTER},'Exactly four existing trusted reviews may change')
 review={name:checks(values[name]) if name in values else pin for name,pin in original.items()}
 for name in EXTRA_REVIEWS:need(name not in review,'Additional review already existed');review[name]=checks(values[name])
 need(len(review)==18,'16 original reviews plus two explicit added guards required')
 return review

def plan(revision):
 base_report,old=baseline()
 values,bindings,diffs=payloads(revision)
 after,changed=legacy.projected(old,values)
 need(set(changed)==set(PAYLOADS) and after['file_count']==6917,'Exactly six replacements, no additions/deletions')
 policy=load(ROOT/'tools/lua_protection_policy.json')
 selected={r['path'] for r in legacy.parent.parent.previous.base.protection.selected_files([r['path'] for r in after['files']],policy)}
 need(len(selected)==184 and not selected.intersection(changed),'All184 protected modules must remain byte-identical')
 review=trusted_reviews(base_report,values)
 tree,groups,rewritten,moves=legacy.parent.parent.previous.base.parent.rotation_plan(inc.read_entries(BASE_VPK),old,after,set(changed))
 sizes=[sum(i['row']['bytes'] for i in group) for group in groups]
 disk=inc.capacity(VIEW,OUTPUT,2*sum(map(len,values.values()))+2**22,sum(sizes[i] for i in rewritten),pack.HEADER.size+len(tree)+48,0)
 result={'schema':1,'status':'PLAN_ONLY_NOT_SIGNED','dry_run':True,'workshop_id':ITEM,'release_sequence':SEQUENCE,'revision':REVISION,
  'source_revision':revision,'baseline_release_sequence':BASE_SEQUENCE,'baseline_content_sha256':BASE_CONTENT,'baseline_report_sha256':BASE_REPORT_SHA,
  'canonical_journal_sha256':pack.runtime.digest(JOURNAL),'approved_steamids64':list(APPROVED),'added_steamid64':ADDED,'max_players':4,
  'changed_runtime_paths':sorted(changed),'added_runtime_paths':[],'removed_runtime_paths':[],'files':6917,'content_sha256':after['content_sha256'],
  'target_pins':{n:checks(v) for n,v in sorted(values.items())},'source_bindings':bindings,'reviewed_runtime_diff':diffs,
  'trusted_review_pins':review,'protected_modules_preserved':184,'payment_policy_scope':'Only roster cardinality5; original authenticated payment boundaries retained',
  'archive_bundle_hash':EXPECTED_BUNDLE,'auxiliary_input_pins':{n:checks((ROOT/n).read_bytes()) for n in dict.fromkeys(AUXILIARY_INPUTS)},
  'rebuilt_archives':sorted(rewritten),'archive_migrations':moves,'disk_preflight':disk,'baseline_package_files':base_report['package_files'],
  'candidate':str(VIEW),'trusted_source':str(TRUSTED),'output':str(OUTPUT/(ITEM+'.vpk')),
  'container_bytes':after['bytes']+pack.HEADER.size+len(tree)+48,'native_addon':ADDON,
  'signature_valid':False,'signing_key_read':False,'ready_for_upload':False,'workshop_upload_performed':False,'native_test':'NOT_RUN',
  'unrelated_fourteen_path_candidate_preserved':True,'backend_deployment_performed':False}
 return result,old,after,values,tree,groups

def merged(base,overlay,old,new,review):
 old_rows={r['path']:r for r in old['files']};rows={r['path']:r for r in new['files']}
 changed={n for n,r in rows.items() if old_rows.get(n)!=r}
 need(set(rows)==set(old_rows) and changed==set(PAYLOADS),'Merged scope must be exactly six replacements')
 need(inc.all_files(overlay)==changed|set(inc.METADATA),'Overlay must contain exactly six paths and signed metadata')
 sources={n:pack.protect_data.source_path(overlay if n in changed else base,n) for n in rows}
 for n,row in rows.items():need(pack.runtime.checksums(sources[n])=={k:row[k] for k in ('bytes','md5','sha256')},'Merged hash mismatch: '+n)
 need(pack.runtime.CRITICAL<=rows.keys(),'Critical runtime missing')
 pack.runtime.require_production(base)
 need(parsed_ids(base,ORIGINAL)==sorted(ORIGINAL) and parsed_ids(overlay,APPROVED)==sorted(APPROVED),'Only original4 -> exact approved5 is permitted')
 for n in (*pack.handoff.GATE_FILES,HANDOFF,ROSTER,COMMERCE,PROBE):
  need(pack.runtime.digest(sources[n])==pack.runtime.digest(pack.protect_data.source_path(review,n)),'Explicit trusted gate source mismatch: '+n)
 return sources,changed

def reviewed(path,digest):
 need(re.fullmatch(r'[0-9a-f]{64}',digest or '') and pack.runtime.digest(path)==digest,'Explicit reviewed plan SHA256 required')
 value=load(path);need(value['status']=='PLAN_ONLY_NOT_SIGNED' and value['dry_run'] is True and not value['signature_valid'],'Unsigned exact plan required')
 return value

def build_signed(revision,reviewed_path,reviewed_sha,key):
 expected=reviewed(reviewed_path,reviewed_sha)
 actual,old,manifest,values,tree,groups=plan(revision)
 need(legacy.parent.parent.same_plan(actual,expected),'Reviewed plan/source/input drift')
 need(key is not None,'Existing external signing key required')
 key=pack.handoff.regular_path(pack.protect_data.external(key,source=BASE))
 preserved=(*legacy.FROZEN_V01_OUTPUTS,*legacy.FROZEN_V02_OUTPUTS,legacy.OVERLAY,legacy.VIEW,legacy.TRUSTED,legacy.UNSIGNED,legacy.OUTPUT)
 for target in (OVERLAY,VIEW,TRUSTED,OUTPUT):
  inc.external(target,exists=False);need(not target.exists(),'All final directories must be NEW')
  need(not pack.runtime.within(key,target) and not pack.runtime.within(target,key.parent),'Key/output overlap')
 inc.disjoint([BASE,BASE_TRUSTED,BASE_VPK.parent,OVERLAY,VIEW,TRUSTED,OUTPUT,*preserved])
 with scene_maps():
  baseline(full=True)
  OVERLAY.mkdir(parents=True,exist_ok=False);TRUSTED.mkdir(parents=True,exist_ok=False)
  for n,raw in values.items():inc.write_new(OVERLAY/n,raw)
  for n,pin in actual['trusted_review_pins'].items():
   raw=values[n] if n in values else (BASE_TRUSTED/n).read_bytes()
   need(checks(raw)==pin,'Trusted review drift');inc.write_new(TRUSTED/n,raw)
  inc.write_new(OVERLAY/pack.handoff.MANIFEST,pack.runtime.canonical_bytes(manifest)+b'\n')
  pack.protect_data.sign_manifest(OVERLAY/pack.handoff.MANIFEST,key,OVERLAY/pack.handoff.SIGNATURE,SEQUENCE)
  _,_,metadata=inc.metadata(OVERLAY)
  sources,changed=merged(BASE,OVERLAY,old,manifest,TRUSTED)
  inc.materialize(VIEW,sources,changed,manifest,metadata)
  with admission_context(values),inc.trusted_source(TRUSTED):
   _,verified,signed,_=pack.authenticate(VIEW)
  need(verified==manifest and signed['release_sequence']==SEQUENCE,'Signed candidate differs')
  verification,files=inc.build_volumes(VIEW,OUTPUT,BASE_VPK,tree,groups,set(actual['rebuilt_archives']),manifest,'hardlink')
  need(pack.package_inventory(BASE_VPK)==actual['baseline_package_files'] and pack.runtime.verify(BASE,old)['ok'],'Immutable3102 base changed')
 final,*_=plan(revision);need(legacy.parent.parent.same_plan(actual,final),'Inputs/journal changed while building')
 actual.update(status='BUILT_SIGNED_FIVE_ACCOUNT_PENDING_NATIVE_AND_SERVER',dry_run=False,signature_valid=True,signing_key_read=True,
  full_runtime_validator_passed=True,payload_changed=False,package_files=files,vpk_sha256=files[0]['sha256'],verification=verification,
  signature_sha256=pack.runtime.digest(VIEW/pack.handoff.SIGNATURE))
 return actual

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 choice=parser.add_mutually_exclusive_group();choice.add_argument('--plan',action='store_true');choice.add_argument('--scope',action='store_true');choice.add_argument('--build',action='store_true')
 parser.add_argument('--source-revision');parser.add_argument('--report',type=Path);parser.add_argument('--reviewed-plan',type=Path);parser.add_argument('--reviewed-plan-sha256');parser.add_argument('--key',type=Path)
 a=parser.parse_args()
 if a.report:need(not a.report.exists(),'NEW report required before any operation')
 if not any((a.plan,a.scope,a.build)):
  need(not any((a.source_revision,a.report,a.reviewed_plan,a.reviewed_plan_sha256,a.key)),'Static mode accepts no operation inputs')
  print(json.dumps({'status':'STATIC_NO_ACTION','release_sequence':SEQUENCE,'runtime_paths':list(PAYLOADS),'approved_steamids64':list(APPROVED),'max_players':4,'signing_key_read':False,'uploads':0}));return
 if a.scope:
  need(not any((a.source_revision,a.reviewed_plan,a.reviewed_plan_sha256,a.key)),'Scope is not a signing plan')
  _,bindings,diffs=payloads(None,worktree=True)
  value={'status':'UNSIGNED_WORKTREE_SCOPE_ONLY','bindings':bindings,'diffs':diffs,'ready_for_signing':False}
 elif a.build:
  need(a.report is not None,'Build requires an explicit NEW completed-report destination')
  value=build_signed(a.source_revision,a.reviewed_plan,a.reviewed_plan_sha256,a.key)
 else:
  need(a.report is not None and not any((a.reviewed_plan,a.reviewed_plan_sha256,a.key)),'Plan requires NEW report and never reads key');value,*_=plan(a.source_revision)
 if a.report:
  inc.write_new(a.report,(json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode())
 print(json.dumps({k:value[k] for k in ('status','release_sequence','content_sha256','files','ready_for_upload') if k in value},ensure_ascii=False))

if __name__=='__main__':
 try:main()
 except Exception as error:print(json.dumps({'status':'REFUSED_NO_UPLOAD','error':str(error)}));raise SystemExit(1)
