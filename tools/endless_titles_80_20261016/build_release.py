"""Build and test a title-only immutable archive candidate, without activation.

The parent is the reviewed fbf16 collection-rarity release. Its other rules, compatibility
aliases, purchases and prices remain byte-for-byte equivalent in bundle data.
Existing local challenge-context changes are deliberately excluded from the
candidate settlement. No network, database or running-pointer writes occur.
"""
from __future__ import annotations

import argparse
import copy
import difflib
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import Bundle, read_csv

BASE = "fbf16c3e996fa377f0d3cacd726c919f93958ecaf8be94a52b89ee08719f52e9"
CANDIDATE = "60d6ce00a7d3257b6982492fdfdf68aa8deacdb4d46f837248ecfbef5ebdec94"
DEFAULT_OUTPUT = ROOT / "output/endless_titles_80_20261016/release_fbf16"
ORIGINAL = ROOT / "output/endless_titles_80_20261016/original"
CSV = "data/csv/存档系统/archive_titles.csv"
TITLE_SOURCE = "systems/archive_titles.lua"
SETTLEMENT_SOURCE = "systems/archive_settlement.lua"
SYNC = '    require("systems/archive_titles").sync(archive)\n'
SYNC_BEFORE = '    require("systems/archive_welfare_rewards").reconcile(archive, stats, apply_effects)\n'
POINTERS = ("server/bundles/current.json", "scripts/vscripts/config/generated/archive_http_bundle.lua")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def text(path):
    return path.read_text(encoding="utf-8-sig")


