"""Exercise future VIP payment archive credits using rolled-back SQL fixtures.

No gateway is contacted and no payment/profile fixture survives this function.
Gateway signature checks remain in the existing payment API test suite.
"""
from __future__ import annotations

import hashlib
import json
import re
import uuid


class _RollbackFixtures(Exception):
    pass


def verify(connection, archive_migration_sql, payment_migration_sql, bundle_data):
    from psycopg.types.json import Jsonb

    checks = []
    nonce = uuid.uuid4().hex
    account = hashlib.sha256(("vip-recharge-fixture:" + nonce).encode()).hexdigest()
    test_account = hashlib.sha256(("vip-test-fixture:" + nonce).encode()).hexdigest()
    sku = "archive_vip_fixture_" + nonce
    marker = "archive_vip_fixture_item_" + nonce

    def check(condition, label):
        if not condition:
            raise AssertionError(label)
        checks.append(label)

    def apply(source):
        inner = re.sub(r"(?im)^begin;\s*", "", source, count=1)
        inner = re.sub(r"(?im)^commit;\s*$", "", inner, count=1)
        check(not re.search(r"(?im)^commit;", inner), "migration_outer_commit_removed")
        connection.execute(inner)

    def stats(who=account):
        return connection.execute(
            "SELECT vip_recharge_total_fen,vip_level,shop_paid_currency FROM public.player_gameplay_stats WHERE player_id=%s",
            (who,)).fetchone()

    def close(order):
        connection.execute("UPDATE payments.orders SET state='closed' WHERE order_id=%s", (order,))

    def create_order(amount, who=account, provider="wechat"):
        identity = connection.execute("SELECT appid,mchid FROM payments.providers WHERE provider=%s", (provider,)).fetchone()
        check(identity is not None, provider + "_fixture_provider_present")
        order = ("WX" if provider == "wechat" else "AL") + uuid.uuid4().hex[:30]
        transaction = "9" + str(uuid.uuid4().int)
        reward = {"version": 4, "item_id": marker, "purchase_limit": 0, "effects": {},
                  "grants": {"items": {}, "item_limits": {}, "entitlements": [], "lines": []}}
        connection.execute(
            "INSERT INTO payments.orders(order_id,account_id,sku,amount,reward,state,provider,appid,mchid) VALUES(%s,%s,%s,%s,%s,'pending',%s,%s,%s)",
            (order, who, sku, amount, Jsonb(reward), provider, *identity))
        return order, transaction, amount, *identity

    def deliver(receipt):
        return connection.execute("SELECT payments.deliver(%s,%s,%s,%s,%s)", receipt).fetchone()[0]

    def denied(label, receipt):
        try:
            with connection.transaction():
                deliver(receipt)
        except Exception as exc:
            check("payment_mismatch" in str(exc), label)
        else:
            raise AssertionError(label + ": accepted")

    try:
        with connection.transaction():
            original_deliver = connection.execute(
                "SELECT pg_get_functiondef('payments.deliver(text,text,integer,text,text)'::regprocedure)").fetchone()[0]
            original_reset = connection.execute(
                "SELECT pg_get_functiondef('payments.finish_reset(text,text,text,text)'::regprocedure)").fetchone()[0]
            apply(archive_migration_sql)
            defaults = {row["field_id"]: row["default_value"]
                        for row in bundle_data["configs"]["player_gameplay_stats"]["rows"]}
            for who in (account, test_account):
                connection.execute("SELECT public.ensure_player_gameplay_stats(%s,%s)", (who, Jsonb(defaults)))
            connection.execute(
                "INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,grants,category_id,product_type,icon,purchase_limit) VALUES(%s,%s,'isolated archive test','rolled back',1,'{}',false,0,%s,'fixture','item','fixture',0)",
                (sku, marker, Jsonb({"items": {}, "item_limits": {}, "entitlements": [], "lines": []})))

            historical = create_order(100)
            connection.execute(
                "UPDATE payments.orders SET state='delivered',transaction_id=%s,paid_at=now(),granted_at=now() WHERE order_id=%s",
                (historical[1], historical[0]))
            apply(payment_migration_sql)
            check(stats() == (0, 0, 0), "historical_deliveries_not_backfilled")
            connection.execute("UPDATE payments.orders SET state='delivered' WHERE order_id=%s", (historical[0],))
            check(stats() == (0, 0, 0), "historical_receipt_replay_not_backfilled")
            expected = sorted((row["level"], row["required_recharge_fen"])
                              for row in bundle_data["configs"]["archive_vip_levels"]["rows"])
            actual = connection.execute("SELECT level,required_fen FROM payments.vip_recharge_levels ORDER BY level").fetchall()
            check(actual == expected, "vip_thresholds_match_game_bundle")
            check(connection.execute("SELECT pg_get_functiondef('payments.deliver(text,text,integer,text,text)'::regprocedure)").fetchone()[0] == original_deliver,
                  "gateway_delivery_function_unchanged")
            check(connection.execute("SELECT pg_get_functiondef('payments.finish_reset(text,text,text,text)'::regprocedure)").fetchone()[0] == original_reset,
                  "test_reset_function_unchanged")

            pending = create_order(100)
            check(stats() == (0, 0, 0), "pending_not_credited")
            denied("amount_mismatch_not_credited", (pending[0], pending[1], 101, pending[3], pending[4]))
            denied("merchant_mismatch_not_credited", (pending[0], pending[1], pending[2], "invalid-app", pending[4]))
            denied("invalid_transaction_not_credited", (pending[0], "fake", *pending[2:]))
            check(stats() == (0, 0, 0), "invalid_receipts_preserve_vip_stats")
            close(pending[0])

            fake = create_order(100)
            connection.execute("UPDATE payments.orders SET state='delivered',transaction_id=%s WHERE order_id=%s",
                               (fake[1], fake[0]))
            check(stats() == (0, 0, 0), "state_only_fake_receipt_not_credited")
            review = create_order(100)
            connection.execute("UPDATE payments.orders SET state='paid_review',transaction_id=%s,paid_at=now() WHERE order_id=%s",
                               (review[1], review[0]))
            check(deliver(review)["state"] == "paid_review" and stats() == (0, 0, 0), "review_hold_not_credited")
            close(review[0])
            cleared = create_order(100)
            connection.execute("UPDATE payments.orders SET cleared_at=now() WHERE order_id=%s", (cleared[0],))
            check(deliver(cleared)["state"] == "delivered" and stats() == (0, 0, 0), "cleared_delivery_not_credited")

            connection.execute("UPDATE payments.test_settings SET enabled=true WHERE singleton")
            connection.execute("INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)", (test_account,))
            test_receipt = create_order(100, test_account)
            check(deliver(test_receipt)["state"] == "delivered" and stats(test_account) == (0, 0, 0),
                  "enabled_test_account_delivery_not_credited")

            last_receipt = None
            for level, threshold in expected:
                remaining = threshold - 1 - stats()[0]
                if remaining > 0:
                    check(deliver(create_order(remaining))["state"] == "delivered", "tier_" + str(level) + "_delivery_before_boundary")
                check(stats()[:2] == (threshold - 1, level - 1), "tier_" + str(level) + "_not_early")
                last_receipt = create_order(1)
                first = deliver(last_receipt)
                check(first["state"] == "delivered" and stats()[:2] == (threshold, level),
                      "tier_" + str(level) + "_credited_at_boundary")
                before = stats()
                deliver(last_receipt)
                check(stats() == before, "tier_" + str(level) + "_receipt_idempotent")
            check(stats()[2] == 0, "recharge_does_not_mint_paid_wallet_currency")
            check(connection.execute("SELECT active AND expires_at IS NULL FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='vip'", (account,)).fetchone()[0],
                  "verified_delivery_activates_vip_membership")
            check(connection.execute("SELECT count(*) FROM payments.vip_recharge_credits WHERE account_id=%s", (test_account,)).fetchone()[0] == 0,
                  "test_account_has_no_credit_ledger")

            if connection.execute("SELECT 1 FROM payments.providers WHERE provider='alipay'").fetchone():
                same_transaction = last_receipt[1]
                second_channel = create_order(1, provider="alipay")
                second_channel = (second_channel[0], same_transaction, *second_channel[2:])
                check(deliver(second_channel)["state"] == "delivered" and stats()[0] == expected[-1][1] + 1,
                      "cross_gateway_transaction_identifiers_are_distinct")
            for role in ("goufayu_app", "goufayu_payment", "anon", "authenticated"):
                check(not connection.execute("SELECT has_table_privilege(%s,'payments.vip_recharge_credits','INSERT,UPDATE,DELETE')", (role,)).fetchone()[0],
                      role + "_cannot_edit_credit_ledger")
            raise _RollbackFixtures()
    except _RollbackFixtures:
        pass
    check(connection.execute("SELECT count(*) FROM public.survival_players WHERE account_id IN (%s,%s)", (account, test_account)).fetchone()[0] == 0,
          "both_fixture_accounts_rolled_back")
    check(connection.execute("SELECT count(*) FROM payments.products WHERE sku=%s", (sku,)).fetchone()[0] == 0,
          "fixture_product_rolled_back")
    return {"ok": True, "checks": checks, "check_count": len(checks),
            "database_changes_committed": False, "real_gateway_contacted": False,
            "existing_payment_orders_modified": False}
