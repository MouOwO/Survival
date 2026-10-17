"""Install the exact remotely verified bundle; preserve unrelated local changes."""
from pathlib import Path,PurePosixPath
import hashlib,json,os,secrets

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/shop_catalog_20261016/release'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def replace(path,raw):
    temporary=path.with_name(path.name+'.shop-'+secrets.token_hex(5))
    try:
        temporary.write_bytes(raw);os.replace(temporary,path)
    finally:
        if temporary.exists():temporary.unlink()
def main():
    plan_raw=(OUT/'release_plan.json').read_bytes();plan=json.loads(plan_raw)
    verified=json.loads((ROOT/'design_refs/shop_catalog_20261016/deployment/verify.json').read_bytes())
    assert verified['status']=='VERIFIED' and verified['archive_bundle']==plan['candidate']
    assert verified['plan_sha256']==sha(plan_raw)
    assert verified['health']['archive']['ok'] and verified['health']['payment']['ok']
    assert verified['payment_catalog_hash']==plan['payment_catalog_hash']
    for name,digest in plan['local_input_hashes'].items():assert sha((ROOT/name).read_bytes())==digest,'local_input_changed:'+name
    candidate=OUT/'candidate'
    manifest=json.loads((OUT/'candidate_manifest.json').read_bytes())['files']
    for name,digest in manifest.items():
        p=PurePosixPath(name);assert not p.is_absolute() and '..' not in p.parts and name.startswith('addon/')
        assert sha((candidate/name).read_bytes())==digest
    pointers={}
    for name,digest in plan['old_game_pointer_sha256'].items():
        target=ROOT/name;raw=target.read_bytes();expected=(candidate/'addon'/name).read_bytes()
        assert sha(raw)==digest or raw==expected,'local_pointer_changed:'+name
        assert sha((OUT/'rollback_local'/name).read_bytes())==digest
        pointers[name]=(raw,expected)
    installed=[]
    for name,digest in manifest.items():
        relative=PurePosixPath(name).relative_to('addon')
        if str(relative).replace('\\','/') in pointers:continue
        path=ROOT.joinpath(*relative.parts);raw=(candidate/name).read_bytes()
        path.parent.mkdir(parents=True,exist_ok=True)
        assert not path.is_symlink()
        if path.exists():assert path.read_bytes()==raw,'immutable_local_file_changed:'+str(relative)
        else:
            with path.open('xb') as stream:stream.write(raw)
        installed.append(str(relative).replace('\\','/'))
    try:
        for name,(old,new) in pointers.items():replace(ROOT/name,new)
        for name,(_,new) in pointers.items():assert (ROOT/name).read_bytes()==new
        assert json.loads((ROOT/'server/bundles/current.json').read_bytes())['hash']==plan['candidate']
    except BaseException:
        for name,(old,_) in pointers.items():replace(ROOT/name,old)
        raise
    result={'status':'INSTALLED_AFTER_REMOTE_VERIFICATION','bundle':plan['candidate'],
      'previous_bundle':plan['base'],'installed_immutable_files':installed,
      'pointer_hashes':{name:sha((ROOT/name).read_bytes()) for name in pointers},
      'rollback_local':'design_refs/shop_catalog_20261016/release/rollback_local',
      'unrelated_source_or_git_changes':False,'new_match_required':True}
    (OUT/'local_installation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))
if __name__=='__main__':main()
