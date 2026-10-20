"""Install the exact verified server bundle into the game; preserve unrelated edits."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import os
import re
import shutil

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/points_daily_unique_20261019/release_v3'
plan=json.loads((OUT/'plan.json').read_bytes())
assert plan['status']=='SEALED_NOT_DEPLOYED'
digest=plan['bundle']
source=OUT/'candidate/addon/server/bundles'/digest
raw=(source/'bundle.json').read_bytes()
assert hashlib.sha256(raw).hexdigest()==digest
data=json.loads(raw)
pointers=['server/bundles/current.json','scripts/vscripts/config/generated/archive_http_bundle.lua']
before={name:(ROOT/name).read_bytes() for name in pointers}
pointer_equivalence=[]
for name,original in before.items():
    if hashlib.sha256(original).hexdigest()==plan['local_pointer_sha256'][name]:continue
    # Other local work changed the generated header. Accept only the same
    # literal parent pointer, with no additional Lua statements.
    assert name.endswith('archive_http_bundle.lua'),'local_pointer_changed'
    code='\n'.join(line for line in original.decode('utf-8-sig').splitlines() if not line.lstrip().startswith('--')).strip()
    match=re.fullmatch(r'return\s*\{\s*protocol\s*=\s*1\s*,\s*hash\s*=\s*"([0-9a-f]{64})"\s*\}',code)
    assert match and match[1]==plan['parent_bundle'],'local_pointer_changed'
    pointer_equivalence.append({'file':name,'before_sha256':hashlib.sha256(original).hexdigest(),'reason':'Only generated header/line endings changed; exact literal parent pointer verified'})
backup=OUT/'local_before_install'
backup.mkdir(exist_ok=True)
for name in pointers:
    assert (ROOT/name).read_bytes()==before[name],'local_pointer_changed_during_install'
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
report={'status':'LOCAL_VERIFIED_BUNDLE_INSTALLED','bundle':digest,'pointer_files':pointers,'backup':str(backup),'pointer_equivalence':pointer_equivalence}
(OUT/'local_install.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
