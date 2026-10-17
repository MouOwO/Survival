"""Generate a separate, reviewed shop-home list without rebuilding other tabs.

Only the marked block at the end of commerce_components.js is generated. Prices,
rewards, the full product list and the older video presentation are never changed.
The manifest must contain an explicit, reviewed list; there is no all-items fallback.
--check and --print-block write nothing. --model-source/--model-output produce a
separate narrow integration candidate for the untracked market model.
The model integration keeps ordinary and VIP bundles exclusive to their own tabs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "data/ui/shop_home_catalog_20261016.json"
PRODUCT_ART = "data/ui/commerce_product_art_v1.json"
SCRIPT = "panorama/src/scripts/custom_game/common/commerce_components.js"
BEGIN = "// BEGIN GENERATED SHOP HOME CATALOG 20261016"
END = "// END GENERATED SHOP HOME CATALOG 20261016"
SKU = re.compile(r"[A-Za-z0-9_-]+\Z")
SOURCE_ID = re.compile(r"P\d{3}\Z")

MODEL_OLD = '    function groupOrder(id){var value=(presentation().groups||{})[id];return Array.isArray(value)?value:null;}'
MODEL_NEW = '''    function groupOrder(id){
        if(id==="home"){
            var home=config&&config.SurvivalShopHomeCatalog;
            var order=home&&typeof home.List==="function"?home.List():null;
            return Array.isArray(order)?order:[];
        }
        var value=(presentation().groups||{})[id];return Array.isArray(value)?value:null;
    }'''
MODEL_HOME_OLD = '''    function homeProducts(items){
        var home=config&&config.SurvivalShopHomeCatalog;
        return home&&typeof home.Compose==="function"?home.Compose(rows(items),isListed):[];
    }
'''
MODEL_HOME_PREVIOUS = MODEL_HOME_OLD.replace('home.Compose(rows(items),isListed)',
                                            'home.Compose(rows(items),function(item){return item.product_type!=="bundle"&&isListed(item);})')
MODEL_HOME = '''    function homeProducts(items){
        var home=config&&config.SurvivalShopHomeCatalog;
        var composed=home&&typeof home.Compose==="function"?home.Compose(rows(items),function(item){return item.product_type!=="bundle"&&isListed(item);}):[];
        // Reviewed video placeholders have no formal SKU or buying eligibility.
        // Keep them in the source evidence, never in the live storefront.
        return rows(composed).filter(function(item){return item.product_type!=="bundle"&&isListed(item);});
    }
'''
MODEL_VIP_OLD = '    function isVip(item){return number(item.required_vip_level)>0||listedInVideo(item,"vip")||item.category_id==="vip";}'
MODEL_VIP = '    function isVip(item){return number(item.required_vip_level)>0||item.category_id==="vip";}'
MODEL_GROUPS_OLD = '''    function inGroup(item,id){
        if(!isListed(item))return false;
        if(id==="all")return true;
        if(listedInVideo(item,id))return true;
        if(id==="home")return groupOrder("home")===null;
        if(id==="vip")return isVip(item);
        if(id==="bundles")return item.product_type==="bundle"&&!isVip(item);
        if(id==="promotions")return discount(item);
        return false;
    }
    function groupFor(item){
        if(!item)return "all";
        if(isVip(item))return "vip";
        if(item.product_type==="bundle")return "bundles";
        if(discount(item))return "promotions";
        return listedInVideo(item,"home")?"home":"all";
    }'''
MODEL_GROUPS = '''    function inGroup(item,id){
        if(!isListed(item))return false;
        // Product type and VIP requirements come from the server catalog.
        // Discounts and legacy display lists cannot move bundles to other tabs.
        if(item.product_type==="bundle")return id===(isVip(item)?"vip":"bundles");
        if(id==="vip"||id==="bundles")return false;
        if(id==="all")return true;
        if(listedInVideo(item,id))return true;
        if(id==="home")return groupOrder("home")===null;
        if(id==="promotions")return discount(item);
        return false;
    }
    function groupFor(item){
        if(!item)return "all";
        if(item.product_type==="bundle")return isVip(item)?"vip":"bundles";
        if(discount(item))return "promotions";
        return listedInVideo(item,"home")?"home":"all";
    }'''

CONTROLLER_OLD = '''        var items=products.filter(function(p){return M?K.InGroup(p,category):p.category_id===category;});
        if(M)items=K.SortProducts(items,category);'''
CONTROLLER_NEW = '''        var items=M&&category==="home"?(K.HomeProducts?K.HomeProducts(products):[]):products.filter(function(p){return M?K.InGroup(p,category):p.category_id===category;});
        if(M&&category!=="home")items=K.SortProducts(items,category);'''
INSPECT_OLD = '''visibleSkus:M?K.SortProducts(rows(catalog.products).filter(function(item){return K.InGroup(item,category);}),category).map(function(item){return item.sku;}):[]'''
INSPECT_NEW = '''visibleSkus:M?(category==="home"?(K.HomeProducts?K.HomeProducts(rows(catalog.products)):[]):K.SortProducts(rows(catalog.products).filter(function(item){return K.InGroup(item,category);}),category)).map(function(item){return item.home_display_id||item.sku;}):[]'''

MARKET_HOME = '''    // Local video placeholders are presentation only, with no product identity.
    function homeUnavailableRow(parent,item){
        var row=make("Panel",parent,"","BLMarketRow BLMarketHomeUnavailable");
        row.style.width="1072px";row.style.minWidth="1072px";row.style.height="64px";row.style.minHeight="64px";
        row.style.margin="0px";row.style.padding="0px";row.hittest=true;row.hittestchildren=false;
        var well=box(make("Panel",row,"","BLMarketArt"),8,8,48,48);well.hittest=false;
        var glyph=box(label(well,"?","BLMarketUnavailableIcon"),0,0,48,48);
        glyph.style.textAlign="center";glyph.style.fontSize="30px";glyph.style.color="#9d9b8c";
        var name=box(label(row,item.title,"BLMarketName"),82,17,332,30);
        var state=box(label(row,"未开放","BLMarketUnavailableState"),424,17,144,30);state.style.color="#aaa89a";
        row.__menuCell={iconPanel:well,namePanel:name,countPanel:null};
        row.SetPanelEvent("onmouseover",function(){if(valid(row))$.DispatchEvent("DOTAShowTextTooltip",row,item.description);});
        row.SetPanelEvent("onmouseout",function(){$.DispatchEvent("DOTAHideTextTooltip",row);});
        return row;
    }
'''


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate manifest field: " + key)
        result[key] = value
    return result


def read_manifest(blob, known_skus):
    manifest = json.loads(blob, object_pairs_hook=no_duplicate_keys)
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise ValueError("Unsupported shop-home schema")
    source = manifest.get("source")
    if not isinstance(source, dict) or source.get("kind") not in {"user_confirmed", "video_frame"}:
        raise ValueError("A reviewed shop-home source is required")
    reference = source.get("reference")
    if not isinstance(reference, str) or not reference.strip():
        raise ValueError("Shop-home evidence reference is required")
    times = source.get("timestamps_seconds", [])
    if not isinstance(times, list) or any(
        isinstance(value, bool) or not isinstance(value, (int, float))
        or not math.isfinite(value) or value < 0 for value in times
    ):
        raise ValueError("Invalid video evidence timestamps")
    if source["kind"] == "video_frame" and not times:
        raise ValueError("Video evidence needs an exact timestamp")
    entries = manifest.get("entries")
    if not isinstance(entries, list):
        raise ValueError("An explicit entries array is required")
    seen, sources = set(), set()
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("kind") not in {"product", "unavailable"}:
            raise ValueError("Invalid home entry kind")
        source_id, name = entry.get("source_id"), entry.get("name")
        if not isinstance(source_id, str) or not SOURCE_ID.fullmatch(source_id) or source_id in sources:
            raise ValueError("Duplicate or invalid home source: " + repr(source_id))
        if not isinstance(name, str) or not name.strip() or any(c in name for c in "<>\r\n"):
            raise ValueError("A plain display name is required")
        allowed = {"kind", "source_id", "name", "sku"} if entry["kind"] == "product" else {"kind", "source_id", "name"}
        if set(entry) - allowed:
            raise ValueError("Unexpected home entry fields: " + source_id)
        if entry["kind"] == "product":
            sku = entry.get("sku")
            if not isinstance(sku, str) or not SKU.fullmatch(sku) or sku in seen:
                raise ValueError("Duplicate or invalid home SKU: " + repr(sku))
            if sku not in known_skus or sku != "video_" + source_id.lower():
                raise ValueError("Unknown or mismatched home SKU: " + sku)
            seen.add(sku)
        sources.add(source_id)
    return manifest


def generated_block(blob, known_skus):
    manifest = read_manifest(blob, known_skus)
    digest = hashlib.sha256(blob).hexdigest()
    lines = [BEGIN, "// Source: " + MANIFEST + "; SHA256 " + digest,
             "(function(){", '    "use strict";',
             "    var cfg=GameUI.CustomUIConfig(),entries=["]
    for entry in manifest["entries"]:
        lines.append("        " + json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + ",")
    if manifest["entries"]:
        lines[-1] = lines[-1][:-1]
    lines.extend(["    ];",
                  '    function identity(entry){return entry.kind==="product"?entry.sku:"home_unavailable_"+entry.source_id;}',
                  "    function compose(products,isListed){",
                  "        var bySku=Object.create(null),result=[];",
                  '        (Array.isArray(products)?products:[]).forEach(function(item){if(item&&typeof item.sku==="string"&&!bySku[item.sku])bySku[item.sku]=item;});',
                  "        entries.forEach(function(entry){",
                  '            if(entry.kind==="unavailable"){',
                  '                var placeholder={home_unavailable:true,home_display_id:identity(entry),source_id:entry.source_id,title:entry.name,',
                  '                    description:entry.name+"：暂未开放。",enabled:false};',
                  "                if(Object.freeze)Object.freeze(placeholder);result.push(placeholder);",
                  "            }else{",
                  '                var item=bySku[entry.sku];if(item&&typeof isListed==="function"&&isListed(item))result.push(item);',
                  "            }",
                  "        });",
                  "        return result;",
                  "    }",
                  "    cfg.SurvivalShopHomeCatalog={",
                  "        sourceHash:" + json.dumps(digest) + ",",
                  "        List:function(){return entries.map(identity);},",
                  "        Compose:compose", "    };", "})();", END])
    return "\n".join(lines)


def patch_components_source(original, block):
    text = original.decode("utf-8")
    newline = "\r\n" if "\r\n" in text else "\n"
    begin_count, end_count = text.count(BEGIN), text.count(END)
    if begin_count == 0 and end_count == 0:
        separator = newline if text.endswith("\n") else newline * 2
        return original + (separator + block.replace("\n", newline) + newline).encode("utf-8")
    if begin_count != 1 or end_count != 1:
        raise ValueError("Missing or duplicate shop-home block markers")
    start, end = text.index(BEGIN), text.index(END) + len(END)
    if end <= start:
        raise ValueError("Reversed shop-home block markers")
    return (text[:start] + block.replace("\n", newline) + text[end:]).encode("utf-8")


def patch_model_source(original):
    text = original.decode("utf-8")
    newline = "\r\n" if "\r\n" in text else "\n"
    updated = MODEL_NEW.replace("\n", newline)
    if updated not in text:
        text = replace_once(text, MODEL_OLD, updated, "groupOrder")
    helper = MODEL_HOME.replace("\n", newline)
    legacy_helper = MODEL_HOME_OLD.replace("\n", newline)
    if legacy_helper in text:
        text = replace_once(text, legacy_helper, helper, "home single-product filter")
    previous_helper = MODEL_HOME_PREVIOUS.replace("\n", newline)
    if previous_helper in text:
        text = replace_once(text, previous_helper, helper, "home formal-product filter")
    if helper not in text:
        text = replace_once(text, "    function groups(catalog){", helper + "    function groups(catalog){", "home composition")
    text = replace_once(text,
                        "count:products.filter(function(item){return inGroup(item,definition.id);}).length",
                        'count:definition.id==="home"?homeProducts(products).length:products.filter(function(item){return inGroup(item,definition.id);}).length', "home count")
    text = replace_once(text, "var model={Groups:groups,GroupFor:groupFor,", "var model={Groups:groups,HomeProducts:homeProducts,GroupFor:groupFor,", "home model API")
    text = replace_once(text, MODEL_VIP_OLD, MODEL_VIP, "authoritative VIP classification")
    text = replace_once(text, MODEL_GROUPS_OLD.replace("\n", newline), MODEL_GROUPS.replace("\n", newline), "exclusive bundle groups")
    return text.encode("utf-8")


def replace_once(text, old, new, label):
    if new in text:
        if text.count(new) != 1:
            raise ValueError("Duplicate integration block: " + label)
        return text
    if text.count(old) != 1:
        raise ValueError("Source changed; expected one exact " + label + " anchor")
    return text.replace(old, new, 1)


def patch_controller_source(original):
    text = original.decode("utf-8")
    newline = "\r\n" if "\r\n" in text else "\n"
    text = replace_once(text, CONTROLLER_OLD.replace("\n", newline), CONTROLLER_NEW.replace("\n", newline), "home render")
    text = replace_once(text, INSPECT_OLD, INSPECT_NEW, "home inspection")
    return text.encode("utf-8")


def patch_market_source(original):
    text = original.decode("utf-8")
    newline = "\r\n" if "\r\n" in text else "\n"
    helper = MARKET_HOME.replace("\n", newline)
    anchor = "    M.Row=function(parent,item,props){"
    if helper not in text:
        text = replace_once(text, anchor, helper + anchor, "unavailable row")
    text = replace_once(text, anchor + newline,
                        anchor + newline + '        if(item&&item.home_unavailable===true)return homeUnavailableRow(parent,item);' + newline,
                        "unavailable row dispatch")
    return text.encode("utf-8")


def known_products(root):
    rows = json.loads((root / PRODUCT_ART).read_bytes())["products"]
    return {row["sku"] for row in rows}


def sha(blob):
    return hashlib.sha256(blob).hexdigest()


def prepare_candidates(source_root, directory, block):
    source_root, directory = source_root.resolve(), directory.resolve()
    targets = [(SCRIPT, lambda raw: patch_components_source(raw, block), False),
               ("panorama/src/scripts/custom_game/black_lion_market_model.js", patch_model_source, True),
               ("panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js", patch_controller_source, True),
               ("panorama/src/scripts/custom_game/black_lion_market.js", patch_market_source, True)]
    records = []
    for relative, transform, excluded in targets:
        source, output = source_root / relative, directory / Path(relative).name
        if source.resolve() == output.resolve():
            raise ValueError("Candidate source is read-only: " + relative)
        original = source.read_bytes()
        updated = transform(original)
        if transform(updated) != updated:
            raise ValueError("Non-repeatable candidate transform: " + relative)
        records.append({"path": relative, "source": str(source), "candidate": str(output),
                        "source_sha256": sha(original), "candidate_sha256": sha(updated),
                        "excluded_from_commit": excluded, "idempotent": True,
                        "original": original, "updated": updated})
    directory.mkdir(parents=True, exist_ok=True)
    for record in records:
        output = Path(record["candidate"])
        output.write_bytes(record.pop("updated"))
        output.with_suffix(output.suffix + ".original").write_bytes(record.pop("original"))
    (directory / "sources.json").write_bytes((json.dumps({"files": records}, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--print-block", action="store_true")
    parser.add_argument("--model-source", type=Path)
    parser.add_argument("--model-output", type=Path)
    parser.add_argument("--expect-model-sha")
    parser.add_argument("--components-source", type=Path)
    parser.add_argument("--components-output", type=Path)
    parser.add_argument("--expect-components-sha")
    parser.add_argument("--candidate-source-root", type=Path)
    parser.add_argument("--candidate-dir", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    if args.model_source or args.model_output:
        if not args.model_source or not args.model_output or args.print_block:
            parser.error("Model integration requires --model-source and --model-output")
        source, output = args.model_source.resolve(), args.model_output.resolve()
        if source == output:
            parser.error("Model source is read-only; choose a separate candidate output")
        original = source.read_bytes()
        if args.expect_model_sha and sha(original) != args.expect_model_sha:
            raise ValueError("Concurrent model change; source SHA256 differs")
        updated = patch_model_source(original)
        if args.check:
            if not output.exists() or output.read_bytes() != updated:
                raise ValueError("Market model candidate is stale")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(updated)
        print(json.dumps({"result": "SHOP_HOME_MODEL_CANDIDATE_PASS", "source_sha256": sha(original),
                          "candidate_sha256": sha(updated)}))
        return
    if args.components_source and not args.components_output:
        parser.error("A custom components source requires a separate --components-output")
    manifest_path = args.manifest or root / MANIFEST
    if not manifest_path.is_absolute():
        manifest_path = root / manifest_path
    blob = manifest_path.read_bytes()
    block = generated_block(blob, known_products(root))
    if args.candidate_source_root or args.candidate_dir:
        if not args.candidate_source_root or not args.candidate_dir or args.print_block or args.check:
            parser.error("Candidate preparation requires --candidate-source-root and --candidate-dir")
        records = prepare_candidates(args.candidate_source_root, args.candidate_dir, block)
        print(json.dumps({"result": "SHOP_HOME_INTEGRATION_CANDIDATES_PASS", "files": records}))
        return
    if args.print_block:
        print(block)
        return
    source = (args.components_source or root / SCRIPT).resolve()
    output = (args.components_output or source).resolve()
    if args.components_source and source == output:
        parser.error("Custom components source is read-only; choose a separate output")
    original = source.read_bytes()
    if args.expect_components_sha and sha(original) != args.expect_components_sha:
        raise ValueError("Concurrent components change; source SHA256 differs")
    updated = patch_components_source(original, block)
    if args.check:
        if not output.exists() or output.read_bytes() != updated:
            raise ValueError("Generated shop-home catalog is stale")
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(updated)
    print(json.dumps({"result": "SHOP_HOME_CATALOG_CHECK_PASS" if args.check else "SHOP_HOME_CATALOG_GENERATED",
                      "home_count": len(read_manifest(blob, known_products(root))["entries"]),
                      "manifest_sha256": sha(blob), "components_source_sha256": sha(original),
                      "components_sha256": sha(updated)}))


if __name__ == "__main__":
    main()
