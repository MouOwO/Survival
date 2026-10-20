"""Install the exact verified server bundle into the game; preserve unrelated edits."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import os
import shutil

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/points_goods_unique_20261018/release'
plan=json.loads((OUT/'plan.json').read_bytes())
assert plan['status']=='SEALED_NOT_DEPLOYED'
digest=plan['bundle']
source=OUT/'candidate/addon/server/bundles'/digest
raw=(source/'bundle.json').read_bytes()
assert hashlib.sha256(raw).hexdigest()==digest
data=json.loads(raw)
pointers=['server/bundles/current.json','scripts/vscripts/config/generated/archive_http_bundle.lua']
assert all(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==plan['local_pointer_sha256'][name] for name in pointers),'local_pointer_changed'
backup=OUT/'local_before_install'
backup.mkdir(exist_ok=True)
for name in pointers:
    saved=backup/name
    saved.parent.mkdir(parents=True,exist_ok=True)
    assert not saved.exists(),'local_install_already_started'
    shutil.copyfile(ROOT/name,saved)
destination=ROOT/'server/bundles'/digest
destination.mkdir(exist_ok=True)
for name,text in data['sources'].items():
    relative=PurePosixPath(name)
    assert not relative.is_absolute() and '..' not in relative.parts and '\\' not in name
    assert (source/name).read_text('utf-8')==text
    target=destination/name
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists():assert target.read_text('utf-8')==text
    else:shutil.copyfile(source/name,target)
target=destination/'bundle.json'
if target.exists():assert target.read_bytes()==raw
else:shutil.copyfile(source/'bundle.json',target)
for name in pointers:
    reviewed=(OUT/'candidate/addon'/name).read_bytes()
    temporary=(ROOT/name).with_suffix('.points-unique.tmp')
    assert not temporary.exists()
    temporary.write_bytes(reviewed)
    os.replace(temporary,ROOT/name)
report={'status':'LOCAL_VERIFIED_BUNDLE_INSTALLED','bundle':digest,'pointer_files':pointers,'backup':str(backup)}
(OUT/'local_install.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
