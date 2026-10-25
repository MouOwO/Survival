"""List runtime files, or stage that exact list into an explicit external directory.

This is an addon staging tool, not a Workshop uploader or ignore configuration.
Default operation writes a manifest only; it never changes the source project.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RULES = {
    "scripts/npc": {".txt"},
    "scripts/vscripts": {".lua"},
    "panorama/layout": {".vxml_c"},
    "panorama/scripts": {".vjs_c"},
    "panorama/styles": {".vcss_c"},
    "panorama/images": {".vtex_c", ".vsvg_c"},
    "panorama/fonts": {".otf", ".ttf", ".ttc", ".txt"},
    "panorama/videos": {".webm", ".mp4", ".avi"},
    "panorama/localization": {".txt"},
    "materials": {".vmat_c", ".vtex_c"},
    "models": {".vmdl_c", ".vanim_c", ".vmesh_c", ".vphys_c", ".vagrp_c", ".vseq_c"},
    "particles": {".vpcf_c"},
    "soundevents": {".vsndevts_c"},
    "sounds": {".vsnd_c"},
    "resource": {".txt"},
    # Map entity aggregation can reference loose models beside the map VPK.
    "maps": {".vmdl_c", ".vmat_c", ".vtex_c", ".vphys_c", ".vanim_c", ".vmesh_c", ".vpcf_c"},
}
EXACT = {"addoninfo.txt", "scripts/custom_net_tables.txt"}
OPTIONAL_EXACT = {"scripts/custom.gameevents"}
EXCLUDED_EXACT = {
    # Historical base is rebuilt by offline regression helpers. It has no
    # shipping layout entry; retain the fixture in source, exclude its package.
    "panorama/styles/custom_game/lottery_fullscreen_v2.vcss_c": "retired UI regression fixture",
}
SCENE_MAPS = {
    "maps/portraits/builder_io_companion_v2.vpk",
    "maps/portraits/doom_soft_a.vpk",
    "maps/portraits/juggernaut_arcana_origins_v5.vpk",
}
CRITICAL = {
    "addoninfo.txt", "scripts/custom_net_tables.txt",
    "scripts/vscripts/addon_game_mode.lua", "scripts/npc/npc_units_custom.txt",
    "scripts/vscripts/config/release_profile.lua",
    "scripts/npc/npc_abilities_custom.txt", "scripts/npc/npc_items_custom.txt",
    "scripts/npc/npc_heroes_custom.txt", "scripts/npc/portraits_custom.txt",
    "panorama/layout/custom_game/custom_ui_manifest.vxml_c",
    "panorama/layout/custom_game/custom_loading_screen.vxml_c",
    "resource/custom_game_whitelist.txt", "resource/addon_english.txt", "resource/addon_schinese.txt",
}
BLOCKED_PARTS = {"tests", "__pycache__", "node_modules", ".venv", ".pytest_cache"}
RELEASE_PROFILE = "scripts/vscripts/config/release_profile.lua"


def require_production(root: Path) -> None:
    """Read only the controlled literal profile grammar; never execute its Lua."""
    path = root / RELEASE_PROFILE
    if not path.is_file() or is_link(path) or not within(path.resolve(strict=True), root.resolve(strict=True)):
        raise ValueError("Release profile is missing or linked")
    text = path.read_text(encoding="utf-8-sig")
    token = re.compile(r"\s+|--[^\r\n]*|\"[^\"\\\r\n]*\"|'[^'\\\r\n]*'|[A-Za-z_][A-Za-z_0-9]*|[{}=,;]")
    position, values = 0, []
    while position < len(text):
        match = token.match(text, position)
        if match is None:
            raise ValueError("Release profile must be a single literal channel table")
        value = match.group()
        position = match.end()
        if value.startswith("--"):
            if value.startswith("--["):
                raise ValueError("Release profile block comments are not supported")
        elif not value.isspace():
            values.append(value)
    if values and values[-1] == ";":
        values.pop()
    if len(values) == 7 and values[-2] == ",":
        values.pop(-2)
    if (len(values) != 6 or values[:4] != ["return", "{", "channel", "="]
            or values[-1] != "}" or values[4] not in {'"production"', "'production'"}):
        raise ValueError("Release profile must explicitly select production")


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def checksums(path: Path) -> dict:
    """Hash one stable read. MD5 is a change index, never authentication."""
    before = path.stat()
    hashes = {"md5": hashlib.md5(usedforsecurity=False), "sha256": hashlib.sha256()}
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            for result in hashes.values():
                result.update(block)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ValueError("Source changed while hashing: " + str(path))
    return {"bytes": after.st_size, **{name: result.hexdigest() for name, result in hashes.items()}}


def canonical_bytes(value: dict) -> bytes:
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"),
                      allow_nan=False).encode("ascii")


def manifest_payload(data: dict) -> bytes:
    """Stable bytes for the content ID and optional detached release signatures.

    Local paths and diagnostics are excluded. Every shipped path, size and both
    file hashes are covered; no private signing key belongs in this document.
    """
    return canonical_bytes({name: data[name] for name in
                            ("schema", "kind", "hash_algorithms", "file_count", "bytes", "files")})


def safe_relative(value: str) -> bool:
    return (isinstance(value, str) and bool(value) and "\\" not in value
            and ":" not in value and "\x00" not in value and not value.startswith("/")
            and all(part not in {"", ".", ".."} for part in value.split("/")))


def validate_manifest(data: dict, *, require_dual: bool = True) -> None:
    if not isinstance(data, dict) or not isinstance(data.get("files"), list):
        raise ValueError("Invalid runtime manifest")
    paths = []
    for row in data["files"]:
        if not isinstance(row, dict) or not safe_relative(row.get("path")):
            raise ValueError("Unsafe manifest path")
        paths.append(row["path"])
        if isinstance(row.get("bytes"), bool) or not isinstance(row.get("bytes"), int) or row["bytes"] < 0:
            raise ValueError("Invalid manifest size: " + row["path"])
        for name, width in (("sha256", 64), ("md5", 32)):
            value = row.get(name)
            if name == "md5" and value is None and not require_dual:
                continue
            if not isinstance(value, str) or not re.fullmatch("[0-9a-f]{" + str(width) + "}", value):
                raise ValueError("Invalid manifest " + name + ": " + row["path"])
    if len(paths) != len(set(paths)) or len(paths) != len({path.casefold() for path in paths}):
        raise ValueError("Duplicate manifest path")
    if paths != sorted(paths):
        raise ValueError("Manifest paths must be sorted")
    if data.get("kind") != "runtime_release_allowlist" or data.get("schema") not in {1, 2}:
        raise ValueError("Unsupported runtime manifest schema")
    if data.get("schema") == 1:
        if require_dual:
            raise ValueError("Legacy SHA-only manifest can be compared, but not verified or staged")
        return
    if data.get("hash_algorithms") != ["md5", "sha256"]:
        raise ValueError("Unsupported manifest hash algorithms")
    if (type(data.get("file_count")) is not int or type(data.get("bytes")) is not int
            or data.get("file_count") != len(paths)
            or data.get("bytes") != sum(row["bytes"] for row in data["files"])):
        raise ValueError("Manifest totals do not match file entries")
    if data.get("content_sha256") != hashlib.sha256(manifest_payload(data)).hexdigest():
        raise ValueError("Manifest content ID mismatch")


def atomic_write_json(path: Path, data: dict) -> None:
    """Replace a single report atomically, never an addon directory."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n", dir=path.parent,
                                         prefix="." + path.name + ".", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def is_link(path: Path) -> bool:
    return path.is_symlink() or bool(getattr(path, "is_junction", lambda: False)())


