"""Run real Lua 5.1 integration tests; never opens game, accounts or a server."""
import difflib
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "design_refs/shop_catalog_20261016/audit"
LUA = Path("C:/Program Files/lua/bin/lua5.1.exe")
FILES = ["scripts/vscripts/systems/commerce_archive_source_bonus.lua",
         "scripts/vscripts/systems/permanent_reward_effect_service.lua",
         "scripts/vscripts/tests/test_commerce_archive_source_bonus.lua"]
BASELINE = OUT / "baseline/permanent_reward_effect_service_before_p151.lua"
HOOK = b"        add_values(totals_by_player[player_id], require('systems/commerce_archive_source_bonus').project(save))"

def run(args):
    result = subprocess.run([str(LUA), *args], cwd=ROOT, text=True, encoding="utf-8", capture_output=True)
    return {"exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    original = BASELINE.read_bytes()
    current = (ROOT / FILES[1]).read_bytes()
    newline = b"\r\n" if b"\r\n" in original else b"\n"
    assert current.count(HOOK) == 1 and current.replace(HOOK + newline, b"") == original, "Unexpected production service mutation"
    (OUT / "source_projection_service.diff").write_text("".join(difflib.unified_diff(
        original.decode("utf-8").replace("\r\n", "\n").splitlines(True), current.decode("utf-8").replace("\r\n", "\n").splitlines(True),
        fromfile="dirty_baseline", tofile="current_with_p151")), encoding="utf-8")
    syntax = run(["-e", ";".join("assert(loadfile(" + json.dumps(f) + "))" for f in FILES)])
    tested = run([FILES[2]])
    assert tested["exit_code"] == 0 and not tested["stderr"], tested
    assert "[EventBus] handler error" not in tested["stdout"], "Event bus swallowed a test assertion"
    count = re.search(r"COMMERCE_ARCHIVE_SOURCE_BONUS_PASS tests=(\d+) source_definitions=(\d+)", tested["stdout"])
    assert count and int(count[1]) == 11 and int(count[2]) == 77
    legacy_file = "scripts/vscripts/tests/test_pure_permanent_rewards.lua"
    legacy_current = run([legacy_file])
    old_code = "package.preload['systems/permanent_reward_effect_service']=function() return assert(loadfile('" + BASELINE.relative_to(ROOT).as_posix() + "'))() end;dofile('" + legacy_file + "')"
    legacy_baseline = run(["-e", old_code])
    current_errors = legacy_current["stdout"].count("[EventBus] handler error")
    baseline_errors = legacy_baseline["stdout"].count("[EventBus] handler error")
    assert current_errors == baseline_errors and legacy_current["exit_code"] == legacy_baseline["exit_code"], "Legacy behavior changed"
    for name,result in [("source_projection_tests",tested),("legacy_current",legacy_current),("legacy_dirty_baseline",legacy_baseline)]:
        (OUT / (name+".log")).write_text(result["stdout"]+result["stderr"],encoding="utf-8")
    report = {
        "status": "PASS", "tests": int(count[1]), "formal_source_definitions": int(count[2]),
        "lua": str(LUA), "syntax_exit_code": syntax["exit_code"],
        "service_delta": "One additive projection hook; removing it recovers the original dirty file byte for byte.",
        "test_names": [line[5:] for line in tested["stdout"].splitlines() if line.startswith("PASS ")],
        "source_sha256": {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in FILES},
        "original_dirty_service_sha256": hashlib.sha256(original).hexdigest(),
        "legacy_regression": {"pure_phase_pass": "PURE_PERMANENT_REWARDS_PASS" in legacy_current["stdout"],
            "baseline_swallowed_tower_assertions": baseline_errors, "current_swallowed_tower_assertions": current_errors,
            "conclusion": "Unchanged existing tower-growth fixture assertions; not counted as a passing full regression."},
        "scope": "Real Lua 5.1 modules and event-driven permanent reward service with synthetic profiles; no game engine, network, database, payment or real account.",
        "frozen_scope": "Social draws only mutate social_counts, not shadow/cage; exact committed social delta remains unamplified. Frozen source changes are never replayed.",
        "ordering": "Shadow/cage source boost precedes existing Longinus five-percent projection; time-orb transient boss bonus remains separate and deduplicated.",
    }
    assert syntax["exit_code"] == 0, syntax
    (OUT / "source_projection_validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({key:report[key] for key in ("status","tests","formal_source_definitions","legacy_regression")},ensure_ascii=False,indent=2))

if __name__ == "__main__": main()
