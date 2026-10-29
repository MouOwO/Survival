"""Build read-only welfare reward previews from the maintained configuration.

The generated file supplies artwork and reward labels while a server snapshot is
unavailable. It deliberately has no claim state, progress or eligibility fields.
Run --check to verify source consistency and generated text (with normalized LF).
"""
from pathlib import Path
import argparse
import csv
import hashlib
import io
import json

ROOT = Path(__file__).resolve().parents[1]
BENEFITS = "data/csv/存档系统/archive_benefit_rewards.csv"
STACKABLES = "data/csv/存档系统/archive_stackable_items.csv"
RESOURCES = "data/ui/item_resources.json"
OUTPUT = "panorama/src/scripts/custom_game/benefit_presentation_data.js"
TRACKS = {
    "daily_time": ("day", "minutes"),
    "daily_wins": ("day", "wins"),
    "weekly_time": ("week", "minutes"),
}
QUALITIES = {"", "N", "R", "SR", "SSR", "UR"}


def csv_rows(root, relative):
    text = (root / relative).read_text(encoding="utf-8-sig")
    return [row for row in csv.DictReader(io.StringIO(text))
            if next(iter(row.values()), "") and not next(iter(row.values())).startswith("#")]


def flag(value):
    if value not in ("", "0", "1"):
        raise ValueError("invalid_boolean:" + str(value))
    return value == "1"


def integer(value, label, positive=False):
    result = int(value)
    if str(result) != str(value) or result < (1 if positive else 0):
        raise ValueError("invalid_integer:" + label)
    return result


def build_data(root=ROOT):
    resources = json.loads((root / RESOURCES).read_text(encoding="utf-8-sig"))
    if resources.get("schema_version") != 1 or not isinstance(resources.get("items"), list):
        raise ValueError("resource_schema")
    lookup = {}
    for item in resources["items"]:
        if not isinstance(item.get("id"), str) or not isinstance(item.get("aliases"), list):
            raise ValueError("resource_identity")
        for key in [item["id"], *item["aliases"]]:
            if not isinstance(key, str) or key in lookup and lookup[key]["id"] != item["id"]:
                raise ValueError("resource_alias:" + str(key))
            lookup[key] = item
    stackables = {}
    for row in csv_rows(root, STACKABLES):
        if not flag(row["enabled"]):
            continue
        identity = row["item_id"]
        entry = stackables.setdefault(identity, {})
        for source, target in (("display_name", "name"), ("description", "description"), ("quality", "quality")):
            if row.get(source):
                value = row[source].upper() if source == "quality" else row[source]
                if target in entry and entry[target] != value:
                    raise ValueError("stackable_presentation_conflict:" + identity)
                entry[target] = value

    def rewards(ids_text, counts_text):
        ids = ids_text.split("|") if ids_text else []
        counts = counts_text.split("|") if counts_text else []
        if len(ids) != len(counts) or len(set(ids)) != len(ids):
            raise ValueError("reward_counts_mismatch:" + ids_text)
        result = []
        for identity, count_text in zip(ids, counts):
            if identity not in lookup:
                raise ValueError("reward_resource_missing:" + identity)
            resource, stackable = lookup[identity], stackables.get(identity, {})
            name = stackable.get("name", resource.get("name", ""))
            description = stackable.get("description", resource.get("description", ""))
            quality = stackable.get("quality", resource.get("quality", "")).upper()
            if not name or not isinstance(description, str) or quality not in QUALITIES:
                raise ValueError("reward_presentation_invalid:" + identity)
            result.append({"id": identity, "name": name,
                           "count": integer(count_text, identity, positive=True),
                           "description": description, "quality": quality})
        return result

    tracks = {name: [] for name in TRACKS}
    seen = set()
    for row in csv_rows(root, BENEFITS):
        if not flag(row["enabled"]):
            continue
        identity, track = row["reward_id"], row["track"]
        # This fixed tier belongs only to the login popup, never this menu.
        if identity == track == "public_beta_login":
            continue
        if not identity or identity in seen or track not in TRACKS:
            raise ValueError("benefit_identity:" + identity)
        seen.add(identity)
        if (row["period"], row["metric"]) != TRACKS[track]:
            raise ValueError("benefit_period_metric:" + identity)
        entry = {"id": identity, "required": integer(row["required"], identity),
                 "monthly_only": flag(row.get("monthly_only", "")),
                 "auto_claim": flag(row.get("auto_claim", "")),
                 "base_rewards": rewards(row["base_item_ids"], row["base_counts"]),
                 "monthly_rewards": rewards(row["pass_item_ids"], row["pass_counts"])}
        if not entry["base_rewards"] and not entry["monthly_rewards"]:
            raise ValueError("benefit_rewards_empty:" + identity)
        if entry["monthly_only"] and (entry["base_rewards"] or not entry["monthly_rewards"]):
            raise ValueError("benefit_monthly_only:" + identity)
        tracks[track].append(entry)
    for track, rows in tracks.items():
        if not rows or len({row["required"] for row in rows}) != len(rows):
            raise ValueError("benefit_requirements:" + track)
        rows.sort(key=lambda row: row["required"])
    return {"schemaVersion": 1, "sourceHashes": {
        # Git checks out the CSVs with native line endings. Hash their canonical
        # UTF-8/LF text so the presentation output is identical on every host.
        source: hashlib.sha256((root / source).read_text(encoding="utf-8-sig").encode("utf-8")).hexdigest()
        for source in (BENEFITS, STACKABLES, RESOURCES)}, "tracks": tracks}


def render(data):
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    return ("// AUTO-GENERATED by tools/build_benefit_presentation.py.\n"
            "// Display-only definitions; claim authority remains in the server snapshot.\n"
            '(function(){"use strict";\nvar data=' + payload + ";\n"
            'function freeze(value){if(!value||typeof value!=="object")return;'
            "Object.keys(value).forEach(function(key){freeze(value[key]);});"
            "if(Object.freeze)Object.freeze(value);}\nfreeze(data);\n"
            "GameUI.CustomUIConfig().SurvivalBenefitDefinitions=data;\n})();\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = build_data()
    output = render(data).encode("utf-8")
    target = ROOT / OUTPUT
    if args.check:
        if not target.exists() or target.read_text(encoding="utf-8-sig") != output.decode("utf-8"):
            raise SystemExit("benefit_presentation_out_of_date: run tools/build_benefit_presentation.py")
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(output)
    print(json.dumps({"status": "CHECK_PASS" if args.check else "GENERATED",
                      "tracks": {key: len(rows) for key, rows in data["tracks"].items()},
                      "sha256": hashlib.sha256(output).hexdigest()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
