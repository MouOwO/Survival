"""Build a portable EXE from committed source and the actual published helper.

All generated sources, PyInstaller work, bundles and receipts stay outside both
addon trees. This operator does not publish, start Dota or change installations.
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
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ICON = 'goufayu.ico'
SOURCE = ('app.py', 'windows.py', 'storage.py', 'build.py', 'README.txt', 'requirements-build.txt', ICON)


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], timeout=30)


def write(path, data):
    with path.open('xb') as stream:
        stream.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=ROOT,
                        help='Actual release checkout when building from an isolated worktree')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--reviewed-release-sequence', type=int, required=True)
    parser.add_argument('--reviewed-manifest', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,4}', args.version):
        raise RuntimeError('explicit_player_version_required')
    parts = tuple(int(value) for value in args.version.split('.'))
    datetime(*parts[:3])
    launcher_name = f'GoufayuLauncher-{parts[0]:04}{parts[1]:02}{parts[2]:02}.{parts[3]}'
    target = args.output.resolve()
    project = args.project.resolve(strict=True)
    common = ('rev-parse', '--path-format=absolute', '--git-common-dir')
    if git(*common) != subprocess.check_output(['git', '-C', str(project), *common], timeout=30):
        raise RuntimeError('release_checkout_must_share_launcher_repository')
    content = project.parents[2] / 'content/dota_addons/Survival'
    if any(target == tree or tree in target.parents for tree in (ROOT, project, content)):
        raise RuntimeError('build_must_be_outside_addon_trees')
    revision = git('rev-parse', 'HEAD').decode().strip()
    sources = {}
    for name in SOURCE:
        relative = 'tools/player_launcher/' + name
        raw = git('show', revision + ':' + relative)
        physical = (ROOT / relative).read_bytes()
        same = physical == raw if name == ICON else physical.replace(b'\r\n', b'\n') == raw.replace(b'\r\n', b'\n')
        if not same:
            raise RuntimeError('uncommitted_launcher_source')
        sources[name] = raw
    sys.path.insert(0, str(ROOT / 'tools'))
    from release_packager.core import baseline
    parent = baseline(project)
    published = parent['report']
    helper_revision = published['source_revisions']['game']
    helper = git('show', helper_revision + ':tools/workshop_test/file_http_bridge.py')
    if (published['release_sequence'] != args.reviewed_release_sequence or
            parent['baseline']['official_parent_manifest'] != args.reviewed_manifest):
        raise RuntimeError('published_binding_requires_review')
    target.mkdir(parents=True, exist_ok=False)
    stage = target / 'source'; stage.mkdir()
    for name, raw in sources.items():
        write(stage / name, raw)
    write(stage / 'file_http_bridge.py', helper)
    binding = dict(schema=1, version=args.version, workshop_id='3824360109',
                   release_sequence=published['release_sequence'],
                   steam_manifest=parent['baseline']['official_parent_manifest'],
                   source_revision=revision, helper_revision=helper_revision,
                   access_mode='public' if published.get('public_admission_enabled') is True else 'test',
                   helper_sha256=hashlib.sha256(helper).hexdigest(),
                   storage_sha256=hashlib.sha256(sources['storage.py']).hexdigest(),
                   icon_sha256=hashlib.sha256(sources[ICON]).hexdigest(),
                   package_files=published['package_files'])
    write(stage / 'launcher_binding.json', json.dumps(binding, sort_keys=True).encode() + b'\n')
    # Version metadata is embedded in the PE as well as the JSON binding.
    version = f"VSVersionInfo(ffi=FixedFileInfo(filevers={parts!r}, prodvers={parts!r}, mask=0x3f, flags=0, OS=0x40004, fileType=1, subtype=0, date=(0,0)), kids=[StringFileInfo([StringTable('080404B0',[StringStruct('FileDescription','我在dota2苟发育专用登录器'),StringStruct('ProductName','我在dota2苟发育'),StringStruct('FileVersion','{args.version}'),StringStruct('ProductVersion','{args.version}')])]),VarFileInfo([VarStruct('Translation',[2052,1200])])])"
    write(stage / 'version.txt', version.encode('utf-8'))
    command = [str(args.python.resolve(strict=True)), '-B', '-X', 'utf8', '-m', 'PyInstaller',
               '--noconfirm', '--clean', '--onefile', '--windowed', '--noupx',
               '--name', launcher_name, '--distpath', str(target / 'dist'), '--workpath', str(target / 'work'),
               '--specpath', str(target / 'spec'), '--version-file', str(stage / 'version.txt'),
               '--icon', str(stage / ICON), '--add-data', str(stage / ICON) + ';.',
               '--add-data', str(stage / 'launcher_binding.json') + ';.', str(stage / 'app.py')]
    with (target / 'build.log').open('xb') as output:
        result = subprocess.run(command, cwd=stage, stdout=output, stderr=subprocess.STDOUT, timeout=600)
    if result.returncode:
        raise RuntimeError('pyinstaller_failed_see_preserved_log')
    exe = target / 'dist' / (launcher_name + '.exe')
    sha = hashlib.sha256(exe.read_bytes()).hexdigest()
    write(target / 'dist/SHA256SUMS.txt', (sha + '  ' + exe.name + '\n').encode())
    write(target / 'dist/使用说明.txt', sources['README.txt'].replace(b'@@EXE@@', exe.name.encode('ascii')))
    write(target / 'dist/version.json', json.dumps(dict(binding, exe=exe.name, sha256=sha,
                                                       bytes=exe.stat().st_size), sort_keys=True).encode() + b'\n')
    archive = target / (launcher_name + '.zip')
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as z:
        for file in sorted((target / 'dist').iterdir()):
            z.write(file, file.name)
    receipt = dict(kind='PORTABLE_PLAYER_EXE_BUILD', artifact_root=str(target),
                   at_utc=datetime.now(timezone.utc).isoformat(), source_revision=revision,
                   helper_revision=helper_revision, source_sha256s={n:hashlib.sha256(b).hexdigest() for n,b in sources.items()},
                   binding=binding, exe=str(exe), exe_bytes=exe.stat().st_size, exe_sha256=sha,
                   archive=str(archive), archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                   toolchain=json.loads(subprocess.check_output([str(args.python), '-c',
                       'import json,platform,PyInstaller; print(json.dumps({"python":platform.python_version(),"pyinstaller":PyInstaller.__version__}))'])),
                   windows_code_signed=False, game_files_changed=False, upload_performed=False)
    write(target / 'build_receipt.json', json.dumps(receipt, sort_keys=True).encode() + b'\n')
    print(json.dumps(dict(status='EXE_BUILT_NOT_PUBLISHED', receipt=str(target / 'build_receipt.json'),
                          exe=str(exe), bytes=exe.stat().st_size, sha256=sha)))


if __name__ == '__main__':
    main()
