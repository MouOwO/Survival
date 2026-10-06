"""Verify preserved title; --restore restores title-owned files with backups.
Shared archive/backend snapshots are references and are never blindly restored.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,shutil
p=argparse.ArgumentParser();p.add_argument('--restore',action='store_true');p.add_argument('--root',type=Path);a=p.parse_args()
here=Path(__file__).resolve().parent;manifest=json.loads((here/'manifest.json').read_text(encoding='utf-8'))
for f in manifest['files']:
 source=(here/f['path']).resolve()
 assert source.is_relative_to(here) and source.is_file(),f['path']
 assert hashlib.sha256(source.read_bytes()).hexdigest()==f['sha256'],'Checksum mismatch: '+f['path']
print('Verified: '+manifest['display_name'])
if a.restore:
 root=a.root.resolve() if a.root else next((x for x in here.parents if (x/'scripts/vscripts').is_dir() and (x/'panorama/src').is_dir()),None)
 assert root and (root/'scripts/vscripts').is_dir() and (root/'panorama/src').is_dir(),'Specify addon checkout with --root'
 backup=root/'output/title_restore_backups'/datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
 for f in manifest['files']:
  if f['role']!='title':continue
  target=(root/f['workspace_path']).resolve();assert target.is_relative_to(root)
  if target.exists():
   old=backup/f['workspace_path'];old.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(target,old)
  target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(here/f['path'],target)
 print('Title files restored. Previous files: '+str(backup))
 print('Shared archive/backend integration was preserved; use saved references to reconcile if it has changed.')
