"""Prepare a source-bound overlay against an exact read-only live snapshot.

No upload, credentials, service change or database write. Unrelated live fixes
are retained. Every replacement must have one exact context match.
"""
from __future__ import annotations
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BASE = 'e14088f0cc1de7e3a9e5c387d77489369c6deda1'
FILES = {
    'api/archive_backend/test_access.py': 'server/archive_backend/test_access.py',
    'web/player_web_auth/service.py': 'server/player_web_auth/service.py',
    'web/player_web_auth/run.py': 'server/player_web_auth/run.py',
    'payment/payment_backend/service.py': 'server/payment_backend/service.py',
    'payment/payment_backend/endpoints.py': 'server/payment_backend/endpoints.py',
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], timeout=30)


def overlay(base, revised, active):
    before, after, result = [value.decode('utf-8').splitlines(True)
                             for value in (base, revised, active)]
    changes = []
    groups = difflib.SequenceMatcher(None, before, after, autojunk=False).get_grouped_opcodes(n=3)
    for group in groups:
        # Merge adjacent edits and bind three lines of exact context on each
        # side. Reverse application leaves earlier hunk coordinates untouched.
        a, b, c, d = group[0][1], group[-1][2], group[0][3], group[-1][4]
        changes.append((before[a:b], after[c:d]))
    for old, new in reversed(changes):
        matches = [i for i in range(len(result) - len(old) + 1)
                   if result[i:i + len(old)] == old]
        if len(matches) != 1:
            raise ValueError('live_overlay_context_changed_requires_review')
        i = matches[0]
        result[i:i + len(old)] = new
    raw = ''.join(result).encode('utf-8')
    compile(raw, 'source_bound_cloud_candidate', 'exec')
    return raw, len(changes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if git('rev-parse', 'HEAD').decode().strip() != args.source_revision:
        raise ValueError('current_committed_launch_source_required')
    snapshot = json.loads((args.snapshot / 'source_backup_receipt.json').read_bytes())
    indexed = {row['path']: row for row in snapshot['files']}
    args.output.mkdir(parents=True, exist_ok=False)
    proofs = []
    for target, source in FILES.items():
        old = git('show', BASE + ':' + source).replace(b'\r\n', b'\n')
        new = git('show', args.source_revision + ':' + source).replace(b'\r\n', b'\n')
        if (ROOT / source).read_bytes().replace(b'\r\n', b'\n') != new:
            raise ValueError('uncommitted_launch_backend_source')
        active = (args.snapshot / target).read_bytes()
        if sha(active) != indexed[target]['sha256']:
            raise ValueError('live_snapshot_changed')
        candidate, count = overlay(old, new, active.replace(b'\r\n', b'\n'))
        path = args.output / target
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as stream:
            stream.write(candidate)
        proofs.append(dict(target=target, source=source, base_revision=BASE,
                           source_revision=args.source_revision, base_sha256=sha(old),
                           revised_sha256=sha(new), active_parent_sha256=sha(active),
                           result_sha256=sha(candidate), bytes=len(candidate), edits=count))
    manifest = dict(schema=1, kind='SOURCE_BOUND_EXISTING_PRODUCTION_BACKEND_OVERLAY',
                    host='47.111.16.128', source_revision=args.source_revision,
                    remote_parent_roots=snapshot['remote_roots'], files=proofs,
                    environment_changes={'SURVIVAL_ACCESS_MODE': 'public',
                                         'PLAYER_WEB_AUTH_ACCESS_MODE': 'public'},
                    payment_config_changes={'access_mode': 'public'},
                    unrelated_live_fixes_preserved=True, secrets_included=False,
                    deployment_performed=False, database_modified=False)
    raw = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    (args.output / 'manifest.json').write_bytes(raw)
    archive = args.output / 'backend-overlay.tar'
    with tarfile.open(archive, 'x') as tar:
        for name in (*FILES, 'manifest.json'):
            tar.add(args.output / name, arcname=name, recursive=False)
    receipt = dict(kind='PUBLIC_LAUNCH_BACKEND_CANDIDATE', artifact_root=str(args.output),
                   manifest_sha256=sha(raw), archive_sha256=sha(archive.read_bytes()),
                   archive_bytes=archive.stat().st_size, file_count=len(FILES),
                   source_revision=args.source_revision, target_host='47.111.16.128',
                   uploaded=False, secrets_included=False)
    (args.output / 'candidate_receipt.json').write_text(json.dumps(receipt) + '\n')
    print(json.dumps(receipt))


if __name__ == '__main__':
    main()
