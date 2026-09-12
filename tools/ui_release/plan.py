from pathlib import Path
import json,re,hashlib,collections
R=Path(__file__).resolve().parents[2]; E=R.parents[2]
T=E/'content/dota_addons/survival_ui_handoff_v1/panorama'; G=E/'game/dota_addons/survival_ui_handoff_v1/panorama'
F=E/'content/dota_addons/Survival/panorama'; A=R/'panorama/src'; build=json.loads((R/'art/ui/development/remaining_ui_handoff_v1/build.json').read_text(encoding='utf-8-sig'))
roots=['layout/custom_game/custom_ui_manifest.xml']+build['inputs']
queue=collections.deque(roots);sources={};missing=[]
while queue:
 rel=queue.popleft()
 if rel in sources:continue
 file=T/rel
 if not file.exists():file=F/rel
 if not file.exists():missing.append(rel);continue
 sources[rel]=str(file.resolve());text=file.read_text(encoding='utf-8-sig')
 for dep in re.findall(r'file://\{resources\}/([A-Za-z0-9_./-]+\.(?:js|css|xml))',text):
  if (T/dep).exists() or (F/dep).exists():queue.append(dep)
  else:missing.append(dep)
def compiled(rel):
 p=Path(rel);return str(p.with_suffix({'.xml':'.vxml_c','.js':'.vjs_c','.css':'.vcss_c'}[p.suffix])).replace('\\','/')
runtime={}
for rel in sources:
 cr=compiled(rel);file=G/cr
 if not file.exists():file=R/'panorama'/cr
 if not file.exists():missing.append(cr)
 else:runtime[cr]=str(file.resolve())
# Keep image families conservatively: scripts construct item paths from live CSV/registry.
for root in ['images','localization']:
 for p in (G/root).rglob('*'):
  if p.is_file():runtime[p.relative_to(G).as_posix()]=str(p.resolve())
asset_sources={}
for p in (T/'images').rglob('*'):
 if p.is_file():asset_sources[p.relative_to(T).as_posix()]=str(p.resolve())
# Preserve existing production font registration; no alternate duplicate font families.
cleanup=[]
for p in (R/'spikes').rglob('*'):
 if p.is_dir() and (p.name.endswith('_frames') or p.name in ['edge_profile','browser_profile']):
  if not any(Path(x) in p.parents for x in cleanup):cleanup.append(str(p.resolve()))
# Old non-loaded skin authoring and compiled files are superseded by current entry closure.
for root in [A,F,R/'panorama']:
 for section,ext in [('scripts','.js'),('styles','.css')]:
  for stem in ['main_hud_skin','main_hud_assets']:
   rel=section+'/custom_game/'+stem+ext
   if rel in sources:continue
   dest=root/(compiled(rel) if root==R/'panorama' else rel)
   if dest.exists():cleanup.append(str(dest.resolve()))
# Local candidate directories contain many past versions. Keep only this build's inputs/assets;
# retained unversioned dependencies are managed by the release source closure above.
candidate=R/'art/ui/development/remaining_ui_handoff_v1/candidate/panorama'
for section in ['scripts','styles','layout']:
 for p in (candidate/section).rglob('*'):
  if p.is_file() and p.relative_to(candidate).as_posix() not in sources:cleanup.append(str(p.resolve()))
size=lambda p:sum(x.stat().st_size for x in p.rglob('*') if x.is_file()) if p.is_dir() else p.stat().st_size
plan={'version':build['version'],'sources':sources,'asset_sources':asset_sources,'runtime':runtime,'missing':sorted(set(missing)),'cleanup':cleanup,'cleanup_bytes':sum(size(Path(x)) for x in cleanup),'backup_root':str(Path('D:/survival_ui_backups')/('release_'+build['version']))}
(R/'tools/ui_release/plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'version':plan['version'],'source_count':len(sources),'asset_sources':len(asset_sources),'runtime_count':len(runtime),'missing':plan['missing'],'cleanup_targets':len(cleanup),'cleanup_MB':round(plan['cleanup_bytes']/1024**2)},ensure_ascii=False))