def within(path: Path, parent: Path) -> bool:
    return path == parent or parent in path.parents


def map_files(root: Path) -> set[str]:
    """Read the shipping map names from AddonInfo, retaining explicitly used scenes."""
    info = root / "addoninfo.txt"
    if not info.is_file():
        raise ValueError("Missing addoninfo.txt")
    match = re.search(r'"maps"\s+"([^"\r\n]+)"', info.read_text(encoding="utf-8-sig"))
    if not match:
        raise ValueError("AddonInfo maps are missing; refusing to guess shipping maps")
    result = set(SCENE_MAPS)
    for name in match.group(1).split():
        if not re.fullmatch(r"[A-Za-z0-9_/-]+", name) or ".." in name.split("/"):
            raise ValueError("Invalid AddonInfo map name")
        result.add("maps/" + name + ".vpk")
    # The sole Workshop entry reopens this fixed internal gameplay map. Keep
    # it in signed inventories even though it is not exposed in the lobby list.
    if match.group(1) == "ws4_entry":
        result.add("maps/template_map.vpk")
    if match.group(1) == "ws4_lobby":
        result.add("maps/template_map.vpk")
    return result


def select(root: Path, *, check_critical: bool = True) -> tuple[list[str], list[dict]]:
    root = root.resolve(strict=True)
    selected = set(EXACT) | map_files(root)
    selected.update(name for name in OPTIONAL_EXACT if (root / name).is_file())
    excluded = []
    for folder, extensions in RULES.items():
        base = root / folder
        if not base.exists():
            continue
        if is_link(base):
            raise ValueError("Runtime root is a link/junction: " + folder)
        for current, dirs, names in os.walk(base, followlinks=False):
            current_path = Path(current)
            for name in list(dirs):
                path = current_path / name
                relative = path.relative_to(root).as_posix()
                if is_link(path):
                    raise ValueError("Runtime directory is a link/junction: " + relative)
                if name in BLOCKED_PARTS or name.startswith("."):
                    dirs.remove(name)
                    excluded.append({"path": relative + "/", "reason": "development directory"})
            for name in names:
                path = current_path / name
                relative = path.relative_to(root).as_posix()
                if is_link(path):
                    raise ValueError("Runtime file is a link: " + relative)
                suffix = path.suffix.lower()
                if relative in EXCLUDED_EXACT:
                    excluded.append({"path": relative, "reason": EXCLUDED_EXACT[relative]})
                elif name.startswith(".") or any(part in BLOCKED_PARTS for part in path.relative_to(root).parts):
                    excluded.append({"path": relative, "reason": "development file"})
                elif suffix in extensions:
                    selected.add(relative)
                elif suffix.endswith("_c"):
                    raise ValueError("Unreviewed compiled resource type: " + relative)
                else:
                    excluded.append({"path": relative, "reason": "not a runtime allowlist type"})
    if check_critical:
        missing = sorted(p for p in CRITICAL | map_files(root) if not (root / p).is_file())
        if missing:
            raise ValueError("Missing required runtime files: " + ", ".join(missing))
    selected = {p for p in selected if (root / p).is_file()}
    for p in selected:
        source = root / p
        if is_link(source) or not within(source.resolve(strict=True), root):
            raise ValueError("Runtime selection escapes source root: " + p)
    return sorted(selected), sorted(excluded, key=lambda row: row["path"])


