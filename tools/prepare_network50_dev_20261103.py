"""Copy a fresh, tree-external Tools snapshot. Never launch or grant anything.

plan is read-only. prepare copies (no hardlinks), hashes source/destination,
rehashes every source, then creates only the two fresh explicit junctions.
Any drift/failure leaves evidence and files in place; no cleanup/overwrite.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parents[2]
AUTHOR = ENGINE / "content/dota_addons/Survival"
STORE = Path("D:/Survival_本地排演/network50_dev_20261103")
ALIAS = "svt_network50_dev"
RUNTIME_DIRS = ("scripts", "panorama", "maps", "materials", "models", "particles",
                "resource", "soundevents", "sounds", "cfg")
SKIP_DIRS = {".git", ".idea", ".vscode", ".codex", "output", "tools", "tests",
             "__pycache__", "node_modules", "secrets", "credentials"}
SKIP_SUFFIXES = {".pem", ".key", ".pfx", ".p12", ".env", ".mdmp", ".dmp",
                 ".zip", ".7z", ".bak", ".tmp", ".pyc", ".log"}


def need(value, message):
    if not value:
        raise ValueError(message)


def reparse(path):
    value = os.lstat(path)
    return stat.S_ISLNK(value.st_mode) or bool(getattr(value, "st_file_attributes", 0) & 0x400)


def no_reparse_ancestors(path):
    for part in (path, *path.parents):
        if os.path.lexists(part):
            need(not reparse(part), "reparse_ancestor_refused:" + str(part))


def source_stat(path):
    value = path.stat()
    need(stat.S_ISREG(value.st_mode) and not reparse(path), "normal_file_required:" + str(path))
    return dict(size=value.st_size, mtime_ns=value.st_mtime_ns, device=value.st_dev, inode=value.st_ino)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_new(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(payload)


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def head(repo):
    value = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"],
                           capture_output=True, text=True, check=True)
    commit = value.stdout.strip()
    need(bool(re.fullmatch(r"[0-9a-f]{40}", commit)), "git_head_required")
    # Observation only, not a source-release assertion and no Git mutations.
    return commit


def roots(run):
    need(bool(re.fullmatch(r"run[0-9]{2}", run)), "exact_run_name_required")
    base = STORE / run
    need(base.absolute().parent == STORE.absolute(), "exact_external_parent_required")
    need(not base.absolute().is_relative_to(ROOT.absolute()), "lab_must_be_outside_addon")
    mounts = ((ROOT.parent / ALIAS, base / "game"),
              (AUTHOR.parent / ALIAS, base / "content"))
    for path in (STORE, base, *(p for p, _ in mounts)):
        no_reparse_ancestors(path)
    for path in (base, *(p for p, _ in mounts)):
        need(not os.path.lexists(path), "fresh_path_required:" + str(path))
    return base, mounts


def trusted_gates():
    checks = {
        "scripts/vscripts/config/release_profile.lua": r'channel\s*=\s*"development"',
        "scripts/vscripts/config/player_web_auth.lua": r"enabled\s*=\s*false",
        "scripts/vscripts/config/commerce_payment_access.lua": r"enabled\s*=\s*false",
    }
    out = {}
    for relative, pattern in checks.items():
        path = ROOT / relative
        text = path.read_text(encoding="utf-8-sig")
        text = re.sub(r"--[^\n]*", "", text)
        need(re.search(pattern, text), "trusted_offline_gate_required:" + relative)
        out[relative] = sha(path)
    offline = ROOT / "scripts/vscripts/debug/offline_logic_test.lua"
    text = offline.read_text(encoding="utf-8-sig")
    for marker in ("offline_logic_tools_required", "offline_logic_web_auth_conflict", "storage=session_memory cloud=false"):
        need(marker in text, "existing_offline_latch_required:" + marker)
    out[offline.relative_to(ROOT).as_posix()] = sha(offline)
    return out


def inventory():
    records, excluded, absent = [], [], []
    for name in RUNTIME_DIRS:
        directory = ROOT / name
        if not directory.exists():
            absent.append(name)
            continue
        need(not reparse(directory), "source_root_reparse_refused:" + name)
        for current, directories, files in os.walk(directory, followlinks=False):
            current = Path(current)
            keep = []
            for child in sorted(directories):
                path = current / child
                relative = path.relative_to(ROOT).as_posix()
                if child in SKIP_DIRS or child.startswith(".") or relative == "panorama/src":
                    excluded.append(relative + "/")
                    continue
                need(not reparse(path), "source_reparse_refused:" + relative)
                keep.append(child)
            directories[:] = keep
            for child in sorted(files):
                path = current / child
                relative = path.relative_to(ROOT).as_posix()
                if child.startswith(".") or path.suffix.lower() in SKIP_SUFFIXES:
                    excluded.append(relative)
                    continue
                need(path.suffix.lower() != ".vpk" or relative.startswith("maps/"),
                     "bare_package_outside_maps_refused:" + relative)
                if path.suffix.lower() == ".vpk":
                    need(not re.search(r"(?:_dir|_[0-9]{3})\.vpk$", child, re.I),
                         "package_volume_refused:" + relative)
                records.append(dict(area="game", relative=relative, source=str(path), observed=source_stat(path)))
    addon = ROOT / "addoninfo.txt"
    records.append(dict(area="game", relative="addoninfo.txt", source=str(addon), observed=source_stat(addon)))
    # Tools may recompile resources whose metadata names the original addon.
    # A short author list misses imported CSS/XML/images and makes that compile
    # fail. Preserve the complete current Panorama dependency tree in run02+.
    # Editable models/maps remain outside this UI-only author snapshot; their
    # compiled runtime dependencies are copied under the game allowlist above.
    author_panorama = AUTHOR / "panorama"
    no_reparse_ancestors(author_panorama)
    need(author_panorama.is_dir(), "complete_author_panorama_required")
    for current, directories, files in os.walk(author_panorama, followlinks=False):
        current = Path(current)
        keep = []
        for child in sorted(directories):
            path = current / child
            if child in SKIP_DIRS or child.startswith("."):
                excluded.append("content/" + path.relative_to(AUTHOR).as_posix() + "/")
                continue
            need(not reparse(path), "author_reparse_refused:" + str(path))
            keep.append(child)
        directories[:] = keep
        for child in sorted(files):
            path = current / child
            relative = path.relative_to(AUTHOR).as_posix()
            if child.startswith(".") or path.suffix.lower() in SKIP_SUFFIXES:
                excluded.append("content/" + relative)
                continue
            need(path.suffix.lower() != ".vpk", "author_bare_package_refused:" + relative)
            records.append(dict(area="content", relative=relative, source=str(path), observed=source_stat(path)))
    records.sort(key=lambda row: (row["area"], row["relative"]))
    need(len({(r["area"], r["relative"].casefold()) for r in records}) == len(records), "case_collision_refused")
    need(any(r["relative"] == "maps/template_map.vpk" for r in records), "normal_template_map_required")
    return records, excluded, absent


def plan(run="run01"):
    base, mounts = roots(run)
    gates = trusted_gates()
    records, excluded, absent = inventory()
    return dict(status="LOCAL_DEVELOPMENT_COPY_PLAN_NOT_PREPARED", run=run, external_root=str(base),
                mounts=[dict(path=str(path), target=str(target)) for path, target in mounts],
                files=len(records), bytes=sum(r["observed"]["size"] for r in records),
                source_heads=dict(game=head(ROOT), content=head(AUTHOR)), trusted_gate_sha256=gates,
                content_scope="complete_current_panorama_dependency_tree",
                absent_optional_runtime_dirs=absent, excluded=excluded,
                source_is_workspace_observation_not_immutable_release=True,
                hardlinks=0, processes_started=0, sdk_calls=0, transactions=0,
                _records=records)


def prepare(run="run01"):
    report = plan(run)
    records = report.pop("_records")
    base = Path(report["external_root"])
    base.mkdir(parents=True, exist_ok=False)
    (base / "game").mkdir()
    (base / "content").mkdir()
    write_new(base / "plan.json", encoded(report))
    try:
        for row in records:
            source = Path(row["source"])
            need(source_stat(source) == row["observed"], "source_drift_before_copy:" + row["relative"])
            target = base / row["area"] / row["relative"]
            target.parent.mkdir(parents=True, exist_ok=True)
            digest = hashlib.sha256()
            with source.open("rb") as src, target.open("xb") as dst:
                while block := src.read(2 * 1024 * 1024):
                    dst.write(block)
                    digest.update(block)
            need(source_stat(source) == row["observed"], "source_drift_during_copy:" + row["relative"])
            row["sha256"] = digest.hexdigest()
            need(sha(target) == row["sha256"], "copied_digest_mismatch:" + row["relative"])
            need(source.stat().st_ino != target.stat().st_ino or source.stat().st_dev != target.stat().st_dev,
                 "hardlink_refused:" + row["relative"])
        # A second pass catches an early source changed while later files copied.
        for row in records:
            source = Path(row["source"])
            need(source_stat(source) == row["observed"] and sha(source) == row["sha256"],
                 "source_drift_second_pass:" + row["relative"])
        need(dict(game=head(ROOT), content=head(AUTHOR)) == report["source_heads"], "observed_source_heads_changed")
        need(trusted_gates() == report["trusted_gate_sha256"], "trusted_gate_drift")
        manifest = dict(format=1, purpose="tools_development_snapshot_not_release", files=records,
                        source_heads=report["source_heads"], file_bytes=report["bytes"])
        raw = encoded(manifest)
        write_new(base / "files.manifest.json", raw)
        report.update(status="LOCAL_DEVELOPMENT_COPY_PREPARED_NOT_LAUNCHED", manifest_sha256=hashlib.sha256(raw).hexdigest(),
                      verified_source_second_pass=True, verified_copy_sha256=True, hardlinks=0,
                      prepared_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                      limitation="Offline session-memory provider does not implement complete HTTP lottery/catalogue/checkout; not a real 30-ticket acceptance.",
                      suggested_argv=[str(ENGINE / "game/bin/win64/dota2.exe"), "-steam", "-tools", "-noassetbrowser", "-dev", "-addon", ALIAS,
                                      "-novid", "-console", "-vconsole", "-vconport", "29069", "+survival_offline_logic_test", "1",
                                      "+dota_launch_custom_game", ALIAS, "template_map"])
        # Fresh alias only; do not examine or touch any other alias/process.
        for entry in report["mounts"]:
            mount, target = Path(entry["path"]), Path(entry["target"])
            need(not os.path.lexists(mount), "mount_appeared_during_copy_preserve_all:" + str(mount))
            command = "New-Item -ItemType Junction -Path '" + str(mount).replace("'", "''") + "' -Target '" + str(target).replace("'", "''") + "' | Out-Null"
            subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command], check=True,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            need(mount.resolve() == target.resolve() and reparse(mount), "fresh_mount_target_mismatch")
        write_new(base / "prepared.json", encoded(report))
        return report
    except Exception as exc:
        write_new(base / "failed.json", encoded(dict(status="FAILED_PRESERVE_ALL_FILES_NO_CLEANUP", reason=str(exc),
                  processes_started=0, transactions=0, source_heads=report["source_heads"])))
        raise


def verify(run="run01"):
    base = STORE / run
    report = json.loads((base / "prepared.json").read_bytes())
    raw = (base / "files.manifest.json").read_bytes()
    need(hashlib.sha256(raw).hexdigest() == report["manifest_sha256"], "manifest_drift")
    manifest = json.loads(raw)
    for row in manifest["files"]:
        target = base / row["area"] / row["relative"]
        need(not reparse(target) and sha(target) == row["sha256"], "snapshot_drift:" + row["relative"])
    for entry in report["mounts"]:
        need(Path(entry["path"]).resolve() == Path(entry["target"]).resolve(), "snapshot_mount_drift")
    return dict(status="LOCAL_DEVELOPMENT_SNAPSHOT_VERIFIED_NOT_LAUNCHED", files=report["files"], bytes=report["bytes"],
                manifest_sha256=report["manifest_sha256"], processes_started=0, transactions=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("plan", "prepare", "verify"), nargs="?", default="plan")
    parser.add_argument("--run", default="run01")
    args = parser.parse_args()
    report = globals()[args.action](args.run)
    report.pop("_records", None)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
