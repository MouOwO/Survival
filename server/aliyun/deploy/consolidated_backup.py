"""Local snapshots for the consolidated host; never claims an offsite copy.

Two pg_dumpall streams preserve every database and role in the PG17 clusters.
SQLite uses its online backup API. Output is root-private and append-only;
there is no pruning, upload, application restart, or player-data mutation.
"""
from __future__ import annotations

import argparse
from contextlib import closing
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import sqlite3
import subprocess
import tarfile

CHUNK = 1024 * 1024
RESERVE = 2 * 1024**3
MAX_STREAM = 2 * 1024**3
CLUSTERS = ("goufayu-db", "goufayu-ws4-db")
SQLITE = (Path("/var/lib/goufayu-ws4-web/auth.sqlite3"),
          Path("/var/lib/xiaofeng-pay/orders.db"))


def sha(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(CHUNK), b""):
            result.update(block)
    return result.hexdigest()


def database_dump(container, destination):
    digest = hashlib.sha256()
    size = 0
    with destination.with_suffix(".stderr").open("xb") as diagnostic:
        process = subprocess.Popen(
            ["podman", "exec", "-u", "postgres", container,
             "pg_dumpall", "-U", "postgres"], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=diagnostic)
        try:
            with destination.open("xb") as raw, gzip.GzipFile(
                    filename="", mode="wb", fileobj=raw, compresslevel=3) as out:
                for block in iter(lambda: process.stdout.read(CHUNK), b""):
                    size += len(block)
                    if size > MAX_STREAM or shutil.disk_usage(destination.parent).free < RESERVE:
                        raise RuntimeError("backup_storage_budget_reached")
                    digest.update(block)
                    out.write(block)
            if process.wait(timeout=30) != 0:
                raise RuntimeError("postgres_cluster_export_failed")
        finally:
            process.stdout.close()
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    verified = hashlib.sha256()
    verified_size = 0
    with gzip.open(destination, "rb") as stream:
        for block in iter(lambda: stream.read(CHUNK), b""):
            verified.update(block)
            verified_size += len(block)
    if not size or verified_size != size or verified.digest() != digest.digest():
        raise RuntimeError("postgres_export_roundtrip_failed")
    return {"container": container, "path": str(destination),
            "bytes": destination.stat().st_size, "sha256": sha(destination),
            "uncompressed_bytes": size, "uncompressed_sha256": digest.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path,
                        default=Path("/var/backups/survival-consolidated"))
    args = parser.parse_args()
    if os.name != "posix" or os.geteuid() != 0:
        raise RuntimeError("linux_root_required")
    import fcntl

    os.umask(0o077)
    root = args.output_root
    if (not root.is_absolute() or root.resolve() != root
            or not root.is_relative_to("/var/backups") or root == Path("/var/backups")):
        raise RuntimeError("private_backup_root_required")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    with (root / "backup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if shutil.disk_usage(root).free < RESERVE + 512 * 1024**2:
            raise RuntimeError("insufficient_backup_reserve")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        folder = root / (stamp + "-" + secrets.token_hex(4))
        folder.mkdir(mode=0o700)
        receipt = {"kind": "ACTUAL_CONSOLIDATED_LOCAL_BACKUP_RECEIPT",
                   "status": "IN_PROGRESS", "created_at_utc": stamp,
                   "backup_directory": str(folder), "offsite_copy": False,
                   "operator_sha256": sha(Path(__file__)), "clusters": [], "sqlite": []}
        receipt_path = folder / "backup_receipt.json"
        receipt_path.write_text(json.dumps(receipt, indent=2), encoding="utf8")
        try:
            for container in CLUSTERS:
                receipt["clusters"].append(database_dump(container, folder / (container + ".sql.gz")))
            for source in SQLITE:
                info = source.stat()
                target = folder / (source.parent.name + "-" + source.name)
                with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True, timeout=15)) as src:
                    with closing(sqlite3.connect(target)) as dst:
                        src.backup(dst, pages=256, sleep=0.05)
                        if dst.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                            raise RuntimeError("sqlite_integrity_failed")
                receipt["sqlite"].append({"source": str(source), "path": str(target),
                                          "sha256": sha(target), "source_uid": info.st_uid,
                                          "source_gid": info.st_gid, "integrity": "ok"})
            roots = [*Path("/etc").glob("goufayu*"), Path("/etc/xiaofeng-pay"),
                     Path("/etc/nginx"), Path("/etc/letsencrypt"),
                     *Path("/etc/systemd/system").glob("goufayu*"),
                     Path("/etc/systemd/system/xiaofeng-pay.service"),
                     *Path("/etc/systemd/system").glob("survival-consolidated-backup.*")]
            archive = folder / "configuration.tar.gz"
            entries = logical_bytes = 0

            def bounded(info):
                nonlocal entries, logical_bytes
                entries += 1
                logical_bytes += info.size if info.isfile() else 0
                if entries > 4096 or logical_bytes > 32 * 1024**2:
                    raise RuntimeError("configuration_backup_budget_reached")
                return info

            with tarfile.open(archive, "x:gz", compresslevel=3) as stream:
                for source in roots:
                    if source.exists():
                        stream.add(source, arcname=str(source).lstrip("/"), filter=bounded)
            receipt["configuration"] = {"path": str(archive), "sha256": sha(archive),
                                        "entries": entries, "logical_bytes": logical_bytes}
            receipt["status"] = "LOCAL_SNAPSHOT_COMPLETE_OFFSITE_NOT_CONFIGURED"
        except Exception as error:
            receipt["status"] = "FAILED_PARTIAL_FILES_PRESERVED"
            receipt["error_type"] = type(error).__name__
            raise
        finally:
            receipt_path.write_text(json.dumps(receipt, indent=2), encoding="utf8")
        print(json.dumps({"status": receipt["status"], "receipt": str(receipt_path),
                          "clusters": len(receipt["clusters"]), "offsite_copy": False}))


if __name__ == "__main__":
    main()
