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
    "scripts/npc/npc_abilities_custom.txt", "scripts/npc/npc_items_custom.txt",
    "scripts/npc/npc_heroes_custom.txt", "scripts/npc/portraits_custom.txt",
    "panorama/layout/custom_game/custom_ui_manifest.vxml_c",
    "panorama/layout/custom_game/custom_loading_screen.vxml_c",
    "resource/custom_game_whitelist.txt", "resource/addon_english.txt", "resource/addon_schinese.txt",
}
BLOCKED_PARTS = {"tests", "__pycache__", "node_modules", ".venv", ".pytest_cache"}


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


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
    return result


def select(root: Path, *, check_critical: bool = True) -> tuple[list[str], list[dict]]:
    root = root.resolve(strict=True)
    selected = set(EXACT) | map_files(root)
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
    paths, excluded = select(root, check_critical=check_critical)
    files = []
    for relative in paths:
        source = root / relative
        before = source.stat()
        checksum = digest(source)
        after = source.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise ValueError("Source changed while hashing: " + relative)
        files.append({"path": relative, "bytes": after.st_size, "sha256": checksum})
    return {"schema": 1, "kind": "runtime_release_allowlist", "source_root": str(root),
            "files": files, "file_count": len(files), "bytes": sum(row["bytes"] for row in files),
            "by_directory": dict(sorted(Counter(row["path"].split("/")[0] for row in files).items())),
            "excluded_runtime_tree_files": excluded,
            "development_roots_not_traversed": ["panorama/src", "art", "artifacts", "apps", "tools", "server", "docs", "output", "design_refs", "validation", "tmp", "data", "cfg", ".git", ".aws", ".codex", ".agents"],
            "workshop_upload_performed": False,
            "limitations": ["Manifest and staging do not replace an installed-game smoke test.",
                            "All compiled runtime asset families and Lua modules are retained for dynamic dependencies; this is not a filename-only reachability prune.",
                            "Tests and Tools-mode-only automation fixtures are excluded from the client candidate, retained in source control."]}


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
    for row in data["files"]:
        relative = Path(row["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Unsafe manifest path")
        source = root / relative
        if is_link(source) or not within(source.resolve(strict=True), root) or digest(source) != row["sha256"]:
            raise ValueError("Source changed after manifest: " + row["path"])
    destination.mkdir(parents=True, exist_ok=False)
    for row in data["files"]:
        source = root / row["path"]
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        if target.stat().st_size != row["bytes"] or digest(target) != row["sha256"]:
            raise ValueError("Staged file verification failed: " + row["path"])
    (destination / "_release_manifest.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True, help="Write the reviewed per-file manifest here")
    parser.add_argument("--stage", type=Path, help="Also copy the exact manifest to a NEW absolute external directory")
    args = parser.parse_args()
    try:
        report_path = args.manifest.resolve(strict=False)
        if within(report_path, ROOT) and not within(report_path, ROOT / "output"):
            raise ValueError("A manifest inside the addon must be written under output/")
        data = manifest(ROOT)
        if args.stage:
            stage(ROOT, args.stage, data)
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (ValueError, OSError) as error:
        print("Runtime release failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps({"manifest": str(args.manifest), "files": data["file_count"], "bytes": data["bytes"], "staged": str(args.stage) if args.stage else None, "uploaded": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
