"""Build a NEW external Lua tree with audited, offline Lua 5.1 obfuscation.

Based on Prometheus by Elias Oelschner, https://github.com/prometheus-lua/Prometheus
This is obfuscation, not cryptographic secrecy. Original development files are
never rewritten; a failed selected transformation never falls back to plaintext.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import build_runtime_release as runtime

ROOT = Path(__file__).resolve().parents[1]
POLICY = Path(__file__).with_name("lua_protection_policy.json")
SUPPORT = Path(__file__).with_name("lua_protection")
EXPECTED_STEPS = ["ConstantArray", "NumbersToExpressions", "WrapInFunction"]
EXECUTED_SOURCE_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
LOADED_TOOL_LF_HASHES = {
    "tools/protect_runtime_lua.py": EXECUTED_SOURCE_LF_SHA256,
    "tools/build_runtime_release.py": runtime.EXECUTED_SOURCE_LF_SHA256,
    **{path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
       for path in sorted(SUPPORT.glob("*.lua"))},
}


def loaded_tool_bindings() -> list[dict]:
    records = []
    for path, loaded in sorted(LOADED_TOOL_LF_HASHES.items()):
        actual = hashlib.sha256((ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        if actual != loaded:
            raise ValueError("Loaded protection tool/helper changed after import: " + path)
        records.append({"path": path, "loaded_lf_sha256": loaded,
                        "normalization": "CRLF_TO_LF"})
    return records


def check_policy(data: dict) -> None:
    if (data.get("schema") != 1 or data.get("language") != "Lua51"
            or data.get("kind") != "offline_lua51_obfuscation_policy"
            or data.get("steps") != EXPECTED_STEPS
            or data.get("generated_prefix") != "scripts/vscripts/config/generated/"
            or runtime.RELEASE_PROFILE not in data.get("always_plaintext", [])):
        raise ValueError("Unsupported Lua protection policy")
    for name in data.get("business_modules", []):
        if not runtime.safe_relative(name) or not name.startswith("scripts/vscripts/") or not name.endswith(".lua"):
            raise ValueError("Unsafe business module path")
    if runtime.RELEASE_PROFILE in data.get("business_modules", []):
        raise ValueError("Release profile must remain literal plaintext")


def dependency_identity(root: Path, policy: dict) -> dict:
    root = root.resolve(strict=True)
    if runtime.within(root, ROOT) or runtime.within(ROOT, root):
        raise ValueError("Prometheus source must be outside the addon")
    paths = sorted([*root.glob("src/**/*.lua"), root / "cli.lua", root / "LICENSE"])
    records = []
    for path in paths:
        if not path.is_file() or runtime.is_link(path) or not runtime.within(path.resolve(strict=True), root):
            raise ValueError("Missing or linked dependency source")
        records.append({"path": path.relative_to(root).as_posix(), "bytes": path.stat().st_size,
                        "sha256": runtime.digest(path)})
    actual = hashlib.sha256(runtime.canonical_bytes(records)).hexdigest()
    lock = policy["dependency"]
    if (actual != lock["source_tree_sha256"] or len(records) != lock["source_tree_files"]
            or runtime.digest(root / "LICENSE") != lock["license_sha256"]):
        raise ValueError("Prometheus source/License does not match the audited pinned dependency")
    return {**lock, "path": str(root), "verified_source_tree_sha256": actual}


def checked_destination(source: Path, destination: Path) -> Path:
    if not destination.is_absolute():
        raise ValueError("Output must be an explicit absolute NEW external directory")
    source, destination = source.resolve(strict=True), destination.resolve(strict=False)
    if (runtime.within(destination, source) or runtime.within(source, destination)
            or runtime.within(destination, ROOT.parents[2])):
        raise ValueError("Output must be outside the source and installed game/content tree")
    if destination.exists():
        raise ValueError("Output already exists; use a new directory, never overwrite a candidate")
    return destination


def selected_files(paths: list[str], policy: dict) -> list[dict]:
    result = []
    exclusions = policy["generated_exclusions"]
    prefix = policy["generated_prefix"]
    business = set(policy["business_modules"])
    for relative in paths:
        if relative.startswith(prefix) and Path(relative).name not in exclusions:
            result.append({"path": relative, "kind": "generated_table"})
        elif relative in business:
            result.append({"path": relative, "kind": "business"})
    present = {row["path"] for row in result}
    missing = business - present
    if missing:
        raise ValueError("Business modules required by protection policy are missing: " + ", ".join(sorted(missing)))
    if not any(row["kind"] == "generated_table" for row in result):
        raise ValueError("No generated data tables selected")
    if present & set(policy["always_plaintext"]):
        raise ValueError("Always-plaintext module selected for transformation")
    return result


def run(command: list[str], *, timeout: int = 120) -> str:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if result.returncode:
        message = (result.stdout + result.stderr).decode("utf-8", errors="replace")[-6000:]
        raise ValueError("Lua protection command failed: " + message)
    return result.stdout.decode("utf-8", errors="strict")


def syntax_check(paths: list[Path], luac: Path) -> None:
    for index in range(0, len(paths), 32):
        run([str(luac), "-p", *[str(path) for path in paths[index:index + 32]]])


def compare_values(source: Path, destination: Path, rows: list[dict], lua: Path, work: Path) -> dict:
    # Paths and kinds are constrained ASCII identifiers. No executable policy
    # text or arbitrary user-supplied Lua is loaded as the comparison list.
    list_file = work / "selected_tables.lua"
    text = "return {\n" + "".join("{path=" + json.dumps(row["path"]) + ",kind="
                                    + json.dumps(row["kind"]) + "},\n" for row in rows) + "}\n"
    list_file.write_text(text, encoding="ascii", newline="\n")
    output = run([str(lua), str(SUPPORT / "verify_values.lua"), str(source), str(destination), str(list_file)], timeout=180)
    checks = []
    summary = None
    for line in output.splitlines():
        fields = line.split("\t")
        if fields[0] == "VALUE_PASS" and len(fields) == 4:
            checks.append({"path": fields[1], "source_seconds": float(fields[2]), "protected_seconds": float(fields[3])})
        elif fields[0] == "VALUE_SUMMARY" and len(fields) == 4:
            summary = {"files": int(fields[1]), "source_seconds": float(fields[2]), "protected_seconds": float(fields[3])}
        else:
            raise ValueError("Unexpected semantic verification output")
    if summary is None or summary["files"] != len(rows) or [row["path"] for row in checks] != [row["path"] for row in rows]:
        raise ValueError("Incomplete semantic verification")
    return {"status": "PASS", "all_generated_values_exact": True,
            "business_probe_modules": [row["path"] for row in rows if row["kind"] == "business"],
            "new_runtime_io_os_debug_dependency": False, "gameplay_rng_untouched_while_loading": True,
            "load_time_measurement": "Single local Lua 5.1 parse-and-load pass; not a Dota frame-time benchmark.",
            "summary": summary, "files": checks}


def protect(source: Path, destination: Path, dependency: Path, lua: Path, luac: Path, policy: dict,
            *, data_strings: bool = False, lua_only_input: bool = False) -> dict:
    if type(lua_only_input) is not bool:
        raise ValueError("lua_only_input must be an explicit boolean")
    tools = loaded_tool_bindings()
    check_policy(policy)
    source = source.resolve(strict=True)
    runtime.require_production(source)
    destination = checked_destination(source, destination)
    identity = dependency_identity(dependency, policy)
    if not lua.is_file() or not luac.is_file():
        raise ValueError("Explicit Lua 5.1 and luac 5.1 executables are required")
    paths = [relative for relative in runtime.select(source, check_critical=not lua_only_input)[0]
             if relative.startswith("scripts/vscripts/") and relative.endswith(".lua")]
    rows = selected_files(paths, policy)
    selected = {row["path"] for row in rows}
    original = {relative: runtime.checksums(source / relative) for relative in paths}
    report = {"schema": 1, "kind": "offline_lua51_protection", "status": "INCOMPLETE",
              "source_root": str(source), "destination": str(destination), "dependency": identity,
              "policy_sha256": hashlib.sha256(runtime.canonical_bytes(policy)).hexdigest(),
              "claim": policy["claim"], "steps": policy["steps"],
              "generated_string_obfuscation": {"enabled": data_strings, "step": "EncryptStrings" if data_strings else None,
                                               "private_rng": data_strings, "cryptographic_confidentiality": False},
              "generated_steps": ["ConstantArray", "EncryptStrings", "NumbersToExpressions", "WrapInFunction"]
                                 if data_strings else policy["steps"],
              "source_files": len(paths), "selected_files": len(rows), "unchanged_plaintext_modules": len(paths) - len(rows),
              "input_scope": "LUA_ONLY_PROJECTION" if lua_only_input else "FULL_RUNTIME_SOURCE",
              "critical_runtime_assets_checked": not lua_only_input,
              "complete_candidate_materialization_verified": False,
              "executed_tool_inputs": tools,
              "source_modified": False, "network_used_for_transform": False, "native_dota_smoke_test": "NOT_RUN",
              "workshop_upload_performed": False, "files": []}
    destination.mkdir(parents=True, exist_ok=False)
    work = destination / "_protection_work"
    work.mkdir()
    report_path = destination / "_lua_protection_report.json"
    runtime.atomic_write_json(report_path, report)
    try:
        # Selected files are never copied as plaintext: failures leave no
        # apparently successful, partly protected candidate.
        for relative in paths:
            if relative not in selected:
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source / relative, target)
        syntax_check([source / path for path in paths], luac)
        for number, row in enumerate(rows, 1):
            relative = row["path"]
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            seed = int(hashlib.sha256((relative + original[relative]["sha256"]).encode("ascii")).hexdigest()[:8], 16) % 2147483646 + 1
            started = time.perf_counter()
            run([str(lua), str(SUPPORT / "prometheus_offline_driver.lua"), str(dependency.resolve()),
                 str(source / relative), str(target), str(seed),
                 "generated_table_strings" if data_strings and row["kind"] == "generated_table" else "baseline"])
            after = runtime.checksums(target)
            if after["sha256"] == original[relative]["sha256"]:
                raise ValueError("Selected module was not transformed: " + relative)
            report["files"].append({**row, "before": original[relative], "after": after,
                                    "seed": seed, "build_seconds": time.perf_counter() - started})
            if number % 10 == 0 or number == len(rows):
                print(json.dumps({"protected": number, "selected": len(rows), "path": relative}), flush=True)
        syntax_check([destination / path for path in paths], luac)
        report["syntax"] = {"status": "PASS", "all_lua_files": len(paths), "compiler": str(luac)}
        report["semantic_verification"] = compare_values(source, destination, rows, lua, work)
        dependency_identity(dependency, policy)
        if loaded_tool_bindings() != tools:
            raise ValueError("Protection tools changed during preparation")
        for relative in paths:
            if runtime.checksums(source / relative) != original[relative]:
                raise ValueError("Development source changed during protection: " + relative)
            if relative not in selected and runtime.checksums(destination / relative) != original[relative]:
                raise ValueError("Unselected Lua copy changed: " + relative)
        report["status"] = "PASS_REQUIRES_NATIVE_SMOKE"
        runtime.atomic_write_json(report_path, report)
        return report
    except Exception as error:
        report["status"] = "FAILED_DO_NOT_PUBLISH"
        report["error"] = str(error)
        runtime.atomic_write_json(report_path, report)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True, help="NEW absolute external Lua candidate directory")
    parser.add_argument("--prometheus-root", type=Path, required=True, help="External source tree matching pinned policy hashes")
    parser.add_argument("--lua", type=Path, default=Path("C:/Program Files/lua/bin/lua5.1.exe"))
    parser.add_argument("--luac", type=Path, default=Path("C:/Program Files/lua/bin/luac5.1.exe"))
    parser.add_argument("--policy", type=Path, default=POLICY)
    parser.add_argument("--data-string-obfuscation", action="store_true",
                        help="Also obfuscate pure generated-table strings with an isolated private decoder RNG")
    parser.add_argument("--lua-only-input", action="store_true",
                        help="Explicit Lua projection input; skip only non-Lua critical asset presence, not production policy or later full-candidate/native validation")
    args = parser.parse_args()
    try:
        report = protect(args.source, args.output, args.prometheus_root, args.lua, args.luac,
                         json.loads(args.policy.read_text(encoding="utf-8-sig")), data_strings=args.data_string_obfuscation,
                         lua_only_input=args.lua_only_input)
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print("Lua protection failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps({"status": report["status"], "selected": report["selected_files"], "all_lua": report["source_files"],
                      "report": str(args.output / "_lua_protection_report.json"),
                      "load_times": report["semantic_verification"]["summary"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
