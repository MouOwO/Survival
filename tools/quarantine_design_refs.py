"""Back up unreferenced design_refs files outside both addons; never blind-delete.

Review: python tools/quarantine_design_refs.py --manifest <audit.json> --destination D:/Survival_待删除/<new-batch>
Move:   add --apply. Resume an interrupted matching batch: add --apply --resume.
Restore by verified copy: --restore <batch>/quarantine_manifest.json [--apply].
The default performs validation and reports actions without changing any file.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ROOTS = {"game": ROOT, "content": ROOT.parents[2] / "content/dota_addons/Survival"}
MANIFEST_NAME = "quarantine_manifest.json"
JOURNAL_NAME = "journal.jsonl"
SCHEMA = 1


class QuarantineError(ValueError):
    pass


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _linked(path: Path) -> bool:
    return path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction())


def _no_links(path: Path) -> None:
    for part in [path, *path.parents]:
        if _linked(part):
            raise QuarantineError(f"Links and junctions are not allowed: {part}")


def _inside(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def _roots(roots: dict[str, Path]) -> dict[str, Path]:
    if set(roots) != {"game", "content"}:
        raise QuarantineError("Exactly game and content roots are required")
    checked = {}
    for repo, raw in roots.items():
        path = Path(raw).absolute()
        _no_links(path)
        path = path.resolve(strict=True)
        if not path.is_dir():
            raise QuarantineError(f"Not a repository directory: {path}")
        checked[repo] = path
    if _inside(checked['game'], checked['content']) or _inside(checked['content'], checked['game']):
        raise QuarantineError("Repository roots must be separate")
    return checked


def _relative(value: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        raise QuarantineError(f"Invalid relative path: {value!r}")
    path = PurePosixPath(value)
    parts = value.split('/')
    if path.is_absolute() or any(x in {'', '.', '..'} for x in parts):
        raise QuarantineError(f"Path traversal or non-normalized path: {value!r}")
    if len(parts) < 2 or parts[0] != 'design_refs' or any(x.casefold() == '.git' for x in parts):
        raise QuarantineError(f"Only files strictly inside design_refs are allowed: {value!r}")
    return path.as_posix()


def _source(roots: dict[str, Path], repo: str, relative: str) -> Path:
    if repo not in roots:
        raise QuarantineError(f"Unknown repository: {repo}")
    relative = _relative(relative)
    path = roots[repo] / relative
    _no_links(path)
    if not _inside(path.resolve(strict=False), roots[repo] / 'design_refs'):
        raise QuarantineError(f"Source escapes design_refs: {path}")
    if path.exists() and not path.is_file():
        raise QuarantineError(f"Source is not a regular file: {path}")
    return path


def _destination(raw: Path, roots: dict[str, Path]) -> Path:
    raw = Path(raw).absolute()
    _no_links(raw)
    target = raw.resolve(strict=False)
    if any(x.casefold() == '.git' for x in target.parts):
        raise QuarantineError("A quarantine batch cannot be inside .git")
    if target == target.parent or any(_inside(target, root) for root in roots.values()):
        raise QuarantineError("Quarantine must be outside both addon roots")
    return target


def _matches(path: Path, row: dict) -> bool:
    _no_links(path)
    return path.is_file() and path.stat().st_size == row['bytes'] and digest(path) == row['sha256']


def _validate_row(row: dict, roots: dict[str, Path]) -> dict:
    if not isinstance(row, dict):
        raise QuarantineError("Each manifest row must be an object")
    repo = row.get('repo')
    relative = _relative(row.get('path'))
    size = row.get('bytes')
    sha256 = row.get('sha256')
    if isinstance(size, bool) or not isinstance(size, int) or size < 0:
        raise QuarantineError(f"Invalid expected size for {relative}")
    if not isinstance(sha256, str) or not re.fullmatch('[0-9a-f]{64}', sha256):
        raise QuarantineError(f"An exact lowercase SHA-256 is required for {relative}")
    if row.get('reference_count', 0) != 0:
        raise QuarantineError(f"Referenced files cannot be quarantined: {relative}")
    _source(roots, repo, relative)
    return {'repo': repo, 'path': relative, 'bytes': size, 'sha256': sha256,
            'reason': row.get('reason', 'zero incoming references in reviewed audit')}


def load_plan(manifest: Path, roots: dict[str, Path]) -> dict:
    roots = _roots(roots)
    manifest = Path(manifest)
    _no_links(manifest.absolute())
    raw = manifest.read_bytes()
    data = json.loads(raw.decode('utf-8-sig'))
    if data.get('schema_version') != SCHEMA or data.get('action') != 'move_to_external_quarantine_only':
        raise QuarantineError("Expected a reviewed zero-reference quarantine manifest")
    rows = [_validate_row(row, roots) for row in data.get('files', [])]
    keys = [(r['repo'], r['path'].casefold()) for r in rows]
    if len(keys) != len(set(keys)):
        raise QuarantineError("Manifest contains duplicate source paths")
    return {'roots': roots, 'rows': rows, 'audit_sha256': hashlib.sha256(raw).hexdigest(),
            'audit_manifest': str(manifest.resolve()), 'source_head': data.get('source_head', {})}


def _append(batch: Path, event: dict) -> None:
    journal = batch / JOURNAL_NAME
    _no_links(journal)
    event = {'at': datetime.now(timezone.utc).isoformat(), **event}
    with journal.open('a', encoding='utf-8', newline='\n') as stream:
        stream.write(json.dumps(event, ensure_ascii=False) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def _write_new(path: Path, value: dict) -> None:
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())


def _head(root: Path) -> str | None:
    if not (root / '.git').exists():
        return None
    result = subprocess.run(['git', '-c', f'safe.directory={root}', '-C', str(root), 'rev-parse', 'HEAD'],
                            capture_output=True, text=True, timeout=15, check=True)
    value = result.stdout.strip()
    if not re.fullmatch('[0-9a-f]{40,64}', value):
        raise QuarantineError(f'Cannot record repository HEAD: {root}')
    return value


def _load_batch(manifest: Path, roots: dict[str, Path]) -> tuple[Path, dict]:
    manifest = Path(manifest).absolute()
    _no_links(manifest)
    if manifest.name != MANIFEST_NAME:
        raise QuarantineError(f"Expected {MANIFEST_NAME}")
    batch = _destination(manifest.parent, roots)
    integrity_path = batch / 'manifest_integrity.json'
    _no_links(integrity_path)
    integrity = json.loads(integrity_path.read_text('utf-8-sig'))
    if integrity.get('sha256') != digest(manifest):
        raise QuarantineError("Quarantine manifest integrity check failed")
    data = json.loads(manifest.read_text('utf-8-sig'))
    if data.get('schema_version') != SCHEMA or data.get('kind') != 'design_refs_external_quarantine':
        raise QuarantineError("Not a recognized quarantine batch")
    if data.get('batch_path') != str(batch) or data.get('source_roots') != {k: str(v) for k, v in roots.items()}:
        raise QuarantineError("Batch root or source roots do not match this invocation")
    rows = [_validate_row(row, roots) for row in data.get('files', [])]
    keys = [(r['repo'], r['path'].casefold()) for r in rows]
    if len(keys) != len(set(keys)):
        raise QuarantineError("Batch contains duplicate source paths")
    data['files'] = rows
    return batch, data


def _payload(batch: Path, row: dict) -> Path:
    path = batch / row['repo'] / _relative(row['path'])
    _no_links(path)
    if not _inside(path.resolve(strict=False), batch):
        raise QuarantineError("Payload escapes its batch")
    if path.exists() and not path.is_file():
        raise QuarantineError(f"Payload is not a regular file: {path}")
    return path


def _publish_copy(source: Path, target: Path, row: dict, run_id: str) -> None:
    """Publish an absent file without replacement; keep original until verified.

    A same-directory temporary file plus a hard link gives an exclusive atomic
    publish on NTFS and POSIX. If the filesystem lacks hard links, fail safely.
    """
    _no_links(source)
    _no_links(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    _no_links(target.parent)
    temporary = target.parent / ('.' + target.name + '.' + run_id + '.' + uuid.uuid4().hex + '.partial')
    try:
        with source.open('rb') as src, temporary.open('xb') as dst:
            shutil.copyfileobj(src, dst, 1024 * 1024)
            dst.flush()
            os.fsync(dst.fileno())
        shutil.copystat(source, temporary, follow_symlinks=False)
        if not _matches(temporary, row):
            raise QuarantineError(f"Copy failed integrity validation: {source}")
        # os.link never overwrites an existing destination, including on Windows.
        os.link(temporary, target, follow_symlinks=False)
    finally:
        if temporary.exists() and not _linked(temporary):
            temporary.unlink()
    if not _matches(target, row):
        raise QuarantineError(f"Published file failed integrity validation: {target}")


def quarantine(plan: dict, destination: Path, *, apply: bool = False, resume: bool = False) -> dict:
    roots, rows = plan['roots'], plan['rows']
    batch = _destination(destination, roots)
    existing = None
    if batch.exists():
        if not resume:
            raise QuarantineError("Destination already exists; use a new batch or explicitly --resume a matching batch")
        _, existing = _load_batch(batch / MANIFEST_NAME, roots)
        if existing.get('audit_sha256') != plan['audit_sha256'] or existing['files'] != rows:
            raise QuarantineError("Resume requires the exact original audit manifest")
    elif resume:
        raise QuarantineError("Cannot resume a batch that does not exist")
    reviewed=[]
    for row in rows:
        source = _source(roots, row['repo'], row['path'])
        backup = _payload(batch, row)
        source_exists, backup_exists = source.exists(), backup.exists()
        if source_exists and not _matches(source, row):
            raise QuarantineError(f"Source changed after audit; nothing will be moved: {source}")
        if backup_exists and not _matches(backup, row):
            raise QuarantineError(f"Backup hash mismatch; never overwrite it: {backup}")
        if not source_exists and not backup_exists:
            raise QuarantineError(f"Source and backup are both absent: {source}")
        reviewed.append((row, source, backup, source_exists, backup_exists))
    result={'action': 'quarantine', 'applied': apply, 'batch_path': str(batch),
            'files': len(rows), 'bytes': sum(r['bytes'] for r in rows),
            'moved_files': 0, 'moved_bytes': 0, 'already_moved': 0,
            'manifest': str(batch / MANIFEST_NAME)}
    if not apply:
        return result
    if existing is None:
        heads = {repo: _head(root) for repo, root in roots.items()}
        for repo, expected in plan['source_head'].items():
            if expected is not None and heads.get(repo) != expected:
                raise QuarantineError(f'Repository HEAD changed after audit: {repo}')
        metadata = {}
        for row, source, _, _, _ in reviewed:
            st = source.stat()
            metadata[row['repo'] + ':' + row['path']] = {'mtime_ns': st.st_mtime_ns, 'mode': st.st_mode}
        batch.mkdir(parents=True, exist_ok=False)
        _no_links(batch)
        existing={'schema_version': SCHEMA, 'kind': 'design_refs_external_quarantine',
                  'run_id': datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_') + uuid.uuid4().hex[:12],
                  'created_at': datetime.now(timezone.utc).isoformat(), 'batch_path': str(batch),
                  'source_roots': {k: str(v) for k,v in roots.items()},
                  'audit_manifest': plan['audit_manifest'], 'audit_sha256': plan['audit_sha256'],
                  'source_head': heads, 'source_metadata': metadata, 'files': rows}
        _write_new(batch / MANIFEST_NAME, existing)
        _write_new(batch / 'manifest_integrity.json', {'sha256': digest(batch / MANIFEST_NAME)})
    for row, source, backup, _, _ in reviewed:
        event={'repo': row['repo'], 'path': row['path'], 'sha256': row['sha256'], 'bytes': row['bytes']}
        # Recheck after preflight to catch changed producers and safe interruption.
        if not source.exists():
            if not _matches(backup, row):
                raise QuarantineError(f"Missing source without a verified backup: {source}")
            _append(batch, {**event, 'state': 'already_moved_verified'})
            result['already_moved'] += 1
            continue
        if not _matches(source, row):
            raise QuarantineError(f"Source changed during operation: {source}")
        _append(batch, {**event, 'state': 'planned'})
        if backup.exists():
            if not _matches(backup, row):
                raise QuarantineError(f"Backup changed during operation: {backup}")
        else:
            _publish_copy(source, backup, row, existing['run_id'])
        if not _matches(source, row) or not _matches(backup, row):
            raise QuarantineError(f"Keep both files; copy/source changed during operation: {source}")
        source.unlink()
        _append(batch, {**event, 'state': 'moved_verified'})
        result['moved_files'] += 1
        result['moved_bytes'] += row['bytes']
    _append(batch, {'state': 'quarantine_complete', 'result': result})
    return result


def restore(manifest: Path, roots: dict[str, Path], *, apply: bool = False) -> dict:
    roots = _roots(roots)
    batch, data = _load_batch(manifest, roots)
    actions=[]; conflicts=[]; already=0; not_quarantined=0
    for row in data['files']:
        source = _source(roots, row['repo'], row['path'])
        backup = _payload(batch, row)
        if source.exists():
            if _matches(source, row): already += 1
            else: conflicts.append({'repo': row['repo'], 'path': row['path'], 'reason': 'source exists with different bytes; kept unchanged'})
        if backup.exists():
            if not _matches(backup, row):
                raise QuarantineError(f"Backup integrity failure: {backup}")
            if not source.exists(): actions.append((row, source, backup))
        elif source.exists() and _matches(source, row):
            not_quarantined += 1
        else:
            conflicts.append({'repo': row['repo'], 'path': row['path'], 'reason': 'no verified backup available'})
    result={'action': 'restore', 'applied': apply, 'batch_path': str(batch),
            'files_to_restore': len(actions), 'bytes_to_restore': sum(r['bytes'] for r,_,_ in actions),
            'restored_files': 0, 'already_present': already, 'not_quarantined': not_quarantined,
            'conflicts': conflicts, 'backup_retained': True}
    if apply:
        for row, source, backup in actions:
            if source.exists():
                if _matches(source, row): continue
                result['conflicts'].append({'repo': row['repo'], 'path': row['path'], 'reason': 'source appeared during restore; kept unchanged'})
                continue
            if not _matches(backup, row):
                raise QuarantineError(f"Backup changed during restore: {backup}")
            _append(batch, {'state': 'restore_planned', 'repo': row['repo'], 'path': row['path']})
            _publish_copy(backup, source, row, data['run_id'])
            _append(batch, {'state': 'restored_verified', 'repo': row['repo'], 'path': row['path'], 'sha256': row['sha256']})
            result['restored_files'] += 1
        _append(batch, {'state': 'restore_complete', 'result': result})
    return result


def main(argv=None) -> int:
    parser=argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    action=parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--manifest', type=Path, help='Reviewed zero-reference candidate JSON')
    action.add_argument('--restore', type=Path, help='External quarantine_manifest.json')
    parser.add_argument('--destination', type=Path, help='New batch outside both addons')
    parser.add_argument('--apply', action='store_true', help='Actually move files or restore verified copies')
    parser.add_argument('--resume', action='store_true', help='Resume only the exact original matching batch')
    parser.add_argument('--game-root', type=Path, default=DEFAULT_ROOTS['game'])
    parser.add_argument('--content-root', type=Path, default=DEFAULT_ROOTS['content'])
    args=parser.parse_args(argv)
    roots={'game': args.game_root, 'content': args.content_root}
    try:
        if args.restore:
            if args.destination or args.resume:
                raise QuarantineError('--restore determines its batch; do not pass --destination or --resume')
            result=restore(args.restore, roots, apply=args.apply)
        else:
            if not args.destination:
                raise QuarantineError('--destination is required for a quarantine review/apply')
            result=quarantine(load_plan(args.manifest, roots), args.destination, apply=args.apply, resume=args.resume)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 2 if result.get('conflicts') else 0
    except (QuarantineError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        print(json.dumps({'ok': False, 'error': str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
