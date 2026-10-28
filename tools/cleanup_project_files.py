"""Verify an exact cleanup plan; --apply archives and verifies before deleting.

Plans contain relative paths, sizes and SHA256, and are tied to a Git HEAD.
Only reviewed historical output/design files and the retired ST2 GPU family
are eligible. No directory recursion or wildcard deletion is performed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROTECTED_OUTPUT = {
    'ecs_backend_work', 'workshop_web_auth_20261024', 'ws4_web_auth_20261024',
    'four_accounts_20261022', 'ui_layout_20261028', 'map_resources_20261028',
    'native_arcade_cloud_20261027', 'arcade_cleanup_20261027',
    'arcade_payment_link_20261027', 'ui_qa_20261025_release',
    'survival_world_v2', 'project_knowledge_20261024',
    'package_cleanup_20261028', 'package_slim_20261028_round1',
}


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def no_links(path):
    for entry in (path, *path.parents):
        try:
            metadata = entry.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode) or getattr(metadata, 'st_file_attributes', 0) & 0x400:
            raise ValueError('Reparse/link path forbidden: ' + str(entry))


def eligible(name):
    parts = name.split('/')
    if (not name or '\\' in name or ':' in name or name.startswith('/')
            or any(p in {'', '.', '..'} or p.casefold() == '.git' for p in parts)):
        return False
    if any(p.casefold() in {'baseline', 'before', 'initial_sync', 'alias_updates',
                            'trusted_source', 'source_history_2703_2704'} for p in parts):
        # Standalone browser snapshots are handled only inside preview/ below.
        if not (name.startswith('output/ui_qa_20261025/browser/') and '/preview/' in name):
            return False
    if any(p.casefold().startswith(('.env', '.ssh')) for p in parts):
        return False
    if PurePosixPath(name).suffix.casefold() in {'.pem', '.key', '.pfx', '.p12', '.sqlite', '.sqlite3', '.db'}:
        return False
    if name.startswith('panorama/images/custom_game/st2_localmount/'):
        return name.endswith('.vtex_c')
    if name == 'panorama/styles/custom_game/survival_hud_st2_local.vcss_c':
        return True
    if name.startswith('output/'):
        return len(parts) > 2 and parts[1] not in PROTECTED_OUTPUT and not name.startswith('output/ui_qa_20261025/release/')
    return name.startswith('design_refs/') and len(parts) > 2


def validate(root, plan):
    root = root.absolute()
    no_links(root)
    if plan.get('schema') != 1 or plan.get('action') != 'archive_verify_then_delete_exact_files':
        raise ValueError('Unrecognized cleanup plan')
    if plan.get('root') != str(root):
        raise ValueError('Plan belongs to another root')
    head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if head != plan.get('head'):
        raise ValueError('Git HEAD changed; review a new plan')
    dirty = set(subprocess.check_output(['git', '-C', str(root), 'diff', '--name-only', '-z']).decode('utf-8').split('\0'))
    staged = subprocess.check_output(['git', '-C', str(root), 'diff', '--cached', '--name-only', '-z'])
    if staged:
        raise ValueError('Existing index changes must be reviewed first')
    seen = set()
    rows = plan.get('files')
    if not isinstance(rows, list) or not rows:
        raise ValueError('Empty cleanup plan')
    for row in rows:
        name = row.get('path', '')
        if not eligible(name) or name.casefold() in seen or name in dirty:
            raise ValueError('Unsafe, duplicate or modified cleanup target: ' + name)
        seen.add(name.casefold())
        path = root / name
        no_links(path)
        if not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError('Target is missing or outside the root: ' + name)
        if (type(row.get('bytes')) is not int or row['bytes'] < 0
                or not isinstance(row.get('sha256'), str) or len(row['sha256']) != 64
                or not row.get('reason') or path.stat().st_size != row['bytes'] or sha(path) != row['sha256']):
            raise ValueError('Cleanup target changed: ' + name)
    if plan.get('bytes') != sum(r['bytes'] for r in rows):
        raise ValueError('Cleanup total mismatch')
    return rows


def cleanup(root, plan, archive, *, apply=False):
    rows = validate(root, plan)
    archive = archive.absolute()
    no_links(archive)
    if archive.is_relative_to(root.absolute()) or archive.exists():
        raise ValueError('Use a NEW archive outside the project')
    if archive.suffix.lower() != '.zip':
        raise ValueError('Recovery archive must be ZIP')
    result = {'schema': 1, 'files': len(rows), 'bytes': plan['bytes'],
              'archive': str(archive), 'applied': False}
    if not apply:
        return result
    archive.parent.mkdir(parents=True, exist_ok=True)
    no_links(archive.parent)
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=3, allowZip64=True) as output:
        for row in rows:
            # PNG/JPEG are already compressed; keep these copies cheap to create.
            kind = zipfile.ZIP_STORED if PurePosixPath(row['path']).suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp', '.zip'} else zipfile.ZIP_DEFLATED
            output.write(root / row['path'], row['path'], compress_type=kind)
        output.writestr('_cleanup_manifest.json', json.dumps(plan, ensure_ascii=False, indent=2))
    with zipfile.ZipFile(archive) as saved:
        if set(saved.namelist()) != {r['path'] for r in rows} | {'_cleanup_manifest.json'}:
            raise ValueError('Recovery archive file set differs')
        for row in rows:
            with saved.open(row['path']) as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            if digest != row['sha256'] or saved.getinfo(row['path']).file_size != row['bytes']:
                raise ValueError('Recovery archive verification failed')
    # Revalidate the entire plan after archive creation and before any deletion.
    validate(root, plan)
    journal = archive.with_suffix('.deleted.jsonl')
    with journal.open('x', encoding='utf-8') as log:
        for row in rows:
            path = root / row['path']
            no_links(path)
            if path.stat().st_size != row['bytes'] or sha(path) != row['sha256']:
                raise ValueError('Source changed immediately before deletion')
            path.unlink()
            log.write(json.dumps({'path': row['path'], 'sha256': row['sha256']}) + '\n')
            log.flush()
            os.fsync(log.fileno())
    result.update(applied=True, archive_bytes=archive.stat().st_size,
                  archive_sha256=sha(archive), deleted_files=len(rows), archive_fully_verified=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text('utf-8'))
    # Reports are task output, never another source file or an archive input.
    no_links(args.report.absolute())
    if not args.report.absolute().is_relative_to(ROOT / 'output') or args.report.absolute() in {args.plan.absolute(), args.archive.absolute()}:
        raise ValueError('Report must be separate task output')
    result = cleanup(ROOT, plan, args.archive, apply=args.apply)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
