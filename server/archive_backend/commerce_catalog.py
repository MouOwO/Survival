"""Validate exchange products against the same capabilities as paid rewards."""
import csv
import io
from pathlib import Path
from payment_backend.csv_catalog import SOURCES, compile_catalog, rows, number

CURRENCIES = {'u_coin': 'U币', 'shop_points': '积分', 'shop_gold': '金币'}

def csv_text(records):
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=list(records[0]))
    writer.writeheader(); writer.writerows(records)
    return out.getvalue()

def build_catalog(root):
    base = Path(root) / 'data/csv'
    directory = base / '商城兑换系统'
    products = rows((directory / 'commerce_products.csv').read_text(encoding='utf-8-sig'))
    rewards = (directory / 'commerce_rewards.csv').read_text(encoding='utf-8-sig')
    if any(r['reward_type'] not in ('stat', 'item') for r in rows(rewards)):
        raise ValueError('commerce_reward_type_unsupported')
    converted = []
    for p in products:
        if p['currency'] not in CURRENCIES:
            raise ValueError('unsupported_commerce_currency:' + p['sku'])
        number(p['price'], True, 1, 100000000)
        expected = p['source_original_price'] or p['source_current_price']
        if number(p['price'], True) != number(expected, True):
            raise ValueError('commerce_reference_price_mismatch:' + p['sku'])
        converted.append({k: p[k] for k in ('sku', 'display_name', 'category_id', 'product_type',
            'purchase_limit', 'enabled', 'sort_order', 'icon', 'description', 'ownership_id')})
        # Only reuse reward validation. This value is never published as a cash price.
        converted[-1]['price_yuan'] = '1.00'
        if p['source_id'] == 'P103':
            if p['ownership_id'] != 'lottery_ember_of_legacy' or number(p['purchase_limit'], True) != 0:
                raise ValueError('commerce_ember_ownership_invalid')
            converted[-1]['ownership_id'] += '_single'
        if not (Path(root) / 'panorama/src/images' / p['icon']).is_file():
            raise ValueError('commerce_icon_missing:' + p['sku'])
    catalog = compile_catalog({
        'payment_categories': (base / '商城支付系统/payment_categories.csv').read_text(encoding='utf-8-sig'),
        'payment_products': csv_text(converted), 'payment_rewards': rewards,
    }, {name: (base / name).read_text(encoding='utf-8-sig') for name in SOURCES}, max_products=200)
    originals = {p['sku']: p for p in products}
    for p in catalog['products']:
        row = originals[p['sku']]
        p['item_id'] = row['ownership_id']
        del p['amount']
        p.update(currency=row['currency'], currency_name=CURRENCIES[row['currency']],
                 price=number(row['price'], True), source_id=row['source_id'], purchase_method='wallet')
        p['ownership_quantity'] = number(row.get('ownership_quantity') or 1, True, 1, 100)
    return catalog
