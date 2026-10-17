"""Current catalog quotes and the two immutable, server-issued order rates."""
U_COIN_PER_YUAN = 100
HISTORICAL_U_COIN_PER_YUAN = 1000
SNAPSHOT_RATES = (U_COIN_PER_YUAN, HISTORICAL_U_COIN_PER_YUAN)


def _error(code):
    # Catalog compilation intentionally has no payment SDK dependency.
    from .wechat import PaymentError
    return PaymentError(code, 500)


def snapshot_rate(pricing):
    """Missing pricing only occurs on legacy receipts issued before snapshots."""
    if pricing is None:
        return HISTORICAL_U_COIN_PER_YUAN
    if (not isinstance(pricing, dict)
        or type(pricing.get('u_coin_per_yuan')) is not int
        or pricing['u_coin_per_yuan'] not in SNAPSHOT_RATES):
        raise _error('payment_pricing_mismatch')
    return pricing['u_coin_per_yuan']


def quote(amount_fen, *, rate=U_COIN_PER_YUAN, maximum=1000000):
    if type(amount_fen) is not int or not 1 <= amount_fen <= maximum:
        raise _error('payment_amount_invalid')
    if type(rate) is not int or rate not in SNAPSHOT_RATES or amount_fen * rate % 100:
        raise _error('payment_pricing_mismatch')
    return dict(u_coin_price=amount_fen * rate // 100, u_coin_per_yuan=rate)
