"""Publish the accepted EXE to a new immutable static download directory.

Uses the existing production SSH pin and existing nginx static root. Never
reloads nginx, changes API code, edits databases or modifies any game package.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REMOTE = '/var/www/xiaofengnet.com/launcher'
URL = 'https://xiaofengnet.com/launcher/'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def committed(relative):
    revision = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD']).decode().strip()
    raw = subprocess.check_output(['git', '-C', str(ROOT), 'show', revision + ':' + relative])
    if raw.replace(b'\r\n', b'\n') != (ROOT / relative).read_bytes().replace(b'\r\n', b'\n'):
        raise RuntimeError('uncommitted_download_operator')
    return revision, raw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-receipt', type=Path, required=True)
    parser.add_argument('--acceptance-receipt', type=Path, required=True)
    parser.add_argument('--acceptance-sha', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    build = json.loads(args.build_receipt.read_bytes())
    acceptance = json.loads(args.acceptance_receipt.read_bytes())
    if (sha(args.acceptance_receipt) != args.acceptance_sha or
            acceptance.get('user_confirmed_entered_game') is not True or
            acceptance.get('exe_sha256') != build['exe_sha256']):
        raise RuntimeError('accepted_exact_exe_required')
    version = build['binding']['version']
    if version != '2026.11.19.1': raise RuntimeError('reviewed_version_required')
    revision, template = committed('tools/player_launcher/download.html')
    committed('tools/player_launcher/publish_download.py')
    out = args.output.resolve()
    if ROOT == out or ROOT in out.parents: raise RuntimeError('external_output_required')
    out.mkdir(parents=True, exist_ok=False)
    files = {}
    exe = Path(build['exe']); archive = Path(build['archive'])
    if sha(exe) != build['exe_sha256'] or sha(archive) != build['archive_sha256']:
        raise RuntimeError('build_artifact_changed')
    for file in sorted(exe.parent.iterdir()):
        if file.name not in (exe.name, 'SHA256SUMS.txt', '使用说明.txt', 'version.json'):
            raise RuntimeError('unexpected_distribution_file')
        files[file.name] = file
    files[archive.name] = archive
    text = template.decode('utf-8')
    for key, value in {'VERSION':version, 'EXE':exe.name, 'SIZE':f'{exe.stat().st_size/1000000:.1f}',
                       'SHA256':build['exe_sha256']}.items():
        text = text.replace('@@' + key + '@@', value)
    if '@@' in text: raise RuntimeError('page_placeholder_unfilled')
    page = out / 'index.html'; page.write_text(text, encoding='utf-8')
    planned = dict(kind='ACCEPTED_PLAYER_DOWNLOAD_STATIC_PUBLICATION', artifact_root=str(out),
                   at_utc=datetime.now(timezone.utc).isoformat(), operator_revision=revision,
                   build_receipt_sha256=sha(args.build_receipt), acceptance_sha256=args.acceptance_sha,
                   version=version, exe_sha256=build['exe_sha256'], url=URL,
                   files={name:dict(sha256=sha(path), bytes=path.stat().st_size) for name,path in files.items()},
                   index_sha256=sha(page), api_code_changed=False, nginx_reloaded=False)
    (out / 'plan.json').write_text(json.dumps(planned, sort_keys=True)+'\n')
    if not args.apply:
        print(json.dumps(dict(status='STATIC_DOWNLOAD_PLAN_ONLY', plan=str(out/'plan.json')))); return
    sys.path.insert(0, str(ROOT/'tools/archive_caps_20261020'))
    import remote_driver as driver
    # Refuse overwrites. An interrupted publication must be reconciled explicitly.
    payload = dict(root=REMOTE, version=version, files=planned['files'], index_sha256=sha(page))
    setup = '''from pathlib import Path
import json,os
p=Path(P['root']);v=p/P['version']
assert p.parent==Path('/var/www/xiaofengnet.com')
assert not p.is_symlink() and not p.exists(), 'existing_download_requires_review'
p.mkdir(mode=0o755);v.mkdir(mode=0o755)
print(json.dumps({'stage_created':True}))
'''
    driver.remote('P='+repr(payload)+'\n'+setup)
    (out / 'intent.json').write_text(json.dumps(dict(payload=payload, upload_started=True))+'\n')
    for name, path in files.items():
        driver.run(['scp.exe', *driver.OPTIONS, str(path), driver.HOST + ':' + REMOTE + '/' + version + '/' + name], timeout=120)
    driver.run(['scp.exe', *driver.OPTIONS, str(page), driver.HOST + ':' + REMOTE + '/index.html.pending'], timeout=60)
    check = '''from pathlib import Path
import hashlib,json,os
p=Path(P['root']);v=p/P['version']
assert {f.name for f in v.iterdir()}==set(P['files'])
for name,f in P['files'].items():
 q=v/name; assert not q.is_symlink() and q.stat().st_size==f['bytes'] and hashlib.sha256(q.read_bytes()).hexdigest()==f['sha256'];q.chmod(0o644)
q=p/'index.html.pending';assert hashlib.sha256(q.read_bytes()).hexdigest()==P['index_sha256'];q.chmod(0o644)
os.rename(q,p/'index.html')
print(json.dumps({'all_remote_bytes_verified':True,'index_published':True}))
'''
    result = json.loads(driver.remote('P='+repr(payload)+'\n'+check))
    receipt = dict(planned, remote_verified=result, status='STATIC_FILES_PUBLISHED_NEEDS_PUBLIC_HTTPS_READBACK')
    (out/'publication_receipt.json').write_text(json.dumps(receipt,sort_keys=True)+'\n')
    print(json.dumps(dict(status=receipt['status'], url=URL, receipt=str(out/'publication_receipt.json'))))


if __name__=='__main__':main()
