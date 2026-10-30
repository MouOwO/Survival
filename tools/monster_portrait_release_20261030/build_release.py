"""Prepare a separate, signed portrait+map candidate; never mutate upload state.

Inputs are a fixed portrait Git revision and the existing map update. The
failed Steam request remains pending until its official recovery completes.
"""
from pathlib import Path
from contextlib import contextmanager
import argparse,copy,hashlib,importlib.util,json,re,subprocess,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('portrait_map_parent',ROOT/'tools/map_release_20261029/build_release.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
inc,pack,need=base.inc,base.pack,base.need
SEQUENCE=2026103003;REVISION='WS4-UNIT-PORTRAITS-TRANSITION-03';ITEM=base.ITEM
SOURCE='HEAD'
PREFIX='20261030_ws4_unit_portraits_v04'
OVERLAY=Path('D:/Survival_发布候选')/(PREFIX+'_overlay')
TRUSTED=Path('D:/Survival_发布候选')/(PREFIX+'_trusted_source')
VIEW=Path('D:/Survival_发布候选')/(PREFIX+'_view')
OUTPUT=Path('D:/Survival_工坊输出')/PREFIX
REPORT=ROOT/'output/portrait_transition_publish_20261030'
PACKAGE_REPORT='package_v04.json'
def saved(name):
 for tree in (SOURCE,SOURCE+'^3'):
  result=subprocess.run(['git','cat-file','blob',tree+':'+name],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  if not result.returncode:return result.stdout
 raise ValueError('Missing task input: '+name)
@contextmanager
def portrait_scene_maps(values):
 # The frozen publisher permits only its exact background-map allowlist.
 # Extend it for this invocation with the 188 reviewed, signed portrait maps;
 # arbitrary gameplay maps remain rejected by the original guard.
 additions={n for n in values if re.fullmatch(r'maps/portraits/monster_[0-9a-f]{20}_v1\.vpk',n)}
 expected={'maps/'+s['map']+'.vpk' for s in json.loads(saved('art/portraits/monsters/manifest.json'))['assets'].values()}
 need(len(additions)==188 and additions==expected,'Exact reviewed portrait map set required')
 previous=pack.runtime.SCENE_MAPS
 try:
  pack.runtime.SCENE_MAPS=previous|additions
  yield
 finally:pack.runtime.SCENE_MAPS=previous
def payloads():
 values=base.payloads()
 manifest=json.loads(saved('art/portraits/monsters/manifest.json'))
 need(len(manifest['assets'])==197 and manifest['unique_scenes']==188 and len(manifest['backgrounds'])==29,'Verified portrait inventory differs')
 names={'panorama/layout/custom_game/survival_hud.vxml_c',*('panorama/scripts/custom_game/'+n+'.vjs_c' for n in ('combat_stats','portrait_presentation','monster_portrait_scenes','monster_portrait_renderer','topnav_remaining_5d5c1152eb'))}
 names.update('maps/'+s['map']+'.vpk' for s in manifest['assets'].values())
 names.update(s['texture'].removeprefix('s2r://')+'_c' for s in manifest['backgrounds'].values())
 need(len({s['texture'] for s in manifest['backgrounds'].values()})==28 and len(names)==222,'Exact compiled portrait inventory required')
 for name in sorted(names):values[name]=saved(name)
 qa=base.load(ROOT/'output/portrait_optimization_20261030/verification.json')
 need(qa['status']=='PASS' and qa['all_assets_loaded']==197 and qa['prewarmed_worlds']==188 and qa['first_click_scene_allocations']==0 and qa['offline_cycle_units']==12 and qa['all_six_heroes_visual'] and qa['empty_monster_keys'] and qa['test_only_panels_removed'],'Actual offline receipt required')
 transition=base.load(ROOT/'output/portrait_transition_20261030/verification.json')
 need(transition['status']=='PASS_OFFLINE_PORTRAIT_TRANSITIONS' and transition['reviewed_frames']==340
      and transition['uncovered_painted_states']==0 and not transition['native_body_flash_seen']
      and not transition['white_render_target_flash_seen'] and transition['native_opacity']==1
      and transition['test_only_panels_removed'],'Final native transition receipt required')
 for name in ('combat_stats','monster_portrait_renderer'):
  need(base.sha(saved('panorama/src/scripts/custom_game/'+name+'.js').replace(b'\r\n',b'\n'))==transition['source_lf_sha256'][name],'Native-verified portrait source changed')
 need(all(marker not in values['panorama/layout/custom_game/survival_hud.vxml_c'] for marker in (b'portrait_qa_probe',b'portrait_transition_qa')),'Temporary UI must be absent')
 return values
def run(build=False,key=None,reviewed=None):
 for p in (OVERLAY,TRUSTED,VIEW,OUTPUT):pack.handoff.regular_path(p,must_exist=False);need(not p.exists(),'New candidate paths required')
 need(pack.runtime.digest(base.BASE_REPORT)==base.BASE_REPORT_SHA,'Immutable baseline report changed')
 state=base.load(base.JOURNAL);journal=pack.runtime.digest(base.JOURNAL)
 prior=state if state.get('uploaded') else state.get('previous_release',{})
 need(prior.get('release_sequence')==2026102901 and prior.get('uploaded') is True and prior.get('content_sha256')==base.BASE_CONTENT,'Known last uploaded release required')
 if not state.get('uploaded'):
  need(state.get('status')=='SUBMIT_REQUEST_PENDING' and state.get('release_sequence')==2026102902,'Only known failed pending state may remain during local preparation')
 with inc.trusted_source(base.BASE_TRUSTED):_,before,signed,_=pack.authenticate(base.BASE)
 need(before['content_sha256']==base.BASE_CONTENT and signed['release_sequence']==2026102901,'Signed baseline mismatch')
 inventory=pack.package_inventory(base.BASE_VPK);need(inventory==base.load(base.BASE_REPORT)['package_files']==prior['package_files'],'Base archives changed')
 pack.verify_vpk(base.BASE_VPK,before)
 values=payloads();old={r['path']:r for r in before['files']}
 values={n:v for n,v in values.items() if n not in old or base.checks(v)['sha256']!=old[n]['sha256']}
 rows=copy.deepcopy(old)
 for n,v in values.items():rows[n]=dict(path=n,**base.checks(v))
 policy=base.load(ROOT/'tools/lua_protection_policy.json')
 protected=set(r['path'] for r in base.protection.selected_files(list(rows),policy))
 need(len(protected)==184 and not protected.intersection(values),'Protected Lua must remain byte-identical')
 review={n:(base.BASE_TRUSTED/n).read_bytes() for n in inc.all_files(base.BASE_TRUSTED)}
 need(len(review)==16 and not set(review).intersection(values),'Account gates and authentication reviews must remain unchanged')
 need('scripts/vscripts/config/generated/archive_http_bundle.lua' not in values,'No backend activation')
 after=copy.deepcopy(before);after['files']=[rows[n] for n in sorted(rows)];after['file_count']=len(rows);after['bytes']=sum(r['bytes'] for r in rows.values());after['content_sha256']=base.sha(pack.runtime.manifest_payload(after));pack.runtime.validate_manifest(after)
 tree,groups,rewritten,moves=base.parent.rotation_plan(inc.read_entries(base.BASE_VPK),before,after,set(values))
 sizes=[sum(x['row']['bytes'] for x in g) for g in groups]
 disk=inc.capacity(VIEW,OUTPUT,sum(map(len,values.values()))*2+2**22,sum(sizes[i] for i in rewritten),pack.HEADER.size+len(tree)+48,0)
 plan=dict(schema=1,revision=REVISION,release_sequence=SEQUENCE,workshop_id=ITEM,source_git_head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),portrait_source_revision=SOURCE,baseline_release_sequence=2026102901,baseline_content_sha256=base.BASE_CONTENT,canonical_journal_sha256=journal,pending_journal_preserved=not state.get('uploaded'),content_sha256=after['content_sha256'],files=after['file_count'],changed_runtime_paths=sorted(values),target_pins={n:base.checks(v) for n,v in values.items()},protected_modules_preserved=184,protected_modules_rebuilt=0,account_gates_payment_backend_preserved=True,trusted_review_files=16,rebuilt_archives=sorted(rewritten),archive_migrations=moves,disk_preflight=disk,candidate=str(VIEW),trusted_source=str(TRUSTED),output=str(OUTPUT/(ITEM+'.vpk')),container_bytes=after['bytes']+pack.HEADER.size+len(tree)+48)
 need(pack.runtime.digest(base.JOURNAL)==journal,'Journal changed during plan')
 if not build:return plan
 need(reviewed and base.same_plan(base.load(reviewed),plan),'Reviewed input plan changed')
 key=pack.handoff.regular_path(pack.protect_data.external(key,source=base.BASE));need(key.is_file(),'Existing external signing key required')
 for p in (OVERLAY,TRUSTED,VIEW,OUTPUT):need(not pack.runtime.within(key,p) and not pack.runtime.within(p,key.parent),'Key/output overlap')
 OVERLAY.mkdir(parents=True);TRUSTED.mkdir(parents=True)
 for n,v in values.items():inc.write_new(OVERLAY/n,v)
 for n,v in review.items():inc.write_new(TRUSTED/n,v)
 inc.write_new(OVERLAY/pack.handoff.MANIFEST,pack.runtime.canonical_bytes(after)+b'\n')
 pack.protect_data.sign_manifest(OVERLAY/pack.handoff.MANIFEST,key,OVERLAY/pack.handoff.SIGNATURE,SEQUENCE)
 _,_,metadata=inc.metadata(OVERLAY);sources,changed=inc.validate_merged(base.BASE,OVERLAY,before,after,TRUSTED);need(changed==set(values),'Unexpected overlay scope')
 inc.materialize(VIEW,sources,changed,after,metadata)
 with portrait_scene_maps(values),inc.trusted_source(TRUSTED):_,verified,signature,_=pack.authenticate(VIEW)
 need(verified==after and signature['release_sequence']==SEQUENCE,'Final signed view differs')
 with portrait_scene_maps(values):
  verification,files=inc.build_volumes(VIEW,OUTPUT,base.BASE_VPK,tree,groups,rewritten,after,'hardlink')
 need(pack.package_inventory(base.BASE_VPK)==inventory and pack.runtime.verify(base.BASE,before)['ok'],'Original baseline changed')
 need(pack.runtime.digest(base.JOURNAL)==journal,'Upload journal must remain untouched')
 current=payloads();need(all(current[n]==v for n,v in values.items()),'Task inputs changed during build')
 plan.update(status='BUILT_SIGNED_MONSTER_PORTRAITS_AND_MAP',dry_run=False,signature_valid=True,full_runtime_validator_passed=True,payload_changed=False,workshop_upload_performed=False,package_files=files,vpk_sha256=files[0]['sha256'],verification=verification,native_test='DEVELOPMENT_COMPILED_BYTES_VERIFIED;SIGNED_CANDIDATE_PENDING',ready_for_upload=False)
 return plan
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--build',action='store_true');p.add_argument('--key',type=Path);p.add_argument('--reviewed-plan',type=Path);p.add_argument('--report',type=Path,required=True);p.add_argument('--source-revision',default='HEAD');a=p.parse_args()
 SOURCE=subprocess.check_output(['git','rev-parse','--verify',a.source_revision+'^{commit}'],cwd=ROOT,text=True).strip()
 need(not a.report.exists(),'New report required');r=run(a.build,a.key,a.reviewed_plan);a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf8');print(json.dumps({k:r[k] for k in ('release_sequence','content_sha256','files','rebuilt_archives','pending_journal_preserved')}))
