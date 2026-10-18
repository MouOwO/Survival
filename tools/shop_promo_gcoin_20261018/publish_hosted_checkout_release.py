"""Explicit approved transport for the frozen, code-only checkout release."""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/shop_promo_gcoin_20261018/hosted_checkout'
TAR_SHA = '90659f3cb5fbb92d34f3b8425e0f4e89c473a8d86c9deb837cfdf06fa7e40133'
OLD_MANIFEST = '17433d5c9185e1b1589bdabf346af4fef66d5c50bd5a77e0ce3ef6da4eeb6a43'
NEW_MANIFEST = '754926e3e7ef11603e3070eb5304cb778f55a5c8b7dfcc370d8f2612dfda4303'


def main(mode):
    plan = json.loads((OUT / 'release/plan.json').read_bytes())
    review = json.loads((OUT / 'release/review.json').read_bytes())
    audit = json.loads((OUT / 'remote/preflight.json').read_bytes())['records'][0]
    assert plan['tarball_sha256'] == TAR_SHA and plan['baseline_manifest_sha256'] == OLD_MANIFEST
    assert plan['candidate_manifest_sha256'] == NEW_MANIFEST and plan['candidate'] == '20261018-checkout-gcoin-v1'
    raw = (ROOT / plan['tarball']).read_bytes();assert hashlib.sha256(raw).hexdigest() == TAR_SHA
    manifest = json.loads((OUT / 'release' / plan['candidate'] / 'manifest.json').read_bytes())
    assert hashlib.sha256((OUT / 'release' / plan['candidate'] / 'manifest.json').read_bytes()).hexdigest() == NEW_MANIFEST
    spec = importlib.util.spec_from_file_location('approved_checkout_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
    transport = importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
    sys.path.insert(0, str(ROOT / 'tools'))
    import aliyun_local_config
    from aliyun_test_connection import verify_known_hosts
    config = aliyun_local_config.load(ROOT);verify_known_hosts(ROOT / 'tools/deploy/goufayu_test_known_hosts')
    transport.OPTIONS[transport.OPTIONS.index('-i') + 1] = str(config['ssh_key'])
    transport.OPTIONS.extend(['-o', 'GlobalKnownHostsFile=none', '-o', 'HostKeyAlgorithms=ssh-ed25519',
        '-o', 'PreferredAuthentications=publickey', '-o', 'PasswordAuthentication=no', '-o', 'KbdInteractiveAuthentication=no'])
    transport.OUT = OUT / 'deployment'
    source = 'MODE=' + repr(mode) + '\nSTAGE=' + repr('/tmp/survival-checkout-gcoin-20261018-' + TAR_SHA[:12])
    source += '\nPLAN=' + repr(plan) + '\nCANDIDATE_MANIFEST=' + repr(manifest)
    source += '\nBASELINE_JS_SHA=' + repr(audit['public_script_sha256'])
    source += '\nCANDIDATE_JS_SHA=' + repr(review['candidate_checkout_js_sha256']) + '\n'
    if mode == 'prepare':source += 'PAYLOAD=' + repr(base64.b64encode(raw).decode('ascii')) + '\n'
    source += Path(__file__).with_name('hosted_checkout_operator.py').read_text(encoding='utf-8-sig')
    return transport.execute(source, mode, timeout=300)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('prepare', 'activate', 'verify', 'rollback'))
    main(parser.parse_args().mode)
