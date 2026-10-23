"""Build a credentials-free guest bundle from the exact installed frozen stage."""
import argparse
import hashlib
import ipaddress
import json
from pathlib import Path
import shutil

import local_host as host


def build(destination,address):
    ip,port=address.rsplit(':',1)
    host.need(str(ipaddress.IPv4Address(ip))==ip and port=='27015','join_address_invalid')
    descriptor=host.STAGE/host.INSTALL_MANIFEST
    data=host.json_file(descriptor)
    base=host.baseline()
    expected=host.expected_manifest(base,host.overlay(base))
    host.need(data.get('kind')=='WS4-LOCAL-1' and data.get('base_content_sha256')==host.BASE_SHA
        and data.get('runtime')==expected,'guest_source_identity_changed')
    host.verify_stage(expected)
    host.need(not destination.exists(),'guest_bundle_already_exists')
    host.private_files.no_reparse(destination)
    destination.mkdir(parents=True)
    marker=descriptor.read_bytes()
    digest=hashlib.sha256(marker).hexdigest()
    (destination/'client_manifest.json').write_bytes(marker)
    addon=destination/host.ADDON;addon.mkdir()
    for row in expected['files']:
        name=row['path']
        host.need(name not in (host.PRIVATE_REL,host.INSTALL_MANIFEST),'private_file_in_runtime')
        path=addon/name;path.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(host.STAGE/name,path)
        host.need(host.runtime.checksums(path)=={k:row[k] for k in ('bytes','md5','sha256')},'guest_copy_checksum_failed')
    (addon/host.INSTALL_MANIFEST).write_bytes(marker)
    source=(host.HERE/'join_client.ps1').read_text(encoding='utf8')
    host.need(source.count('__MANIFEST_SHA256__')==1,'guest_manifest_pin_not_unique')
    (destination/'join_client.ps1').write_text(source.replace('__MANIFEST_SHA256__',digest),encoding='utf-8-sig')
    (destination/'加入测试.cmd').write_bytes((host.HERE/'launch_join.cmd').read_bytes())
    (destination/'server_address.txt').write_text(address+'\n',encoding='ascii')
    readme=('WS4 异地加入方客户端\n\n'
        '1. 本电脑保持 Steam 在线，使用四个测试账号之一；安装 Dota 2 Workshop Tools。\n'
        '2. 安装官方 Radmin VPN，使用作者另行提供的网络名称和密码加入同一私有网络。\n'
        '3. 将整个本文件夹复制到加入电脑，完整保留其中的 survival_ws4_local 子目录。\n'
        '4. 退出这台电脑上的 Dota 2，双击“加入测试.cmd”。首次将校验并安装约3.77GB的冻结测试副本。\n'
        '   若未找到 Dota，请按提示填写 dota 2 beta/game 的完整路径。\n'
        '5. 主机应重新使用“两人开局”入口，停在原生队伍设置；等两人都到齐后再开始并选模式。\n'
        '6. 加入方只连接主机，不创建自己的对局，不运行云端连接助手。\n\n'
        '默认主机地址：'+address+'\n'
        '需要切换主机地址时修改 server_address.txt，格式为 IPv4:27015。\n'
        '本包不含云端凭据、SSH密钥、Radmin网络密码、开发工具或玩家存档。\n'
        '首次异地两人入场尚待现场验证，不能把本包校验当成已经联机成功。\n')
    (destination/'使用说明.txt').write_text(readme,encoding='utf-8-sig')
    forbidden=host.PRIVATE_REL
    host.need(not (addon/forbidden).exists(),'guest_bundle_contains_session')
    report={'ok':True,'kind':'WS4-GUEST-1','runtime_files':expected['file_count'],'runtime_bytes':expected['bytes'],
        'runtime_content_sha256':expected['content_sha256'],'client_manifest_sha256':digest,
        'server_address':address,'cloud_credentials_in_bundle':False,'vpn_password_in_bundle':False,
        'native_remote_join_verified':False,'bundle_directory':str(destination)}
    host.runtime.atomic_write_json(destination/'bundle_info.json',report)
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination',type=Path,required=True)
    parser.add_argument('--server',required=True)
    args=parser.parse_args()
    print(json.dumps(build(args.destination.resolve(),args.server),ensure_ascii=False),flush=True)
