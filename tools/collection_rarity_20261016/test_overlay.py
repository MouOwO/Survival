"""Assert the release scope and reject representative unrelated/economy mutations."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import scope

def run(candidate):
    directory = ROOT / "output/collection_rarity_20261016/release" / candidate
    plan = json.loads((directory / "release_plan.json").read_bytes())
    before = json.loads((ROOT / "server/bundles" / plan["base"] / "bundle.json").read_bytes())
    after = json.loads((directory / "bundle" / candidate / "bundle.json").read_bytes())
    assert hashlib.sha256((directory / "bundle" / candidate / "bundle.json").read_bytes()).hexdigest() == candidate
    passed = scope.check(before, after, plan["base"], plan["source_sha256"])
    for relative, expected in plan["files"].items():
        assert hashlib.sha256((directory / relative).read_bytes()).hexdigest() == expected

    def denied(label, mutate):
        altered = copy.deepcopy(after)
        mutate(altered)
        try:
            scope.check(before, altered, plan["base"], plan["source_sha256"])
        except ValueError:
            return label
        raise AssertionError("scope_should_reject:" + label)

    rejected = []
    rejected.append(denied("existing_reward_value", lambda data: data["configs"]["archive_social_items"]["rows"][0].update(effect_values=["999999"])))
    rejected.append(denied("collection_cap", lambda data: data["configs"]["archive_social_items"]["rows"][0].update(max_owned=9999)))
    rejected.append(denied("draw_cost", lambda data: data["configs"]["archive_social_rules"]["rows"][0].update(draw_cost=2)))
    rejected.append(denied("pending_wife_drawn", lambda data: next(r for r in data["configs"]["archive_social_items"]["rows"] if r["item_id"] == "wife_31").update(draw_enabled=True)))
    rejected.append(denied("unapproved_tier_weights", lambda data: data["configs"]["archive_social_rules"]["rows"][0].update(quality_weight_ur=5000)))
    rejected.append(denied("unrelated_catalog", lambda data: data["configs"]["commerce_catalog"]["rows"][0].update(display_name="mutated")))
    rejected.append(denied("unrelated_reducer", lambda data: data["sources"].update({"systems/archive_settlement.lua": "return {}"})))
    rejected.append(denied("unreviewed_social_source", lambda data: data["sources"].update({scope.SOURCE: data["sources"][scope.SOURCE] + "\n--unreviewed"})))
    rejected.append(denied("old_client_economy_upgrade", lambda data: data["compatible_config_hashes"][plan["base"]].update(upgrade_commands=["social_draw"])))
    historical = next(iter(before["compatible_config_hashes"]))
    rejected.append(denied("historical_alias_removed", lambda data: data["compatible_config_hashes"].pop(historical)))
    return {"status": "PASS", "candidate": candidate, "scope": passed,
        "unapproved_mutations_rejected": rejected, "persistent_writes": 0}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate")
    arguments = parser.parse_args()
    print(json.dumps(run(arguments.candidate), ensure_ascii=False))
