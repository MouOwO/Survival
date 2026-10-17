"""Update only local immutable bundle/pointers after verified server activation."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def finalize(candidate):
    if not re.fullmatch(r"[0-9a-f]{64}", candidate):
        raise ValueError("candidate_hash_invalid")
    directory = ROOT / "output/collection_rarity_20261016/release" / candidate
    plan = json.loads((directory / "release_plan.json").read_bytes())
    reports = directory / "deployment"
    activated = json.loads((reports / "activate.json").read_bytes())
    verified = json.loads((reports / "verify.json").read_bytes())
    assert activated["status"] == "DEPLOYED" and verified["status"] == "VERIFIED"
    assert activated["archive_bundle"] == verified["archive_bundle"] == plan["candidate"] == candidate
    assert activated["item_count"] == verified["item_count"] == plan["item_count"]
    for name, digest in plan["files"].items():
        assert sha((directory / name).read_bytes()) == digest, name
    for name, digest in plan["input_hashes"].items():
        assert sha((ROOT / name).read_bytes()) == digest, "task_source_changed:" + name
    source = directory / "bundle" / candidate
    target = ROOT / "server/bundles" / candidate
    assert target.resolve().is_relative_to(ROOT.resolve()) and not target.is_symlink()
    for path in source.rglob("*"):
        assert not path.is_symlink()
        if path.is_file():
            destination = target / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            assert not destination.is_symlink()
            if destination.exists():
                assert destination.read_bytes() == path.read_bytes()
            else:
                with destination.open("xb") as stream:
                    stream.write(path.read_bytes())
    replacements = {
        "server/bundles/current.json": json.dumps({"hash": candidate, "protocol": 1}, separators=(",", ":")).encode() + b"\n",
        "scripts/vscripts/config/generated/archive_http_bundle.lua": ("-- Verified collection rarity server deployment; reopen the map.\nreturn { protocol = 1, hash = \"" + candidate + "\" }\n").encode(),
    }
    backup = reports / "local_pointer_backup"
    backup.mkdir(exist_ok=True)
    changes = {}
    for name, raw in replacements.items():
        destination = ROOT / name
        old = destination.read_bytes()
        if old == raw:
            continue
        assert plan["base"].encode() in old, "local_pointer_changed_since_review:" + name
        saved = backup / ("current.json" if name.endswith(".json") else "archive_http_bundle.lua")
        if saved.exists():
            assert saved.read_bytes() == old
        else:
            with saved.open("xb") as stream:
                stream.write(old)
        changes[name] = {"previous_sha256": sha(old), "new_sha256": sha(raw)}
    for name, raw in replacements.items():
        destination = ROOT / name
        if destination.read_bytes() == raw:
            continue
        temporary = destination.with_name(destination.name + ".rarity-next")
        assert not temporary.exists() and not temporary.is_symlink()
        with temporary.open("xb") as stream:
            stream.write(raw)
        os.replace(temporary, destination)
    result = {"status": "LOCAL_GAME_HASH_UPDATED", "archive_bundle": candidate, "item_count": plan["item_count"],
        "pointers": changes, "old_bundle_retained": (ROOT / "server/bundles" / plan["base"] / "bundle.json").is_file(),
        "unrelated_configuration_rebuilt": False, "requires_new_map": True}
    (reports / "local_activation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", "utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True)
    args = parser.parse_args()
    print(json.dumps(finalize(args.candidate), ensure_ascii=False))
