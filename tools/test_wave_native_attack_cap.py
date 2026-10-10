"""Offline BAT-only native attack-cap policy suite; writes only temporary fixtures.

    python tools/test_wave_native_attack_cap.py
    python tools/test_wave_native_attack_cap.py --stage PATH_TO_CANDIDATE

--stage overlays the candidate's policy, wave spawn, CSV and generator. All
remaining modules and the real NPC KV come from the repository. No Dota or
network connection is used, and no generated production file is rewritten.
"""
from __future__ import annotations
import argparse
import csv
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, help="read-only candidate overlay")
    parser.add_argument("--root", type=Path, default=ROOT,
                        help="repository root (normally derived from this script)")
    parser.add_argument("--lua", default=os.environ.get("LUA"), help="Lua 5.1 executable")
    args = parser.parse_args()
    root = args.root.resolve()
    stage = args.stage.resolve() if args.stage else root
    lua = (args.lua or shutil.which("lua5.1") or shutil.which("lua")
           or "C:/Program Files/lua/bin/lua5.1.exe")
    sys.path.insert(0, str(root / "tools"))
    # Existing project parser; imports have no resource extraction side effects.
    from build_wave_monster_cosmetics import parse_kv

    def source(relative: str) -> Path:
        candidate = stage / relative
        return candidate if candidate.is_file() else root / relative

    npc = parse_kv(source("scripts/npc/npc_units_custom.txt").read_text(encoding="utf-8-sig"))["DOTAUnits"]

    def lua_value(value):
        if isinstance(value, dict):
            return "{" + ",".join("[" + json.dumps(key) + "]=" + lua_value(item)
                                  for key, item in value.items()) + "}"
        return json.dumps(value, ensure_ascii=False)

    csv_relative = "data/csv/怪物与波次系统/monster_archetypes.csv"
    csv_path = source(csv_relative)
    generated = source("scripts/vscripts/config/generated/monster_archetypes.lua")
    builder = source("tools/build_configs.py")
    namespace = {"__name__": "wave_cap_test_builder", "__file__": str(root / "tools/build_configs.py")}
    exec(compile(builder.read_text(encoding="utf-8"), str(builder), "exec"), namespace)
    with tempfile.TemporaryDirectory(prefix="survival_wave_native_cap_test_") as temporary:
        temp = Path(temporary)
        fixture = temp / "actual_unit_kv_fixture.lua"
        fixture.write_text("return " + lua_value(npc) + "\n", encoding="utf-8")
        roundtrip = temp / "monster_archetypes.lua"
        namespace["build"](csv_path, roundtrip)
        assert roundtrip.read_text(encoding='utf-8-sig') == generated.read_text(encoding='utf-8-sig'), "CSV/generated config drift"
        validate = namespace["validate_monster_attack_speed_policy"]
        headers = ["archetype_id", "passive_skill_ids", "native_attack_speed_policy"]
        for row in [["test", "", "typo"], ["test", "ogre_magi_bloodlust", "bat_only_v1"]]:
            try:
                validate(csv_path, headers, [(4, row)])
            except ValueError:
                pass
            else:
                raise AssertionError("invalid policy accepted: " + str(row))
        for row in [["new", "future_native_ability", ""], ["new", "", ""], ["audited", "", "bat_only_v1"]]:
            validate(csv_path, headers, [(4, row)])
        # When reviewing the overlay before integration, prove that adding the
        # policy column did not alter any existing designer-authored cell.
        baseline = list(csv.reader(io.StringIO((root / csv_relative).read_text(encoding="utf-8-sig"))))
        candidate = list(csv.reader(io.StringIO(csv_path.read_text(encoding="utf-8-sig"))))
        if "native_attack_speed_policy" not in baseline[0]:
            assert len(baseline) == len(candidate), "CSV rows changed"
            for before, after in zip(baseline, candidate):
                assert before == (after[:-1] if after else after), "existing CSV cell changed"
        print("WAVE_CAP_GENERATOR_PASS exact roundtrip; typo/passive conflict rejected; unknown defaults safe", flush=True)
        suite = [
            ("test_wave_native_attack_cap.lua", [str(stage), str(fixture), str(root)]),
            ("test_wave_native_attack_cap_spawn.lua", [str(source("scripts/vscripts/systems/wave_system.lua").parent)]),
            ("test_wave_native_attack_cap_sources.lua", [str(stage)]),
        ]
        for name, params in suite:
            subprocess.run([lua, str(Path(__file__).with_name(name)), *params], cwd=root, check=True)
    print("WAVE_NATIVE_ATTACK_CAP_SUITE_PASS; no production files written")


if __name__ == "__main__":
    main()
