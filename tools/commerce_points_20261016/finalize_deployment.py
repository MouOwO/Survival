"""Synchronize local game pointers only after verified remote activation.

No global bundle build, no alteration of unrelated working-tree configuration.
Copies exact approved immutable bytes and preserves both previous pointers.
"""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,os

ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'design_refs/commerce_points_20261016/deployment'
RELEASE=ROOT/'design_refs/commerce_points_20261016/release/archive-commerce-points-caf4493bb7ad'
BEFORE='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
AFTER='caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59'
def sha(raw):return hashlib.sha256(raw).hexdigest()

def main():
    activated=json.loads((REPORT/'activate.json').read_text('utf-8'))
    verified=json.loads((REPORT/'verify.json').read_text('utf-8'))
    assert activated['status']=='DEPLOYED' and verified['status']=='VERIFIED'
    assert activated['archive_bundle']==verified['archive_bundle']==AFTER
    manifest=json.loads((RELEASE/'manifest.json').read_text('utf-8'))
    for name,digest in manifest['files'].items():assert sha((RELEASE/name).read_bytes())==digest,name
    plan=json.loads((RELEASE/'release_plan.json').read_text('utf-8'))
    # Repeated execution verifies the completed transition without restoring old bytes.
    done=REPORT/'local_activation.json'
    if done.exists():
        record=json.loads(done.read_text('utf-8'))
        assert record['new_bundle']==AFTER
        for name,entry in record['pointers'].items():assert sha((ROOT/name).read_bytes())==entry['new_sha256']
        print(json.dumps(record,ensure_ascii=False));return
    for name,digest in plan['input_hashes'].items():assert sha((ROOT/name).read_bytes())==digest,'local_input_changed:'+name
    source=RELEASE/'candidate/addon/server/bundles'/AFTER
    data=json.loads((source/'bundle.json').read_bytes())
    for name in ['systems/commerce_settlement.lua','systems/lottery_http_settlement.lua']:
        assert (ROOT/'scripts/vscripts'/name).read_text('utf-8-sig')==data['sources'][name],name
    target=ROOT/'server/bundles'/AFTER
    assert target.resolve().is_relative_to(ROOT.resolve()) and not target.is_symlink()
    for path in source.rglob('*'):
        assert not path.is_symlink()
        if path.is_file():
            destination=target/path.relative_to(source);destination.parent.mkdir(parents=True,exist_ok=True)
            assert not destination.is_symlink()
            if destination.exists():assert destination.read_bytes()==path.read_bytes(),str(destination)
            else:
                with destination.open('xb') as stream:stream.write(path.read_bytes())
    pointers={'server/bundles/current.json':RELEASE/'candidate/addon/server/bundles/current.json',
        'scripts/vscripts/config/generated/archive_http_bundle.lua':RELEASE/'candidate/addon/scripts/vscripts/config/generated/archive_http_bundle.lua'}
    saved=REPORT/'local_pointer_backup';saved.mkdir(exist_ok=True);record={}
    for name,candidate in pointers.items():
        destination=ROOT/name;old=destination.read_bytes();raw=candidate.read_bytes()
        assert BEFORE.encode() in old and AFTER.encode() in raw,name
        backup=saved/('server_current.json' if name.endswith('.json') else 'archive_http_bundle.lua')
        if backup.exists():assert backup.read_bytes()==old
        else:
            with backup.open('xb') as stream:stream.write(old)
        record[name]={'previous_sha256':sha(old),'new_sha256':sha(raw),'backup':backup.relative_to(ROOT).as_posix()}
    for name,candidate in pointers.items():
        destination=ROOT/name;temporary=destination.with_name(destination.name+'.commerce-points-next')
        assert not temporary.exists() and not temporary.is_symlink()
        with temporary.open('xb') as stream:stream.write(candidate.read_bytes())
        os.replace(temporary,destination)
    result={'status':'LOCAL_GAME_HASH_UPDATED','at_utc':datetime.now(timezone.utc).isoformat(),'previous_bundle':BEFORE,'new_bundle':AFTER,'pointers':record,
        'unrelated_configuration_rebuilt':False,'old_bundle_retained':(ROOT/'server/bundles'/BEFORE/'bundle.json').is_file(),'requires_new_map':True,'game_validation':False}
    done.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf-8')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
