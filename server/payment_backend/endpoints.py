"""Fixed per-instance public routes; no caller-controlled payment destinations."""
from dataclasses import dataclass

DEFAULT_PUBLIC_BASE = 'https://pay.xiaofengnet.com'
WS4_PUBLIC_BASE = DEFAULT_PUBLIC_BASE + '/ws4-payments'
LEGACY_CONFIG = '/etc/goufayu-payment/config.json'
WS4_CONFIG = '/etc/goufayu-ws4-payment/config.json'
PUBLIC_PATHS = frozenset((
    '/checkout', '/checkout/alipay', '/checkout/status', '/checkout/qr',
    '/checkout/return', '/checkout.js', '/checkout.css', '/alipay-redirect.js',
    '/v1/payments/wechat/notify', '/v1/payments/alipay/notify',
))


@dataclass(frozen=True)
class PaymentEndpoints:
    public_base: str = DEFAULT_PUBLIC_BASE

    def __post_init__(self):
        if type(self.public_base) is not str or self.public_base not in (DEFAULT_PUBLIC_BASE, WS4_PUBLIC_BASE):
            raise ValueError('payment_public_base_invalid')

    @property
    def prefix(self):
        return '/ws4-payments' if self.public_base == WS4_PUBLIC_BASE else ''

    @property
    def isolated(self):
        return bool(self.prefix)

    def public_path(self, path):
        if path not in PUBLIC_PATHS:
            raise ValueError('payment_public_path_invalid')
        return self.prefix + path

    def url(self, path):
        if path not in PUBLIC_PATHS:
            raise ValueError('payment_public_path_invalid')
        return self.public_base + path

    def render_template(self, text):
        """Only call on authored static checkout templates, before user data."""
        if not self.prefix:
            return text
        for path in ('/checkout.css', '/checkout.js', '/checkout/qr', '/checkout/status', '/alipay-redirect.js'):
            text = text.replace('"' + path + '"', '"' + self.public_path(path) + '"')
        return text


def runtime_binding(config_path, port, config):
    """Validate explicit config/port/public-route pairing before loading keys."""
    if type(config_path) is not str or type(port) is not int:
        raise ValueError('payment_runtime_binding_invalid')
    endpoints = PaymentEndpoints(config.get('public_base', DEFAULT_PUBLIC_BASE))
    allowed = (LEGACY_CONFIG, 8766, DEFAULT_PUBLIC_BASE), (WS4_CONFIG, 18769, WS4_PUBLIC_BASE)
    if ((config_path, port, endpoints.public_base) not in allowed
            or config.get('bind', '127.0.0.1') != '127.0.0.1'):
        raise ValueError('payment_runtime_binding_invalid')
    return endpoints


def key_directory(config, provider):
    if provider not in ('wechat', 'alipay'):
        raise ValueError('payment_key_directory_invalid')
    allowed = ('/etc/goufayu-payment/' + provider, '/etc/goufayu-ws4-payment/' + provider)
    value = config.get(provider + '_key_directory', allowed[0])
    if type(value) is not str or value not in allowed:
        raise ValueError('payment_key_directory_invalid')
    return value
