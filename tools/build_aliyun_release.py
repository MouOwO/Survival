"""Build a secret-free, checksummed host-Python release from both source repos."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def copy_code(source: Path, target: Path):
    for path in source.rglob("*"):
        if path.is_symlink():
            raise ValueError("source symlink rejected: " + path.name)
        if not path.is_file() or "__pycache__" in path.parts:
            continue
        if path.suffix not in {".py", ".lua"}:
            continue
        destination = target / path.relative_to(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)


def copy_linux_deploy(source: Path, target: Path):
    """Git autocrlf must not produce CRLF shell/logrotate files on the ECS."""
    shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for path in target.rglob("*"):
        if path.is_symlink():
            raise ValueError("deployment symlink rejected")
        if path.is_file():
            # The deployment directory contains text sources only. Decode first
            # so an unexpected binary addition refuses packaging.
            content = path.read_bytes().decode("utf-8")
            path.write_bytes(content.replace("\r\n", "\n").encode("utf-8"))


def build(backend_root: Path, output: Path, release_id: str):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,95}", release_id) or release_id == "current":
        raise ValueError("invalid release id")
    release = output.resolve() / release_id
    if release.exists():
        raise ValueError("release already exists; use a new id")
    # Only explicit source files: never copy .env, VCS, logs, credentials or DB dumps.
    if not (backend_root / "backend/fishing_api/postgres.py").is_file():
        raise ValueError("backend PostgreSQL adapter is missing")
    release.mkdir(parents=True)
    copy_code(backend_root / "backend/fishing_api", release / "backend/fishing_api")
    shutil.copyfile(backend_root / "backend/run_fishing_api.py", release / "backend/run_fishing_api.py")
    copy_code(ROOT / "server/archive_backend", release / "backend/archive_backend")
    shutil.copyfile(backend_root / "requirements.txt", release / "requirements.txt")
    addon = release / "addon"
    csv_names = ("star_blessing_reward_definitions", "fishing_system_rules", "player_gameplay_stats")
    for name in csv_names:
        relative = Path("data/csv/玩家档案系统") / (name + ".csv")
        (addon / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, addon / relative)
    bundle = load("release_archive_bundle", ROOT / "server/archive_backend/bundle.py")
    bundle_dest = addon / "server/bundles"
    # Keep old settlement versions for durable pending operations created before deployment.
    existing = ROOT / "server/bundles"
    if existing.exists():
        for path in existing.iterdir():
            if path.is_dir() and re.fullmatch(r"[0-9a-f]{64}", path.name):
                checked = bundle.Bundle(path)
                shutil.copytree(checked.directory, bundle_dest / checked.hash,
                                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    digest = bundle.build(ROOT, bundle_dest, update_game_config=False)
    candidate = release / "game-config/archive_http_bundle.lua"
    candidate.parent.mkdir()
    candidate.write_text('-- Apply to the TEST game only after backend acceptance.\nreturn { protocol = 1, hash = "' + digest + '" }\n', encoding="utf-8")
    database = load("release_database_tool", ROOT / "server/aliyun/database/dbtool.py")
    database.collect(backend_root, ROOT, release / "database")
    deploy_source = ROOT / "server/aliyun/deploy"
    copy_linux_deploy(deploy_source, release / "deploy")
    for path in (ROOT / "server/aliyun/tests").glob("*.py"):
        (release / "tests").mkdir(exist_ok=True)
        shutil.copyfile(path, release / "tests" / path.name)
    docs = ROOT / "docs/ALIYUN_TEST_MIGRATION.md"
    if docs.exists():
        (release / "README.md").write_text(docs.read_text(encoding="utf-8").replace("../server/aliyun/validation/", "validation/"), encoding="utf-8")
    (release / "BACKEND_AUDIT.md").write_text((ROOT / "docs/ALIYUN_BACKEND_AUDIT.md").read_text(encoding="utf-8").replace("](ALIYUN_TEST_MIGRATION.md)", "](README.md)"), encoding="utf-8")
    validation = ROOT / "server/aliyun/validation"
    if validation.exists():
        shutil.copytree(validation, release / "validation")
    files = {p.relative_to(release).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(release.rglob("*")) if p.is_file()}
    manifest = {"format": 1, "release": release_id, "python": "3.11", "database": "PostgreSQL 17",
                "payment_mode": "test", "archive_bundle": digest, "files": files,
                "includes_secrets": False, "game_configuration_changed": False}
    (release / "release_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    archive = output.resolve() / (release_id + ".tar.gz")
    with tarfile.open(archive, "x:gz") as tar:
        def normalize(info):
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mode = 0o755 if info.isdir() or "/pg-bin/" in info.name or info.name.endswith(".sh") else 0o644
            return info
        tar.add(release, arcname=release_id, filter=normalize)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(archive.suffix + ".sha256").write_text(checksum + "  " + archive.name + "\n", encoding="ascii", newline="\n")
    return {"release": str(release), "archive": str(archive), "sha256": checksum,
            "files": len(files), "archive_bundle": digest, "deployed": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend-root", type=Path, default=Path("D:/survival_database"))
    parser.add_argument("--output", type=Path, default=ROOT / "output/aliyun_releases")
    parser.add_argument("--release-id", required=True)
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.backend_root.resolve(), arguments.output, arguments.release_id), ensure_ascii=False))
