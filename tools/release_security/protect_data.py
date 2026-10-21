"""AES-256-GCM source vaults and detached Ed25519 release signatures.

Vaults are for source/configuration storage, not files for Dota's asset loader.
Use the separate Lua protection builder for runnable distribution copies.
Private keys and plaintext staging are kept outside the installed project.
"""
from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

ROOT=Path(__file__).resolve().parents[2]
INSTALL=ROOT.parents[2]
MAGIC=b'SURVIVAL-GCM-V1\x00'
DOMAIN=b'Survival.release-manifest.v2\x00'
VAULT_MANIFEST='_source_manifest.json'
CHUNK=1024*1024


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('ascii')


def linked(path):
    return path.is_symlink() or bool(getattr(path,'is_junction',lambda:False)())


def external(path, source=None):
    path=Path(path)
    if not path.is_absolute():raise ValueError('An explicit absolute external path is required')
    resolved=path.resolve()
    if resolved==INSTALL or INSTALL in resolved.parents:raise ValueError('Private backup/key path must be outside the game/content installation')
    if source:
        source=Path(source).resolve()
        if resolved==source or source in resolved.parents or resolved in source.parents:raise ValueError('Backup must be outside, and not an ancestor of, the source')
    parent=path
    while parent!=parent.parent:
        if parent.exists() and linked(parent):raise ValueError('Links and junctions are not allowed')
        parent=parent.parent
    return resolved


def restrict_directory(path):
    if os.name=='nt':
        who=subprocess.check_output(['whoami','/user','/fo','csv','/nh'],text=True)
        sid=next(csv.reader([who.strip()]))[1]
        result=subprocess.run(['icacls',str(path),'/inheritance:r','/grant:r',f'*{sid}:(OI)(CI)F','*S-1-5-18:(OI)(CI)F'],capture_output=True)
        if result.returncode:raise ValueError('Cannot restrict private directory ACL; no keys were written')
    else:path.chmod(0o700)


def private_directory(path):
    path.mkdir(parents=True,exist_ok=False)
    restrict_directory(path)


def write_new(path, data, mode=0o600):
    path=Path(path)
    descriptor=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,mode)
    with os.fdopen(descriptor,'wb') as stream:
        stream.write(data);stream.flush();os.fsync(stream.fileno())


def key_id(key):return hashlib.sha256(key).hexdigest()[:32]


def public_id(key):
    return key_id(key.public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw))


