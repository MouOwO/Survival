"""Run the packaged title reducer offline; no account, database or HTTP access."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess


TITLE_IDS = (
    "peak_perfection", "jinghong", "youlong", "jian_tianya", "tianxia_diyi",
    "cangqiong", "sihai", "daoyuan", "chushen",
)


def run_checks(bundle_directory, lua):
    directory = Path(bundle_directory).resolve()
    raw = (directory / "bundle.json").read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if directory.name != digest:
        raise AssertionError("immutable bundle directory does not match its digest")
    bundle = json.loads(raw)
    for relative, source in bundle["sources"].items():
        filename = (directory / relative).resolve()
        if not filename.is_relative_to(directory):
            raise AssertionError("bundle source path escapes its directory")
        if filename.read_text(encoding="utf-8") != source:
            raise AssertionError("bundle source mismatch: " + relative)
    configs = bundle["configs"]
    rows = configs["archive_titles"]["rows"]
    assert [row["title_id"] for row in rows] == list(TITLE_IDS)
    assert [row["title_level"] for row in rows] == list(range(1, 10))
    assert [row["required_wave"] for row in rows] == list(range(1, 642, 80))
    assert all(row.get("enabled") is True for row in rows)
    checks = [{"case": "nine_title_csv_contract", "status": "PASS"}]
    worker_calls = 0
    serial = 0
    defaults = {
        row["field_id"]: row.get("default_value", 0)
        for row in configs["player_gameplay_stats"]["rows"]
    }

    def profile(wave, **archive_fields):
        # Preclaim unrelated achievement rewards so an endless transition tests
        # title selection without awarding unrelated synthetic gameplay stats.
        completed = {}
        for name in ("archive_achievements", "archive_endless_achievements", "archive_welfare_rewards"):
            for row in configs.get(name, {}).get("rows", []):
                if row.get("achievement_id"):
                    completed[row["achievement_id"]] = True
        archive = {"endless_best_wave": wave, "completed": completed, **archive_fields}
        return {
            "schema_version": 1, "account_id": "synthetic-title-smoke", "revision": 0,
            "public": {}, "entitlements": {}, "achievements": {},
            "save": {"archive": archive, "gameplay_stats": copy.deepcopy(defaults), "content_inventory": {}},
        }

    def command(kind="title_equip", **fields):
        nonlocal serial
        serial += 1
        return {"id": "offline_title_smoke_%d:operation" % serial, "kind": kind, **fields}

    def invoke(saved, operation):
        nonlocal worker_calls
        payload = {
            "configs": configs, "profile": saved, "command": operation,
            "has_pass": False, "seed": 1234567, "server_time": 2000000000,
        }
        original = copy.deepcopy(saved)
        completed = subprocess.run(
            [str(lua), "worker.lua"], cwd=directory,
            input=json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8"),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        worker_calls += 1
        result = json.loads(completed.stdout.decode("utf-8"))
        assert saved == original, "worker transport must not mutate its input"
        if "gameplay_stats" in result:
            assert result["gameplay_stats"] == saved["save"]["gameplay_stats"], "title smoke changed gameplay attributes"
        return result

    def accept(saved, operation, expected_title, *, manual=False, expected_best=None):
        result = invoke(saved, operation)
        assert result.get("ok") is True, result
        archive = result["archive"]
        assert archive.get("equipped_title", "") == expected_title, (operation, archive)
        assert (archive.get("title_selection_manual") is True) is manual
        if expected_best is not None:
            assert archive["endless_best_wave"] == expected_best
        saved["save"]["archive"] = archive
        saved["save"]["gameplay_stats"] = result["gameplay_stats"]
        return result

    def passed(name, **details):
        checks.append({"case": name, "status": "PASS", **details})

    boundaries = (
        (0, ""), (1, "peak_perfection"), (80, "peak_perfection"),
        (81, "jinghong"), (160, "jinghong"), (161, "youlong"),
        (640, "daoyuan"), (641, "chushen"), (720, "chushen"), (1000, "chushen"),
    )
    for wave, title in boundaries:
        saved = profile(wave)
        accept(saved, command(title_id=""), title, expected_best=wave)
        passed("automatic_boundary_%d" % wave, best_wave=wave, title_id=title)

    for old in ("peak_perfection", "chushen", "missing", ""):
        saved = profile(161, equipped_title=old, titles_owned={title: True for title in TITLE_IDS})
        accept(saved, command("endless_reconcile"), "youlong", expected_best=161)
        passed("legacy_selection_" + (old or "empty"), title_id="youlong")

    for wave, locked in ((0, "peak_perfection"), (80, "jinghong")):
        saved = profile(wave, titles_owned={title: True for title in TITLE_IDS})
        before = copy.deepcopy(saved)
        result = invoke(saved, command(title_id=locked))
        assert result.get("ok") is False and result.get("terminal") is True
        assert result.get("error") == "称号未解锁或不存在"
        assert saved == before
        passed("locked_title_%d" % wave, requested_title=locked)

    # This is the worker boundary, not the separate HTTP field validator.
    # Unknown command fields must never become trusted saved progress.
    saved = profile(1)
    injected = command(title_id="chushen", endless_best_wave=1000, wave=1000,
                       title_selection_manual=True, titles_owned={"chushen": True})
    result = invoke(saved, injected)
    assert result.get("ok") is False and result.get("error") == "称号未解锁或不存在"
    assert saved["save"]["archive"]["endless_best_wave"] == 1
    passed("injected_progress_cannot_unlock_title", validation_scope="worker_saved_progress")
    saved = profile(81)
    accept(saved, command(title_id="", endless_best_wave=1000, wave=1000), "jinghong", expected_best=81)
    passed("automatic_ignores_command_progress", best_wave=81)

    result = invoke(profile(1000), command(title_id="missing"))
    assert result.get("ok") is False and result.get("error") == "称号未解锁或不存在"
    passed("unknown_title_denied")

    saved = profile(80, equipped_title="peak_perfection")
    for wave, best, title in ((81, 81, "jinghong"), (1, 81, "jinghong"), (161, 161, "youlong")):
        accept(saved, command("endless", wave=wave, difficulty=1), title, expected_best=best)
        passed("automatic_endless_%d" % wave, best_wave=best, title_id=title)

    saved = profile(161)
    accept(saved, command(title_id="peak_perfection"), "peak_perfection", manual=True, expected_best=161)
    passed("manual_lower_title", title_id="peak_perfection")
    accept(saved, command("endless", wave=241, difficulty=1), "peak_perfection", manual=True, expected_best=241)
    passed("manual_survives_new_tier", best_wave=241)
    accept(saved, command(title_id=""), "jian_tianya", expected_best=241)
    passed("empty_choice_restores_automatic", title_id="jian_tianya")

    saved = profile(161)
    repeated = command(title_id="peak_perfection")
    accept(saved, repeated, "peak_perfection", manual=True, expected_best=161)
    before = copy.deepcopy(saved)
    duplicate = accept(saved, repeated, "peak_perfection", manual=True, expected_best=161)
    assert duplicate.get("duplicate") is True and saved == before
    passed("duplicate_worker_receipt", title_id="peak_perfection")

    return {
        "status": "PASS", "cases": len(checks), "checks": checks,
        "worker_calls": worker_calls, "bundle": digest,
        "gameplay_attributes_unchanged": True, "real_accounts": 0,
        "database_connections": 0, "network_requests": 0,
        "scope": "real packaged Lua worker; HTTP field validation is a separate boundary",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle_directory", type=Path)
    parser.add_argument("--lua", default="lua5.1")
    args = parser.parse_args()
    print(json.dumps(run_checks(args.bundle_directory, args.lua), ensure_ascii=False, indent=2))
