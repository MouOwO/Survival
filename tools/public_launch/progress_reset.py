"""Maintenance-only progression reset preserving balances and paid ownership.

No commit, service, file, HTTP or database connection occurs here. The caller
must stop writers, verify a full backup and pass the exact preview fingerprint.
Payment orders/credits are preserved; ordinary rewards are reset independently.
"""
from __future__ import annotations
from collections import defaultdict
from copy import deepcopy
from decimal import Decimal
import hashlib
import json
import re

from account_cleanup import engine as account_engine

BALANCES = ('starjoy_points', 'starjoy_points_earned', 'shop_paid_currency')
PAID_VIP = ('vip_level', 'vip_recharge_total_fen')
KEEP = frozenset(('public.survival_players', 'public.archive_daily_unique_backups',
                  'public.archive_leaderboard_identities',
                  'payments.orders', 'payments.vip_recharge_credits',
                  'payments.test_accounts', 'payments.test_resets'))
MAX_ACCOUNTS = 5
MAX_ORDERS = 64


def need(value, code):
    if not value:
        raise ValueError(code)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True,
                      allow_nan=False, default=str).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def number(value):
    need(not isinstance(value, bool), 'boolean_is_not_a_balance')
    try:
        result = Decimal(str(value))
    except Exception:
        raise ValueError('finite_bounded_amount_required') from None
    need(result.is_finite() and 0 <= result <= 10**15, 'finite_bounded_amount_required')
    return result


def item_id(value):
    need(isinstance(value, str) and re.fullmatch(r'[a-z][a-z0-9_]{0,95}', value),
         'paid_item_identifier_invalid')
    return value


def preservation(rows, defaults):
    """Derive only retained balances, actual paid items and paid stat deltas."""
    state = (rows.get('public.player_archive_state') or [{}])[0]
    old_stats = (rows.get('public.player_gameplay_stats') or [{}])[0]
    archive = state.get('archive') or {}
    wallets = deepcopy(archive.get('commerce', {}).get('balances', {}))
    need(isinstance(wallets, dict) and len(wallets) <= 16, 'bounded_wallet_map_required')
    for key, value in wallets.items():
        item_id(key)
        number(value)
    retained = {key: str(number(old_stats.get(key, defaults.get(key, 0)))) for key in BALANCES}
    paid = [row for row in rows.get('payments.orders', []) if row.get('state') == 'delivered']
    need(len(paid) <= MAX_ORDERS, 'paid_order_review_budget_exceeded')
    inventory, effects, entitlement_ids, paid_archive = {}, defaultdict(Decimal), set(), {}
    for order in paid:
        need(order.get('sku') in ('video_p033', 'u_coin_recharge'),
             'new_paid_product_requires_launch_preservation_review')
        need(order.get('cleared_at') is None, 'cleared_paid_order_requires_separate_review')
        reward = order.get('reward')
        need(isinstance(reward, dict), 'paid_reward_snapshot_missing')
        items = deepcopy(order.get('applied_items') or {})
        need(isinstance(items, dict) and len(items) <= 128, 'paid_item_snapshot_invalid')
        if order.get('sku') != 'u_coin_recharge':
            marker = item_id(reward.get('item_id'))
            count = reward.get('quantity', 1)
            need(type(count) is int and 1 <= count <= 999999, 'paid_item_quantity_invalid')
            if marker not in items:
                items[marker] = count
            else:
                need(type(items[marker]) is int and items[marker] >= count,
                     'paid_marker_snapshot_inconsistent')
        for key, count in items.items():
            item_id(key)
            need(type(count) is int and 0 <= count <= 999999, 'paid_item_quantity_invalid')
            inventory[key] = inventory.get(key, 0) + count
        applied = order.get('applied_effects') or {}
        need(isinstance(applied, dict) and len(applied) <= 128, 'paid_effect_snapshot_invalid')
        for key, value in applied.items():
            need(key in defaults, 'paid_effect_not_in_current_defaults')
            if key not in (*BALANCES, *PAID_VIP):
                effects[key] += number(value)
        grants = order.get('applied_entitlements') or {}
        need(isinstance(grants, dict) and len(grants) <= 16, 'paid_entitlement_snapshot_invalid')
        entitlement_ids.update(item_id(key) for key in grants)
        changes = order.get('applied_archive') or {}
        need(isinstance(changes, dict), 'paid_archive_snapshot_invalid')
        if order.get('sku') != 'u_coin_recharge':
            # Existing monthly-pass deliveries retain their current claim state;
            # expiry/ownership comes from the original entitlement rows below.
            need(not changes or set(changes) <= {'vip_claimed', 'vip_claimed_before_present'},
                 'unknown_paid_archive_scope_requires_review')
            if changes:
                need(isinstance(archive.get('vip_claimed', {}), dict), 'paid_claim_state_invalid')
                paid_archive['vip_claimed'] = deepcopy(archive.get('vip_claimed', {}))
    funded = bool(paid or rows.get('payments.vip_recharge_credits'))
    if funded:
        retained.update({key: str(number(old_stats.get(key, defaults.get(key, 0)))) for key in PAID_VIP})
    entitlements = [deepcopy(row) for row in rows.get('public.archive_entitlements', [])
                    if row.get('entitlement_id') in entitlement_ids]
    need({row['entitlement_id'] for row in entitlements} == entitlement_ids,
         'paid_entitlement_current_state_missing')
    fresh_archive = {'version': 1, **paid_archive}
    if wallets:
        fresh_archive['commerce'] = {'balances': wallets}
    return dict(archive=fresh_archive, inventory=inventory,
                effects={key: str(value) for key, value in sorted(effects.items())},
                stats=retained, entitlements=entitlements, paid_orders=len(paid))


