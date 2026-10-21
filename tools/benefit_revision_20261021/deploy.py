"""Narrow config-only welfare revision, pinned to the deployed 47acc release."""
from pathlib import Path
import argparse
import base64
import copy
import hashlib
import importlib.util
import io
import json
import sys
import tarfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tmp/benefit_revision_20261021/release_candidate'
OPERATOR=Path(__file__).with_name('remote_operator.py')
PARENT='47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e'
PARENT_RELEASE='20261021-benefits-47accd81d922'
PARENT_MANIFEST='39e845fd37a2966bbc57a616e661970a0736a0959ee9b00f2e1caf8ebdbae0fe'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
canonical=lambda value:json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
spec=importlib.util.spec_from_file_location('revision_pinned_transport',ROOT/'tools/archive_caps_20261020/remote_driver.py')
transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)


def fetch():
    source='PARENT='+repr(PARENT)+'\nRELEASE='+repr(PARENT_RELEASE)+'\nMANIFEST='+repr(PARENT_MANIFEST)+'\n'
    source+='''
from pathlib import Path
import base64,hashlib,json,sys,subprocess
root=Path('/opt/goufayu/releases/current').resolve(strict=True)
sha=lambda raw:hashlib.sha256(raw).hexdigest()
assert root.name==RELEASE
manifest=(root/'release_manifest.json').read_bytes();assert sha(manifest)==MANIFEST
data=json.loads(manifest)
for name,digest in data['files'].items():assert sha((root/name).read_bytes())==digest
bundle=(root/'addon/server/bundles'/PARENT/'bundle.json').read_bytes();assert sha(bundle)==PARENT
pay=Path('/opt/goufayu/payments/current').resolve()
assert pay.name=='20261018-checkout-gcoin-v1'
pid=subprocess.check_output(['systemctl','show','--property=MainPID','--value','goufayu-payment.service'],text=True).strip();assert pid=='5427'
sys.path.insert(0,str(pay))
from deploy import connection
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.info.dbname=='goufayu_test'
 sync=conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
 ledger=dict(conn.execute('SELECT migration_id,sha256 FROM _goufayu_migrations'))
 configs=dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM archive_config_sets"))
 functions={signature:sha(definition.encode()) for signature,definition in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'")}
 conn.rollback()
print(json.dumps(dict(ok=True,archive_release=RELEASE,archive_bundle=PARENT,archive_manifest_sha256=MANIFEST,manifest=data,bundle_b64=base64.b64encode(bundle).decode(),sync_definition=sync,sync_sha256=sha(sync.encode()),ledger=ledger,configs=configs,functions=functions,payment_release=pay.name,payment_manifest_sha256=sha((pay/'manifest.json').read_bytes()),payment_pid=pid)))
'''
    result=json.loads(transport.remote(source,timeout=110).strip().splitlines()[-1]);assert result.pop('ok')
    OUT.mkdir(parents=True,exist_ok=True)
    raw=base64.b64decode(result.pop('bundle_b64'),validate=True);assert sha(raw)==PARENT
    (OUT/'parent_bundle.json').write_bytes(raw);(OUT/'baseline.json').write_bytes(canonical(result))
    print(json.dumps(dict(ok=True,phase='BASELINE_FETCHED_READ_ONLY',bundle=PARENT,ledger_entries=len(result['ledger']),player_reads=0,writes=0)))


