"""Reviewed ten-sin startup patch over the immutable, uploaded REBIRTH2803 package.

Default verifies a read-only plan. --build writes new external artifacts only;
it preserves every protected module, gate, map, UI and payment resource.
"""
from pathlib import Path
import argparse,copy,hashlib,importlib.util,json,sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('rebirth_parent_map2802',ROOT/'tools/map_resources_20261028/build_map_resources.py')
parent=importlib.util.module_from_spec(spec);spec.loader.exec_module(parent)
incremental,pack,need=parent.incremental,parent.pack,parent.need
BASE=Path('D:/Survival_发布候选/20261028_ws4_rebirth_selection_v01_view')
BASE_TRUSTED=Path('D:/Survival_发布候选/20261028_ws4_rebirth_selection_v01_overlay_trusted_source')
BASE_VPK=Path('D:/Survival_工坊输出/20261028_ws4_rebirth_selection_v01/3824360109.vpk')
BASE_REPORT=ROOT/'output/rebirth_selection_20261028/package.json'
BASE_REPORT_SHA='a9492685a24d871dc003a02bf08b2145952f7171409e3bc7088b44c5b21c2320'
BASE_RECEIPT=ROOT/'output/map_resources_20261028/download_evidence/20261028T010453Z_f4ad7619af99475c859dad247cb377d3/verification.json'
BASE_RECEIPT_SHA='5babf60a6c7c06bd3867dfb45f9defae57d477ac3728bedea66394ab03f3b948'
BASE_CONTENT='7d39ab251f4c8f20d8338a49a8335b0447c0e4e8f6a196978312b40f8981ab96'
SEQUENCE,REVISION=2026102804,'WS4-TEN-SIN-STARTUP-01'
OVERLAY=Path('D:/Survival_发布候选/20261028_ws4_ten_sin_startup_v01_overlay')
TRUSTED=OVERLAY.with_name(OVERLAY.name+'_trusted_source')
VIEW=Path('D:/Survival_发布候选/20261028_ws4_ten_sin_startup_v01_view')
OUTPUT=Path('D:/Survival_工坊输出/20261028_ws4_ten_sin_startup_v01')
PINS_PATH=Path(__file__).with_name('pins.json')
PATCH_PATH=Path(__file__).with_name('challenge_startup.patch')
PINS=json.loads(PINS_PATH.read_text(encoding='utf8'))
TARGET_PINS={PINS['runtime_path']:PINS['target']}

def checksums(raw):
    return dict(bytes=len(raw),md5=hashlib.md5(raw).hexdigest(),sha256=hashlib.sha256(raw).hexdigest())

def target_source():
    need(checksums((ROOT/PINS['runtime_path']).read_bytes())==PINS['local_source'],'Reviewed local source drift')
    original=(BASE/PINS['runtime_path']).read_bytes()
    need(checksums(original)==PINS['frozen_source'],'Frozen challenge source drift')
    patch=PATCH_PATH.read_bytes()
    need(checksums(patch)==PINS['patch'],'Reviewed patch drift')
    value=original.decode('utf-8-sig').replace('\r\n','\n')
    hunks=[];old=[];new=[]
    for line in patch.decode('utf8').splitlines(keepends=True):
        if line.startswith(('---','+++')):continue
        if line.startswith('@@'):
            if old:hunks.append((''.join(old),''.join(new)))
            old=[];new=[]
        elif line.startswith(' '):old.append(line[1:]);new.append(line[1:])
        elif line.startswith('-'):old.append(line[1:])
        elif line.startswith('+'):new.append(line[1:])
    if old:hunks.append((''.join(old),''.join(new)))
    need(len(hunks)==PINS['changed_hunks']==4,'Unexpected patch structure')
    for old,new in hunks:
        need(value.count(old)==1,'Frozen patch context is not unique')
        value=value.replace(old,new,1)
    raw=value.encode('utf8')
    need(checksums(raw)==PINS['target'],'Frozen patch output mismatch')
    return raw


def capture(path,sha=None):
    raw=pack.read_metadata(pack.handoff.regular_path(path),pack.MAX_MANIFEST)
    need(sha is None or hashlib.sha256(raw).hexdigest()==sha,'Reviewed input changed: '+path.name)
    return raw

