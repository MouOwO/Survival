"""Compatibility entry point for the single maintained item-resource table.

Without update arguments this regenerates views from data/ui/item_resources.json.
Historical commerce_product_art_v1.json remains evidence and cannot overwrite
reviewed resource bindings. Use --sku/--resource-id/--runtime-uri together for an
explicit artwork update; --check never writes files.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

import build_item_resources

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "data/ui/item_resources.json"
PNG = re.compile(r"(?:custom_game|items|spellicons)/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.png\Z")
VTEX = re.compile(r"s2r://panorama/images/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.vtex\Z")


def safe_uri(value):
    if not isinstance(value, str) or len(value) > 512:
        return False
    relative = value.removeprefix("file://{images}/")
    return bool(PNG.fullmatch(relative) or VTEX.fullmatch(value))


def update_resource(root, sku, resource_id, runtime_uri, check=False):
    """Update an exact established SKU binding without guessing names or images."""
    if not safe_uri(runtime_uri):
        raise ValueError("Unsafe product art URI")
    source, resources, aliases = build_item_resources.load(root)
    if resource_id not in resources or aliases.get(sku) != resource_id:
        raise ValueError("SKU/resource identity differs; review aliases in " + SOURCE)
    row = resources[resource_id]
    if row['kind'] != 'image':
        raise ValueError("Use the existing specialized renderer for " + resource_id)
    if row['uri'] == runtime_uri:
        return False
    if check:
        raise ValueError("Requested explicit product art differs from maintained table")
    row['uri'] = runtime_uri
    (root / SOURCE).write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding='utf-8')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--sku")
    parser.add_argument("--resource-id")
    parser.add_argument("--runtime-uri")
    args = parser.parse_args()
    requested = (args.sku, args.resource_id, args.runtime_uri)
    if any(requested) and not all(requested):
        parser.error("--sku, --resource-id and --runtime-uri must be supplied together")
    root = args.root.resolve()
    updated = update_resource(root, *requested, check=args.check) if all(requested) else False
    result = build_item_resources.build(root=root, check=args.check)
    result.update(entry_point='commerce_product_art_compatibility', explicit_resource_updated=updated)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
