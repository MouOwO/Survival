import urllib.request,zipfile,hashlib,json,time
from pathlib import Path
root=Path('output/video_shop_20261015/postgres_test');root.mkdir(parents=True,exist_ok=True)
url='https://get.enterprisedb.com/postgresql/postgresql-17.11-1-windows-x64-binaries.zip';archive=root/'postgresql-17.11.zip'
if not archive.exists():
 with urllib.request.urlopen(url,timeout=90) as src,archive.open('wb') as dst:
  while chunk:=src.read(4*1024*1024):dst.write(chunk)
print('POSTGRES_ARCHIVE_READY',archive.stat().st_size,flush=True)
target=(root/'portable').resolve();target.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive) as z:
 members=[e for e in z.infolist() if e.filename.startswith(('pgsql/bin/','pgsql/lib/','pgsql/share/')) and not e.is_dir()]
 for entry in members:
  dest=(target/entry.filename).resolve();assert target in dest.parents,'Unsafe archive target'
  if not dest.exists():
   dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(z.read(entry))
(root/'download.json').write_text(json.dumps({'source':url,'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'version':'17.11','files':len(members),'purpose':'Local loopback-only synthetic payment bundle tests; no OS service'},indent=2),encoding='utf8')
print('POSTGRES_PORTABLE_READY',target,flush=True)
