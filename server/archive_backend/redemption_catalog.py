"""Compile redeemable shop offers, retaining existing ownership identities."""
from __future__ import annotations

import copy
from .commerce_catalog import build_catalog
from payment_backend.csv_catalog import build as cash_catalog


def vip_related(product):
    grants = product.get("grants", {})
    return ("vip" in product["sku"].lower() or product.get("category_id") == "vip"
            or bool(grants.get("required_vip_level")) or bool(grants.get("vip_claims"))
            or bool(grants.get("vip_claim_effects"))
            or any("vip" in identity.lower() for identity in grants.get("entitlements", []))
            or any("vip" in identity.lower() for identity in grants.get("items", {}))
            or any("vip" in field.lower() for field in product.get("effects", {}))
            or any(row.get("kind") == "vip_reward" for row in grants.get("lines", [])))


def offers(root):
    products = {p["sku"]: p for p in cash_catalog(root)["catalog"]["products"]}
    products.update({p["sku"]: p for p in build_catalog(root)["products"]})
    accepted, excluded = {}, []
    for sku, product in sorted(products.items()):
        reason = ("VIP相关内容" if vip_related(product) else
                  "商品尚未开放或奖励尚未实现" if not product["enabled"] and
                  not (product.get("currency") == "shop_gold" and product.get("effects")) else "")
        if reason:
            excluded.append({"sku": sku, "title": product["title"], "reason": reason})
        else:
            accepted[sku] = product
    return accepted, excluded


def reward_spec(catalog, skus):
    if not isinstance(skus, list) or not skus or len(skus) > 256 or len(set(skus)) != len(skus):
        raise ValueError("redeem_product_list_invalid")
    leaves, markers, wallet, entitlements, seen = {}, set(), {}, {}, set()

    def walk(sku, stack=()):
        if sku in stack or sku not in catalog:
            raise ValueError("redeem_product_not_allowed:" + str(sku))
        p = catalog[sku]
        if vip_related(p):
            raise ValueError("redeem_vip_forbidden")
        grants = p["grants"]
        if p["product_type"] == "bundle":
            components = grants.get("components")
            if not components:
                raise ValueError("redeem_bundle_not_implemented")
            markers.add(p["item_id"])
            for component in components:
                if component["quantity"] != 1:
                    raise ValueError("redeem_bundle_quantity_invalid")
                walk(component["sku"], (*stack, sku))
            return
        if sku in seen:
            return
        seen.add(sku)
        if p.get("recharge_u_coin_per_unit"):
            wallet["u_coin"] = max(wallet.get("u_coin", 0), p["recharge_u_coin_per_unit"])
            markers.add(p["item_id"])
            return
        if grants.get("entitlements"):
            if grants["entitlements"] != ["archive_pass"]:
                raise ValueError("redeem_entitlement_not_allowed")
            days = grants.get("entitlement_days", {}).get("archive_pass")
            if type(days) is not int or not 1 <= days <= 365:
                raise ValueError("redeem_entitlement_duration_invalid")
            entitlements["archive_pass"] = max(entitlements.get("archive_pass", 0), days)
            markers.add(p["item_id"])
            return
        product = copy.deepcopy(p)
        product.update(price=0, currency="u_coin", enabled=True, purchase_method="redemption")
        product.setdefault("ownership_quantity", 1)
        product.setdefault("purchase_limit", 0)
        # Several shop SKUs sell the same single consumable ticket.
        identity = ("item:" + next(iter(grants["items"])) if not p.get("effects")
                    and len(grants.get("items", {})) == 1 else "product:" + p["item_id"])
        leaves.setdefault(identity, product)

    for sku in skus:
        walk(sku)
    return {"products": sorted(leaves.values(), key=lambda p: p["sku"]),
            "markers": sorted(markers), "wallet": wallet, "entitlements": entitlements}