def build():
    sys.path.insert(0,str(ROOT/'server'))
    from archive_backend.bundle import read_csv
    baseline=json.loads((OUT/'baseline.json').read_bytes())
    parent=json.loads((OUT/'parent_bundle.json').read_bytes())
    source=ROOT/'data/csv/存档系统/archive_benefit_rewards.csv'
    raw=source.read_bytes().replace(b'\r\n',b'\n')
    approved=json.loads((OUT.parent/'backend_after.json').read_bytes())
    assert sha(source.read_bytes())==approved['hashes']['data/csv/存档系统/archive_benefit_rewards.csv']
    updated=read_csv(source);key=updated['key'];old={row[key]:row for row in parent['configs']['archive_benefit_rewards']['rows']};new={row[key]:row for row in updated['rows']}
    assert old.keys()==new.keys() and len(old)==19
    expected={entry['reward_id']:set(entry['fields']) for entry in approved['row_changes']}
    actual={identity:{field for field in old[identity].keys()|new[identity].keys() if old[identity].get(field)!=new[identity].get(field)} for identity in old if old[identity]!=new[identity]}
    assert actual==expected and len(actual)==9,'configuration_revision_scope_changed'
    candidate=copy.deepcopy(parent);candidate['configs']['archive_benefit_rewards']=updated
    candidate['csv_hashes']['data/csv/存档系统/archive_benefit_rewards.csv']=sha(raw)
    commands=sorted({kind for rule in candidate['compatible_config_hashes'].values() for kind in rule['commands']} - {'benefit_claim'})
    candidate['compatible_config_hashes'][PARENT]=dict(commands=commands,upgrade_commands=[])
    digest=sha(canonical(candidate));disabled=copy.deepcopy(candidate)
    for row in disabled['configs']['archive_benefit_rewards']['rows']:row['enabled']=False
    disabled['compatible_config_hashes'][digest]=dict(commands=commands,upgrade_commands=[])
    disabled_hash=sha(canonical(disabled))
    overlay={}
    for bundle,identity in ((candidate,digest),(disabled,disabled_hash)):
        directory=OUT/'bundles'/identity;directory.mkdir(parents=True,exist_ok=True)
        (directory/'bundle.json').write_bytes(canonical(bundle))
        overlay['addon/server/bundles/'+identity+'/bundle.json']=canonical(bundle)
        for name,value in bundle['sources'].items():
            path=directory/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(value.encode())
            overlay['addon/server/bundles/'+identity+'/'+name]=value.encode()
    overlay['addon/data/csv/存档系统/archive_benefit_rewards.csv']=raw
    plan={key:baseline[key] for key in ('archive_release','archive_bundle','archive_manifest_sha256','sync_sha256','ledger','configs','functions','payment_release','payment_manifest_sha256','payment_pid')}
    plan.update(bundle=digest,rollback_bundle=disabled_hash,new_release='20261021-benefit-revision-'+digest[:12],rollback_release='20261021-benefit-revision-safe-'+disabled_hash[:12],overlay={name:sha(value) for name,value in overlay.items()},row_changes=approved['row_changes'],migrations=[])
    files={'plan.json':canonical(plan),'remote_operator.py':OPERATOR.read_bytes(),**{'overlay/'+name:value for name,value in overlay.items()}}
    buffer=io.BytesIO()
    with tarfile.open(fileobj=buffer,mode='w:gz') as archive:
        for name,value in sorted(files.items()):
            entry=tarfile.TarInfo(name);entry.size=len(value);entry.mode=0o600;entry.mtime=0;archive.addfile(entry,io.BytesIO(value))
    archive_raw=buffer.getvalue();(OUT/'release.tar.gz').write_bytes(archive_raw);(OUT/'plan.json').write_bytes(files['plan.json'])
    seal=dict(stage='/root/goufayu_upload/benefit-revision-'+sha(files['plan.json'])[:16],plan_sha256=sha(files['plan.json']),archive_sha256=sha(archive_raw),files={name:sha(value) for name,value in files.items()})
    (OUT/'seal.json').write_bytes(canonical(seal))
    print(json.dumps(dict(ok=True,phase='SEALED_NOT_ACTIVATED',bundle=digest,rollback_bundle=disabled_hash,changed_rows=len(actual),changed_fields=sum(map(len,actual.values())),python_changed=False,lua_sources_changed=False)))


def execute(mode):
    seal=json.loads((OUT/'seal.json').read_bytes());assert sha(OPERATOR.read_bytes())==seal['files']['remote_operator.py'],'sealed_operator_changed'
    source='STAGE='+repr(seal['stage'])+'\nMODE='+repr(mode)+'\nEXPECTED='+repr(seal)+'\n'
    if mode=='prepare':
        raw=(OUT/'release.tar.gz').read_bytes();assert sha(raw)==seal['archive_sha256']
        source+='PAYLOAD='+repr(base64.b64encode(raw).decode())+'\n'
        source+='''
from pathlib import Path,PurePosixPath
import base64,hashlib,io,tarfile
root=Path(STAGE);assert root.parent==Path('/root/goufayu_upload') and not root.is_symlink()
root.mkdir(parents=True,exist_ok=True,mode=0o700);root.chmod(0o700)
raw=base64.b64decode(PAYLOAD,validate=True);assert hashlib.sha256(raw).hexdigest()==EXPECTED['archive_sha256']
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert len(members)==len(EXPECTED['files'])
 for member in members:
  name=PurePosixPath(member.name)
  assert member.isfile() and not name.is_absolute() and '..' not in name.parts and member.name in EXPECTED['files']
  value=archive.extractfile(member).read();assert hashlib.sha256(value).hexdigest()==EXPECTED['files'][member.name]
  target=root/member.name;assert not target.is_symlink();target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
  if target.exists():assert target.read_bytes()==value
  else:target.write_bytes(value)
  target.chmod(0o600)
'''
    source+='''
from pathlib import Path
import hashlib
root=Path(STAGE)
for name,digest in EXPECTED['files'].items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest
exec(compile((root/'remote_operator.py').read_bytes(),str(root/'remote_operator.py'),'exec'))
'''
    output=transport.remote(source,timeout=180 if mode=='activate' else 110)
    result=json.loads(output.strip().splitlines()[-1]);assert result['ok']
    (OUT/('remote_'+mode+'.json')).write_bytes(canonical(result));print(output.strip())


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('mode',choices=('fetch','build','prepare','validate','activate','verify','rollback-safe'))
    mode=parser.parse_args().mode
    fetch() if mode=='fetch' else build() if mode=='build' else execute(mode)
