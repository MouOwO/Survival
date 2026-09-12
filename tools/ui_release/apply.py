from pathlib import Path
import json,zipfile,hashlib,shutil,sys,time
R=Path(__file__).resolve().parents[2];E=R.parents[2];F=E/'content/dota_addons/Survival/panorama';P=json.loads((R/'tools/ui_release/plan.json').read_text(encoding='utf8'));B=Path(P['backup_root']);stage=sys.argv[1]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as s:
  for b in iter(lambda:s.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def allowed(p):
 p=p.resolve()
 if not any(p.is_relative_to(x.resolve()) for x in [R/'panorama',R/'spikes',F]):raise RuntimeError('Unsafe target '+str(p))
 return p
if P['missing']:raise RuntimeError('Unresolved dependencies')
if stage=='backup':
 B.mkdir(parents=True,exist_ok=True);zpath=B/'before_and_removed.zip'
 if zpath.exists():raise RuntimeError('Backup already exists; preserve it')
 files={}
 for root in [R/'panorama',F]:
  for f in root.rglob('*'):
   if f.is_file():files[str(f.resolve())]=f
 for entry in P['cleanup']:
  p=allowed(Path(entry))
  for f in (p.rglob('*') if p.is_dir() else [p]):
   if f.is_file():files[str(f.resolve())]=f
 records=[]
 with zipfile.ZipFile(zpath,'w',compression=zipfile.ZIP_STORED,allowZip64=True) as z:
  for i,(absolute,p) in enumerate(files.items()):
   if p.is_symlink():raise RuntimeError('Unexpected symlink '+absolute)
   arc=absolute.replace(':','').replace('\\','/');z.write(p,arc);records.append({'path':absolute,'entry':arc,'sha256':sha(p),'bytes':p.stat().st_size})
 with zipfile.ZipFile(zpath) as z:
  bad=z.testzip()
  if bad:raise RuntimeError('Backup CRC failed '+bad)
 (B/'manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
 (R/'tools/ui_release/backup_verified.json').write_text(json.dumps({'archive':str(zpath),'files':len(records),'sha256':sha(zpath),'crc_verified':True}),encoding='utf8')
 print('BACKUP_VERIFIED',len(records))
elif stage=='promote':
 if not (R/'tools/ui_release/backup_verified.json').exists():raise RuntimeError('Verified backup required')
 copied=[]
 for group,roots in [('sources',[F,R/'panorama/src']),('asset_sources',[F,R/'panorama/src']),('runtime',[R/'panorama'])]:
  for rel,source in P[group].items():
   source=Path(source)
   for root in roots:
    dest=allowed(root/rel);dest.parent.mkdir(parents=True,exist_ok=True)
    if not dest.exists() or sha(dest)!=sha(source):shutil.copy2(source,dest);copied.append(str(dest))
    if sha(dest)!=sha(source):raise RuntimeError('Copy mismatch '+str(dest))
 (R/'tools/ui_release/promoted.json').write_text(json.dumps({'version':P['version'],'copied':copied,'verified_sources':len(P['sources']),'verified_runtime':len(P['runtime'])},ensure_ascii=False,indent=2),encoding='utf8')
 print('PROMOTION_VERIFIED',len(copied))
