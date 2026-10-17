"""Install the verified immutable bundle without rewriting unrelated configs."""
from pathlib import Path,PurePosixPath
import hashlib,json,os,secrets
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/shop_functional_20261016/release_v2'
DEPLOY=ROOT/'design_refs/shop_functional_20261016/deployment_v2'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def atomic(path,raw):
    tmp=path.with_name(path.name+'.functional-'+secrets.token_hex(5))
    tmp.write_bytes(raw);os.replace(tmp,path)
def main():
    plan_raw=(OUT/'release_plan.json').read_bytes();p=json.loads(plan_raw)
    verify=json.loads((DEPLOY/'verify.json').read_bytes())
    assert verify['status']=='VERIFIED' and verify['plan_sha256']==sha(plan_raw)
    assert verify['archive_bundle']==p['candidate'] and verify['payment_catalog_hash']==p['cash_hash']
    assert all(h['ok'] for h in verify['health'].values())
    for n,h in p['input_hashes'].items():assert sha((ROOT/n).read_bytes())==h,'input_drift:'+n
    bundle=OUT/'candidate/addon/server/bundles'/p['candidate'];data=json.loads((bundle/'bundle.json').read_bytes())
    assert sha((bundle/'bundle.json').read_bytes())==p['candidate']
    for n,s in data['sources'].items():assert (bundle/n).read_bytes()==s.encode('utf8')
    pointers={}
    for n,h in p['pointer_hashes'].items():
        raw=(ROOT/n).read_bytes();new=(OUT/'candidate/addon'/n).read_bytes()
        assert sha(raw)==h or raw==new,'concurrent_pointer_change:'+n
        assert sha((OUT/'rollback_local'/n).read_bytes())==h
        pointers[n]=(raw,new)
    installed=[]
    for path in bundle.rglob('*'):
        if not path.is_file():continue
        relative=PurePosixPath(path.relative_to(bundle).as_posix());assert '..' not in relative.parts
        target=ROOT/'server/bundles'/p['candidate']/str(relative)
        target.parent.mkdir(parents=True,exist_ok=True);raw=path.read_bytes()
        assert not target.is_symlink()
        if target.exists():assert target.read_bytes()==raw,'immutable_local_file_changed'
        else:
            with target.open('xb') as f:f.write(raw)
        installed.append(target.relative_to(ROOT).as_posix())
    try:
        for n,(old,new) in pointers.items():atomic(ROOT/n,new)
        assert json.loads((ROOT/'server/bundles/current.json').read_bytes())['hash']==p['candidate']
    except BaseException:
        for n,(old,new) in pointers.items():atomic(ROOT/n,old)
        raise
    result={'status':'INSTALLED_AFTER_REMOTE_VERIFICATION','bundle':p['candidate'],'previous_bundle':p['base'],
      'files':installed,'pointers':list(pointers),'new_match_required':True,'unrelated_sources_changed':False}
    (OUT/'local_installation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'status':result['status'],'bundle':p['candidate'],'immutable_files':len(installed),'new_match_required':True}))
if __name__=='__main__':main()
