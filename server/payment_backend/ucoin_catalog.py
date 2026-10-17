"""Compile U-coin item prices into exact server-owned RMB payment products."""
import csv
from decimal import Decimal
import io

from .csv_catalog import compile_catalog, number
from .commerce_bundles import MEMBER_TABLE, compile_commerce
from . import ucoin_recharge
from .ucoin_pricing import U_COIN_PER_YUAN

COMMERCE_TABLES = ('commerce_products', 'commerce_rewards', MEMBER_TABLE)
COMMERCE_SOURCES = tuple('商城兑换系统/' + name + '.csv' for name in COMMERCE_TABLES)
COMMERCE_CURRENCIES = {'u_coin', 'shop_points', 'shop_gold'}
PRODUCT_FIELDS = ('sku', 'display_name', 'category_id', 'product_type', 'price_yuan',
                  'purchase_limit', 'enabled', 'sort_order', 'icon', 'description', 'ownership_id')
REWARD_FIELDS = ('reward_id', 'sku', 'reward_type', 'target_id', 'amount', 'display_name', 'enabled', 'duration_days')


def ucoin_amount_fen(price):
    """Reject rounding: one RMB fen corresponds to exactly one U-coin."""
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
    if not {'commerce_products','commerce_rewards'}<=set(commerce_tables) or set(commerce_tables)-set(COMMERCE_TABLES):
        raise ValueError('commerce_tables_invalid')
    commerce=compile_commerce(commerce_tables,reference,tables['payment_categories'])
    catalog=compile_catalog(tables,reference,max_products=max_products)
    ids={p['sku'] for p in catalog['products']};markers={p['item_id'] for p in catalog['products']}
    for product in commerce['products']:
        sku=product['sku']
        if product['currency'] != 'u_coin':
            continue
        if sku in ids or product['item_id'] in markers:raise ValueError('payment_commerce_identity_duplicate:'+sku)
        ids.add(sku);markers.add(product['item_id'])
        price=product['price']
        amount = ucoin_amount_fen(price)
        # The existing verified payment delivery grants one ownership marker.
        if number(product.get('ownership_quantity') or 1, True, 1, 100) != 1:
            raise ValueError('ucoin_ownership_quantity_unsupported:' + sku)
        # Wallet-only display keys never become payment authorities.
        paid={key:product[key] for key in ('sku','item_id','title','description','effects','enabled','sort_order','purchase_limit','category_id','product_type','icon','grants')}
        paid.update(amount=amount,u_coin_price=price,u_coin_per_yuan=U_COIN_PER_YUAN,exchange_rate=U_COIN_PER_YUAN)
        paid['grants']['pricing']={'u_coin_price':price,'u_coin_per_yuan':U_COIN_PER_YUAN}
        if 'original_price' in product:
            paid['original_u_coin_price']=product['original_price']
            paid['grants']['pricing']['original_u_coin_price']=product['original_price']
        catalog['products'].append(paid)
    if ucoin_recharge.SKU in ids or ucoin_recharge.ITEM_ID in markers:
        raise ValueError('payment_recharge_identity_duplicate')
    catalog['products'].append(ucoin_recharge.product())
    if len(catalog['products'])>max_products:raise ValueError('payment_products_limit')
    catalog['products'].sort(key=lambda p:p['sort_order'])
    catalog['u_coin_per_yuan'] = U_COIN_PER_YUAN
    catalog['exchange_rate'] = U_COIN_PER_YUAN
    return catalog