def write_immutable(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_bytes() != raw:
            raise ValueError("immutable_candidate_changed:" + str(path))
    else:
        path.write_bytes(raw)


def known_local_settlement(parent):
    """Reconstruct only the pre-existing challenge drift observed in this task.

    This also permits a fresh checkout to reproduce the candidate without the
    ignored original/ capture. The task delta is checked against this baseline.
    """
    before = "function M.settle(profile, command, pass)\n"
    after = "function M.settle(profile, command, pass, context)\n"
    old_call = "        local ok, reason = challenge_rewards.apply(command, archive, stats, pass, apply_effects)\n"
    new_call = (
        "        local random_int\n"
        "        if context and context.challenge_random_seed then\n"
        '            random_int = require("systems/archive_cooperative_reward_policy").random_int(context.challenge_random_seed)\n'
        "        end\n"
        "        local ok, reason = challenge_rewards.apply(command, archive, stats, pass, apply_effects, random_int)\n"
    )
    assert parent.count(before) == 1 and parent.count(old_call) == 1
    return parent.replace(before, after, 1).replace(old_call, new_call, 1)


def checked_original(name, expected):
    capture = ORIGINAL / "scripts/vscripts" / name
    if capture.is_file():
        assert text(capture) == expected, "original_source_drifted:" + name
    return expected


def worker_smoke(bundle, lua):
    defaults = {row["field_id"]: row.get("default_value", 0)
                for row in bundle.configs["player_gameplay_stats"]["rows"]}
    profile = {"schema_version": 1, "account_id": "synthetic-title-candidate", "revision": 1,
               "entitlements": {}, "save": {"archive": {"endless_best_wave": 241},
                                             "gameplay_stats": defaults, "content_inventory": {}}}
    original = copy.deepcopy(profile)
    calls = 0

    def run(source, title_id):
        nonlocal calls
        payload = {"configs": bundle.configs, "profile": source, "has_pass": False,
                   "seed": 12345, "server_time": 2000000000,
                   "command": {"id": "title-candidate:" + str(calls + 1),
                               "kind": "title_equip", "title_id": title_id}}
        completed = subprocess.run([str(lua), "worker.lua"], cwd=bundle.directory,
                                   input=canonical(payload), capture_output=True, check=True, timeout=10,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        calls += 1
        return json.loads(completed.stdout)

    automatic = run(profile, "")
    assert automatic.get("ok") is True, automatic
    assert automatic["archive"]["equipped_title"] == "jian_tianya"
    assert automatic["archive"]["title_selection_manual"] is False
    assert automatic["gameplay_stats"] == defaults, "cosmetic_auto_changed_gameplay_stats"
    assert not any(key in automatic for key in ("content_inventory", "response"))
    manual_profile = copy.deepcopy(profile)
    manual_profile["save"]["archive"] = automatic["archive"]
    manual = run(manual_profile, "jinghong")
    assert manual.get("ok") is True and manual["archive"]["equipped_title"] == "jinghong"
    assert manual["archive"]["title_selection_manual"] is True
    assert manual["gameplay_stats"] == defaults, "cosmetic_manual_changed_gameplay_stats"
    denied = run(profile, "chushen")
    assert denied.get("ok") is False and denied.get("terminal") is True
    assert "archive" not in denied and "gameplay_stats" not in denied
    assert profile == original, "synthetic_input_profile_was_modified"
    return {"status": "PASS", "worker_calls": calls, "synthetic_best_wave": 241,
            "automatic_title": "jian_tianya", "manual_title": "jinghong",
            "locked_title_rejected": "chushen", "gameplay_stats_unchanged": True,
            "network_requests": 0, "database_connections": 0, "real_player_data": False}


def build(output, lua, parent_directory):
    if not (parent_directory / "bundle.json").is_file():
        raise ValueError("parent_bundle_missing: supply --parent-bundle PATH to the complete reviewed " + BASE + " directory")
    if parent_directory.name != BASE:
        raise ValueError("parent_bundle_directory_must_be_named:" + BASE)
    parent_raw = (parent_directory / "bundle.json").read_bytes()
    assert sha(parent_raw) == BASE, "parent_bundle_hash_mismatch"
    parent_bundle = Bundle(parent_directory)
    parent = json.loads(parent_raw)
    data = copy.deepcopy(parent)

    parent_titles = parent["sources"][TITLE_SOURCE]
    parent_settlement = parent["sources"][SETTLEMENT_SOURCE]
    original_titles = checked_original(TITLE_SOURCE, parent_titles)
    original_settlement = checked_original(SETTLEMENT_SOURCE, known_local_settlement(parent_settlement))
    current_titles = text(ROOT / "scripts/vscripts" / TITLE_SOURCE)
    current_settlement = text(ROOT / "scripts/vscripts" / SETTLEMENT_SOURCE)
    assert current_settlement.count(SYNC) == 1, "title_settlement_sync_missing_or_duplicated"
    assert current_settlement.replace(SYNC, "", 1) == original_settlement, "unexpected_local_settlement_task_delta"
    assert parent_settlement.count(SYNC_BEFORE) == 1 and SYNC not in parent_settlement
    data["sources"][TITLE_SOURCE] = current_titles
    # Apply our one-line task delta to deployed code, never to the dirty local baseline.
    data["sources"][SETTLEMENT_SOURCE] = parent_settlement.replace(SYNC_BEFORE, SYNC + SYNC_BEFORE, 1)

    data["configs"]["archive_titles"] = read_csv(ROOT / CSV)
    rows = data["configs"]["archive_titles"]["rows"]
    assert [row["title_level"] for row in rows] == list(range(1, 10))
    assert [row["required_wave"] for row in rows] == list(range(1, 642, 80))
    assert all(row["enabled"] is True and row["default_unlocked"] is False for row in rows)
    for old, new in zip(parent["configs"]["archive_titles"]["rows"], rows, strict=True):
        assert all(new[key] == old[key] for key in ("title_id", "display_name", "icon", "description", "enabled")), "unrelated_title_asset_changed"
    data["csv_hashes"][CSV] = sha((ROOT / CSV).read_bytes().replace(b"\r\n", b"\n"))

    changed_sources = sorted(key for key in parent["sources"] if data["sources"][key] != parent["sources"][key])
    assert changed_sources == sorted((TITLE_SOURCE, SETTLEMENT_SOURCE))
    assert set(data["sources"]) == set(parent["sources"])
    assert set(data["configs"]) == set(parent["configs"])
    assert set(data["csv_hashes"]) == set(parent["csv_hashes"])
    assert all(value == data["configs"][key] for key, value in parent["configs"].items() if key != "archive_titles")
    assert all(value == data["csv_hashes"][key] for key, value in parent["csv_hashes"].items() if key != CSV)
    assert all(value == data[key] for key, value in parent.items() if key not in {"configs", "sources", "csv_hashes"})
    assert data.get("compatible_config_hashes", {}) == parent.get("compatible_config_hashes", {})
    assert BASE not in data.get("compatible_config_hashes", {}), "parent_hash_alias_was_added"
    raw = canonical(data)
    digest = sha(raw)
    assert digest != BASE
    candidate = output / "candidate"
    bundle_directory = candidate / "addon/server/bundles" / digest
    write_immutable(bundle_directory / "bundle.json", raw)
    for name, source in data["sources"].items():
        relative = PurePosixPath(name)
        assert not relative.is_absolute() and ".." not in relative.parts and "\\" not in name
        write_immutable(bundle_directory / name, source.encode("utf-8"))
    checked = Bundle(bundle_directory)
    assert checked.hash == digest and checked.tables["archive_titles"]["jinghong"]["required_wave"] == 81
    assert checked.compatible_config_hashes == parent_bundle.compatible_config_hashes
    write_immutable(candidate / "addon/server/bundles/current.json", canonical({"hash": digest, "protocol": 1}))
    write_immutable(candidate / "addon/scripts/vscripts/config/generated/archive_http_bundle.lua",
                    ('-- Candidate only; not published or activated.\nreturn { protocol = 1, hash = "' + digest + '" }\n').encode("utf-8"))
    configuration = {"configs": data["configs"], "compatible_config_hashes": data.get("compatible_config_hashes", {})}
    write_immutable(output / "configuration.json", canonical(configuration))
    smoke = worker_smoke(checked, lua)
    write_immutable(output / "worker_smoke.json", canonical(smoke))
    drift = "".join(difflib.unified_diff(parent_settlement.splitlines(True), original_settlement.splitlines(True),
                                       fromfile="deployed/" + SETTLEMENT_SOURCE, tofile="local_original/" + SETTLEMENT_SOURCE))
    manifest = {"format": 1, "status": "LOCAL_CANDIDATE_ONLY", "base_hash": BASE, "candidate_hash": digest,
                "sources_changed": changed_sources, "configs_changed": ["archive_titles"], "csv_hashes_changed": [CSV],
                "compatibility_unchanged": True, "parent_hash_alias_added": False,
                "commerce_currency_payment_configuration_unchanged": True,
                "original_titles_match_deployed": original_titles == parent_titles,
                "original_settlement_match_deployed": original_settlement == parent_settlement,
                "excluded_preexisting_settlement_drift": drift,
                "candidate_settlement_delta": SYNC.strip(),
                "bundle_validation": "PASS", "worker_smoke": smoke,
                "sources_sha256": {name: {"before": sha(parent["sources"][name].encode("utf-8")),
                                           "after": sha(data["sources"][name].encode("utf-8"))} for name in changed_sources},
                "files": {path.relative_to(candidate).as_posix(): sha(path.read_bytes())
                          for path in sorted(candidate.rglob("*")) if path.is_file()},
                "configuration_sha256": sha(canonical(configuration)),
                "production_deployed": False, "runtime_pointers_modified": False, "network_requests": 0}
    write_immutable(output / "manifest.json", canonical(manifest))
    return {key: manifest[key] for key in ("status", "base_hash", "candidate_hash", "sources_changed",
                                          "configs_changed", "compatibility_unchanged", "worker_smoke")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--parent-bundle", type=Path, default=ROOT / "server/bundles" / BASE,
                        help="Complete reviewed parent bundle directory named " + BASE + "; required external release input on a fresh checkout")
    parser.add_argument("--lua", default=shutil.which("lua5.1") or "C:/Program Files/lua/bin/lua5.1.exe")
    args = parser.parse_args()
    output = args.output.resolve()
    assert output.is_relative_to((ROOT / "output").resolve()), "candidate_output_must_stay_in_ignored_output"
    pointers = {name: (ROOT / name).read_bytes() for name in POINTERS if (ROOT / name).is_file()}
    absent = [name for name in POINTERS if name not in pointers]
    if POINTERS[0] in pointers:
        assert json.loads(pointers[POINTERS[0]])["hash"] in {BASE, CANDIDATE}, "running_pointer_changed"
    if POINTERS[1] in pointers:
        assert any(digest.encode() in pointers[POINTERS[1]] for digest in (BASE, CANDIDATE)), "running_game_pointer_changed"
    try:
        report = build(output, args.lua, args.parent_bundle.resolve())
    finally:
        assert all((ROOT / name).read_bytes() == value for name, value in pointers.items()), "running_pointer_modified"
        assert all(not (ROOT / name).exists() for name in absent), "absent_running_pointer_created"
    report["runtime_pointer_evidence"] = {"present": sorted(pointers), "absent": absent,
                                          "active_parent_confirmed": not absent and all(BASE.encode() in value for value in pointers.values()),
                                          "active_candidate_confirmed": not absent and all(CANDIDATE.encode() in value for value in pointers.values())}
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
