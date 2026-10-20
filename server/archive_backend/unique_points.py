"""Pure preview of the unique lottery inventory repair; never changes stats."""
from __future__ import annotations
import copy
import math
import re

MAX_INTEGER = 9007199254740991
MIGRATION = '20261018_unique_lottery_points_v1'

# One reviewed daily-only update with identical lottery rules and reducer.
IDENTICAL_LOTTERY_UPDATE = ('0328f6ba83a13d309b8b6df84524814cf10ed5287c019282e35e286161d27bac', 'ccc088836ff79f635a002095958f6bcd43f45361e71037c26bfe5054b42f1348')


def legacy_lottery_error(current_hash, recorded_hash, kind):
    # Called only after a completed receipt has already been returned unchanged.
    # An old reducer may reapply effects or credit the obsolete loyalty wallet;
    # postprocessing that result cannot safely undo its unledgered effects.
    if kind in ('lottery_draw', 'lottery_exchange') and (current_hash, recorded_hash) == IDENTICAL_LOTTERY_UPDATE:
        return None
    if recorded_hash != current_hash and kind in ('lottery_draw', 'lottery_exchange'):
        return 'lottery_config_refresh_required'
    return None


def limit_snapshot_ownership(projected, bundle):
    """Clamp only public lottery snapshots, never saved inventories or receipts."""
    items, aliases = catalog(bundle)
    for snapshot in projected.get('snapshots', []):
        for item in snapshot.get('items', []):
            if aliases.get(item.get('id'), item.get('id')) not in items:
                continue
            try:
                count = min(1, integer(item.get('owned_count', 0)))
            except ValueError:
                count = 0
            item.update(owned_count=count, max_owned=1, owned=count > 0, at_max_owned=count == 1)
    return projected


def integer(value):
    if isinstance(value, str) and re.fullmatch(r'[0-9]+', value):
        value = int(value)
    if (isinstance(value, bool) or not isinstance(value, (int, float))
            or not math.isfinite(value) or value != int(value)
            or not 0 <= value <= MAX_INTEGER):
        raise ValueError('lottery_unique_inventory_invalid')
    return int(value)


def catalog(bundle):
    rows = [r for r in bundle.configs['lottery_item_definitions']['rows']
            if r.get('enabled') is not False and r.get('item_type') == '积分道具']
    if not rows or any(r.get('max_owned') != 1 for r in rows):
        raise ValueError('lottery_unique_catalog_invalid')
    source = (bundle.directory / 'config/content_id_aliases.lua').read_text('utf-8')
    literal = re.search(r'local aliases\s*=\s*\{(.*?)\n\}', source, re.S)
    if not literal:
        raise ValueError('lottery_unique_aliases_missing')
    aliases = dict(re.findall(r'^\s*([A-Za-z0-9_]+)\s*=\s*"([A-Za-z0-9_]+)"\s*,?\s*$',
                              literal.group(1), re.M))
    items = {r['item_id']: integer(r.get('duplicate_points', 0)) for r in rows}
    if len(items) != len(rows):
        raise ValueError('lottery_unique_catalog_duplicate')
    return items, aliases


def preview(inventory, archive, items, aliases):
    """Canonicalize only unique lottery IDs; compensate extra copies once.

    The resulting saved count itself makes retries idempotent. Historical
    permanent stats and loyalty rewards have no trustworthy per-copy ledger,
    so this repair deliberately neither reapplies nor subtracts them.
    """
    if not isinstance(inventory, dict) or not isinstance(archive, dict):
        raise ValueError('lottery_unique_state_invalid')
    result, saved = copy.deepcopy(inventory), copy.deepcopy(archive)
    details = []
    converted = 0
    for item_id, rate in sorted(items.items()):
        keys = [key for key in result if aliases.get(key, key) == item_id]
        if not keys:
            continue
        total = sum(integer(result[key]) for key in keys)
        if total > MAX_INTEGER:
            raise ValueError('lottery_unique_inventory_limit')
        count = 1 if total else 0
        amount = max(0, total - 1) * integer(rate)
        converted += amount
        if converted > MAX_INTEGER:
            raise ValueError('commerce_wallet_limit')
        if keys != [item_id] or isinstance(result.get(item_id), str) or result[item_id] != count:
            details.append({'id': item_id, 'previous_count': total, 'extra_copies': max(0, total-1), 'count': count,
                            'converted_points': amount, 'previous_keys': sorted(keys)})
            for key in keys:
                del result[key]
            result[item_id] = count
    if converted:
        commerce = saved.setdefault('commerce', {})
        if not isinstance(commerce, dict):
            raise ValueError('commerce_wallet_invalid')
        balances = commerce.setdefault('balances', {})
        if not isinstance(balances, dict):
            raise ValueError('commerce_wallet_invalid')
        old = balances.get('shop_points', 0)
        if isinstance(old, str):
            raise ValueError('commerce_wallet_invalid')
        old = integer(old)
        if old + converted > MAX_INTEGER:
            raise ValueError('commerce_wallet_limit')
        balances['shop_points'] = old + converted
    return {'content_inventory': result, 'archive': saved, 'details': details,
            'changed_items': len(details), 'converted_points': converted,
            'converted_currency': 'shop_points'}
