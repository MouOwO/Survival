"""Generate the commerce icon bindings from the reviewed presentation manifest.

This tool never reads or changes prices, grants or gameplay catalogs. It updates
only the marked block in common/commerce_components.js; --check writes nothing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "data/ui/commerce_product_art_v1.json"
SCRIPT = "panorama/src/scripts/custom_game/common/commerce_components.js"
BEGIN = "    // BEGIN GENERATED COMMERCE PRODUCT ART V1"
END = "    // END GENERATED COMMERCE PRODUCT ART V1"
CLASSIFICATIONS = {"canonical_reward", "quantity_same_item", "native_technology", "shared_bundle", "ticket", "dedicated_commerce", "legacy_cash_reward", "pass_reward"}
PNG = re.compile(r"(?:custom_game|items|spellicons)/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.png\Z")
VTEX = re.compile(r"s2r://panorama/images/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.vtex\Z")


def safe_uri(value):
    if not isinstance(value, str) or len(value) > 512:
        return False
    relative = value.removeprefix("file://{images}/")
    return bool(PNG.fullmatch(relative) or VTEX.fullmatch(value))


def generated_block(blob):
    manifest = json.loads(blob)
    if manifest.get("schema_version") != 1:
        raise ValueError("Unsupported commerce art schema")
    products = manifest["products"]
    coverage = manifest["coverage"]
    if len(products) != coverage["commerce"] + coverage["additional_cash"]:
        raise ValueError("Incomplete commerce art coverage")
    skus = set()
    counts = {"commerce": 0, "cash": 0}
    lines = [BEGIN, "    // Source: " + MANIFEST + "; SHA256 " + hashlib.sha256(blob).hexdigest(), "    var productArt={"]
    for row in sorted(products, key=lambda item: item["sku"]):
        sku = row["sku"]
        if not re.fullmatch(r"[A-Za-z0-9_-]+", sku) or sku in skus:
            raise ValueError("Duplicate or invalid product SKU: " + sku)
        skus.add(sku)
        if row["classification"] not in CLASSIFICATIONS or row["catalog_source"] not in counts:
            raise ValueError("Unreviewed product art classification: " + sku)
        counts[row["catalog_source"]] += 1
        if not row.get("name") or not row.get("source") or not re.fullmatch(r"[A-Za-z0-9_-]+", row["item_id"]):
            raise ValueError("Missing reviewed art identity: " + sku)
        if not safe_uri(row["runtime_uri"]) or not all(safe_uri(uri) for uri in row["legacy_icons"]):
            raise ValueError("Unsafe product art URI: " + sku)
        if len(set(row["legacy_icons"])) != len(row["legacy_icons"]):
            raise ValueError("Duplicate legacy icon alias: " + sku)
        binding = {key: row[key] for key in ("item_id", "runtime_uri", "legacy_icons")}
        lines.append("        " + json.dumps(sku) + ":" + json.dumps(binding, ensure_ascii=False, separators=(",", ":")) + ",")
    if counts != {"commerce": coverage["commerce"], "cash": coverage["additional_cash"]}:
        raise ValueError("Commerce/cash art coverage differs")
    lines[-1] = lines[-1].removesuffix(",")
    lines.extend(["    };", END])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = (root / MANIFEST).read_bytes()
    block = generated_block(manifest)
    script = root / SCRIPT
    original = script.read_bytes()
    text = original.decode("utf-8")
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise ValueError("Missing or duplicate generated commerce art markers")
    start, end = text.index(BEGIN), text.index(END) + len(END)
    newline = "\r\n" if "\r\n" in text else "\n"
    updated = (text[:start] + block.replace("\n", newline) + text[end:]).encode("utf-8")
    if args.check:
        if updated != original:
            raise ValueError("Generated commerce product art is stale")
    else:
        script.write_bytes(updated)
    print(json.dumps({"result": "COMMERCE_PRODUCT_ART_CHECK_PASS" if args.check else "COMMERCE_PRODUCT_ART_GENERATED", "products": len(json.loads(manifest)["products"]), "manifest": MANIFEST}))


if __name__ == "__main__":
    main()
