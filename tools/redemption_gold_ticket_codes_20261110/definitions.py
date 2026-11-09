"""Compile four additive server definitions from hashes, never plaintext codes.

This is an operator tool, not a client/runtime module. A one-shot compile reads
the existing O(P) shop catalogue once and copies four bounded rewards O(4).
It makes zero database/network calls and adds no stable game-loop work.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PRIVATE = ROOT / "output/redemption_gold_ticket_codes_20261110/private"
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.redemption_catalog import offers, reward_spec

QUANTITIES = (100, 500, 1000, 2000)
TICKET = "special_lottery_ticket"
BASE_SKU = "special_lottery_ticket_single"
BASE_MARKER = "pay_special_lottery_ticket_single"
HASH = re.compile(r"[0-9a-f]{64}\Z")


def require(value, code):
    if not value:
        raise ValueError(code)


def tiers():
    value = json.loads((HERE / "tiers.json").read_text(encoding="utf-8"))
    require(set(value) == {"version", "ticket_content_id", "base_sku", "pool_ids",
                           "per_account_per_code", "tiers"}
            and value["version"] == 1 and value["ticket_content_id"] == TICKET
            and value["base_sku"] == BASE_SKU and value["pool_ids"] == ["cultivation", "dragon_knight", "summer"]
            and value["per_account_per_code"] == 1, "ticket_code_tiers_invalid")
    rows = value["tiers"]
    require(isinstance(rows, list) and len(rows) == len(QUANTITIES), "ticket_code_tiers_invalid")
    for row, quantity in zip(rows, QUANTITIES):
        require(isinstance(row, dict) and set(row) == {"quantity", "label"}
                and type(row["quantity"]) is int and row["quantity"] == quantity
                and row["label"] == f"金色抽奖券×{quantity}", "ticket_code_tiers_invalid")
    return rows


def compile_definitions(code_hashes, *, root=ROOT, catalog=None):
    """Accept exactly {"100": SHA256, "500": SHA256, ...}; no code generation.

    The caller supplies SHA256(normalize(code)), using the existing server's
    normalization contract. Do not pass any actual code to this function.
    """
    require(isinstance(code_hashes, dict)
            and set(code_hashes) == {str(n) for n in QUANTITIES}, "ticket_code_hashes_invalid")
    hashes = list(code_hashes.values())
    require(all(isinstance(h, str) and HASH.fullmatch(h) for h in hashes), "ticket_code_hashes_invalid")
    require(len(set(hashes)) == 4 and len({h[:32] for h in hashes}) == 4, "ticket_code_hashes_duplicated")
    rows = tiers()
    if catalog is None:
        catalog, _ = offers(root)
    require(BASE_SKU in catalog, "ticket_code_base_product_missing")
    spec = reward_spec(catalog, [BASE_SKU])
    require(not spec["markers"] and not spec["wallet"] and not spec["entitlements"]
            and len(spec["products"]) == 1, "ticket_code_base_product_changed")
    base = spec["products"][0]
    grants = base.get("grants", {})
    require(base.get("sku") == BASE_SKU and base.get("item_id") == BASE_MARKER
            and base.get("purchase_limit") == 0 and base.get("ownership_quantity") == 1
            and not base.get("effects") and grants.get("items") == {TICKET: 1}
            and grants.get("item_limits") == {TICKET: 2147483647}
            and not grants.get("entitlements") and not grants.get("vip_claims")
            and not grants.get("vip_claim_effects"), "ticket_code_base_product_changed")
    definitions = []
    for row in rows:
        quantity, label = row["quantity"], row["label"]
        reward = copy.deepcopy(spec)
        product = reward["products"][0]
        product.update(title=label, description=f"兑换获得{quantity}张金色抽奖券，用于修仙、龙骑和暑期宝箱。")
        product["grants"]["items"] = {TICKET: quantity}
        product["grants"]["lines"] = [
            {"kind": "item", "id": TICKET, "quantity": quantity, "label": "金色抽奖券"}]
        digest = code_hashes[str(quantity)]
        definitions.append({"code_id": "r_" + digest[:32], "code_hash": digest,
                            "label": label, "enabled": True, "max_redemptions": 0,
                            "starts_at": None, "expires_at": None, "rewards": reward})
    return {"version": 1, "codes": definitions}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hashes", type=Path, help="Private JSON containing exactly four precomputed hashes")
    parser.add_argument("--output", type=Path, help="NEW registry under output/redemption_gold_ticket_codes_20261110/private")
    args = parser.parse_args(argv)
    if args.hashes is None and args.output is None:
        print(json.dumps({"ok": True, "status": "DEFINITIONS_ONLY_NO_CODES_CREATED",
                          "ticket_content_id": TICKET, "quantities": list(QUANTITIES),
                          "server_modified": False, "plaintext_codes_generated": False}))
        return 0
    require(args.hashes is not None and args.output is not None, "ticket_code_hashes_and_output_required")
    value = compile_definitions(json.loads(args.hashes.read_text(encoding="utf-8")))
    output = args.output.resolve()
    require(output.parent == PRIVATE.resolve(), "ticket_code_private_output_required")
    require(not output.exists(), "ticket_code_new_output_required")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        handle.write("\n")
    print(json.dumps({"ok": True, "codes": 4, "server_modified": False,
                      "plaintext_codes_generated": False, "plaintext_codes_in_output": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
