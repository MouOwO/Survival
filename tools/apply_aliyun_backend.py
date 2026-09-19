"""Apply reviewed staged backend files to the original repo, without touching .env.

Dry-run by default. Every existing source is checked against the recorded baseline
before any write; concurrent/user edits cause a refusal. No deletion or restart.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def allowed(path):
    parts = path.parts
    return ((len(parts) >= 3 and parts[0] == "backend" and parts[1] in {"fishing_api", "archive_backend", "tests"}
             and path.suffix in {".py", ".lua", ".csv"})
            or path.as_posix() in {"requirements.txt", ".env.example", "README.md"})


def apply(stage: Path, target: Path, write: bool):
    stage, target = stage.resolve(), target.resolve()
    baseline = json.loads((stage / "source_baseline.json").read_text(encoding="utf-8"))
    changes = []
    for source in sorted(stage.rglob("*")):
        if not source.is_file() or source.is_symlink():
            continue
        rel = source.relative_to(stage)
        if not allowed(rel) or "__pycache__" in rel.parts:
            continue
        destination = target / rel
        if destination.resolve().is_relative_to(target) is False or destination.is_symlink():
            raise ValueError("unsafe destination")
        if destination.exists() and sha(destination) == sha(source):
            continue
        key = rel.as_posix()
        if destination.exists():
            if key not in baseline or sha(destination) != baseline[key]:
                raise ValueError("source changed since audit: " + key)
        elif key in baseline:
            raise ValueError("source was removed since audit: " + key)
        changes.append((source, destination, rel))
    if write:
        backup = stage / "source_code_backup"
        for source, destination, rel in changes:
            if destination.exists():
                original = backup / rel
                original.parent.mkdir(parents=True, exist_ok=True)
                if not original.exists():
                    shutil.copyfile(destination, original)
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + ".aliyun-new")
            if temporary.exists():
                raise ValueError("temporary file already exists")
            shutil.copyfile(source, temporary)
            temporary.replace(destination)
    return {"applied": write, "target": str(target), "files": [r.as_posix() for _, _, r in changes],
            "env_changed": False, "game_switched": False, "service_restarted": False}


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, default=root / "output/ecs_backend_work")
    parser.add_argument("--target", type=Path, default=Path("D:/survival_database"))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(args.stage, args.target, args.apply), ensure_ascii=False, indent=2))
