"""Run isolated production Lua regressions; never connects to the game/accounts."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LUA = Path("C:/Program Files/lua/bin/lua5.1.exe")
LUAC = LUA.with_name("luac5.1.exe")
OUT = ROOT / "design_refs/shop_functional_20261016/p147"
SOURCES = [
    "scripts/vscripts/systems/commerce_hero_privileges.lua",
    "scripts/vscripts/systems/hero_combat_stat_service.lua",
    "scripts/vscripts/systems/hero_skill_choice_service.lua",
    "scripts/vscripts/combat/damage_filter_service.lua",
    "scripts/vscripts/combat/hero_display_bonus.lua",
    "scripts/vscripts/systems/blademaster_exclusive_service.lua",
]
TESTS = [
    "tools/shop_functional_20261016/test_p147.lua",
    "tools/test_hero_rogue_projection.lua",
    "tools/test_hero_removed_ui_lifecycle.lua",
    "tools/test_hero_growth_hot_path.lua",
    "tools/test_hero_display_bonus.lua",
    "tools/test_blademaster_clone.lua",
    "tools/test_blademaster_attack_rate.lua",
    "tools/test_blademaster_rebirth_unlock.lua",
]


def run_test(relative):
    completed = subprocess.run([str(LUA), relative], cwd=ROOT, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=40)
    output = completed.stdout + completed.stderr
    logfile = OUT / (Path(relative).stem + ".log")
    logfile.write_text(output, encoding="utf-8")
    return {"test": relative, "exit_code": completed.returncode,
            "log": logfile.relative_to(ROOT).as_posix(),
            "markers": [line for line in output.splitlines() if "_PASS" in line]}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    syntax = subprocess.run([str(LUAC), "-p", *SOURCES], cwd=ROOT, capture_output=True,
                            text=True, encoding="utf-8", errors="replace", timeout=40)
    if syntax.returncode:
        raise RuntimeError(syntax.stdout + syntax.stderr)
    with ThreadPoolExecutor(max_workers=4) as executor:
        tests = list(executor.map(run_test, TESTS))
    report = {
        "status": "PASS" if all(item["exit_code"] == 0 for item in tests) else "FAIL",
        "at": datetime.now(timezone.utc).isoformat(),
        "scope": "Actual Lua combat/stat/skill-choice services with isolated native boundary and four owned-profile fixtures. No account, payment, game process or save writes.",
        "gameplay_native_verified": False,
        "schema_changes": False,
        "ownership_marker": "commerce_p147",
        "syntax_files": len(SOURCES),
        "sources": {relative: sha256((ROOT / relative).read_bytes()).hexdigest() for relative in SOURCES},
        "tests": tests,
        "behavior": [
            "Live raw attributes (base, equipment, research, persisted rewards, per-level, weapon/attack/time progression, hero bonuses) all receive an independent 1.08 factor, followed by the unchanged essence factor.",
            "Normal final-damage sums remain unchanged; a separate entity cache multiplies hero basic/ability damage by 1.08, without per-hit inventory reads.",
            "Static HUD bonus calculation includes the same EX factor while keeping accumulated growth outside its green fixed-source subtotal.",
            "Swordmaster defender inherits the EX cache on stat changes; its Q and the main hero Q normalize already-filtered damage before the copied ability passes through EX again.",
            "Five skill rerolls grant once per player/match before the first offer or on a mid-match owned-profile update. Reconnects, repeated snapshots and hero replacements retain spent charges; a fresh match resets them.",
            "Existing sky-seal learned-skill rerolls remain additive, and failed random draws consume no reroll.",
            "Pure-mode fixtures with empty mode-filtered match inventory receive no EX/rerolls even when the separate account UI profile owns P147; no account-profile read is made.",
        ],
        "limits": ["Gameplay checks are native-boundary simulations in Lua 5.1; live P147 ownership/purchase has not been injected into a real account.",
                   "Formal product definitions, prices and regular stat grants are managed by the root task; this change adds only gameplay consumers for the ownership marker."],
    }
    (OUT / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"P147_VALIDATION_{report['status']} syntax={len(SOURCES)} suites={len(tests)}")
    for item in tests:
        print(f"{item['exit_code']} {item['test']} markers={len(item['markers'])}")
    if report["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
