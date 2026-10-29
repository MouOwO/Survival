"""Freeze ALL current runtime content behind the existing native four-account gate.

Default operation is read-only (an explicit --report may record its plan).
--build requires that exact reviewed plan and creates new external production,
protected-Lua, signed-candidate and VPK directories. It never uploads, starts
Dota, installs an addon, changes Git or rewrites development configuration.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import re

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/release_security"))
import build_runtime_release as runtime
import protect_runtime_lua as protection
import assemble_release as assembly
import stream_workshop_vpk as pack

ITEM, SEQUENCE, REVISION = "3824360109", 2026102901, "WS4-ARCHIVE-ALL-01"
BASE = Path("D:/Survival_发布候选/20261028_ws4_ten_sin_startup_v02_view")
BASE_TRUSTED = BASE.with_name("20261028_ws4_ten_sin_startup_v02_overlay_trusted_source")
BASE_RECORD = ROOT / "publishing/workshop/ten_sin_startup_20261028_v02.json"
BASE_REPORT = ROOT / "output/ten_sin_startup_20261028_v02/package.json"
BASE_RECEIPT = ROOT / "output/ten_sin_startup_20261028_v02/download_evidence/20261028T134521Z_bcd096375caa43868149efac30366ab2/verification.json"
JOURNAL = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
PRODUCTION = Path("D:/Survival_发布候选/20261029_ws4_archive_all_v01_source")
PROTECTED = Path("D:/Survival_发布候选/20261029_ws4_archive_all_v01_lua")
CANDIDATE = Path("D:/Survival_发布候选/20261029_ws4_archive_all_v01_view")
TRUSTED = Path("D:/Survival_发布候选/20261029_ws4_archive_all_v01_trusted_source")
OUTPUT = Path("D:/Survival_工坊输出/20261029_ws4_archive_all_v01")
PROMETHEUS = Path("D:/Survival_安全工具/prometheus")
LUA = Path("C:/Program Files/lua/bin/lua5.1.exe")
LUAC = Path("C:/Program Files/lua/bin/luac5.1.exe")
SOURCE_OVERRIDES = (
    "addoninfo.txt", runtime.RELEASE_PROFILE,
    "scripts/vscripts/config/player_web_auth.lua",
    "scripts/vscripts/config/commerce_payment_access.lua",
    "scripts/vscripts/config/workshop_connection.lua",
    "scripts/vscripts/addon_game_mode_client.lua", "maps/ws4_entry.vpk",
)
REVIEW_NAMES = tuple(sorted(p.relative_to(BASE_TRUSTED).as_posix()
                           for p in BASE_TRUSTED.rglob("*") if p.is_file()))
MAIN = "scripts/vscripts/addon_game_mode.lua"
MULTIPLAYER = "scripts/vscripts/config/generated/multiplayer_rules.lua"
LUA_POLICY = "tools/lua_protection_policy.json"
RELEASE_POLICY = "tools/release_security/protection_policy.json"
PUBLIC_KEY = "tools/release_security/trusted_public_key.pem"
EXPECTED_ARCHIVE_BUNDLE = "d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488"
ARCHIVE_BUNDLE_PATH = "scripts/vscripts/config/generated/archive_http_bundle.lua"
ARCHIVE_BUNDLE = ROOT / "output/archive_layout_20261029/bundle_candidate" / EXPECTED_ARCHIVE_BUNDLE / "bundle.json"


def need(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    return pack.handoff.load_json(path)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


@contextmanager
def reviewed_source(root):
    old = pack.handoff.ROOT, pack.handoff.POLICY
    pack.handoff.ROOT, pack.handoff.POLICY = root, root / RELEASE_POLICY
    try:
        yield
    finally:
        pack.handoff.ROOT, pack.handoff.POLICY = old


def main_source(raw):
    """Remove only the dormant developer lobby prefix; retain all gameplay."""
    normalized = raw.decode("utf-8-sig").replace("\r\n", "\n")
    marker = '-- Keep the Workshop entry independent of gameplay and cloud initialization.\n'
    need(normalized.count(marker) == 1, "Native entry MAIN anchor drift")
    prefix, suffix = normalized.split(marker, 1)
    expected = ('-- Keep the independent lobby free from gameplay and cloud initialization.\n'
                'if type(GetMapName) == "function" and GetMapName() == "ws4_lobby" then\n'
                '    local lobby = require("systems/hosted_lobby")\n'
                '    function Precache() end\n'
                '    function Activate()\n'
                '        local ok, reason = lobby.activate()\n'
                '        if not ok then print("[WS4-LOBBY-01] unavailable reason=" .. tostring(reason)) end\n'
                '    end\n    return\nend\n\n')
    need(prefix in ("", expected), "Unreviewed code precedes native entry")
    return (marker + suffix).encode("utf-8")


def destination_guard():
    paths = (PRODUCTION, PROTECTED, CANDIDATE, TRUSTED, OUTPUT)
    for path in paths:
        pack.handoff.regular_path(path, must_exist=False)
        need(not path.exists(), "New output path required: " + str(path))
        need(not runtime.within(path, pack.handoff.INSTALL), "External output required")
    for i, left in enumerate(paths):
        for right in paths[i + 1:]:
            need(not runtime.within(left, right) and not runtime.within(right, left), "Outputs overlap")


def baseline():
    record, report, receipt = [load(p) for p in (BASE_RECORD, BASE_REPORT, BASE_RECEIPT)]
    need(record["release_sequence"] == 2026102805 and record["workshop_id"] == ITEM
         and record["uploaded"] is True and record["download_verified"] is True, "2805 publication evidence mismatch")
    need(runtime.digest(BASE_REPORT) == record["package_report_sha256"], "2805 build report changed")
    need(runtime.digest(BASE_RECEIPT) == record["download_receipt_sha256"], "2805 official receipt changed")
    need(receipt["status"] == "OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED"
         and receipt["steam_manifest"] == "3734424561061643436", "2805 official manifest mismatch")
    with reviewed_source(BASE_TRUSTED):
        _, manifest, signed, _ = pack.authenticate(BASE)
    need(signed["release_sequence"] == 2026102805
         and manifest["content_sha256"] == record["package"]["content_sha256"], "2805 signed baseline drift")
    need(len(REVIEW_NAMES) == 16, "Frozen review inventory drift")
    state = load(JOURNAL)
    need(state.get("release_sequence") == 2026102805 and state.get("uploaded") is True,
         "Canonical journal is no longer the successful 2805 baseline")
    sequences = []
    for file in (ROOT / "publishing/workshop").glob("*.json"):
        value = load(file)
        if value.get("uploaded") is True and isinstance(value.get("release_sequence"), int):
            sequences.append(value["release_sequence"])
    need(not sequences or max(sequences) < SEQUENCE, "2901 is not newer than published records")
    return manifest


def source_spec():
    names, _ = runtime.select(ROOT)
    names = sorted(set(names) | set(SOURCE_OVERRIDES))
    rows = []
    for name in names:
        origin = BASE / name if name in SOURCE_OVERRIDES else ROOT / name
        origin = pack.protect_data.source_path(origin.parent, origin.name)
        raw = main_source(origin.read_bytes()) if name == MAIN else None
        checksum = ({"bytes": len(raw), "md5": hashlib.md5(raw).hexdigest(), "sha256": sha(raw)}
                    if raw is not None else runtime.checksums(origin))
        rows.append({"path": name, "origin": "frozen_2805" if name in SOURCE_OVERRIDES else "current",
                     **checksum})
    return rows


def require_review_inventory(names):
    expected = {*pack.handoff.GATE_FILES, *pack.handoff.NATIVE_CLOUD_ENTRY_GATE_FILES,
                pack.handoff.ACCESS_FILE, "scripts/vscripts/systems/workshop_entry.lua",
                "panorama/src/scripts/custom_game/payment_test.js",
                "panorama/src/scripts/custom_game/production_progress.js", RELEASE_POLICY, PUBLIC_KEY}
    need(set(names) == expected and len(names) == 16, "Complete exact 16-file reviewed-source set required")


def require_archive_bundle(raw):
    found = re.findall(rb'hash\s*=\s*"([0-9a-f]{64})"', raw)
    need(found == [EXPECTED_ARCHIVE_BUNDLE.encode("ascii")], "Wrong coordinated archive backend bundle hash")


def require_production_source(source):
    source = source.resolve(strict=True)
    runtime.require_production(source)
    expected = {
        runtime.RELEASE_PROFILE: {"channel": "production", "native_cloud_roster_required": True},
        "scripts/vscripts/config/player_web_auth.lua": {"enabled": True, "base_url": pack.handoff.NATIVE_CLOUD_BASE},
        "scripts/vscripts/config/session_multiplayer_test.lua": {"enabled": False, "expected_map": "template_map"},
        "scripts/vscripts/config/commerce_payment_access.lua": {
            "enabled": True, "connection_helper": False, "expected_map": "template_map", "base_url": pack.handoff.NATIVE_CLOUD_BASE},
    }
    for name, value in expected.items():
        need(pack.handoff.literal_flat_config(source, name) == value, "Production configuration mismatch: " + name)
    need(pack.handoff.kv((source / "addoninfo.txt").read_text("utf-8-sig")) == pack.handoff.NATIVE_CLOUD_ENTRY_LAYOUT,
         "Native four-player entry layout mismatch")
    need(pack.handoff.configured_ids(source) == pack.handoff.NATIVE_CLOUD_TESTERS, "Four-account production whitelist mismatch")
    require_archive_bundle((source / ARCHIVE_BUNDLE_PATH).read_bytes())


def plan():
    destination_guard()
    before = baseline()
    require_review_inventory(REVIEW_NAMES)
    rows = source_spec()
    extras = sorted(set(REVIEW_NAMES) | {LUA_POLICY, RELEASE_POLICY, PUBLIC_KEY})
    auxiliary = [{"path": n, **runtime.checksums(ROOT / n)} for n in extras if n != MAIN]
    policy = load(ROOT / LUA_POLICY)
    dependency = protection.dependency_identity(PROMETHEUS, policy)
    selected = protection.selected_files([r["path"] for r in rows], policy)
    expected = next(r for r in rows if r["path"] == MULTIPLAYER)
    need(expected["sha256"] == "7bb7fe314dc4f4d7e35ecf52c221037c4deb8900b246cf6de1c5ff94f8ab94de",
         "Native pinned multiplayer plaintext changed")
    require_archive_bundle((ROOT / ARCHIVE_BUNDLE_PATH).read_bytes())
    need(runtime.digest(ARCHIVE_BUNDLE) == EXPECTED_ARCHIVE_BUNDLE, "Coordinated backend candidate bytes differ from game hash")
    old = {r["path"]: r for r in before["files"]}
    current = {r["path"]: r for r in rows}
    result = dict(schema=1, status="READ_ONLY_FULL_RUNTIME_PLAN", revision=REVISION, release_sequence=SEQUENCE,
        workshop_id=ITEM, source_git_head=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        baseline_release_sequence=2026102805, baseline_content_sha256=before["content_sha256"],
        baseline_record_sha256=runtime.digest(BASE_RECORD), baseline_report_sha256=runtime.digest(BASE_REPORT),
        baseline_receipt_sha256=runtime.digest(BASE_RECEIPT), canonical_journal_sha256=runtime.digest(JOURNAL),
        runtime_files=len(rows), runtime_bytes=sum(r["bytes"] for r in rows), source_files=rows,
        auxiliary_inputs=auxiliary, builder_sha256=runtime.digest(Path(__file__)),
        archive_bundle_path=str(ARCHIVE_BUNDLE), archive_bundle_sha256=EXPECTED_ARCHIVE_BUNDLE,
        dependency=dependency, protected_modules_rebuild=len(selected), protected_modules_preserve=0,
        review_files=list(REVIEW_NAMES), production_overrides=list(SOURCE_OVERRIDES),
        main_patch="Remove exact developer lobby prefix only; keep all current ordinary gameplay.",
        added_runtime_paths=sorted(current.keys() - old.keys()), removed_runtime_paths=sorted(old.keys() - current.keys()),
        changed_runtime_paths=sorted(n for n in current.keys() & old.keys() if current[n]["sha256"] != old[n]["sha256"]),
        production_source=str(PRODUCTION), protected_lua=str(PROTECTED), candidate=str(CANDIDATE),
        trusted_source=str(TRUSTED), output=str(OUTPUT / (ITEM + ".vpk")),
        workshop_upload_performed=False, native_smoke_test="NOT_RUN", ready_for_upload=False)
    result["plan_sha256"] = sha(runtime.canonical_bytes(result))
    return result


def write_new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)


def build(reviewed_plan, key, report_dir):
    need(key is not None, "Explicit external existing signing key required")
    key = pack.handoff.regular_path(pack.protect_data.external(key))
    expected = load(reviewed_plan)
    actual = plan()
    need(actual == expected, "Reviewed full-runtime plan changed; review a new plan")
    for path in (PRODUCTION, PROTECTED, CANDIDATE, TRUSTED, OUTPUT):
        need(not runtime.within(key, path) and not runtime.within(path, key.parent), "Key/output overlap")
    need(not report_dir.exists(), "Use a new build report directory")
    report_dir.mkdir(parents=True, exist_ok=False)
    runtime.atomic_write_json(report_dir / "reviewed_plan.json", expected)
    PRODUCTION.mkdir(parents=True, exist_ok=False)
    for row in expected["source_files"]:
        name = row["path"]
        origin = BASE / name if name in SOURCE_OVERRIDES else ROOT / name
        raw = main_source(origin.read_bytes()) if name == MAIN else origin.read_bytes()
        need(sha(raw) == row["sha256"], "Source changed during freeze: " + name)
        write_new(PRODUCTION / name, raw)
    for row in expected["auxiliary_inputs"]:
        target = PRODUCTION / row["path"]
        if target.exists():
            continue
        raw = (ROOT / row["path"]).read_bytes()
        need(sha(raw) == row["sha256"], "Auxiliary input drift")
        write_new(target, raw)
    require_production_source(PRODUCTION)
    source_manifest = runtime.manifest(PRODUCTION)
    need(source_manifest["file_count"] == expected["runtime_files"], "Production runtime inventory mismatch")
    for row, planned in zip(source_manifest["files"], expected["source_files"]):
        need(row == {n: planned[n] for n in ("path", "bytes", "md5", "sha256")}, "Frozen source mismatch")
    runtime.atomic_write_json(report_dir / "production_manifest.json", source_manifest)
    TRUSTED.mkdir(parents=True, exist_ok=False)
    for name in REVIEW_NAMES:
        write_new(TRUSTED / name, (PRODUCTION / name).read_bytes())
    print(json.dumps({"status": "FULL_PRODUCTION_SOURCE_FROZEN", "files": len(expected["source_files"]),
                      "protected_modules": expected["protected_modules_rebuild"]}), flush=True)
    protected = protection.protect(PRODUCTION, PROTECTED, PROMETHEUS, LUA, LUAC,
                                  load(PRODUCTION / LUA_POLICY), data_strings=True)
    need(runtime.digest(PROTECTED / MULTIPLAYER) == pack.handoff.NATIVE_CLOUD_ENTRY_PINS[MULTIPLAYER],
         "Deterministically rebuilt native multiplayer pin mismatch")
    assembled = assembly.assemble(PRODUCTION, CANDIDATE, PROTECTED, key, SEQUENCE,
                                 policy_path=PRODUCTION / RELEASE_POLICY,
                                 lua_policy_path=PRODUCTION / LUA_POLICY, lua=LUA, luac=LUAC)
    runtime.atomic_write_json(report_dir / "assembly.json", assembled)
    OUTPUT.mkdir(parents=True, exist_ok=False)
    with reviewed_source(TRUSTED):
        result = pack.package(CANDIDATE, OUTPUT, ITEM, build=True)
        _, manifest, signed, _ = pack.authenticate(CANDIDATE)
    need(signed["release_sequence"] == SEQUENCE, "Final signed sequence mismatch")
    result.update(revision=REVISION, production_source=str(PRODUCTION), candidate=str(CANDIDATE),
                  trusted_source=str(TRUSTED), output=str(OUTPUT / (ITEM + ".vpk")),
                  protected_modules_rebuilt=protected["selected_files"], protected_modules_preserved=0,
                  full_runtime_validator_passed=True, full_source_plan_sha256=expected["plan_sha256"],
                  native_test="NOT_RUN", ready_for_upload=False)
    runtime.atomic_write_json(report_dir / "package.json", result)
    need(source_spec() == expected["source_files"], "Development runtime changed during build")
    need(runtime.digest(JOURNAL) == expected["canonical_journal_sha256"], "Upload journal changed during build")
    need(runtime.digest(ARCHIVE_BUNDLE) == expected["archive_bundle_sha256"], "Coordinated backend candidate drift")
    need(runtime.verify(CANDIDATE, manifest)["ok"], "Final candidate drift")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--reviewed-plan", type=Path)
    parser.add_argument("--signing-key", type=Path)
    parser.add_argument("--report", type=Path, help="NEW read-only plan result path")
    parser.add_argument("--report-dir", type=Path, default=ROOT / "output/release_archive_20261029/workshop_build")
    args = parser.parse_args(argv)
    try:
        if args.build:
            need(args.reviewed_plan is not None and args.report is None, "Build requires --reviewed-plan, without --report")
            result = build(args.reviewed_plan, args.signing_key, args.report_dir)
        else:
            need(args.reviewed_plan is None and args.signing_key is None, "Keys/plans are build-only")
            result = plan()
            if args.report:
                write_new(args.report, json.dumps(result, ensure_ascii=False, indent=2).encode("utf-8") + b"\n")
        print(json.dumps({k: v for k, v in result.items() if k not in ("source_files", "auxiliary_inputs", "changed_runtime_paths")}, ensure_ascii=False))
    except Exception as error:
        print(json.dumps({"status": "BLOCKED_DO_NOT_UPLOAD", "error": str(error), "workshop_upload_performed": False}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
