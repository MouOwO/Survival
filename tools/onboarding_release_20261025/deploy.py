"""Sealed onboarding deployment using the established pinned SSH transport.

Only the user-approved test game backend is changed. Backup copies on this
Windows host use DPAPI; account rows and credentials never enter task output.
"""
from pathlib import Path, PurePosixPath
import argparse
import base64
import ctypes
from ctypes import wintypes
import hashlib
import importlib.util
import io
import json
import os
import tarfile

ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / 'tmp/onboarding_rollout_20261025'
OUT = HOME / 'candidate'
OPERATOR = Path(__file__).with_name('remote_operator.py')
PROBE = Path(__file__).with_name('runtime_probe.py')
sha = lambda raw: hashlib.sha256(raw).hexdigest()
canonical = lambda data: json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
spec = importlib.util.spec_from_file_location('onboarding_pinned_transport', ROOT / 'tools/archive_caps_20261020/remote_driver.py')
transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)


def seal():
    files = {'plan.json': (OUT / 'plan.json').read_bytes(), 'remote_operator.py': OPERATOR.read_bytes(), 'runtime_probe.py': PROBE.read_bytes()}
    plan = json.loads(files['plan.json'])
    for folder, key in (('overlay', 'overlay'), ('safe_overlay', 'safe_overlay')):
        for name, digest in plan[key].items():
            raw = (OUT / folder / name).read_bytes()
            assert sha(raw) == digest, 'overlay_source_changed'
            files[folder + '/' + name] = raw
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
        for name, raw in sorted(files.items()):
            entry = tarfile.TarInfo(name); entry.size = len(raw); entry.mode = 0o600; entry.mtime = 0
            archive.addfile(entry, io.BytesIO(raw))
    raw = buffer.getvalue()
    value = dict(stage='/root/goufayu_upload/onboarding-20261025-' + sha(canonical({name:sha(value) for name,value in files.items()}))[:16],
                 archive_sha256=sha(raw), files={name:sha(content) for name, content in files.items()}, plan_sha256=sha(files['plan.json']))
    (OUT / 'release.tar.gz').write_bytes(raw); (OUT / 'seal.json').write_bytes(canonical(value))
    print(json.dumps(dict(ok=True, phase='SEALED_NOT_ACTIVATED', release=plan['new_release'], files=len(files))))


def source_for(mode, sealed):
    source = 'STAGE=' + repr(sealed['stage']) + '\nMODE=' + repr(mode) + '\nEXPECTED=' + repr(sealed) + '\n'
    if mode == 'prepare':
        raw = (OUT / 'release.tar.gz').read_bytes(); assert sha(raw) == sealed['archive_sha256']
        source += 'PAYLOAD=' + repr(base64.b64encode(raw).decode()) + '\n'
        source += r'''
from pathlib import Path,PurePosixPath
import base64,hashlib,io,tarfile
root=Path(STAGE)
assert root.parent==Path('/root/goufayu_upload') and not root.is_symlink() and not root.exists()
root.mkdir(mode=0o700,parents=True)
raw=base64.b64decode(PAYLOAD,validate=True)
assert hashlib.sha256(raw).hexdigest()==EXPECTED['archive_sha256']
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert len(members)==len(EXPECTED['files'])
 for entry in members:
  name=PurePosixPath(entry.name)
  assert entry.isfile() and not name.is_absolute() and '..' not in name.parts and entry.name in EXPECTED['files']
  value=archive.extractfile(entry).read();assert hashlib.sha256(value).hexdigest()==EXPECTED['files'][entry.name]
  target=root/entry.name;target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
  with target.open('xb') as output:output.write(value)
  target.chmod(0o600)
'''
    source += r'''
from pathlib import Path
import hashlib
root=Path(STAGE)
for name,digest in EXPECTED['files'].items():
 p=root/name
 assert not p.is_symlink() and hashlib.sha256(p.read_bytes()).hexdigest()==digest
exec(compile((root/'remote_operator.py').read_bytes(),str(root/'remote_operator.py'),'exec'))
'''
    return source


class Blob(ctypes.Structure):
    _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_ubyte))]


