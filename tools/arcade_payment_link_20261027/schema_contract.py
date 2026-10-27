"""Compare stored payment function bodies with their exact reviewed SQL sources."""
from __future__ import annotations

import hashlib
from pathlib import Path
import re

DECLARATION = re.compile(r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+payments\.([a-z_]+)\s*\((.*?)\)\s*RETURNS\s+(.*?)\s+LANGUAGE\s+(sql|plpgsql)\s+(.*?)\s+AS\s+(\$[a-z_]*\$)(.*?)\6\s*;", re.I | re.S)
FINAL_SOURCES = {
    "apply_effects": ("upgrade_starjoy_progress.sql", "apply_effects"),
    "begin_reset": ("upgrade_test_shop.sql", "begin_reset"),
    "catalog": ("upgrade_ucoin_recharge.sql", "catalog"),
    "catalog_pre_quantity": ("upgrade_commerce_bundles.sql", "catalog"),
    "catalog_pre_recharge": ("upgrade_ucoin_rate_100.sql", "catalog_pre_recharge"),
    "commerce_bundle_effects": ("upgrade_commerce_bundles.sql", "commerce_bundle_effects"),
    "create_order": ("upgrade_order_quantity.sql", "create_order"),
    "create_order_channel": ("upgrade_order_quantity.sql", "create_order_channel"),
    "create_order_quantity": ("upgrade_ucoin_rate_100.sql", "create_order_quantity"),
    "create_order_quantity_pre_recharge": ("upgrade_order_quantity.sql", "create_order_quantity"),
    "credit_vip_recharge": ("upgrade_vip_recharge.sql", "credit_vip_recharge"),
    "deliver": ("upgrade_ucoin_recharge.sql", "deliver"),
    "deliver_pre_recharge": ("upgrade_commerce_bundles.sql", "deliver"),
    "deliver_v3": ("upgrade_stat_shop.sql", "deliver"),
    "entitlement_days": ("upgrade_monthly_pass.sql", "entitlement_days"),
    "finish_reset": ("upgrade_ucoin_recharge.sql", "finish_reset"),
    "finish_reset_pre_commerce_bundles": ("upgrade_csv_shop.sql", "finish_reset"),
    "finish_reset_pre_recharge": ("upgrade_commerce_bundles.sql", "finish_reset"),
    "finish_reset_v3": ("upgrade_test_shop.sql", "finish_reset"),
    "get_order": ("schema.sql", "get_order"),
    "is_test_account": ("upgrade_test_shop.sql", "is_test_account"),
    "max_order_quantity": ("upgrade_order_quantity.sql", "max_order_quantity"),
    "pending": ("schema.sql", "pending"),
    "product_block": ("upgrade_order_quantity.sql", "product_block"),
    "product_block_pre_quantity": ("upgrade_commerce_bundles.sql", "product_block"),
    "product_block_quantity": ("upgrade_order_quantity.sql", "product_block_quantity"),
    "purchased_units": ("upgrade_order_quantity.sql", "purchased_units"),
    "receipt_quantity": ("upgrade_ucoin_recharge.sql", "receipt_quantity"),
    "receipt_quantity_pre_recharge": ("upgrade_order_quantity.sql", "receipt_quantity"),
    "recharge_wallet_balance": ("upgrade_ucoin_recharge.sql", "recharge_wallet_balance"),
    "scale_order_quantity": ("upgrade_ucoin_rate_100.sql", "scale_order_quantity"),
    "update_gateway": ("upgrade_alipay_qr.sql", "update_gateway"),
    "validate_commerce_bundle": ("upgrade_commerce_bundles.sql", "validate_commerce_bundle"),
    "validate_order_quantity_snapshot": ("upgrade_ucoin_rate_100.sql", "validate_order_quantity_snapshot"),
    "validate_order_quantity_snapshot_pre_recharge": ("upgrade_ucoin_rate_100.sql", "validate_order_quantity_snapshot_pre_recharge"),
}


def body_hash(value):
    return hashlib.sha256(value.replace("\r\n", "\n").strip().encode()).hexdigest()


def compile_contract(directory):
    result = {}
    for target, (filename, source_name) in FINAL_SOURCES.items():
        text = (Path(directory) / filename).read_text(encoding="utf-8-sig")
        declarations = [match for match in DECLARATION.finditer(text) if match[1].lower() == source_name]
        if len(declarations) != 1:
            raise ValueError("payment_sql_function_declaration_ambiguous:" + target)
        match = declarations[0]
        args = []
        for argument in match[2].split(",") if match[2].strip() else []:
            tokens = re.split(r"\s+", argument.strip().lower())
            if len(tokens) < 2 or tokens[1] not in ("text", "jsonb", "integer", "boolean"):
                raise ValueError("payment_sql_function_argument_unreviewed:" + target)
            args.append(tokens[1])
        modifiers = re.sub(r"\s+", "", match[5].lower())
        if modifiers != "securitydefinersetsearch_path=pg_catalog,public,pg_temp":
            raise ValueError("payment_sql_function_security_unreviewed:" + target)
        body = match[7]
        if target == "deliver_pre_recharge":
            # This migration deliberately patches the existing delivery body
            # instead of reauthoring it. Reproduce only its three exact edits.
            edits = (
                ("payments.product_block(a,o.reward->>'item_id',(o.reward->>'purchase_limit')::integer,o.reward->'grants',o.reward->'effects')",
                 "payments.product_block_quantity(a,o.reward->>'item_id',(o.reward->>'purchase_limit')::integer,o.reward->'grants',o.reward->'effects',payments.receipt_quantity(o.reward))"),
                ("jsonb_build_object(item,1)", "jsonb_build_object(item,payments.receipt_quantity(o.reward))"),
                ("SELECT * INTO o FROM payments.orders WHERE order_id=p_order FOR UPDATE;",
                 "SELECT * INTO o FROM payments.orders WHERE order_id=p_order FOR UPDATE;\n PERFORM payments.validate_order_quantity_snapshot(o.reward,o.amount);"),
            )
            quantity_source = (Path(directory) / "upgrade_order_quantity.sql").read_text(encoding="utf-8-sig")
            if "definition:=replace(replace(replace(definition,old_guard,new_guard),old_marker,new_marker),locked_select,snapshot_check)" not in quantity_source:
                raise ValueError("payment_delivery_patch_source_changed")
            for old, new in edits:
                if body.count(old) != 1:
                    raise ValueError("payment_delivery_patch_target_changed")
                body = body.replace(old, new)
        result[target] = {"arguments": ", ".join(args), "returns": match[3].strip().lower(),
                          "language": match[4].lower(), "body_sha256": body_hash(body),
                          "security_definer": True, "owner": "goufayu_owner",
                          "search_path": ["search_path=pg_catalog, public, pg_temp"],
                          "source": filename, "source_function": source_name}
    if len(result) != 35:
        raise ValueError("payment_sql_function_contract_incomplete")
    return result
