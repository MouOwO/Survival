"""Build and verify a legacy ZIP patch from a pinned frozen-resource audit."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import local_host as host

MANIFEST_SHA256='2be968c893f4584fc65438fff696e541fc92f86f2ccd66d50bd48641c365ceda'


def build(bundle,audit_path,archive,include=()):
    descriptor=bundle/'client_manifest.json'
    host.private_files.no_reparse(descriptor)
    host.need(hashlib.sha256(descriptor.read_bytes()).hexdigest()==MANIFEST_SHA256,'patch_manifest_identity_changed')
    manifest=host.json_file(descriptor)
    host.need(manifest.get('kind')=='WS4-LOCAL-1' and manifest.get('base_content_sha256')==host.BASE_SHA,'patch_base_identity_changed')
    host.runtime.validate_manifest(manifest['runtime'])
    known={row['path']:row for row in manifest['runtime']['files']}
    audit=host.json_file(audit_path)
    issues=audit.get('issues',[])
    host.need(audit.get('status')=='CLIENT_RESOURCE_AUDIT_COMPLETE' and audit.get('files')==len(known)
        and audit.get('issue_count')==len(issues),'patch_audit_incomplete')
    selected=set(include)
    for issue in issues:
        name=issue.get('path')
        host.need(isinstance(name,str) and name in known,'patch_unknown_resource')
        selected.add(name)
    host.need(bool(selected) and selected<=known.keys(),'patch_unknown_resource')
    rows=[known[name] for name in sorted(selected)]
    # Even without compression, keep payload and ZIP headers below signed 2 GiB.
    host.need(sum(row['bytes'] for row in rows)+len(rows)*2048+16*1024*1024<2**31,'patch_requires_multiple_archives')
    host.need(not archive.exists(),'patch_archive_already_exists')
    host.private_files.no_reparse(archive)
    metadata={}
    source=(host.HERE/'join_client.ps1').read_text(encoding='utf-8-sig')
    host.need(source.count('__MANIFEST_SHA256__')==1,'patch_script_pin_invalid')
    metadata['join_client.ps1']=b'\xef\xbb\xbf'+source.replace('__MANIFEST_SHA256__',MANIFEST_SHA256).encode('utf8')
    for target,source_name in (('加入测试.cmd','launch_join.cmd'),('join_game.cmd','launch_join.cmd'),('check_resources.cmd','audit_client.cmd')):
        metadata[target]=(host.HERE/source_name).read_bytes()
    metadata['server_address.txt']=b'26.34.7.221:27015\n'
    inventory={'kind':'WS4-RESOURCE-PATCH-1','client_manifest_sha256':MANIFEST_SHA256,'files':rows}
    metadata['patch_inventory.json']=json.dumps(inventory,ensure_ascii=False,indent=2).encode('utf8')
    metadata['修复说明.txt']=('\ufeff将本包完整解压到客户端根目录，例如D:\\WS4，允许覆盖同名冻结资源。\n'
        f'本包一次补齐{len(rows)}份资源，均已按固定清单核对。不要revert源码或关闭资源校验。\n'
        '压缩包使用常规ZIP且小于2GB，不使用ZIP64；请等待解压完成。\n'
        '然后运行check_resources.cmd，等待全部资源扫描完成；异常0份后再运行join_game.cmd。\n'
        '如仍有异常，提供client_resource_audit.json。保留旧目录，待新副本通过后再处理。\n').encode('utf8')
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=1,allowZip64=False) as target:
        for row in rows:
            path=bundle/host.ADDON/row['path']
            host.private_files.no_reparse(path)
            host.need(host.runtime.checksums(path)=={key:row[key] for key in ('bytes','md5','sha256')},'patch_source_bytes_changed')
            target.write(path,host.ADDON+'/'+row['path'])
        for name,raw in metadata.items():target.writestr(name,raw)
    # CRC alone can validate an empty entry. Compare every decompressed byte
    # with the pinned size and hashes as well, including all launcher metadata.
    expected={host.ADDON+'/'+row['path']:row for row in rows}
    expected.update({name:{'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()} for name,raw in metadata.items()})
    with zipfile.ZipFile(archive) as source:
        host.need(set(source.namelist())==set(expected) and len(source.infolist())==len(expected),'patch_archive_layout_changed')
        for name,row in expected.items():
            digest=hashlib.sha256();size=0
            with source.open(name) as stream:
                for block in iter(lambda:stream.read(8*1024*1024),b''):digest.update(block);size+=len(block)
            host.need(size==row['bytes'] and digest.hexdigest()==row['sha256'],'patch_archive_bytes_changed')
    digest=hashlib.sha256()
    with archive.open('rb') as stream:
        for block in iter(lambda:stream.read(8*1024*1024),b''):digest.update(block)
    return {'ok':True,'archive':str(archive),'archive_bytes':archive.stat().st_size,'archive_sha256':digest.hexdigest(),
        'resources':len(rows),'resource_bytes':sum(row['bytes'] for row in rows),'all_entry_hashes_verified':True,'legacy_zip_without_zip64':True}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle',type=Path,required=True)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--include',action='append',default=[])
    args=parser.parse_args()
    result=build(args.bundle,args.audit,args.archive,args.include)
    host.runtime.atomic_write_json(args.archive.with_suffix('.report.json'),result)
    print(json.dumps(result,ensure_ascii=False),flush=True)
