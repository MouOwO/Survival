from pathlib import Path
import json,shutil,hashlib
R=Path.cwd();p=json.loads((R/'tools/ui_release/plan.json').read_text(encoding='utf8'));B=Path(p['backup_root'])/'recordings';items=[]
def sha(f):
 h=hashlib.sha256()
 with f.open('rb') as s:
  for b in iter(lambda:s.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
for f in (R/'spikes').rglob('*'):
 if f.is_file() and 'evidence' in f.relative_to(R).parts and f.suffix.lower() in ['.avi','.mp4','.webm']:
  if f.is_symlink():raise RuntimeError('Unexpected link')
  dest=B/f.relative_to(R);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,dest)
  h=sha(f)
  if sha(dest)!=h:raise RuntimeError('Capture backup mismatch')
  items.append({'source':str(f.resolve()),'backup':str(dest.resolve()),'sha256':h,'bytes':f.stat().st_size})
(R/'tools/ui_release/recordings_backup.json').write_text(json.dumps(items,ensure_ascii=False,indent=2),encoding='utf8')
print('RECORDINGS_BACKED_UP',len(items),'MB',sum(x['bytes'] for x in items)//1024**2)
