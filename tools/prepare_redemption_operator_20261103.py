"""Create a separate eight-resource candidate recipe; never edit frozen0204."""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT/'tools/lottery_replay_release_20261102'
NEW=ROOT/'tools/lottery_redemption_release_20261103'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
def once(text,old,new):
    assert text.count(old)==1,(old,text.count(old))
    return text.replace(old,new,1)
def blob(path):
    return subprocess.check_output(['git','show','14812ec239d3dd24634b9b860b81e35a9a9fd721:'+path],cwd=ROOT)
def main():
    assert not NEW.exists() or not any(NEW.iterdir())
    names=('adapt','build_release','ledger','release_checks','rehearsal','verify_download','native_admission','validator')
    files={n:(OLD/(n+'.py')).read_text('utf8') for n in names}
    for n,text in files.items():
        for before,after in (
            ('lottery_replay_release_20261102','lottery_redemption_release_20261103'),
            ('lottery_replay_rehearsal_20261102','lottery_redemption_rehearsal_20261103'),
            ('20261102_ws4_lottery_replay_v11','20261103_ws4_lottery_redemption_v12'),
            ('2026110204','2026110301'),('svt_lr0204','svt_lc0301')):
            text=text.replace(before,after)
        files[n]=text
    cache='panorama/scripts/custom_game/common/lottery_cache.vjs_c'
    author='panorama/src/scripts/custom_game/common/lottery_cache.js'
    physical=(ROOT/author).read_bytes();git=blob(author)
    assert physical==git.replace(b'\n',b'\r\n')
    pin=dict(source=author,content_source='panorama/scripts/custom_game/common/lottery_cache.js',
        source_git_sha256=sha(git),source_sha256=sha(physical),
        source_normalization='GIT_LF_TO_COMPILER_CRLF_ONLY',compiled_sha256=sha(blob(cache)))
    b=files['build_release']
    b=once(b,"impl.REVISION='WS4-LOTTERY-REPLAY-RECEIPT-04'","impl.REVISION='WS4-LOTTERY-REDEMPTION-REFRESH-01'")
    b=once(b,"'b6e7c3f542d111e1eaceeb1414632fb50ecb1d2ad410ced17d84f3c506a743e3'",repr(sha(blob('scripts/vscripts/systems/lottery_http_service.lua'))))
    insert=("CACHE="+repr(cache)+"\nimpl.PAYLOADS=(*impl.PAYLOADS[:2],CACHE,*impl.PAYLOADS[2:])\n"
        "impl.COMPILED[CACHE]="+repr(pin)+"\n"
        "a.function(impl,'compiled_pins_ready',[(\"PAYLOADS[:2]\",\"PAYLOADS[:3]\"),(\"})==2\",\"})==3\")])\n"
        "impl.FROZEN_V09_OUTPUTS=(*impl.FROZEN_V09_OUTPUTS,\n"
        " *(Path('D:/Survival_发布候选')/('20261102_ws4_lottery_replay_v11'+s) for s in ('_overlay','_view','_trusted_source','_unsigned_review')),\n"
        " Path('D:/Survival_工坊输出/20261102_ws4_lottery_replay_v11'))\n")
    b=once(b,'impl.AUXILIARY_INPUTS=tuple',insert+'impl.AUXILIARY_INPUTS=tuple')
    b=once(b,",'backend_deploy.py'",'')
    b=once(b,'payload_count=7','payload_count=8')
    files['build_release']=b
    files['ledger']=once(files['ledger'],"len(result['changed_runtime_paths'])==7","len(result['changed_runtime_paths'])==8")
    files['release_checks']=once(files['release_checks'],"[\n    ('BUILT_SIGNED", "[\n    ('len(source_bindings)==2','len(source_bindings)==3'),\n    ('BUILT_SIGNED")
    files['rehearsal']=once(files['rehearsal'],'scoped_runtime_paths=7','scoped_runtime_paths=8')
    files['verify_download']=files['verify_download'].replace("'len(b.PAYLOADS) == 7'","'len(b.PAYLOADS) == 8'").replace('scoped_runtime_paths=7','scoped_runtime_paths=8')
    n=files['native_admission']
    n=once(n,'impl.need(len(b.PAYLOADS)==7','impl.need(len(b.PAYLOADS)==8')
    n=once(n,'set(b.PAYLOADS[:2]) and len(b.COMPILED)==2','set(b.PAYLOADS[:3]) and len(b.COMPILED)==3')
    n=once(n,"'len(b.PAYLOADS)==7'","'len(b.PAYLOADS)==8'")
    files['native_admission']=n
    native_sha=sha(n.encode())
    v=files['validator']
    v=once(v,'f1e88a6f688bd7c3256bde1b1e20b9f4e6faf93c81e21b6fee3f3763aed3482c',native_sha)
    v=once(v,'    "scripts/vscripts/systems/lottery_http_service.lua",\\n))',
        '    "scripts/vscripts/systems/lottery_http_service.lua",\\n    "'+cache+'",\\n))')
    v=once(v,')\nfor old, new in TRANSFORMS:',
        "    ('len(report.get(\"source_artifact_pins\", {})) == 2', 'len(report.get(\"source_artifact_pins\", {})) == 3'),\n)\nfor old, new in TRANSFORMS:")
    v=v.replace('seven-resource','eight-resource').replace('two-compiled, twenty-two-review','three-compiled, twenty-two-review')
    files['validator']=v
    NEW.mkdir(exist_ok=True)
    for n,text in files.items():
        compile(text,str(NEW/(n+'.py')),'exec')
        (NEW/(n+'.py')).write_text(text,encoding='utf8',newline='\n')
    policy=json.loads((ROOT/'publishing/workshop/release_authority_lottery_replay_20261102.json').read_bytes())
    for key,value in list(policy.items()):
        if isinstance(value,str):policy[key]=value.replace('lottery_replay_release_20261102','lottery_redemption_release_20261103')
    for prefix in ('validator','recipe','rehearsal','download','native_admission'):
        policy[prefix+'_sha256']=sha(Path(policy[prefix+'_path']).read_bytes())
    policy.update(release_sequence=2026110301,scope='LOTTERY_REDEMPTION_REFRESH_EIGHT_RESOURCES')
    policy['required_feature_ancestors']={'game':['14812ec239d3dd24634b9b860b81e35a9a9fd721'],'content':['a9590039044285dd96ca056a720747973f16cf2c']}
    p=ROOT/'publishing/workshop/release_authority_lottery_redemption_20261103.json'
    assert not p.exists();p.write_text(json.dumps(policy,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
    print(json.dumps(dict(status='NEW_OPERATOR_SOURCES_ONLY',authority_sha256=sha(p.read_bytes()),native_sha256=native_sha,files=len(files),cache_binding=pin)))
if __name__=='__main__':main()
