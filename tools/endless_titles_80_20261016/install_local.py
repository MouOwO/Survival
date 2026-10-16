"""Synchronize the local game only after matching cloud activation and verify."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
RELEASE = ROOT / "output/endless_titles_80_20261016/release_fbf16"
REPORT = ROOT / "output/endless_titles_80_20261016/deployment"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def pointer_hash(name, raw):
    if name.endswith(".json"):
        data = json.loads(raw)
        assert data["protocol"] == 1
        return data["hash"]
    matches = re.findall(rb'\bhash\s*=\s*"([0-9a-f]{64})"', raw)
    assert len(matches) == 1, "ambiguous_game_pointer"
    return matches[0].decode()


def replace_file(destination, raw):
    temporary = destination.with_name(destination.name + ".endless-titles-next")
    assert not temporary.exists() and not temporary.is_symlink()
    try:
        with temporary.open("xb") as stream:
            stream.write(raw)
        os.replace(temporary, destination)
    finally:
        if temporary.is_file() and not temporary.is_symlink():
            temporary.unlink()


def main():
    plan_raw = (RELEASE / "release_plan.json").read_bytes()
    plan = json.loads(plan_raw)
    activated = json.loads((REPORT / "activate.json").read_bytes())
    verified = json.loads((REPORT / "verify.json").read_bytes())
    assert activated["status"] == "DEPLOYED" and verified["status"] == "VERIFIED"
    candidate = plan["candidate"]
    for evidence in (activated, verified):
        assert evidence["archive_bundle"] == candidate and evidence["plan_sha256"] == sha(plan_raw)
        assert evidence["archive_release"] == plan["target_release"]
        assert evidence["operator_sha256"] == sha(Path(__file__).with_name("deploy_remote.py").read_bytes())
    payload_paths = list((RELEASE / "payload").rglob("*"))
    assert all(not path.is_symlink() for path in payload_paths)
    assert {path.relative_to(RELEASE / "payload").as_posix() for path in payload_paths if path.is_file()} == set(plan["files"])
    for name, digest in plan["files"].items():
        assert sha((RELEASE / "payload" / name).read_bytes()) == digest
    for name, digest in plan["input_hashes"].items():
        assert sha((ROOT / name).read_bytes()) == digest, "title_input_changed:" + name
    source = RELEASE / "payload/bundle" / candidate
    target = ROOT / "server/bundles" / candidate
    assert target.resolve().is_relative_to(ROOT.resolve()) and not target.is_symlink()
    for path in source.rglob("*"):
        assert not path.is_symlink()
        if path.is_file():
            destination = target / path.relative_to(source)
            assert not any(p.is_symlink() for p in (destination, *destination.parents) if p != ROOT.parent)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists():
                assert destination.read_bytes() == path.read_bytes()
            else:
                with destination.open("xb") as stream:
                    stream.write(path.read_bytes())
    assert sha((target / "bundle.json").read_bytes()) == candidate
    replacements = {
        "server/bundles/current.json": json.dumps({"hash": candidate, "protocol": 1}, separators=(",", ":")).encode() + b"\n",
        "scripts/vscripts/config/generated/archive_http_bundle.lua": (
            "-- Verified endless title tiers every 80 waves; reopen the map.\n"
            'return { protocol = 1, hash = "' + candidate + '" }\n').encode(),
    }
    backup = REPORT / "local_pointer_backup"
    backup.mkdir(exist_ok=True)
    changes, previous_values = {}, {}
    for name, raw in replacements.items():
        destination = ROOT / name
        assert not destination.is_symlink()
        previous = destination.read_bytes()
        previous_values[name] = previous
        if previous == raw:
            continue
        assert pointer_hash(name, previous) == plan["base"], "local_pointer_changed:" + name
        saved = backup / destination.name
        if saved.exists():
            assert saved.read_bytes() == previous
        else:
            with saved.open("xb") as stream:
                stream.write(previous)
        changes[name] = {"previous_sha256": sha(previous), "new_sha256": sha(raw)}
    written = []
    try:
        for name, raw in replacements.items():
            destination = ROOT / name
            assert destination.read_bytes() == previous_values[name], "concurrent_pointer_change:" + name
            if previous_values[name] == raw:
                continue
            replace_file(destination, raw)
            written.append(name)
    except BaseException:
        for name in reversed(written):
            destination = ROOT / name
            assert destination.read_bytes() == replacements[name], "concurrent_pointer_change_during_rollback:" + name
            replace_file(destination, previous_values[name])
        raise
    result = {"status": "LOCAL_GAME_HASH_UPDATED", "archive_bundle": candidate,
              "pointers": changes, "old_bundle_retained": (ROOT / "server/bundles" / plan["base"] / "bundle.json").is_file(),
              "requires_new_map": True}
    (REPORT / "local_activation.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