def dpapi(raw, decrypt=False):
    assert os.name == 'nt', 'windows_dpapi_required'
    buffer = ctypes.create_string_buffer(raw)
    incoming = Blob(len(raw), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    outgoing = Blob()
    crypt = ctypes.WinDLL('crypt32', use_last_error=True)
    crypt.CryptProtectData.argtypes = [ctypes.POINTER(Blob), wintypes.LPCWSTR, ctypes.POINTER(Blob), wintypes.LPVOID, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(Blob)]
    crypt.CryptProtectData.restype = wintypes.BOOL
    crypt.CryptUnprotectData.argtypes = [ctypes.POINTER(Blob), ctypes.POINTER(wintypes.LPWSTR), ctypes.POINTER(Blob), wintypes.LPVOID, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(Blob)]
    crypt.CryptUnprotectData.restype = wintypes.BOOL
    if decrypt:
        ok = crypt.CryptUnprotectData(ctypes.byref(incoming), None, None, None, None, 1, ctypes.byref(outgoing))
    else:
        ok = crypt.CryptProtectData(ctypes.byref(incoming), 'Survival onboarding deployment backup', None, None, None, 1, ctypes.byref(outgoing))
    if not ok:
        raise RuntimeError('encrypted_backup_protection_failed')
    try:
        return ctypes.string_at(outgoing.data, outgoing.size)
    finally:
        free = ctypes.WinDLL('kernel32', use_last_error=True).LocalFree
        free.argtypes = [wintypes.HLOCAL]; free.restype = wintypes.HLOCAL
        free(ctypes.cast(outgoing.data, wintypes.HLOCAL))


def protected_backup(sealed, record):
    source = 'STAGE=' + repr(sealed['stage']) + '\n'
    source += r'''
from pathlib import Path
import json,base64,hashlib
root=Path(STAGE);record=json.loads((root/'private_backup.json').read_bytes());p=Path(record['path'])
assert p.parent==Path('/var/backups/goufayu-payment') and not p.is_symlink() and p.stat().st_size==record['size']
raw=p.read_bytes();assert len(raw)<32*1024*1024 and hashlib.sha256(raw).hexdigest()==record['sha256']
print(json.dumps(dict(ok=True,backup_b64=base64.b64encode(raw).decode())))
'''
    response = json.loads(transport.remote(source, timeout=60).strip().splitlines()[-1])
    raw = base64.b64decode(response['backup_b64'], validate=True)
    assert sha(raw) == record['sha256'], 'downloaded_backup_digest_mismatch'
    protected = dpapi(raw)
    assert sha(dpapi(protected, decrypt=True)) == record['sha256'], 'encrypted_backup_roundtrip_failed'
    dest = HOME / ('database-' + record['sha256'][:16] + '.dump.dpapi')
    with dest.open('xb') as output:
        output.write(protected)
    ack = dict(ok=True, encrypted_verified=True, sha256=record['sha256'], encrypted_sha256=sha(protected), encrypted_size=len(protected), local_path=str(dest.relative_to(ROOT)))
    (HOME / 'protected_backup.json').write_bytes(canonical(ack))
    source = 'STAGE=' + repr(sealed['stage']) + '\nACK=' + repr(ack) + '\n'
    source += r'''
from pathlib import Path
import json
root=Path(STAGE);saved=json.loads((root/'private_backup.json').read_bytes())
assert saved['sha256']==ACK['sha256'] and ACK['encrypted_verified'] is True
p=root/'offsite_ack.json'
with p.open('xb') as output:output.write(json.dumps(ACK,sort_keys=True,separators=(',',':')).encode())
p.chmod(0o600)
print(json.dumps(dict(ok=True,phase='OFFSITE_ENCRYPTED_BACKUP_VERIFIED')))
'''
    acknowledged = json.loads(transport.remote(source, timeout=45).strip().splitlines()[-1])
    assert acknowledged['ok']
    return acknowledged


def execute(mode):
    sealed = json.loads((OUT / 'seal.json').read_bytes())
    assert sha(OPERATOR.read_bytes()) == sealed['files']['remote_operator.py'], 'sealed_operator_changed'
    assert sha(PROBE.read_bytes()) == sealed['files']['runtime_probe.py'], 'sealed_probe_changed'
    try:
        output = transport.remote(source_for(mode, sealed), timeout=110)
        result = json.loads(output.strip().splitlines()[-1]); assert result['ok'], 'remote_action_failed'
        (OUT / ('remote_' + mode + '.json')).write_bytes(canonical(result))
        print(json.dumps(result, ensure_ascii=False))
        if mode == 'backup':
            ack = protected_backup(sealed, result)
            print(json.dumps(ack))
    except Exception:
        if mode == 'backup':
            # Backups and offsite transfer must never strand the old service.
            recovery = transport.remote(source_for('resume', sealed), timeout=60)
            (OUT / 'backup_recovery.json').write_text(recovery, encoding='utf-8')
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('seal', 'prepare', 'validate', 'backup', 'resume', 'activate', 'verify', 'rollback-safe'))
    mode = parser.parse_args().mode
    seal() if mode == 'seal' else execute(mode)
