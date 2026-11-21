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
import re
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
    parser.add_argument('--project', type=Path, default=ROOT,
                        help='Actual release checkout when publishing from an isolated worktree')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--expected-index-sha', help='Exact current index SHA256 required for a later version')
    args = parser.parse_args()
    build = json.loads(args.build_receipt.read_bytes())
    acceptance = json.loads(args.acceptance_receipt.read_bytes())
    if sha(args.acceptance_receipt) != args.acceptance_sha:
        raise RuntimeError('accepted_exact_exe_required')
    from acceptance import verify
    acceptance_stage = verify(build, acceptance)
    project = args.project.resolve(strict=True)
    common = ['rev-parse', '--path-format=absolute', '--git-common-dir']
    if subprocess.check_output(['git', '-C', str(ROOT), *common], timeout=30) != subprocess.check_output(['git', '-C', str(project), *common], timeout=30):
        raise RuntimeError('release_checkout_must_share_launcher_repository')
    from distribution import inspect_public, release_identity, verify_binding
    committed('tools/player_launcher/distribution.py')
    expected = release_identity(project)
    if not verify_binding(build['binding'], expected):
        raise RuntimeError('launcher_must_match_current_official_workshop_download')
    version = build['binding']['version']
    if not re.fullmatch(r'[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,4}', version):
        raise RuntimeError('reviewed_version_required')
    if args.expected_index_sha is not None and not re.fullmatch(r'[a-f0-9]{64}', args.expected_index_sha):
        raise RuntimeError('explicit_parent_index_sha_required')
    revision, template = committed('tools/player_launcher/download.html')
    committed('tools/player_launcher/publish_download.py')
    committed('tools/player_launcher/acceptance.py')
    out = args.output.resolve()
    content = project.parents[2] / 'content/dota_addons/Survival'
    if any(out == tree or tree in out.parents for tree in (ROOT, project, content)):
        raise RuntimeError('external_output_required')
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
    for key, value in {'VERSION':version, 'RELEASE':str(expected['release_sequence']), 'EXE':exe.name,
                       'ZIP':archive.name, 'SIZE':f'{exe.stat().st_size/1000000:.1f}',
                       'SHA256':build['exe_sha256']}.items():
        text = text.replace('@@' + key + '@@', value)
    if '@@' in text: raise RuntimeError('page_placeholder_unfilled')
    page = out / 'index.html'; page.write_text(text, encoding='utf-8')
    planned = dict(kind='ACCEPTED_PLAYER_DOWNLOAD_STATIC_PUBLICATION', artifact_root=str(out),
                   at_utc=datetime.now(timezone.utc).isoformat(), operator_revision=revision,
                   build_receipt_sha256=sha(args.build_receipt), acceptance_sha256=args.acceptance_sha,
                   version=version, exe_sha256=build['exe_sha256'], url=URL,
                   acceptance_stage=acceptance_stage,
                   expected_parent_index_sha256=args.expected_index_sha,
                   files={name:dict(sha256=sha(path), bytes=path.stat().st_size) for name,path in files.items()},
                   index_sha256=sha(page), api_code_changed=False, nginx_reloaded=False)
    (out / 'plan.json').write_text(json.dumps(planned, sort_keys=True)+'\n')
    if not args.apply:
        print(json.dumps(dict(status='STATIC_DOWNLOAD_PLAN_ONLY', plan=str(out/'plan.json')))); return
    sys.path.insert(0, str(project/'tools/archive_caps_20261020'))
    import remote_driver as driver
    # Refuse overwrites. An interrupted publication must be reconciled explicitly.
    payload = dict(root=REMOTE, version=version, files=planned['files'], index_sha256=sha(page),
                   previous_index_sha256=args.expected_index_sha)
    setup = '''from pathlib import Path
import hashlib,json,os
p=Path(P['root']);v=p/P['version']
assert p.parent==Path('/var/www/xiaofengnet.com')
assert not p.is_symlink() and not v.exists(), 'immutable_version_already_present'
if p.exists():
 assert P['previous_index_sha256'] is not None, 'reviewed_parent_index_required'
 old=p/'index.html';raw=old.read_bytes()
 assert not old.is_symlink() and hashlib.sha256(raw).hexdigest()==P['previous_index_sha256'], 'parent_index_changed'
 backup=Path('/var/backups/goufayu-launcher')/P['version'];backup.mkdir(parents=True,exist_ok=False,mode=0o700)
 with (backup/'index.html').open('xb') as stream:stream.write(raw)
 (backup/'index.html').chmod(0o600)
else:
 assert P['previous_index_sha256'] is None, 'expected_parent_index_missing'
 p.mkdir(mode=0o755)
v.mkdir(mode=0o755)
print(json.dumps({'stage_created':True}))
'''
    driver.remote('P='+repr(payload)+'\n'+setup)
    (out / 'intent.json').write_text(json.dumps(dict(payload=payload, upload_started=True))+'\n')
    for name, path in files.items():
        driver.run(['scp.exe', *driver.OPTIONS, str(path), driver.HOST + ':' + REMOTE + '/' + version + '/' + name], timeout=120)
    driver.run(['scp.exe', *driver.OPTIONS, str(page), driver.HOST + ':' + REMOTE + '/index.' + version + '.pending'], timeout=60)
    check = '''from pathlib import Path
import hashlib,json,os,fcntl
p=Path(P['root']);v=p/P['version']
assert {f.name for f in v.iterdir()}==set(P['files'])
for name,f in P['files'].items():
 q=v/name; assert not q.is_symlink() and q.stat().st_size==f['bytes'] and hashlib.sha256(q.read_bytes()).hexdigest()==f['sha256'];q.chmod(0o644)
q=p/('index.'+P['version']+'.pending')
with open('/var/lock/goufayu-launcher-publication.lock','a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 assert not q.is_symlink() and hashlib.sha256(q.read_bytes()).hexdigest()==P['index_sha256'];q.chmod(0o644)
 if P['previous_index_sha256'] is not None:
  assert hashlib.sha256((p/'index.html').read_bytes()).hexdigest()==P['previous_index_sha256'], 'parent_index_changed_during_upload'
 else:assert not (p/'index.html').exists(), 'new_index_appeared_during_upload'
 os.rename(q,p/'index.html')
print(json.dumps({'all_remote_bytes_verified':True,'index_published':True}))
'''
    if release_identity(project) != expected:
        raise RuntimeError('workshop_release_changed_during_launcher_upload')
    result = json.loads(driver.remote('P='+repr(payload)+'\n'+check))
    receipt = dict(planned, remote_verified=result, status='STATIC_FILES_PUBLISHED_NEEDS_PUBLIC_HTTPS_READBACK')
    (out/'publication_receipt.json').write_text(json.dumps(receipt,sort_keys=True)+'\n')
    public = inspect_public(expected)
    if (public['status'] != 'LAUNCHER_SYNCED' or public.get('exe_sha256') != build['exe_sha256']
            or public['index_sha256'] != planned['index_sha256'] or release_identity(project) != expected):
        raise RuntimeError('official_launcher_readback_differs_from_build')
    readback = dict(public, kind='CURRENT_WORKSHOP_LAUNCHER_HTTPS_VERIFIED', artifact_root=str(out))
    (out/'public_https_receipt.json').write_text(json.dumps(readback,sort_keys=True)+'\n')
    print(json.dumps(dict(status=public['status'], url=URL, receipt=str(out/'public_https_receipt.json'))))


if __name__=='__main__':main()
