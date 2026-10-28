"""Two reviewed plaintext Lua replacements over signed, downloaded MAP2802.

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
BASE=parent.VIEW;BASE_TRUSTED=parent.TRUSTED
BASE_VPK=parent.OUTPUT/'3824360109.vpk'
BASE_REPORT=ROOT/'output/map_resources_20261028/package.json'
BASE_REPORT_SHA='4b701bce2b41d30ffe4bc5d3628dd44180778e52d70085b58ea7bde801c6a368'
BASE_RECEIPT=ROOT/'output/map_resources_20261028/download_evidence/20261028T010453Z_f4ad7619af99475c859dad247cb377d3/verification.json'
BASE_RECEIPT_SHA='5babf60a6c7c06bd3867dfb45f9defae57d477ac3728bedea66394ab03f3b948'
BASE_CONTENT='310aad0a33116f29304d9ea7251524b4c1721bd5fb2b7952610d63cca2ac09d5'
SEQUENCE,REVISION=2026102803,'WS4-REBIRTH-INSPECT-01'
OVERLAY=Path('D:/Survival_发布候选/20261028_ws4_rebirth_selection_v01_overlay')
TRUSTED=OVERLAY.with_name(OVERLAY.name+'_trusted_source')
VIEW=Path('D:/Survival_发布候选/20261028_ws4_rebirth_selection_v01_view')
OUTPUT=Path('D:/Survival_工坊输出/20261028_ws4_rebirth_selection_v01')
TARGET_PINS={
 'scripts/vscripts/modifiers/modifier_rebirth_scene_display.lua':{'bytes':902,'md5':'688f08fc18101b073360a34b4f19c7f0','sha256':'b30ddedd5b73158238d4be2eefd6df2ca910f56eab6c3554e407b440aae1b02a'},
 'scripts/vscripts/systems/rebirth_scene_display_service.lua':{'bytes':10334,'md5':'d7a188611862036c95856b7519fed6c3','sha256':'3ad3a46e1f87a48398d98763eb970572e928957bf0c79e34194091daeff0de72'},
}

def capture(path,sha=None):
    raw=pack.read_metadata(pack.handoff.regular_path(path),pack.MAX_MANIFEST)
    need(sha is None or hashlib.sha256(raw).hexdigest()==sha,'Reviewed input changed: '+path.name)
    return raw

def projection(before,policy):
    after=copy.deepcopy(before);old={r['path']:r for r in before['files']}
    need(set(TARGET_PINS)<=old.keys(),'Only existing preview Lua may be replaced')
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
    snapshots={p:capture(p) for p in [Path(__file__),parent.PRIMITIVES,ROOT/'tools/build_runtime_release.py',ROOT/'tools/lua_protection_policy.json']}
    report=json.loads(capture(BASE_REPORT,BASE_REPORT_SHA))
    receipt=json.loads(capture(BASE_RECEIPT,BASE_RECEIPT_SHA))
    need(report['release_sequence']==2026102802 and report['content_sha256']==BASE_CONTENT and report['full_runtime_validator_passed'],'MAP2802 report mismatch')
    need(receipt['status']=='OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED' and receipt['steam_manifest']=='2226754158672105621' and receipt['content_sha256']==BASE_CONTENT,'MAP2802 official receipt mismatch')
    with incremental.trusted_source(BASE_TRUSTED): _,before,signed,base_metadata=pack.authenticate(BASE)
    need(before['content_sha256']==BASE_CONTENT and signed['release_sequence']==2026102802 and before['file_count']==6658,'Immutable baseline mismatch')
    inventory=pack.package_inventory(BASE_VPK)
    need(inventory==report['package_files'],'MAP2802 archives mismatch')
    pack.verify_vpk(BASE_VPK,before)
    review={name:capture(BASE_TRUSTED/name) for name in incremental.all_files(BASE_TRUSTED)}
    need(len(review)==16,'Trusted admission/UI review set mismatch')
    for name,pin in TARGET_PINS.items():need(pack.runtime.checksums(ROOT/name)==pin,'Reviewed Lua changed: '+name)
    policy=json.loads(snapshots[ROOT/'tools/lua_protection_policy.json'])
    after=projection(before,policy)
    tree,groups,rewritten,moves=parent.rotation_plan(incremental.read_entries(BASE_VPK),before,after,set(TARGET_PINS))
    need(rewritten=={0},'Review archive rotation before building')
    sizes=[sum(item['row']['bytes'] for item in group) for group in groups]
    disk=incremental.capacity(VIEW,OUTPUT,sum(p['bytes'] for p in TARGET_PINS.values())*2+1024**2,sum(sizes[i] for i in rewritten),pack.HEADER.size+len(tree)+48,0)
    result=dict(schema=1,status='READ_ONLY_REBIRTH_SELECTION_PLAN',revision=REVISION,dry_run=not build,release_sequence=SEQUENCE,
        content_sha256=after['content_sha256'],files=6658,base_release_sequence=2026102802,base_content_sha256=BASE_CONTENT,
        base_package_report_sha256=BASE_REPORT_SHA,base_official_download_sha256=BASE_RECEIPT_SHA,
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
    for name,pin in TARGET_PINS.items():incremental.copy_new(ROOT/name,OVERLAY/name,dict(path=name,**pin))
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
    for name,pin in TARGET_PINS.items():need(pack.runtime.checksums(ROOT/name)==pin,'Lua drift during packaging')
    for folder,metadata in ((BASE,base_metadata),(OVERLAY,metadata),(VIEW,view_metadata)):pack.inventory_unchanged(folder,metadata)
    need(pack.package_inventory(BASE_VPK)==inventory,'Baseline archive drift')
    result.update(status='BUILT_SIGNED_REBIRTH_SELECTION_REQUIRES_NATIVE_SMOKE',signature_valid=True,
        trusted_key_id=signature['key_id'],package_files=files,vpk_sha256=files[0]['sha256'],verification=verification,
        full_runtime_validator_passed=True,full_view_canonical_guard='PASS',immutable_base_unchanged=True)
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');parser.add_argument('--key',type=Path)
    args=parser.parse_args()
    try:print(json.dumps(run(args.build,args.key),ensure_ascii=False))
    except Exception as error:print(json.dumps({'status':'BLOCKED','error':str(error)},ensure_ascii=False));return 1
    return 0
if __name__=='__main__':raise SystemExit(main())