def progression_tables(contract):
    targets = set(account_engine.targets(contract)) - KEEP
    need(all(name.startswith('public.') or name == 'payments.cleared_reward_grants' for name in targets),
         'unreviewed_financial_table_in_reset_scope')
    # The old full-account tool clears all finance. This operator explicitly
    # keeps its financial targets and uses the same reviewed dependency order.
    ordered = [name for name in account_engine.delete_order(contract) if name in targets]
    need(set(ordered) == targets, 'progression_dependency_order_incomplete')
    return ordered


def preview(conn, accounts, contract, defaults):
    need(isinstance(accounts, (tuple, list)) and 1 <= len(accounts) <= MAX_ACCOUNTS
         and len(set(accounts)) == len(accounts)
         and all(re.fullmatch(r'[a-f0-9]{64}', value) for value in accounts),
         'exact_reviewed_database_accounts_required')
    need(isinstance(defaults, dict) and BALANCES[0] in defaults and 'wood_per_second' in defaults,
         'actual_api_gameplay_defaults_required')
    account_engine.validate_schema(conn, contract)
    ordered = progression_tables(contract)
    before, keep = {}, {}
    for account in sorted(accounts):
        snapshot, raw = account_engine.snapshot(conn, account, contract, keep_rows=True)
        need(snapshot['open_payment_orders'] == 0, 'open_payment_orders_block_launch_reset')
        rows = {name: [json.loads(value, parse_float=Decimal) for value in values]
                for name, values in raw.items()}
        before[account] = snapshot
        keep[account] = preservation(rows, defaults)
    value = dict(schema=1, kind='PRESERVE_PAID_PROGRESS_RESET_PLAN', accounts=sorted(accounts),
                 contract_sha256=digest(contract), defaults_sha256=digest(defaults),
                 before=before, preserve=keep, progression_tables=ordered)
    return {**value, 'fingerprint': digest(value)}


