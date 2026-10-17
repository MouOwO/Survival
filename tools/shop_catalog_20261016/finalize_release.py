"""Finalize the reviewed archive-only overlay, without activating any pointer.

PostgreSQL computes the exact jsonb fingerprint in a read-only transaction.
The SQL exception admits one exact configuration and preserves every old guard.
"""
from pathlib import Path
import hashlib,io,json,shutil,subprocess,tarfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/shop_catalog_20261016/release'
DEPLOY=ROOT/'design_refs/shop_catalog_20261016/deployment'

def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf-8')
def main():
    plan=json.loads((OUT/'release_plan.json').read_bytes())
    preflight=json.loads((DEPLOY/'preflight.json').read_bytes())
    configuration=json.loads((OUT/'archive_config.json').read_bytes())
    candidate=plan['candidate_hash'];base=plan['base_hash']
    code='''from pathlib import Path
import hashlib,json,sys
p=Path('/opt/goufayu/payments/current').resolve(strict=True)
a=Path('/opt/goufayu/releases/current').resolve(strict=True)
sys.path.insert(0,str(p));from deploy import connection
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 cfg_sha=c.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(CONFIG,)).fetchone()[0]
 definition=c.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
 catalog=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 c.rollback()
print(json.dumps({'cfg_pg_sha256':cfg_sha,'old_release':str(a),'payment_release':str(p),
 'old_sync_function':hashlib.sha256(definition.encode()).hexdigest(),'payment_catalog_hash':catalog,
 'bundle':json.loads((a/'addon/server/bundles/current.json').read_bytes())['hash']}))
'''
    code='CONFIG='+repr(canonical(configuration).decode('utf-8'))+'\n'+code
    opts=['ssh.exe','-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
      '-o','HostKeyAlgorithms=ssh-ed25519','-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts',
      '-o','IdentitiesOnly=yes','-o','ConnectTimeout=10','-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2'),
      'root@47.110.238.248','/opt/goufayu/payments/current/.venv/bin/python -B -']
    result=subprocess.run(opts,input=code.encode('utf-8'),capture_output=True,cwd=ROOT,timeout=90,
      creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (DEPLOY/'configuration_fingerprint.stderr.txt').write_bytes(result.stderr)
    if result.returncode:raise RuntimeError('readonly_fingerprint_failed:'+str(result.returncode))
    remote=json.loads(result.stdout)
    expected={'old_release':plan['old_archive_release'],'payment_release':plan['old_payment_release'],
      'old_sync_function':plan['old_sync_definition_sha256'],'payment_catalog_hash':plan['payment_catalog_hash'],'bundle':base}
    assert all(remote[k]==v for k,v in expected.items()),'running_baseline_changed'
    old=preflight['function_definitions']['public.archive_sync_config(text,jsonb)']
    marker=' -- Reviewed wife collection:'
    assert old.count(marker)==1 and sha(old.encode())==plan['old_sync_definition_sha256']
    branch=""" -- Reviewed shop catalog: one exact immutable target, no reducer changes.
 if p_hash='%s' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then
   raise exception 'archive_shop_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
"""%(candidate,remote['cfg_pg_sha256'])
    new=old.replace(marker,branch+marker,1);new_sha=sha(new.encode('utf-8'))
    assert new.replace(branch,'',1)==old
    guard="""-- Exact reviewed definition only; preserve ownership, ACL and search_path.
DO $shop_guard$
BEGIN
 IF encode(sha256(convert_to(pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure),'UTF8')),'hex')
    NOT IN ('%s','%s') THEN
  RAISE EXCEPTION 'archive_shop_function_baseline_changed';
 END IF;
END;
$shop_guard$;
"""%(sha(old.encode()),new_sha)
    sql=(guard+new.rstrip()+';\n').encode('utf-8')
    payload=OUT/'payload';payload.mkdir(exist_ok=True)
    sources=OUT/'candidate/addon/server/bundles'/candidate
    assert sha((sources/'bundle.json').read_bytes())==candidate
    dest=payload/'bundle'/candidate;dest.mkdir(parents=True,exist_ok=True)
    for path in sources.rglob('*'):
        if path.is_file():
            target=dest/path.relative_to(sources);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
    shutil.copyfile(OUT/'archive_config.json',payload/'configuration.json')
    (payload/'upgrade_archive_shop_compat.sql').write_bytes(sql)
    for name in ['test_archive_shop_compat.py','smoke.py']:shutil.copyfile(ROOT/'tools/shop_catalog_20261016'/name,payload/name)
    files={p.relative_to(payload).as_posix():sha(p.read_bytes()) for p in payload.rglob('*') if p.is_file()}
    expected_files={'bundle/'+candidate+'/'+p.relative_to(sources).as_posix() for p in sources.rglob('*') if p.is_file()}
    expected_files|={'configuration.json','upgrade_archive_shop_compat.sql','test_archive_shop_compat.py','smoke.py'}
    assert set(files)==expected_files,'unexpected_payload_file'
    archive=OUT/'overlay.tar.gz'
    with tarfile.open(archive,'w:gz') as tar:
        for name in sorted(files):
            raw=(payload/name).read_bytes();info=tarfile.TarInfo(name);info.size=len(raw);info.mode=0o600;info.mtime=0
            tar.addfile(info,io.BytesIO(raw))
    plan.update(version=1,kind='shop_catalog_points_only',base=base,candidate=candidate,
      old_release=plan['old_archive_release'],old_manifest=plan['old_archive_manifest_sha256'],
      old_service=plan['old_service_sha256'],payment_release=plan['old_payment_release'],
      payment_manifest=plan['old_payment_manifest_sha256'],payment_enabled_products=44,
      old_sync_function=sha(old.encode()),new_sync_function=new_sha,cfg_pg_sha256=remote['cfg_pg_sha256'],
      tar_sha256=sha(archive.read_bytes()),files=files,status='READY_FOR_BACKED_UP_SERVER_VALIDATION')
    (OUT/'release_plan.json').write_bytes(canonical(plan))
    (OUT/'configuration_fingerprint.json').write_bytes(canonical(remote))
    (OUT/'archive_sync_config_before.sql').write_text(old,encoding='utf-8')
    (OUT/'archive_sync_config_after.sql').write_text(new,encoding='utf-8')
    print(json.dumps({k:plan[k] for k in ['status','base','candidate','cfg_pg_sha256','new_sync_function','tar_sha256']}))
    print(json.dumps({'payload_files':len(files),'bytes':archive.stat().st_size,'server_transaction':'READ ONLY','server_mutations':0}))
if __name__=='__main__':main()
