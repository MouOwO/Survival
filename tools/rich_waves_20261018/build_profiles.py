"""Generate the isolated rich-mode profile from reviewed recording observations."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "data/balance/rich_n1_wave_stats.json"
OUTPUT = ROOT / "scripts/vscripts/config/generated/rich_wave_profiles.lua"


def lua(value, depth=0):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    entries = list(value.items()) if isinstance(value, dict) else list(enumerate(value, 1))
    if not entries:
        return "{}"
    pad = "    " * (depth + 1)
    return "{\n" + "\n".join(
        pad + "[" + lua(key) + "] = " + lua(child, depth + 1) + ","
        for key, child in entries
    ) + "\n" + "    " * depth + "}"


def generate():
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    observed = {row["record_id"]: row for row in source["observations"]}

    def stats(record_id):
        row = observed[record_id]
        return {key: row[key] for key in ("attack", "health", "war3_armor")} | {
            "source_record_id": record_id, "estimated": False,
        }

    waves = {}
    for wave in range(1, 26):
        rule = source["wave_profiles"][str(wave)]
        waves[wave] = {
            "normal": stats(rule["normal"]),
            "archetype_overrides": {key: stats(ref) for key, ref in rule["archetype_overrides"].items()},
            "batch_overrides": {key: stats(ref) for key, ref in rule["batch_overrides"].items()},
        }
        if rule.get("leader"):
            waves[wave]["leader"] = stats(rule["leader"])
        if rule.get("boss"):
            waves[wave]["boss"] = stats(rule["boss"])
    for wave in (10, 20):
        left, right = source["wave_profiles"][str(wave)]["boss_interpolation_source_waves"]
        # These are designed estimates, kept distinct from actual OCR readings.
        boss = {
            field: round((waves[left]["boss"][field] + waves[right]["boss"][field]) / 2)
            for field in ("attack", "health", "war3_armor")
        }
        waves[wave]["boss"] = boss | {
            "estimated": True, "estimation_method": "linear_between_bosses",
            "source_waves": [left, right],
        }
    payload = {
        "mode_id": "rich", "source_difficulty_id": "N1",
        "total_count_per_wave": 60, "last_recorded_wave": 25,
        "higher_difficulty_policy": source["policies"]["higher_difficulties"],
        "stats_basis": source["stats_basis"], "source_sha256": source["source"]["sha256"],
        "waves": waves,
    }
    return (
        "-- AUTO-GENERATED. DO NOT EDIT DIRECTLY.\n"
        "-- Source: data/balance/rich_n1_wave_stats.json\n"
        "-- Generator: tools/rich_waves_20261018/build_profiles.py\n"
        "-- Observed values are video panel readings; missing bosses are explicitly estimated.\n"
        "return " + lua(payload) + "\n"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    rendered = generate()
    if args.check:
        assert OUTPUT.read_text(encoding="utf-8") == rendered, "Generated rich profiles are stale"
        print("RICH_WAVE_PROFILE_GENERATION_CHECK_PASS")
    else:
        OUTPUT.write_text(rendered, encoding="utf-8")
        print("RICH_WAVE_PROFILE_GENERATION_PASS: 25 waves, 60 total per player, 2 interpolated bosses")


if __name__ == "__main__":
    main()