def projection(before,policy):
    after=copy.deepcopy(before);old={r['path']:r for r in before['files']}
    need(set(TARGET_PINS)<=old.keys(),'Only the existing challenge startup Lua may be replaced')
    after['files']=[dict(path=r['path'],**TARGET_PINS[r['path']]) if r['path'] in TARGET_PINS else r for r in after['files']]
    after['bytes']=sum(r['bytes'] for r in after['files'])
    after['content_sha256']=hashlib.sha256(pack.runtime.manifest_payload(after)).hexdigest()
    pack.runtime.validate_manifest(after)
    new={r['path']:r for r in after['files']}
    chosen={r['path'] for r in parent.protection.selected_files(list(old),policy)}
    need(len(chosen)==180 and not chosen.intersection(TARGET_PINS),'Protected module set cannot change')
    need(all(old[p]==new[p] for p in chosen),'Protected bytes changed')
    need({p for p in old if old[p]!=new[p]}==set(TARGET_PINS),'Unreviewed replacement')
    return after

def run(build=False,key=None):
    for dest in (OVERLAY,TRUSTED,VIEW,OUTPUT):
        incremental.external(dest,exists=False);need(not dest.exists(),'New output directory required: '+dest.name)
    incremental.disjoint([BASE,BASE_TRUSTED,BASE_VPK.parent,OVERLAY,TRUSTED,VIEW,OUTPUT])
    need(build or key is None,'Private key is used only for an explicit build')
    snapshots={p:capture(p) for p in [Path(__file__),parent.PRIMITIVES,ROOT/'tools/build_runtime_release.py',ROOT/'tools/lua_protection_policy.json',PINS_PATH,PATCH_PATH]}
    report=json.loads(capture(BASE_REPORT,BASE_REPORT_SHA))
    receipt=json.loads(capture(BASE_RECEIPT,BASE_RECEIPT_SHA))
    need(report['release_sequence']==2026102803 and report['content_sha256']==BASE_CONTENT and report['full_runtime_validator_passed'],'REBIRTH2803 report mismatch')
    need(receipt['status']=='OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED' and receipt['steam_manifest']=='2226754158672105621' and receipt['content_sha256']=='310aad0a33116f29304d9ea7251524b4c1721bd5fb2b7952610d63cca2ac09d5','MAP2802 official receipt mismatch')
    with incremental.trusted_source(BASE_TRUSTED): _,before,signed,base_metadata=pack.authenticate(BASE)
    need(before['content_sha256']==BASE_CONTENT and signed['release_sequence']==2026102803 and before['file_count']==6658,'Immutable baseline mismatch')
    inventory=pack.package_inventory(BASE_VPK)
    need(inventory==report['package_files'],'REBIRTH2803 archives mismatch')
    pack.verify_vpk(BASE_VPK,before)
    review={name:capture(BASE_TRUSTED/name) for name in incremental.all_files(BASE_TRUSTED)}
    need(len(review)==16,'Trusted admission/UI review set mismatch')
    for name,pin in TARGET_PINS.items():need(checksums(target_source())==pin,'Reviewed patch changed: '+name)
    policy=json.loads(snapshots[ROOT/'tools/lua_protection_policy.json'])
    after=projection(before,policy)
    tree,groups,rewritten,moves=parent.rotation_plan(incremental.read_entries(BASE_VPK),before,after,set(TARGET_PINS))
    need(rewritten=={0},'Review archive rotation before building')
    sizes=[sum(item['row']['bytes'] for item in group) for group in groups]
    disk=incremental.capacity(VIEW,OUTPUT,sum(p['bytes'] for p in TARGET_PINS.values())*2+1024**2,sum(sizes[i] for i in rewritten),pack.HEADER.size+len(tree)+48,0)
    result=dict(schema=1,status='READ_ONLY_TEN_SIN_STARTUP_PLAN',revision=REVISION,dry_run=not build,release_sequence=SEQUENCE,
        content_sha256=after['content_sha256'],files=6658,base_release_sequence=2026102803,base_content_sha256=BASE_CONTENT,
        base_package_report_sha256=BASE_REPORT_SHA,ancestor_2802_download_sha256=BASE_RECEIPT_SHA,base_download_verified=False,
        candidate=str(VIEW),overlay=str(OVERLAY),trusted_source=str(TRUSTED),output=str(OUTPUT/'3824360109.vpk'),
        changed_runtime_paths=sorted(TARGET_PINS),added_runtime_paths=[],deleted_runtime_paths=[],
        protected_modules_preserved=180,protected_modules_rebuilt=0,trusted_review_files=16,
        authentication_payment_code_preserved=True,maps_and_panorama_preserved=True,payload_changed=False,full_input_hash_verification=True,payload_bytes=after['bytes'],
        rebuilt_archives=sorted(rewritten),reused_archives=[1,2,3],archive_migrations=moves,
        container_bytes=after['bytes']+pack.HEADER.size+len(tree)+48,disk_preflight=disk,
        workshop_upload_performed=False,native_test='NOT_RUN',ready_for_upload=False)
    if not build:return result
    need(key is not None,'External signing key required')
    key=pack.handoff.regular_path(pack.protect_data.external(key,source=BASE))
    for dest in (OVERLAY,TRUSTED,VIEW,OUTPUT):need(not pack.runtime.within(key,dest) and not pack.runtime.within(dest,key.parent),'Key/output overlap')
    OVERLAY.mkdir(parents=True);TRUSTED.mkdir(parents=True)
    for name,pin in TARGET_PINS.items():incremental.write_new(OVERLAY/name,target_source())
    for name,raw in review.items():incremental.write_new(TRUSTED/name,raw)
    incremental.write_new(OVERLAY/pack.handoff.MANIFEST,pack.runtime.canonical_bytes(after)+b'\n')
    pack.protect_data.sign_manifest(OVERLAY/pack.handoff.MANIFEST,key,OVERLAY/pack.handoff.SIGNATURE,SEQUENCE)
    actual,document,metadata=incremental.metadata(OVERLAY)
    trust,public=pack.handoff.trusted_policy(pack.handoff.POLICY)
    signature=pack.verify_signed_snapshot(actual,document,public,trust['integrity']['minimum_release_sequence'],trust['integrity']['trusted_key_id'])
    need(actual==after and signature['release_sequence']==SEQUENCE,'Signed overlay mismatch')
    sources,changed=incremental.validate_merged(BASE,OVERLAY,before,after,TRUSTED)
    need(changed==set(TARGET_PINS),'Unexpected merged paths')
    incremental.materialize(VIEW,sources,changed,after,metadata)
    with incremental.trusted_source(TRUSTED): _,verified,view_signature,view_metadata=pack.authenticate(VIEW)
    need(verified==after and view_signature==signature,'Full candidate mismatch')
    verification,files=incremental.build_volumes(VIEW,OUTPUT,BASE_VPK,tree,groups,rewritten,after,'hardlink')
    for path,raw in snapshots.items():need(capture(path)==raw,'Build input drift')
    for name,pin in TARGET_PINS.items():need(checksums(target_source())==pin,'Lua drift during packaging')
    for folder,metadata in ((BASE,base_metadata),(OVERLAY,metadata),(VIEW,view_metadata)):pack.inventory_unchanged(folder,metadata)
    need(pack.package_inventory(BASE_VPK)==inventory,'Baseline archive drift')
    result.update(status='BUILT_SIGNED_TEN_SIN_STARTUP_REQUIRES_NATIVE_SMOKE',signature_valid=True,
        trusted_key_id=signature['key_id'],package_files=files,vpk_sha256=files[0]['sha256'],verification=verification,
        full_runtime_validator_passed=True,full_view_canonical_guard='PASS',immutable_base_unchanged=True)
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');parser.add_argument('--key',type=Path)
    parser.add_argument('--report',type=Path,help='Write the actual result as UTF-8 JSON')
    args=parser.parse_args()
    try:
        result=run(args.build,args.key)
        if args.report:
            need(not args.report.exists(),'A new report path is required')
            args.report.parent.mkdir(parents=True,exist_ok=True)
            args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
        print(json.dumps(result,ensure_ascii=False))
    except Exception as error:print(json.dumps({'status':'BLOCKED','error':str(error)},ensure_ascii=False));return 1
    return 0
if __name__=='__main__':raise SystemExit(main())