def manifest(root: Path, *, check_critical: bool = True) -> dict:
    root = root.resolve(strict=True)
    require_production(root)
    paths, excluded = select(root, check_critical=check_critical)
    files = []
    for relative in paths:
        source = root / relative
        files.append({"path": relative, **checksums(source)})
    data = {"schema": 2, "kind": "runtime_release_allowlist", "source_root": str(root),
            "hash_algorithms": ["md5", "sha256"],
            "files": files, "file_count": len(files), "bytes": sum(row["bytes"] for row in files),
            "by_directory": dict(sorted(Counter(row["path"].split("/")[0] for row in files).items())),
            "excluded_runtime_tree_files": excluded,
            "development_roots_not_traversed": ["panorama/src", "art", "artifacts", "apps", "tools", "server", "docs", "output", "design_refs", "validation", "tmp", "data", "cfg", ".git", ".aws", ".codex", ".agents"],
            "workshop_upload_performed": False,
            "limitations": ["Manifest and staging do not replace an installed-game smoke test.",
                            "MD5 is a change index, not authentication. SHA256 verifies integrity against a trusted manifest; authenticity requires a separately trusted signature.",
                            "Offline verification does not inspect or rewrite remote clients. Native scripts/assets update through the platform release, not arbitrary Panorama filesystem access.",
                            "All compiled runtime asset families and Lua modules are retained for dynamic dependencies; this is not a filename-only reachability prune.",
                            "Tests and Tools-mode-only automation fixtures are excluded from the client candidate, retained in source control."]}
    data["content_sha256"] = hashlib.sha256(manifest_payload(data)).hexdigest()
    return data


