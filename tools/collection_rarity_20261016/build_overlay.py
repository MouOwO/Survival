"""Build rarity-only overlay against the inspected online bundle, never dirty-tree full build."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output/collection_rarity_20261016"
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from archive_backend.bundle import Bundle, read_csv
import scope

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")

def write(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        scope.need(path.read_bytes() == raw, "immutable_candidate_file_changed:" + path.name)
    else:
        with path.open("xb") as stream:
            stream.write(raw)

def build(approved_source_sha256):
    baseline = json.loads((OUTPUT / "baseline.json").read_bytes())
    base_hash = baseline["base"]
    scope.need(json.loads((ROOT / "server/bundles/current.json").read_bytes())["hash"] == base_hash,
        "local_bundle_changed_since_read_only_inspection")
    original = Bundle(ROOT / "server/bundles" / base_hash)
    before = json.loads((original.directory / "bundle.json").read_bytes())
    after = copy.deepcopy(before)
    inputs = {}
    for name in scope.TABLES:
        path = ROOT / "data/csv/存档系统" / (name + ".csv")
        incoming = read_csv(path)
        scope.need(incoming == scope.transformed_table(name, before["configs"][name]),
            "local_table_has_unrelated_change:" + name)
        after["configs"][name] = incoming
        relative = path.relative_to(ROOT).as_posix()
        inputs[relative] = sha(path.read_bytes())
        after["csv_hashes"][relative] = sha(path.read_bytes().replace(b"\r\n", b"\n"))
    path = ROOT / "scripts/vscripts" / scope.SOURCE
    after["sources"][scope.SOURCE] = path.read_text(encoding="utf-8-sig")
    scope.need(sha(after["sources"][scope.SOURCE].encode("utf-8")) == approved_source_sha256,
        "approved_source_hash_mismatch")
    inputs[path.relative_to(ROOT).as_posix()] = sha(path.read_bytes())
    after.setdefault("compatible_config_hashes", {})[base_hash] = {"commands": scope.COMMANDS, "upgrade_commands": []}
    scoped = scope.check(before, after, base_hash, approved_source_sha256)
    raw = canonical(after)
    digest = sha(raw)
    destination = OUTPUT / "release" / digest
    bundled = destination / "bundle" / digest
    write(bundled / "bundle.json", raw)
    for name, text in after["sources"].items():
        write(bundled / name, text.encode("utf-8"))
    Bundle(bundled)
    files = {p.relative_to(destination).as_posix(): sha(p.read_bytes()) for p in sorted(bundled.rglob("*")) if p.is_file()}
    plan = {"version": 1, **{key: baseline[key] for key in ("base", "old_release", "old_manifest", "old_service", "old_sync_function", "payment_release")},
        "candidate": digest, "source_sha256": approved_source_sha256, "input_hashes": inputs, "files": files,
        **scoped, "added_stat_definitions": [], "requires_schema_migration": False,
        "active_pointers_changed": False, "old_client_operations_upgrade": False}
    write(destination / "release_plan.json", canonical(plan))
    archive = destination / "rarity_patch.tar.gz"
    if not archive.exists():
        with tarfile.open(archive, "x:gz") as tar:
            for name in [*files, "release_plan.json"]:
                info = tar.gettarinfo(str(destination / name), arcname=name)
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = "root"
                info.mode = 0o644
                with (destination / name).open("rb") as stream:
                    tar.addfile(info, stream)
    result = {"status": "BUILT_NOT_DEPLOYED", "candidate": digest, "base": base_hash,
        "directory": str(destination), "tar_sha256": sha(archive.read_bytes()), **scoped,
        "active_pointers_changed": False, "persistent_writes": 0}
    write(destination / "build_result.json", canonical(result))
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha256", required=True)
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.source_sha256), ensure_ascii=False))
