"""Compile U-coin item prices into exact server-owned RMB payment products."""
import csv
from decimal import Decimal
import io

from .csv_catalog import compile_catalog, indexed, number, rows

U_COIN_PER_YUAN = 1000
COMMERCE_TABLES = ('commerce_products', 'commerce_rewards')
COMMERCE_SOURCES = tuple('商城兑换系统/' + name + '.csv' for name in COMMERCE_TABLES)
COMMERCE_CURRENCIES = {'u_coin', 'shop_points', 'shop_gold'}
PRODUCT_FIELDS = ('sku', 'display_name', 'category_id', 'product_type', 'price_yuan',
                  'purchase_limit', 'enabled', 'sort_order', 'icon', 'description', 'ownership_id')
REWARD_FIELDS = ('reward_id', 'sku', 'reward_type', 'target_id', 'amount', 'display_name', 'enabled', 'duration_days')


def ucoin_amount_fen(price):
    """Reject rounding: 1 RMB fen buys exactly 10 U-coins."""
    price = number(price, True, 1, 100000000)
    return number(Decimal(price) * 100 / U_COIN_PER_YUAN, True, 1, 1000000)


def csv_text(records, fields):
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=fields)
    writer.writeheader()
    writer.writerows({key: row.get(key,'') for key in fields} for row in records)
    return output.getvalue()


def compile_payment_catalog(tables, commerce_tables, reference, *, max_products=100):
    """Merge legacy cash products with only the catalog's U-coin products.

    Both channels use the original ownership marker, limit and complete rewards.
    The existing compiler validates the merged IDs and every reward capability.
    """
    if set(commerce_tables) != set(COMMERCE_TABLES):
        raise ValueError('commerce_tables_invalid')
    products = indexed(rows(commerce_tables['commerce_products']), 'sku')
    rewards = indexed(rows(commerce_tables['commerce_rewards']), 'reward_id')
    for reward in rewards.values():
        if reward['sku'] not in products:
            raise ValueError('commerce_reward_product_missing:' + reward['sku'])
    converted = []
    metadata = {}
    for sku, product in products.items():
        if product['currency'] not in COMMERCE_CURRENCIES:
            raise ValueError('unsupported_commerce_currency:' + sku)
        if product['currency'] != 'u_coin':
            continue
        price = number(product['price'], True, 1, 100000000)
        expected = product['source_original_price'] or product['source_current_price']
        if price != number(expected, True, 1, 100000000):
            raise ValueError('commerce_reference_price_mismatch:' + sku)
        amount = ucoin_amount_fen(price)
        # The existing verified payment delivery grants one ownership marker.
        if number(product.get('ownership_quantity') or 1, True, 1, 100) != 1:
            raise ValueError('ucoin_ownership_quantity_unsupported:' + sku)
        converted.append({key: product[key] for key in PRODUCT_FIELDS if key != 'price_yuan'})
        converted[-1]['price_yuan'] = format(Decimal(amount) / 100, '.2f')
        metadata[sku] = {'u_coin_price': price, 'u_coin_per_yuan': U_COIN_PER_YUAN,
                         'exchange_rate': U_COIN_PER_YUAN}
    selected_rewards = []
    for reward in rewards.values():
        if reward['sku'] not in metadata:
            continue
        if reward['reward_type'] not in ('stat', 'item'):
            raise ValueError('commerce_reward_type_unsupported:' + reward['sku'])
        selected_rewards.append(reward)
    merged = {
        'payment_categories': tables['payment_categories'],
        'payment_products': csv_text(rows(tables['payment_products']) + converted, PRODUCT_FIELDS),
        'payment_rewards': csv_text(rows(tables['payment_rewards']) + selected_rewards, REWARD_FIELDS),
    }
    catalog = compile_catalog(merged, reference, max_products=max_products)
    catalog['u_coin_per_yuan'] = U_COIN_PER_YUAN
    catalog['exchange_rate'] = U_COIN_PER_YUAN
    for product in catalog['products']:
        if product['sku'] in metadata:
            product.update(metadata[product['sku']])
            # The existing JSON grants column persists the authoritative pricing
            # metadata into catalogs and immutable order reward snapshots.
            product['grants']['pricing'] = {
                'u_coin_price': product['u_coin_price'], 'u_coin_per_yuan': U_COIN_PER_YUAN,
            }
    return catalog