def compare_manifests(baseline: dict, candidate: dict) -> dict:
    """Describe updates without applying changes or deleting old files."""
    validate_manifest(baseline, require_dual=False)
    validate_manifest(candidate)
    old = {row["path"]: row for row in baseline["files"]}
    new = {row["path"]: row for row in candidate["files"]}
    added = sorted(new.keys() - old.keys())
    removed = sorted(old.keys() - new.keys())
    modified = []
    for path in sorted(old.keys() & new.keys()):
        fields = [field for field in ("bytes", "md5", "sha256")
                  if field in old[path] and old[path][field] != new[path][field]]
        if fields:
            modified.append({"path": path, "changed": fields, "before": old[path], "after": new[path]})
    return {"schema": 1, "kind": "runtime_release_diff", "baseline_content_sha256": baseline.get("content_sha256"),
            "candidate_content_sha256": candidate["content_sha256"], "added": added,
            "modified": modified, "removed": removed,
            "unchanged_count": len(old.keys() & new.keys()) - len(modified),
            "changed_bytes": sum(new[path]["bytes"] for path in added)
                             + sum(row["after"]["bytes"] for row in modified),
            "updates_applied": False}


def verify(root: Path, data: dict, *, check_critical: bool = True) -> dict:
    """Verify every expected byte and reject unexpected runtime files."""
    validate_manifest(data)
    root = root.resolve(strict=True)
    missing, modified, errors = [], [], []
    expected = {row["path"]: row for row in data["files"]}
    try:
        require_production(root)
    except (OSError, ValueError) as error:
        errors.append({"path": RELEASE_PROFILE, "error": str(error)})
    for relative, row in expected.items():
        path = root / relative
        if not path.exists():
            missing.append(relative)
            continue
        if is_link(path) or not within(path.resolve(strict=True), root) or not path.is_file():
            errors.append({"path": relative, "error": "not a regular file within source root"})
            continue
        # Ancestor junctions must fail even if they resolve back into the root.
        if any(is_link(parent) for parent in path.parents if parent != root and within(parent, root)):
            errors.append({"path": relative, "error": "linked ancestor"})
            continue
        try:
            actual = checksums(path)
        except (OSError, ValueError) as error:
            errors.append({"path": relative, "error": str(error)})
            continue
        fields = [field for field in ("bytes", "md5", "sha256") if actual[field] != row[field]]
        if fields:
            modified.append({"path": relative, "changed": fields, "expected": row, "actual": actual})
    actual_paths = set()
    try:
        actual_paths = set(select(root, check_critical=check_critical)[0])
    except (OSError, ValueError) as error:
        errors.append({"path": "", "error": str(error)})
    unexpected = sorted(actual_paths - expected.keys())
    outside_policy = sorted(expected.keys() - actual_paths - set(missing)) if not errors else []
    return {"schema": 1, "kind": "runtime_release_verification", "root": str(root),
            "content_sha256": data["content_sha256"], "expected_files": len(expected),
            "missing": missing, "modified": modified, "unexpected_runtime": unexpected,
            "outside_runtime_policy": outside_policy, "errors": errors,
            "ok": not (missing or modified or unexpected or outside_policy or errors),
            "authenticity_verified": False, "files_changed": False}


