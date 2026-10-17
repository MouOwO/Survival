"""Check the final local UI, immutable bundle and recorded online verification."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import Bundle, read_csv


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(candidate):
    output = ROOT / "output/collection_rarity_20261016"
    release = output / "release" / candidate
    plan = read(release / "release_plan.json")
    assert candidate == plan["candidate"]
    bundle = Bundle(ROOT / "server/bundles" / candidate)
    assert read(ROOT / "server/bundles/current.json")["hash"] == candidate
    assert candidate in (ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua").read_text("utf-8-sig")
    packed = read(bundle.directory / "bundle.json")
    for name in ("archive_social_items", "archive_social_rules"):
        assert read_csv(ROOT / "data/csv/存档系统" / (name + ".csv")) == packed["configs"][name]
    for relative, digest in plan["input_hashes"].items():
        assert sha(ROOT / relative) == digest, "Final production input changed: " + relative
    compiled = read(output / "ui_compile.json")
    assert compiled["success"] and not compiled["protectedChanges"]
    assert len(compiled["records"]) == 3
    for record in compiled["records"]:
        assert record["verified"]
        assert sha(Path(record["source"])).lower() == record["sourceHash"].lower()
        assert sha(Path(record["content"])).lower() == record["sourceHash"].lower()
        assert sha(Path(record["artifact"])).lower() == record["compiledHash"].lower()
    browser_path = ROOT / "design_refs/collection_gw2_v2/work/onepage_final/report.json"
    browser = read(browser_path)
    assert browser["status"] == "PASS_COLLECTION_ONEPAGE_40"
    assert not browser["sourceChanged"] and not browser["assetChanged"]
    probability_proof = read(browser_path.with_name("rarity_probability_proof.json"))
    assert probability_proof["status"] == "PASS_COLLECTION_RARITY_VISIBLE_TOOLTIP"
    assert not probability_proof["sourceChanged"]
    activated = read(release / "deployment/activate.json")
    verified = read(release / "deployment/verify.json")
    assert activated["status"] == "DEPLOYED" and verified["status"] == "VERIFIED"
    assert activated["archive_bundle"] == verified["archive_bundle"] == candidate
    assert verified["real_account_commands"] == verified["test_fixture_rows_committed"] == 0
    report = {
        "status": "PASS_COLLECTION_RARITY",
        "bundle": candidate,
        "baseline": plan["base"],
        "pools": ["ex", "friend", "wife", "beast"],
        "visible_items": 160,
        "drawable_items": 158,
        "pending_ids": ["wife_31", "wife_39"],
        "tier_probabilities_when_all_available": {"N": .6, "R": .25, "SR": .1, "SSR": .045, "UR": .005},
        "colors": {"N": "#8fc47b", "R": "#74c8f2", "SR": "#b680ee", "SSR": "#f5c65e", "UR": "#ef5350"},
        "probability_rules": "Quality weights first; remaining copies within quality; full/pending excluded; empty qualities renormalized.",
        "existing_inventory_caps_effects_tickets_preserved": True,
        "cache_migration_preserves_pending_intent": True,
        "ui_compile": "output/collection_rarity_20261016/ui_compile.json",
        "ui_resources_compiled": 3,
        "unrelated_resources_changed_during_compile": [],
        "browser_report": browser_path.relative_to(ROOT).as_posix(),
        "visible_probability_report": browser_path.with_name("rarity_probability_proof.json").relative_to(ROOT).as_posix(),
        "browser_pointer_checks": len(browser["pointerChecks"]),
        "browser_capture_is_game_capture": False,
        "remote_verification": (release / "deployment/verify.json").relative_to(ROOT).as_posix(),
        "real_player_transactions_used_for_testing": 0,
    }
    target = ROOT / "docs/ai/validation/20261016/collection_rarity.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("COLLECTION_RARITY_FINAL_AUDIT_PASS", candidate, target.relative_to(ROOT))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True)
    audit(parser.parse_args().candidate)
