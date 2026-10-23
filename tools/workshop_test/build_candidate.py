"""Patch the authenticated frozen v02 release with only reviewed ws4 transport.

Preserves every protected table, resource and gameplay module. UI is compiled
from its original reviewed source plus the fingerprint message; today's later
gameplay/UI work is not pulled into the frozen test release.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import stream_workshop_vpk as pack

BASE='4edea828552ee522bc19bcfaa1c2a8ea14172d2b'
ORIGINAL=Path('D:/Survival_发布候选/20261022_four_accounts_v02')
CONTENT=ROOT.parents[2]/'content/dota_addons/Survival'
PROFILE='scripts/vscripts/systems/player_profile_service.lua'
PROFILE_HASH='ad2ba8edf96c45f8730df8f1d5289414f8e4f1a3bd05cd95827c9dc690e39a86'
OLD_CONTENT='1c09e562ada4586ba4c046616e94317bf062c308a0c0c507e5af59d7b9024b6d'
SEQUENCE=2026102301
lf=lambda b:b.replace(b'\r\n',b'\n')
crlf=lambda b:lf(b).replace(b'\n',b'\r\n')
sha=lambda b:hashlib.sha256(b).hexdigest()


def git(commit,name):
    return subprocess.check_output(['git','show',commit+':'+name],cwd=ROOT)


def change(raw,before,after):
    assert raw.count(before)==1,'Nonunique reviewed patch context'
    return raw.replace(before,after,1)


def build(args):
    commit=subprocess.check_output(['git','rev-parse',args.reviewed_commit],cwd=ROOT,text=True).strip()
    for path in (args.destination,args.trusted_source,args.output_dir):
        path=path.resolve()
        assert not pack.runtime.within(path,pack.handoff.INSTALL)
    targets=[p.resolve() for p in (args.destination,args.trusted_source,args.output_dir)]
    for index,path in enumerate(targets):
        for other in targets[index+1:]:
            assert not pack.runtime.within(path,other) and not pack.runtime.within(other,path)
    key=pack.protect_data.external(args.signing_key)
    assert all(not pack.runtime.within(key,path) for path in targets)
    assert not args.destination.exists() and not args.trusted_source.exists()
    assert args.output_dir.is_dir() and not list(args.output_dir.iterdir())
    manifest=pack.handoff.load_json(ORIGINAL/pack.handoff.MANIFEST)
    document=pack.handoff.load_json(ORIGINAL/pack.handoff.SIGNATURE)
    policy,public=pack.handoff.trusted_policy()
    pack.verify_signed_snapshot(manifest,document,public,policy['integrity']['minimum_release_sequence'],
                                policy['integrity']['trusted_key_id'])
    assert manifest['content_sha256']==OLD_CONTENT and pack.runtime.verify(ORIGINAL,manifest)['ok']
    patches={}
    for name in ('scripts/vscripts/config/workshop_connection.lua','scripts/vscripts/systems/workshop_connection.lua',
                 'scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua'):
        patches[name]=git(commit,name)
    name='scripts/vscripts/config/workshop_connection.lua'
    patches[name]=change(patches[name],b'enabled = false',b'enabled = true')
    addition=(b'    if reason:match("^workshop_pairing_[0-9a-f]+$") and #reason == 33 then return reason end\n'
        b'    if reason == "workshop_server_key_unavailable" or reason == "workshop_dedicated_server_required"\n'
        b'        or reason == "workshop_connection_invalid" or reason == "workshop_server_not_authorized" then\n'
        b'        return "backend_authentication_failed"\n    end\n')
    startup='scripts/vscripts/systems/startup_loading_service.lua'
    assert addition in lf(git(commit,startup))
    old_startup=crlf(git(BASE,startup))
    assert (ORIGINAL/startup).read_bytes()==old_startup
    patches[startup]=crlf(change(lf(old_startup),b'    reason = tostring(reason or "")\n',
                                b'    reason = tostring(reason or "")\n'+addition))
    args.destination.mkdir(parents=True)
    for row in manifest['files']:
        dest=args.destination/row['path']
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ORIGINAL/row['path'],dest)
    for name,raw in patches.items():
        target=args.destination/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(raw)
    ui_additions={
        'startup_loading.js':('        var preparationError = state && errorMessages[state.error] || "准备尚未完成，请重试。";',
            '        var pairing = state && typeof state.error === "string" && state.error.match(/^workshop_pairing_([0-9a-f]{16})$/);\n'
            '        if (pairing) preparationError = "测试服务器首次接入，请将认证指纹 " + pairing[1] + " 发给作者完成配对。";'),
        'survival_ui.js':('        var text = !profilesReady() && code ? messages[code] || "玩家档案暂未准备完成，请重试。" : "";',
            '        var pairing = typeof code === "string" && code.match(/^workshop_pairing_([0-9a-f]{16})$/);\n'
            '        if (!profilesReady() && pairing) text = "测试服务器首次接入，认证指纹：" + pairing[1] + "，请联系作者完成配对。";')}
    compiler=ROOT.parents[1]/'bin/win64/resourcecompiler.exe'
    provenance={'reviewed_commit':commit,'original_content_sha256':OLD_CONTENT,'unchanged_gameplay':True,'sources':{}}
    for name,(anchor,addition) in ui_additions.items():
        relative='panorama/src/scripts/custom_game/'+name
        current=lf(git(commit,relative)).decode('utf8')
        assert addition in current
        source=lf(git(BASE,relative)).decode('utf8')
        assert source.count(anchor)==1
        patched=source.replace(anchor,anchor+'\n'+addition,1).encode('utf8')
        content=CONTENT/'panorama/scripts/custom_game'/name
        compiled=ROOT/'panorama/scripts/custom_game'/name.replace('.js','.vjs_c')
        before_source,before_binary=content.read_bytes(),compiled.read_bytes()
        try:
            content.write_bytes(patched)
            result=subprocess.run([str(compiler),'-i',str(content),'-fshallow','-nop4'],capture_output=True)
            (ROOT/'output/workshop_auth_20261023'/('frozen_compile_'+name+'.log')).write_bytes(result.stdout+result.stderr)
            assert result.returncode==0 and b'1 compiled, 0 failed' in result.stdout
            target=args.destination/compiled.relative_to(ROOT)
            target.write_bytes(compiled.read_bytes())
            patches[compiled.relative_to(ROOT).as_posix()]=target.read_bytes()
            provenance['sources'][relative]={'base_commit':BASE,'base_sha256':sha(source.encode()),'patched_sha256':sha(patched)}
        finally:
            content.write_bytes(before_source)
            compiled.write_bytes(before_binary)
    args.trusted_source.mkdir(parents=True)
    for name in pack.handoff.GATE_FILES:
        if name==PROFILE:
            raw=(ROOT/'output/four_accounts_20261022/frozen_packager'/name).read_bytes()
            assert sha(raw)==PROFILE_HASH
        else:
            raw=git(BASE,name)
            raw=lf(raw) if name.endswith('/test_access_policy.lua') else crlf(raw)
        assert raw==(ORIGINAL/name).read_bytes()
        if name in patches:raw=patches[name]
        target=args.trusted_source/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(raw)
    for name in ('tools/release_security/protection_policy.json','tools/release_security/trusted_public_key.pem'):
        target=args.trusted_source/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(git(commit,name))
    new_manifest=pack.runtime.manifest(args.destination)
    old_by_path={row['path']:row for row in manifest['files']}
    changed=[]
    for row in new_manifest['files']:
        old=old_by_path.get(row['path'])
        if old is None or old['sha256']!=row['sha256']:
            assert row['path'] in patches,'Unreviewed runtime change'
            changed.append({'path':row['path'],'previous_sha256':old['sha256'] if old else None,'sha256':row['sha256']})
    assert len(changed)==len(patches)==6 and new_manifest['file_count']==manifest['file_count']+2
    for name in patches:
        if name.endswith('.lua'):
            subprocess.run(['C:/Program Files/lua/bin/luac5.1.exe','-p',str(args.destination/name)],check=True,capture_output=True)
    for name in ('_lua_protection_report.json','_snapshot_provenance.json'):
        if (ORIGINAL/name).is_file():shutil.copyfile(ORIGINAL/name,args.destination/name)
    pack.runtime.atomic_write_json(args.destination/pack.handoff.MANIFEST,new_manifest)
    pack.protect_data.sign_manifest(args.destination/pack.handoff.MANIFEST,args.signing_key,
                                    args.destination/pack.handoff.SIGNATURE,SEQUENCE)
    assert pack.runtime.verify(args.destination,new_manifest)['ok']
    provenance.update(content_sha256=new_manifest['content_sha256'],release_sequence=SEQUENCE,changed=changed,
                      protected_modules_preserved=180,private_key_copied=False)
    pack.runtime.atomic_write_json(args.destination/'_ws4_patch_provenance.json',provenance)
    pack.handoff.ROOT=args.trusted_source
    pack.handoff.POLICY=args.trusted_source/'tools/release_security/protection_policy.json'
    result=pack.package(args.destination,args.output_dir,'3824360109',build=True)
    pack.runtime.atomic_write_json(ROOT/'output/workshop_auth_20261023/build.json',result)
    pack.runtime.atomic_write_json(ROOT/'output/workshop_auth_20261023/candidate_provenance.json',provenance)
    print(json.dumps({'status':result['status'],'release_sequence':SEQUENCE,
        'content_sha256':new_manifest['content_sha256'],'changed_files':len(changed),'files':new_manifest['file_count']}))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reviewed-commit',required=True)
    parser.add_argument('--destination',type=Path,required=True)
    parser.add_argument('--trusted-source',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--signing-key',type=Path,required=True)
    build(parser.parse_args())


if __name__=='__main__':main()