def stage(root: Path, destination: Path, data: dict) -> None:
    """Copy individual reviewed files. Never recurse/copy/delete an addon tree."""
    root = root.resolve(strict=True)
    if not destination.is_absolute():
        raise ValueError("--stage requires an explicit absolute external directory")
    destination = destination.resolve(strict=False)
    if within(destination, root) or within(root, destination):
        raise ValueError("Staging directory must be outside, and not an ancestor of, the addon")
    installed_engine = ROOT.parents[2]
    if within(destination, installed_engine):
        raise ValueError("Staging directory must be outside the installed game/content tree")
    if destination.exists():
        raise ValueError("Staging directory already exists; choose a new empty destination")
    result = verify(root, data, check_critical=False)
    if not result["ok"]:
        raise ValueError("Source changed after manifest or failed runtime policy verification")
    destination.mkdir(parents=True, exist_ok=False)
    for row in data["files"]:
        source = root / row["path"]
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        if checksums(target) != {field: row[field] for field in ("bytes", "md5", "sha256")}:
            raise ValueError("Staged file verification failed: " + row["path"])
    if not verify(destination, data, check_critical=False)["ok"]:
        raise ValueError("Staged runtime changed before completion")
    atomic_write_json(destination / "_release_manifest.json", data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--manifest", type=Path, help="Build and write a dual-hash runtime manifest")
    action.add_argument("--verify", type=Path, help="Verify this manifest against --root; never change runtime files")
    parser.add_argument("--root", type=Path, default=ROOT, help="Runtime directory; defaults to this addon")
    parser.add_argument("--stage", type=Path, help="Also copy the exact manifest to a NEW absolute external directory")
    parser.add_argument("--baseline", type=Path, help="Compare a previous runtime manifest without applying updates")
    parser.add_argument("--diff", type=Path, help="Write a difference report (requires --baseline)")
    parser.add_argument("--report", type=Path, help="Write the offline verification report (requires --verify)")
    args = parser.parse_args()
    if args.verify and (args.stage or args.baseline or args.diff):
        parser.error("--verify cannot be combined with staging or baseline comparison")
    if args.report and not args.verify:
        parser.error("--report requires --verify")
    if bool(args.baseline) != bool(args.diff):
        parser.error("--baseline and --diff must be used together")
    try:
        outputs = [path for path in (args.manifest, args.diff, args.report) if path is not None]
        source_root = args.root.resolve(strict=True)
        for path in outputs:
            resolved = path.resolve(strict=False)
            for source in {ROOT, source_root}:
                if within(resolved, source) and not within(resolved, source / "output"):
                    raise ValueError("A generated report inside the addon must be written under output/")
            if args.stage and within(resolved, args.stage.resolve(strict=False)):
                raise ValueError("Report outputs must be outside the staged runtime candidate")
        if len({path.resolve(strict=False) for path in outputs}) != len(outputs):
            raise ValueError("Manifest and report outputs must be different files")
        inputs = [path.resolve(strict=True) for path in (args.verify, args.baseline) if path is not None]
        if any(path.resolve(strict=False) in inputs for path in outputs):
            raise ValueError("Reports must not overwrite input manifests")
        if args.verify:
            data = json.loads(args.verify.read_text(encoding="utf-8-sig"))
            result = verify(args.root, data)
            if args.report:
                atomic_write_json(args.report, result)
            print(json.dumps({key: result[key] for key in
                              ("ok", "content_sha256", "expected_files", "missing", "modified", "unexpected_runtime",
                               "outside_runtime_policy", "errors", "authenticity_verified", "files_changed")}))
            return 0 if result["ok"] else 1
        data = manifest(args.root)
        differences = None
        if args.baseline:
            baseline = json.loads(args.baseline.read_text(encoding="utf-8-sig"))
            differences = compare_manifests(baseline, data)
        if args.stage:
            stage(args.root, args.stage, data)
        atomic_write_json(args.manifest, data)
        if differences is not None:
            atomic_write_json(args.diff, differences)
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("Runtime release failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps({"manifest": str(args.manifest), "files": data["file_count"], "bytes": data["bytes"],
                      "content_sha256": data["content_sha256"],
                      "diff": {"added": len(differences["added"]), "modified": len(differences["modified"]),
                               "removed": len(differences["removed"])} if differences is not None else None,
                      "staged": str(args.stage) if args.stage else None, "uploaded": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
