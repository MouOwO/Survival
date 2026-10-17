"""Validate request counts and expose only immutable server order quotes."""
from .wechat import PaymentError
from . import ucoin_recharge
from .ucoin_pricing import snapshot_rate

MAX_ORDER_QUANTITY=100
MAX_AMOUNT_FEN=1000000

def quantity(value, *, stored=False, sku=None):
    maximum=ucoin_recharge.MAX_QUANTITY if sku==ucoin_recharge.SKU else MAX_ORDER_QUANTITY
    if type(value) is not int or not 1<=value<=maximum:
        raise PaymentError('payment_quantity_invalid' if stored else 'quantity_invalid',500 if stored else 400)
    return value

def snapshot_units(order):
    if ucoin_recharge.is_recharge(order):return ucoin_recharge.validate_snapshot(order)
    reward=order['reward']
    if reward.get('version',1)>=5 and (not {'quantity','unit_amount_fen','unit_pricing'}<=set(reward)
        or not isinstance(reward['unit_pricing'],dict) or not isinstance(reward.get('grants',{}).get('pricing'),dict)):
        raise PaymentError('payment_pricing_mismatch',500)
    count=quantity(reward.get('quantity',1),stored=True)
    unit=reward.get('unit_amount_fen',order['amount'] if count==1 else None)
    if (type(unit) is not int or not 1<=unit<=MAX_AMOUNT_FEN
        or type(order['amount']) is not int or unit*count!=order['amount'] or order['amount']>MAX_AMOUNT_FEN):
        raise PaymentError('payment_pricing_mismatch',500)
    return count,unit

def pricing_original(pricing,expected_ucoin,maximum_original,expected_rate=None):
    if pricing is None:return None
    rate=snapshot_rate(pricing)
    if (not isinstance(pricing,dict) or set(pricing)-{'u_coin_price','u_coin_per_yuan','original_u_coin_price'}
        or type(pricing.get('u_coin_price')) is not int or pricing['u_coin_price']!=expected_ucoin
        or (expected_rate is not None and rate!=expected_rate)):
        raise PaymentError('payment_pricing_mismatch',500)
    if 'original_u_coin_price' not in pricing:return None
    original=pricing['original_u_coin_price']
    if type(original) is not int or not expected_ucoin<=original<=maximum_original:
        raise PaymentError('payment_pricing_mismatch',500)
    return original
