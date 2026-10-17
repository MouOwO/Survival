"""Server-owned, repeatable wallet top-up. Ordinary item quotes stay unchanged."""
from copy import deepcopy
from .ucoin_pricing import U_COIN_PER_YUAN, snapshot_rate

SKU = 'u_coin_recharge'
ITEM_ID = 'u_coin_recharge_receipt'
UNIT_AMOUNT_FEN = 100
U_COIN_PER_UNIT = 100
MAX_QUANTITY = 999999
MAX_AMOUNT_FEN = UNIT_AMOUNT_FEN * MAX_QUANTITY
MAX_WALLET_BALANCE = 9007199254740991


def product():
    # Wallet credit is validated independently of display pricing.
    return dict(sku=SKU, item_id=ITEM_ID, title='U币充值',
        description='每份1元，到账100U币。请适度娱乐，理性消费。',
        amount=UNIT_AMOUNT_FEN, effects={}, enabled=True, sort_order=1000000,
        purchase_limit=0, category_id='item', product_type='recharge',
        icon='custom_game/commerce_jade_v1/coin.png',
        recharge_u_coin_per_unit=U_COIN_PER_UNIT, max_quantity=MAX_QUANTITY,
        grants=dict(items={}, item_limits={}, entitlements=[], effect_labels={},
            lines=[dict(kind='wallet', id='u_coin', quantity=U_COIN_PER_UNIT, label='U币')],
            pricing=dict(u_coin_price=U_COIN_PER_YUAN, u_coin_per_yuan=U_COIN_PER_YUAN),
            recharge_u_coin_per_unit=U_COIN_PER_UNIT))


def is_recharge(order):
    return order.get('sku') == SKU


def public_fields(count):
    return dict(product_type='recharge', recharge_u_coin_per_unit=U_COIN_PER_UNIT,
                recharge_u_coin_total=U_COIN_PER_UNIT * count, max_quantity=MAX_QUANTITY)


def validate_snapshot(order):
    """Never infer wallet rewards from client/catalog display fields."""
    from .wechat import PaymentError
    reward = order.get('reward', {})
    count = reward.get('quantity')
    expected = product()
    grants = deepcopy(expected['grants'])
    if type(count) is not int or not 1 <= count <= MAX_QUANTITY:
        raise PaymentError('payment_quantity_invalid', 500)
    rate = snapshot_rate(reward.get('unit_pricing'))
    expected['grants']['pricing'] = dict(u_coin_price=rate, u_coin_per_yuan=rate)
    grants['pricing'] = deepcopy(expected['grants']['pricing'])
    grants['lines'][0]['quantity'] *= count
    grants['pricing']['u_coin_price'] *= count
    if (reward.get('version') != 6 or reward.get('item_id') != ITEM_ID
        or reward.get('product_type') != 'recharge'
        or type(reward.get('recharge_u_coin_per_unit')) is not int
        or reward['recharge_u_coin_per_unit'] != U_COIN_PER_UNIT
        or type(reward.get('unit_amount_fen')) is not int
        or reward['unit_amount_fen'] != UNIT_AMOUNT_FEN
        or type(order.get('amount')) is not int or order['amount'] != UNIT_AMOUNT_FEN * count
        or reward.get('effects') != {} or reward.get('purchase_limit') != 0
        or reward.get('unit_pricing') != expected['grants']['pricing']
        or reward.get('grants') != grants):
        raise PaymentError('payment_pricing_mismatch', 500)
    return count, UNIT_AMOUNT_FEN
