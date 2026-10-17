"""Pin the exact SQL configuration; package immutable public overlays."""
from pathlib import Path
import hashlib,importlib.util,io,json,shutil,tarfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/shop_functional_20261016/release'
spec=importlib.util.spec_from_file_location('transport',ROOT/'tools/shop_catalog_20261016/deploy_driver.py')
transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
transport.REPORT=ROOT/'design_refs/shop_functional_20261016/deployment'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(d):return json.dumps(d,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def main():
    plan=json.loads((OUT/'release_plan.json').read_bytes());cfg=json.loads((OUT/'archive_config.json').read_bytes())
    code='CONFIG='+repr(canonical(cfg).decode())+'\n'+'''from pathlib import Path
import hashlib,json,sys
p=Path('/opt/goufayu/payments/current').resolve();a=Path('/opt/goufayu/releases/current').resolve()
sys.path.insert(0,str(p));from deploy import connection
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 cfg=c.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(CONFIG,)).fetchone()[0]
 f=c.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
 cash=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0];c.rollback()
print(json.dumps({'cfg':cfg,'sync':hashlib.sha256(f.encode()).hexdigest(),'archive':str(a),'payment':str(p),'cash':cash}))
'''
    result=transport.remote('fingerprint',code)
    assert result['archive']==plan['old_release'] and result['payment']==plan['old_payment'] and result['sync']==plan['old_sync'] and result['cash']==plan['old_cash_hash']
    old=json.loads((transport.REPORT/'preflight.json').read_bytes())['function_definitions']['public.archive_sync_config(text,jsonb)']
    marker=' -- Reviewed wife collection:';assert old.count(marker)==1
    branch=""" -- Reviewed functional commerce: exact immutable target, existing reducers retained.
 if p_hash='%s' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then
   raise exception 'archive_functional_commerce_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
"""%(plan['candidate'],result['cfg'])
    new=old.replace(marker,branch+marker,1);assert new.replace(branch,'',1)==old
    plan['new_sync']=sha(new.encode());plan['cfg_pg_sha']=result['cfg']
    payload=OUT/'payload';payload.mkdir(parents=True,exist_ok=True)
    bundle=OUT/'candidate/addon/server/bundles'/plan['candidate']
    shutil.copytree(bundle,payload/'bundle'/plan['candidate'],dirs_exist_ok=True)
    shutil.copytree(OUT/'payment_reference',payload/'payment_reference',dirs_exist_ok=True)
    for name in ['payment_package.json','archive_config.json']:
        shutil.copyfile(OUT/name,payload/name)
    (payload/'upgrade.sql').write_text(new.rstrip()+';\n',encoding='utf8')
    for name in ['smoke.py','test_functional_catalog_database.py']:
        shutil.copyfile(ROOT/'tools/shop_functional_20261016'/name,payload/name)
    plan['files']={p.relative_to(payload).as_posix():sha(p.read_bytes()) for p in payload.rglob('*') if p.is_file()}
    with tarfile.open(OUT/'overlay.tar.gz','w:gz') as tar:
        for name in sorted(plan['files']):
            raw=(payload/name).read_bytes();info=tarfile.TarInfo(name);info.mode=0o600;info.mtime=0;info.size=len(raw);tar.addfile(info,io.BytesIO(raw))
    plan['tar_sha256']=sha((OUT/'overlay.tar.gz').read_bytes())
    (OUT/'release_plan.json').write_bytes(canonical(plan))
    (OUT/'archive_sync_config_before.sql').write_text(old,encoding='utf8')
    (OUT/'archive_sync_config_after.sql').write_text(new,encoding='utf8')
    print(json.dumps({'candidate':plan['candidate'],'cash_hash':plan['cash_hash'],'payload_files':len(plan['files']),'tar_sha256':plan['tar_sha256'],'mutations':0}))
if __name__=='__main__':main()
