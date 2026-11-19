"""Windows storage adapter for the published protocol-2 bridge.

Only local atomic replacement/cleanup changes; HTTPS, credentials and the Lua
protocol remain in the exact published helper. Startup recovery is bounded and
backs up recognized files before removing any original, with Dota already out.
"""
from __future__ import annotations
from contextlib import contextmanager
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import time

RETRIES = (0.005, 0.010, 0.020, 0.040, 0.080, 0.160)
PREFIX = 'survival_ws4_http_bridge'
BLOCK = re.compile(r'b_n[a-f0-9]{32}_[A-Za-z0-9_]{1,24}_[0-9]{1,10}_[0-9]{1,4}\.txt')


def plain(path, *, directory=False):
    info = path.lstat()
    if info.st_file_attributes & 0x400 or (not path.is_dir() if directory else not path.is_file()):
        raise ValueError('bridge_recovery_required')
    return info


def fingerprint(path):
    info = plain(path)
    if info.st_size > 8192:
        raise ValueError('bridge_recovery_required')
    raw = path.read_bytes()
    after = plain(path)
    if (info.st_ino, info.st_size, info.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
        raise ValueError('bridge_file_changed')
    return raw, (info.st_dev, info.st_ino, info.st_mtime_ns, info.st_size), hashlib.sha256(raw).hexdigest()


def retry(action, metrics, deadline=None):
    for attempt in range(len(RETRIES) + 1):
        try:
            return action()
        except OSError as error:
            transient = (getattr(error, 'winerror', None) in (5, 32, 33)
                         or (os.name == 'nt' and error.errno == errno.EACCES))
            if not transient:
                raise
            if attempt == len(RETRIES) or (deadline is not None and time.monotonic() + RETRIES[attempt] > deadline):
                raise ValueError('transport_files_busy') from error
            metrics['retries'] += 1
            time.sleep(RETRIES[attempt])


def recover(cfg, run, private_acl):
    """One O(F + bytes) scan, <=4096 files/32MiB/20s; no recursive move.

    Caller has taken the single launcher lock and confirmed no Dota process.
    An unknown file or reparse point blocks before any original is removed.
    """
    cfg, run = Path(cfg), Path(run)
    plain(cfg, directory=True)
    deadline = time.monotonic() + 20
    paths, bridge_dir = [], cfg / PREFIX
    for path in cfg.glob(PREFIX + '*'):
        if time.monotonic() > deadline:
            raise ValueError('bridge_recovery_budget')
        if path == bridge_dir:
            plain(path, directory=True)
            for child in path.iterdir():
                stem = child.name
                if not (BLOCK.fullmatch(stem)
                        or re.fullmatch(BLOCK.pattern[:-5] + r'\.sfbtmp', stem)
                        or re.fullmatch(BLOCK.pattern + r'\.[a-f0-9]{32}\.sfbtmp', stem)):
                    raise ValueError('bridge_recovery_required')
                paths.append(child)
                if len(paths) > 4096:
                    raise ValueError('bridge_recovery_budget')
        elif re.fullmatch(PREFIX + r'_(bootstrap|cursor)\.(txt|sfbtmp)', path.name) or re.fullmatch(PREFIX + r'_(bootstrap|cursor)\.txt\.[a-f0-9]{32}\.sfbtmp', path.name):
            paths.append(path)
        else:
            raise ValueError('bridge_recovery_required')
    values, total = [], 0
    for path in paths:
        raw, identity, digest = fingerprint(path)
        total += len(raw)
        if total > 32 * 1024 * 1024 or time.monotonic() > deadline:
            raise ValueError('bridge_recovery_budget')
        if raw and not (raw.startswith(b'"SurvivalFileHttp"\n{\n"protocol" "2"\n')
                        and raw.endswith(b'}\n') and b'\x00' not in raw):
            raise ValueError('bridge_recovery_required')
        values.append((path, raw, identity, digest))
    if not paths and not bridge_dir.exists():
        return dict(files=0, bytes=0, preserved=False)
    backup = run / 'recovered_bridge'
    backup.mkdir(exist_ok=False); private_acl(backup)
    records = []
    for index, (path, raw, identity, digest) in enumerate(values):
        if time.monotonic() > deadline:
            raise ValueError('bridge_recovery_budget')
        target = backup / (str(index) + '.bin')
        with target.open('xb') as stream:
            private_acl(target); stream.write(raw)
        if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
            raise ValueError('bridge_backup_failed')
        records.append(dict(source=str(path), backup=str(target), bytes=len(raw), sha256=digest))
    manifest = backup / 'backup_receipt.json'
    with manifest.open('x', encoding='utf8') as stream:
        private_acl(manifest)
        json.dump(dict(kind='PRIVATE_BRIDGE_RECOVERY_BACKUP', artifact_root=str(backup),
                       files=records, source_removal_started=False), stream)
    # Recheck every original before the first removal. Every operation below is
    # restricted to an individually validated file in the fixed cfg namespace.
    for path, raw, identity, digest in values:
        if time.monotonic() > deadline:
            raise ValueError('bridge_recovery_budget')
        if fingerprint(path)[1:] != (identity, digest):
            raise ValueError('bridge_file_changed')
    metrics = {'retries': 0}
    for path, raw, identity, digest in values:
        def remove(path=path, identity=identity, digest=digest):
            if fingerprint(path)[1:] != (identity, digest):
                raise ValueError('bridge_file_changed')
            path.unlink()
        retry(remove, metrics, deadline)
    if bridge_dir.exists():
        retry(bridge_dir.rmdir, metrics, deadline)
    result = dict(files=len(values), bytes=total, preserved=True,
                  backup_receipt=str(manifest), retries=metrics['retries'])
    done = backup / 'recovery_receipt.json'
    with done.open('x', encoding='utf8') as stream:
        private_acl(done); json.dump(result, stream)
    return result


@contextmanager
def adapter(bridge):
    """Per-session replacement of Files only; restore the published class on exit.

    Steady writes are O(1); retire/close touch only the indexed owned files.
    At most 7 replacement attempts, 315ms total backoff per affected operation.
    There is no polling scan and no additional HTTP/native/game timer.
    """
    original = bridge.Files
    metrics = dict(retries=0, replace_attempts=0, delete_attempts=0,
                   temp_created=0, cleanup_pending=0)

    class ReliableFiles(original):
        deadline = None

        def checked(self, path):
            if os.path.lexists(path):
                if path not in self.owned or fingerprint(path)[2] != self.owned[path]:
                    raise ValueError('bridge_file_changed')

        def write(self, path, body):
            retry(lambda: self.checked(path), metrics, self.deadline)
            temporary = path.with_name(path.name + '.' + secrets.token_hex(16) + '.sfbtmp')
            digest = hashlib.sha256(body).hexdigest()
            with temporary.open('xb') as stream:
                bridge.private_acl(temporary)
                stream.write(body)
            self.owned[temporary] = digest
            metrics['temp_created'] += 1
            try:
                def replace():
                    self.checked(path)
                    metrics['replace_attempts'] += 1
                    os.replace(temporary, path)
                retry(replace, metrics, self.deadline)
                self.owned.pop(temporary)
                self.owned[path] = digest
            finally:
                if temporary in self.owned:
                    self.remove(temporary)

        def remove(self, path):
            digest = self.owned.get(path)
            if not digest or not os.path.lexists(path):
                self.owned.pop(path, None)
                return
            def remove():
                self.checked(path)
                metrics['delete_attempts'] += 1
                path.unlink()
            retry(remove, metrics, self.deadline)
            self.owned.pop(path)

        def retire(self, paths):
            self.deadline = time.monotonic() + 1
            try:
                super().retire(paths)
            finally:
                self.deadline = None

        def close(self):
            self.deadline = time.monotonic() + 2
            for path in list(self.owned):
                if time.monotonic() >= self.deadline:
                    break
                try:
                    self.remove(path)
                except (OSError, ValueError):
                    pass
            metrics['cleanup_pending'] = len(self.owned)
            try:
                self.directory.rmdir()
            except OSError:
                pass
            self.deadline = None

    bridge.Files = ReliableFiles
    try:
        yield metrics
    finally:
        bridge.Files = original