def initialize_keys(directory):
    directory=external(directory)
    if directory.exists():raise ValueError('Key directory already exists; keys are never overwritten')
    private_directory(directory)
    signing=Ed25519PrivateKey.generate()
    public=signing.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo)
    write_new(directory/'data-key.bin',os.urandom(32))
    write_new(directory/'signing-key.pem',signing.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    write_new(directory/'public-key.pem',public)
    metadata={'schema':1,'encryption':'AES-256-GCM','signature':'Ed25519','signing_key_id':public_id(signing.public_key()),'private_keys_must_not_be_bundled':True}
    write_new(directory/'key-info.json',canonical(metadata)+b'\n')
    return metadata


def raw_key(path):
    path=external(Path(path))
    if linked(path):raise ValueError('Key must not be a link')
    data=path.read_bytes()
    if len(data)!=32:raise ValueError('AES key must contain exactly 32 bytes')
    return data


def safe_name(name):
    if not isinstance(name,str) or name==VAULT_MANIFEST or not name or '\\' in name or ':' in name or any(ord(c)<32 for c in name) or name.startswith('/'):return False
    reserved={'CON','PRN','AUX','NUL','CONIN$','CONOUT$',*(f'COM{i}' for i in range(1,10)),*(f'LPT{i}' for i in range(1,10))}
    return all(p not in {'','.','..'} and not p.endswith(('.', ' ')) and p.split('.')[0].upper() not in reserved for p in name.split('/'))


def source_path(root,name):
    if not safe_name(name):raise ValueError('Unsafe source/archive path')
    path=root/name
    if not path.is_file() or linked(path) or root not in path.resolve().parents:raise ValueError('Source is absent or linked: '+name)
    parent=path.parent
    while parent!=root:
        if linked(parent):raise ValueError('Linked source directory: '+name)
        parent=parent.parent
    return path


def collect_sources(root,include_art=False):
    if not (root/'data/csv').is_dir():raise ValueError('Required CSV source directory is absent')
    selections=[('data/csv',{'.csv'}),('scripts/vscripts',{'.lua'}),('panorama/src',{'.js','.css','.xml'}),
                ('server',{'.py','.sql'}),('tools',{'.py','.lua','.cjs','.js','.ps1','.sh','.sql'})]
    if include_art:selections.append(('art/ui/sources',{'.png','.jpg','.jpeg','.tga','.webp','.svg','.vtex','.json','.txt'}))
    names=[]
    for folder,suffixes in selections:
        base=root/folder
        if not base.exists():continue
        def reject_walk_error(error):raise error
        for current,dirs,files in os.walk(base,followlinks=False,onerror=reject_walk_error):
            parent=Path(current)
            if linked(parent):raise ValueError('Linked source root')
            for directory in dirs:
                if linked(parent/directory):raise ValueError('Linked source directory')
            for filename in files:
                path=parent/filename
                if path.suffix.lower() in suffixes:names.append(path.relative_to(root).as_posix())
    return sorted(names)


def make_vault(root,names,destination,key_file):
    root=Path(root).resolve(strict=True);destination=external(destination,root);key=raw_key(key_file)
    if destination.exists():raise ValueError('Vault output already exists')
    if not names or len({n.casefold() for n in names})!=len(names):raise ValueError('Empty or duplicate source list')
    if sum(source_path(root,name).stat().st_size for name in names)>8*1024**3:raise ValueError('Source selection exceeds 8 GiB; split into separate vaults')
    if not destination.parent.exists():private_directory(destination.parent)
    # Plaintext compressed intermediates inherit this private directory ACL.
    with tempfile.TemporaryDirectory(prefix='.source-vault-',dir=destination.parent) as temporary:
        temporary=Path(temporary).resolve();assert temporary.parent==destination.parent
        restrict_directory(temporary)
        private_zip=temporary/'payload.zip';rows=[]
        with zipfile.ZipFile(private_zip,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as archive:
            for name in sorted(names):
                path=source_path(root,name);before=path.stat();md5=hashlib.md5(usedforsecurity=False);sha=hashlib.sha256();size=0
                with path.open('rb') as source,archive.open(name,'w',force_zip64=True) as target:
                    for chunk in iter(lambda:source.read(CHUNK),b''):
                        md5.update(chunk);sha.update(chunk);size+=len(chunk);target.write(chunk)
                after=path.stat()
                if (before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_ino,after.st_size,after.st_mtime_ns) or size!=after.st_size:raise ValueError('Source changed during backup: '+name)
                rows.append({'path':name,'bytes':size,'md5':md5.hexdigest(),'sha256':sha.hexdigest()})
            payload=canonical({'schema':1,'files':rows})
            if len(payload)>8*CHUNK:raise ValueError('Source manifest exceeds 8 MiB; split into separate vaults')
            archive.writestr(VAULT_MANIFEST,payload)
        nonce=os.urandom(12)
        header=canonical({'schema':1,'algorithm':'AES-256-GCM','purpose':'source_backup_not_game_runtime','nonce':base64.b64encode(nonce).decode('ascii'),'key_id':key_id(key),'manifest_sha256':hashlib.sha256(payload).hexdigest()})
        prefix=MAGIC+struct.pack('>I',len(header))+header
        encryptor=Cipher(algorithms.AES(key),modes.GCM(nonce)).encryptor();encryptor.authenticate_additional_data(prefix)
        encrypted=temporary/'encrypted.tmp'
        with private_zip.open('rb') as source,encrypted.open('xb') as target:
            target.write(prefix)
            for chunk in iter(lambda:source.read(CHUNK),b''):target.write(encryptor.update(chunk))
            target.write(encryptor.finalize());target.write(encryptor.tag);target.flush();os.fsync(target.fileno())
        # Same-volume, no-overwrite publication; no partially authenticated file.
        os.link(encrypted,destination)
    return {'files':len(rows),'source_bytes':sum(row['bytes'] for row in rows),'encrypted_bytes':destination.stat().st_size,'manifest_sha256':hashlib.sha256(payload).hexdigest(),'purpose':'source_backup_not_game_runtime'}


def checked_zip(path,header):
    with zipfile.ZipFile(path) as archive:
        entries=archive.infolist();names=[row.filename for row in entries]
        if len(names)!=len(set(n.casefold() for n in names)) or VAULT_MANIFEST not in names:raise ValueError('Duplicate or missing vault manifest')
        info=archive.getinfo(VAULT_MANIFEST)
        if info.file_size>8*CHUNK:raise ValueError('Vault manifest too large')
        payload=archive.read(VAULT_MANIFEST)
        if hashlib.sha256(payload).hexdigest()!=header['manifest_sha256']:raise ValueError('Vault manifest mismatch')
        manifest=json.loads(payload)
        if manifest.get('schema')!=1 or not isinstance(manifest.get('files'),list):raise ValueError('Invalid vault manifest')
        rows=manifest['files'];expected=[r['path'] for r in rows]
        if len(expected)!=len(set(n.casefold() for n in expected)) or set(names)!=set(expected)|{VAULT_MANIFEST}:raise ValueError('Vault file inventory mismatch')
        if sum(r['bytes'] for r in rows)>8*1024**3:raise ValueError('Vault exceeds verification size limit')
        for row in rows:
            name=row['path']
            if not safe_name(name):raise ValueError('Unsafe vault path')
            info=archive.getinfo(name)
            if stat.S_ISLNK(info.external_attr>>16) or info.file_size!=row['bytes']:raise ValueError('Invalid vault file type/size')
            hashes={'md5':hashlib.md5(usedforsecurity=False),'sha256':hashlib.sha256()}
            with archive.open(name) as source:
                for chunk in iter(lambda:source.read(CHUNK),b''):
                    for digest in hashes.values():digest.update(chunk)
            if any(digest.hexdigest()!=row[k] for k,digest in hashes.items()):raise ValueError('Vault content hash mismatch')
        return rows


def verify_vault(vault,key_file,restore=None):
    vault=external(vault);key=raw_key(key_file)
    restore=external(restore) if restore else None
    if restore and restore.exists():raise ValueError('Restore directory must be new; existing files are never overwritten')
    with tempfile.TemporaryDirectory(prefix='.vault-verify-',dir=key_file.parent) as temporary:
        temporary=Path(temporary).resolve();assert temporary.parent==key_file.parent.resolve()
        restrict_directory(temporary)
        plain=temporary/'authenticated.zip'
        with vault.open('rb') as source:
            magic=source.read(len(MAGIC));length_bytes=source.read(4)
            if magic!=MAGIC or len(length_bytes)!=4:raise ValueError('Invalid vault format')
            length=struct.unpack('>I',length_bytes)[0]
            if not 1<=length<=65536:raise ValueError('Invalid vault header size')
            raw=source.read(length);header=json.loads(raw)
            if header.get('schema')!=1 or header.get('algorithm')!='AES-256-GCM' or header.get('purpose')!='source_backup_not_game_runtime' or header.get('key_id')!=key_id(key):raise ValueError('Vault algorithm/key mismatch')
            nonce=base64.b64decode(header['nonce'],validate=True)
            if len(nonce)!=12:raise ValueError('Invalid GCM nonce')
            offset=source.tell();remaining=vault.stat().st_size-offset-16
            if remaining<0:raise ValueError('Truncated vault')
            source.seek(-16,2);tag=source.read(16);source.seek(offset)
            decryptor=Cipher(algorithms.AES(key),modes.GCM(nonce,tag)).decryptor();decryptor.authenticate_additional_data(MAGIC+length_bytes+raw)
            with plain.open('xb') as target:
                while remaining:
                    chunk=source.read(min(CHUNK,remaining))
                    if not chunk:raise ValueError('Truncated ciphertext')
                    target.write(decryptor.update(chunk));remaining-=len(chunk)
                target.write(decryptor.finalize())
        rows=checked_zip(plain,header)
        if restore:
            restore.parent.mkdir(parents=True,exist_ok=True)
            with tempfile.TemporaryDirectory(prefix='.source-restore-',dir=restore.parent) as pending:
                pending=Path(pending).resolve();assert pending.parent==restore.parent
                restrict_directory(pending)
                with zipfile.ZipFile(plain) as archive:
                    for row in rows:
                        target=pending/row['path'];target.parent.mkdir(parents=True,exist_ok=True)
                        with archive.open(row['path']) as source,target.open('xb') as output:shutil.copyfileobj(source,output,CHUNK)
                if restore.exists():raise ValueError('Restore destination appeared; refusing to overwrite')
                # Windows rename refuses an existing target. Publish only the
                # complete authenticated tree; failures leave no final tree.
                pending.rename(restore)
        return {'verified':True,'files':len(rows),'bytes':sum(r['bytes'] for r in rows),'restored_to':str(restore) if restore else None}


def release_api():
    spec=importlib.util.spec_from_file_location('runtime_release',ROOT/'tools/build_runtime_release.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def sign_manifest(manifest,key_file,signature,sequence=1):
    if type(sequence) is not int or not 1<=sequence<2**64:raise ValueError('Invalid release sequence')
    data=json.loads(Path(manifest).read_text('utf-8'));api=release_api();api.validate_manifest(data)
    signing=serialization.load_pem_private_key(external(key_file).read_bytes(),password=None)
    if not isinstance(signing,Ed25519PrivateKey):raise ValueError('Expected Ed25519 private key')
    public=signing.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo)
    document={'schema':2,'algorithm':'Ed25519','key_id':public_id(signing.public_key()),'release_sequence':sequence,'content_sha256':data['content_sha256'],'signature':base64.b64encode(signing.sign(DOMAIN+struct.pack('>Q',sequence)+api.manifest_payload(data))).decode('ascii')}
    write_new(signature,canonical(document)+b'\n')
    return {'signed':True,'key_id':document['key_id'],'content_sha256':data['content_sha256']}


def verify_signature(manifest,signature,public_key,minimum_sequence=1):
    data=json.loads(Path(manifest).read_text('utf-8'));document=json.loads(Path(signature).read_text('utf-8'));api=release_api();api.validate_manifest(data)
    public=Path(public_key).read_bytes();key=serialization.load_pem_public_key(public)
    sequence=document.get('release_sequence')
    if type(minimum_sequence) is not int or minimum_sequence<1 or type(sequence) is not int or not minimum_sequence<=sequence<2**64:raise ValueError('Release sequence is below the trusted minimum or invalid')
    if not isinstance(key,Ed25519PublicKey) or document.get('schema')!=2 or document.get('algorithm')!='Ed25519' or document.get('key_id')!=public_id(key) or document.get('content_sha256')!=data['content_sha256']:raise ValueError('Signature identity mismatch')
    key.verify(base64.b64decode(document['signature'],validate=True),DOMAIN+struct.pack('>Q',sequence)+api.manifest_payload(data))
    return {'signature_valid':True,'key_id':public_id(key),'content_sha256':data['content_sha256'],'release_sequence':sequence}


def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='action',required=True)
    init=sub.add_parser('init-keys');init.add_argument('--directory',type=Path,required=True)
    vault=sub.add_parser('vault');vault.add_argument('--output',type=Path,required=True);vault.add_argument('--key',type=Path,required=True);vault.add_argument('--include-source-art',action='store_true')
    verify=sub.add_parser('verify-vault');verify.add_argument('--vault',type=Path,required=True);verify.add_argument('--key',type=Path,required=True);verify.add_argument('--restore',type=Path)
    sign=sub.add_parser('sign');sign.add_argument('--manifest',type=Path,required=True);sign.add_argument('--key',type=Path,required=True);sign.add_argument('--signature',type=Path,required=True);sign.add_argument('--sequence',type=int,required=True)
    signature=sub.add_parser('verify-signature');signature.add_argument('--manifest',type=Path,required=True);signature.add_argument('--signature',type=Path,required=True);signature.add_argument('--public-key',type=Path,required=True);signature.add_argument('--minimum-sequence',type=int,required=True)
    args=parser.parse_args()
    try:
        if args.action=='init-keys':result=initialize_keys(args.directory)
        elif args.action=='vault':result=make_vault(ROOT,collect_sources(ROOT,args.include_source_art),args.output,args.key)
        elif args.action=='verify-vault':result=verify_vault(args.vault,args.key,args.restore)
        elif args.action=='sign':result=sign_manifest(args.manifest,args.key,args.signature,args.sequence)
        else:result=verify_signature(args.manifest,args.signature,args.public_key,args.minimum_sequence)
    except Exception as error:
        print('Protection failed: '+type(error).__name__+': '+str(error),file=sys.stderr);return 1
    print(json.dumps(result,ensure_ascii=False));return 0


if __name__=='__main__':raise SystemExit(main())