def apply_locked(conn, plan, contract, defaults):
    """No COMMIT: failures roll back every delete and trigger change together."""
    actual = preview(conn, plan['accounts'], contract, defaults)
    need(actual['fingerprint'] == plan['fingerprint'], 'launch_reset_preview_changed')
    enabled = conn.execute("SELECT tgenabled FROM pg_trigger WHERE tgrelid='public.reward_grants'::regclass "
                           "AND tgname='reward_grants_immutable' AND NOT tgisinternal").fetchone()
    need(enabled == ('O',), 'reward_grant_immutability_not_enabled')
    codes = {}
    for before in plan['before'].values():
        for code, reserved, mine, _ in before['code_counters']:
            if code in codes:
                need(codes[code][0] == reserved, 'code_counter_preview_inconsistent')
                codes[code][1] += mine
            else:
                codes[code] = [reserved, mine]
    for code, (reserved, mine) in codes.items():
        result = conn.execute('UPDATE public.redemption_codes SET reserved_count=reserved_count-%s '
                              'WHERE code_id=%s AND reserved_count=%s RETURNING reserved_count',
                              (mine, code, reserved)).fetchone()
        need(result == (reserved - mine,), 'code_counter_changed_before_reset')
    conn.execute('ALTER TABLE public.reward_grants DISABLE TRIGGER reward_grants_immutable')
    removed = {}
    owned = account_engine.scope(contract)
    for name in plan['progression_tables']:
        if name == 'payments.cleared_reward_grants':
            predicate = 'grant_id IN (SELECT grant_id FROM public.reward_grants WHERE account_id=ANY(%s))'
        else:
            predicate = account_engine.ident(owned[name]) + '=ANY(%s)'
        count = conn.execute('DELETE FROM ' + account_engine.table(name) + ' WHERE ' + predicate,
                             (plan['accounts'],)).rowcount
        expected = sum(value['tables'][name]['rows'] for value in plan['before'].values())
        need(count == expected, 'progression_delete_count_changed')
        removed[name] = count
    conn.execute('ALTER TABLE public.reward_grants ENABLE TRIGGER reward_grants_immutable')
    for account, kept in plan['preserve'].items():
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)',
                     (account, canonical(defaults).decode()))
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) '
                     'VALUES(%s,%s::jsonb,%s::jsonb)',
                     (account, canonical(kept['archive']).decode(), canonical(kept['inventory']).decode()))
        if kept['effects']:
            conn.execute('SELECT payments.apply_effects(%s,%s::jsonb)',
                         (account, canonical(kept['effects']).decode()))
        for key, value in kept['stats'].items():
            need(key in (*BALANCES, *PAID_VIP), 'unreviewed_retained_stat')
            conn.execute('UPDATE public.player_gameplay_stats SET ' + account_engine.ident(key)
                         + '=%s WHERE player_id=%s', (Decimal(value), account))
        for row in kept['entitlements']:
            conn.execute('INSERT INTO public.archive_entitlements(account_id,entitlement_id,active,starts_at,expires_at) '
                         'VALUES(%s,%s,%s,%s,%s)',
                         (account, row['entitlement_id'], row['active'], row['starts_at'], row['expires_at']))
        conn.execute('INSERT INTO public.player_onboarding_state(account_id) VALUES(%s)', (account,))
        conn.execute('UPDATE public.survival_players SET profile_revision=profile_revision+1, '
                     'updated_at=clock_timestamp() WHERE account_id=%s', (account,))
        conn.execute('UPDATE payments.test_accounts SET enabled=false,generation=generation+1, '
                     'reset_request=NULL,reset_kind=NULL WHERE account_id=%s', (account,))
    after = {}
    for account in plan['accounts']:
        summary, raw = account_engine.snapshot(conn, account, contract, keep_rows=True)
        after[account] = summary
        for name in ('payments.orders', 'payments.vip_recharge_credits', 'payments.test_resets',
                     'public.archive_leaderboard_identities',
                     'public.archive_daily_unique_backups'):
            need(summary['tables'][name] == plan['before'][account]['tables'][name],
                 'financial_history_or_recovery_backup_changed')
        kept = plan['preserve'][account]
        state = json.loads(raw['public.player_archive_state'][0])
        need(state['archive'] == kept['archive'] and state['content_inventory'] == kept['inventory'],
             'preserved_wallet_or_paid_inventory_mismatch')
        stats = json.loads(raw['public.player_gameplay_stats'][0], parse_float=Decimal)
        for key, default in defaults.items():
            expected = Decimal(kept['stats'][key]) if key in kept['stats'] else (
                Decimal(str(default)) + Decimal(kept['effects'].get(key, '0')))
            need(Decimal(str(stats[key])) == expected, 'fresh_default_or_paid_stat_mismatch:' + key)
        need(summary['tables']['public.archive_entitlements']['rows'] == len(kept['entitlements']),
             'paid_entitlement_count_mismatch')
        actual_entitlements = [json.loads(value) for value in raw['public.archive_entitlements']]
        need(sorted(actual_entitlements, key=lambda row: row['entitlement_id'])
             == sorted(kept['entitlements'], key=lambda row: row['entitlement_id']),
             'paid_entitlement_dates_or_state_changed')
        for name in plan['progression_tables']:
            if name not in ('public.player_archive_state', 'public.player_gameplay_stats',
                            'public.player_onboarding_state', 'public.archive_entitlements'):
                need(summary['tables'][name]['rows'] == 0, 'old_progression_rows_remain')
        need(summary['code_definitions_sha256'] == plan['before'][account]['code_definitions_sha256'],
             'redemption_definition_changed')
    return dict(kind='PROGRESSION_RESET_PAID_PRESERVED_IN_TRANSACTION',
                removed=removed, after=after, after_fingerprint=digest(after),
                orders_preserved=True, recharge_credits_preserved=True,
                paid_items_preserved=True, balances_preserved=True, committed=False)
