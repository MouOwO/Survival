"""Run isolated runtime regressions; never connects to Dota, ECS or a database.

Lua tests mock engine globals. JS tests use a simulated Panorama host. These
checks do not certify frame times, multiplayer transport or engine rendering.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
UI_TESTS = (
    "test_game_info_lifecycle.cjs", "test_shared_ui.cjs",
    "test_combat_selection_recovery.cjs", "test_combat_stats_callbacks.cjs",
    "test_ui_snapshot_cache.cjs", "test_archive_cache.cjs",
    "test_startup_loading_ui.js", "test_match_setup_ui.cjs",
    "test_hero_skill_upgrade.cjs", "test_multiselect_portraits.cjs",
)


def default_lua() -> str | None:
    candidates = [os.environ.get("SURVIVAL_LUA"), "lua5.1", "lua51", "luajit", "lua"]
    if os.name == "nt":
        candidates += ["C:/Program Files/lua/bin/lua5.1.exe",
                       "C:/msys64/mingw64/bin/lua5.1.exe",
                       "C:/msys64/msys64/bin/lua5.1.exe"]
    for candidate in candidates:
        binary = shutil.which(candidate) if candidate else None
        if not binary:
            continue
        result = subprocess.run([binary, "-e", "print(_VERSION)"], capture_output=True,
                                text=True, timeout=10)
        if result.returncode == 0 and result.stdout.strip() == "Lua 5.1":
            return binary
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("all", "lua", "ui"), default="all")
    parser.add_argument("--lua", help="Lua interpreter; default discovers Lua 5.1 / LuaJIT")
    parser.add_argument("--node", default="node")
    parser.add_argument("--output", type=Path,
                        default=ROOT / "output/runtime_regression/latest.json")
    args = parser.parse_args()
    if args.suite in ("all", "lua") and not args.lua:
        args.lua = default_lua()
        if not args.lua:
            parser.error("Lua 5.1 is required for engine-scope regressions; set --lua or SURVIVAL_LUA")
    commands = []
    versions = {}
    for engine, name, flag in (("lua", args.lua, "-v"), ("ui", args.node, "--version")):
        if args.suite not in ("all", engine):
            continue
        binary = shutil.which(name)
        if not binary:
            parser.error(f"Interpreter not found: {name}")
        version = subprocess.run([binary, flag], capture_output=True, text=True,
                                 encoding="utf-8", errors="replace", timeout=10)
        versions[engine] = (version.stdout + version.stderr).strip()
        if engine == "lua":
            # Lua 5.1 already has unpack; the alias lets local 5.4 run legacy
            # tests without changing production's supported language version.
            paths = sorted((ROOT / "scripts/vscripts/tests").glob("test_*.lua"))
            paths.append(ROOT / "tools/check_addon_bootstrap.lua")
            commands.extend((path, [binary, "-e", "unpack = unpack or table.unpack", str(path)])
                            for path in paths)
        else:
            commands.extend((ROOT / "tools" / name, [binary, str(ROOT / "tools" / name)])
                            for name in UI_TESTS)
    results = []
    for path, command in commands:
        started = time.perf_counter()
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=45)
            passed = result.returncode == 0
            output = (result.stdout + result.stderr).strip()
        except subprocess.TimeoutExpired:
            passed, output = False, "isolated_test_timeout_45s"
        relative = path.relative_to(ROOT).as_posix()
        results.append({"test": relative, "passed": passed,
                        "elapsed_seconds": round(time.perf_counter() - started, 3),
                        "output_tail": output[-6000:]})
        print(("PASS " if passed else "FAIL ") + relative, flush=True)
    failed = sum(not result["passed"] for result in results)
    report = {"recorded_at": datetime.now(timezone.utc).isoformat(),
              "validation": "SIMULATION / UNIT; not WORKSHOP or PRODUCTION",
              "interpreters": versions, "passed": len(results) - failed,
              "failed": failed, "results": results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Runtime regression: {len(results) - failed} passed, {failed} failed; report={args.output}")
    return int(failed > 0)


if __name__ == "__main__":
    sys.exit(main())
