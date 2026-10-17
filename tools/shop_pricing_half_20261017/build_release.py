"""Build a scoped overlay on the freshly verified live releases; no activation."""
from pathlib import Path
import base64
import copy
import hashlib
import io
import json
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/shop_pricing_half_20261017'
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle, read_csv
from payment_backend.csv_catalog import build as payment_package


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def reward_values(grants):
    values = copy.deepcopy(grants)
    values.pop('effect_labels', None)
    values.pop('pricing', None)
    for line in values.get('lines', []):
        for field in ('label', 'description'):
            line.pop(field, None)
    return values


def main():
    audit = json.loads((OUT / 'remote/preflight.json').read_bytes())['records'][0]
    baseline = OUT / 'baseline'
    parent_dir = baseline / 'archive/addon/server/bundles' / audit['archive_bundle']
    parent = json.loads((parent_dir / 'bundle.json').read_bytes())
    assert sha((parent_dir / 'bundle.json').read_bytes()) == audit['archive_bundle']
    from archive_backend.commerce_catalog import build_catalog
    commerce = build_catalog(ROOT)
    before = {p['sku']: p for p in parent['configs']['commerce_catalog']['rows']}
    after = {p['sku']: p for p in commerce['products']}
    assert set(before) == set(after), 'commerce_product_set_changed'
    for sku, product in after.items():
        original = copy.deepcopy(before[sku])
        assert original['price'] == product['price'] * 2, 'price_not_half:' + sku
        assert reward_values(original['grants']) == reward_values(product['grants']), 'commerce_reward_change:' + sku
        for field in ('effects', 'enabled', 'item_id', 'title', 'purchase_limit', 'currency', 'ownership_quantity', 'original_price'):
            assert original.get(field) == product.get(field), 'commerce_contract_change:' + sku + ':' + field
        original['price'] = product['price']
        after[sku] = original
    data = copy.deepcopy(parent)
    data['configs']['commerce_catalog'] = dict(key='sku', rows=[after[p['sku']] for p in commerce['products']])
    changed_csv = ['data/csv/商城兑换系统/commerce_products.csv', 'data/csv/存档系统/archive_daily_rules.csv']
    for name in changed_csv:
        path = ROOT / name
        data['configs'][path.stem] = read_csv(path)
        data['csv_hashes'][name] = sha(path.read_bytes().replace(b'\r\n', b'\n'))
    # Completed receipts return before settlement. Only uncommitted commerce
    # intents use the newly published price; lottery retains recorded rules.
    rules = data.setdefault('compatible_config_hashes', {})
    # Older compatibility rules stay frozen, including early schema migrations.
    # The currently running parent has the complete current account schema.
    commands = sorted({c for rule in rules.values() for c in rule['commands']})
    rules[audit['archive_bundle']] = dict(commands=commands, upgrade_commands=['commerce_purchase'])
    raw = canonical(data)
    digest = sha(raw)
    bundle_dir = OUT / 'candidate/archive/addon/server/bundles' / digest
    bundle_dir.mkdir(parents=True, exist_ok=True)
    (bundle_dir / 'bundle.json').write_bytes(raw)
    for name, source in data['sources'].items():
        dest = bundle_dir / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(source, encoding='utf-8', newline='\n')
    Bundle(bundle_dir)
    archive_files = {p.relative_to(OUT / 'candidate/archive').as_posix(): p.read_bytes() for p in bundle_dir.rglob('*') if p.is_file()}
    archive_files['addon/server/bundles/current.json'] = canonical(dict(protocol=1, hash=digest))
    old_compat = (baseline / 'archive/backend/archive_backend/config_compatibility.py').read_text(encoding='utf-8-sig')
    new_compat = (ROOT / 'server/archive_backend/config_compatibility.py').read_text(encoding='utf-8-sig')
    addition = "    # Catalog reads already use the current bundle. Explicitly approved price\n    # publications must use that same catalog for uncommitted purchases too.\n    'commerce_purchase',\n"
    assert new_compat.replace(addition, '') == old_compat, 'unexpected_compatibility_change'
    archive_files['backend/archive_backend/config_compatibility.py'] = new_compat.encode()
    files = {name: (baseline / 'payment' / name).read_bytes() for name in audit['payment_manifest']}
    replacements = ['commerce_bundles.py', 'csv_catalog.py', 'catalog.py', 'ucoin_catalog.py', 'ucoin_recharge.py', 'order_quantity.py', 'service.py']
    additions = ['ucoin_pricing.py', 'upgrade_ucoin_rate_100.sql', 'test_ucoin_rate_100.py', 'test_ucoin_rate_100_database.py']
    for name in replacements + additions:
        source = ROOT / 'server/payment_backend' / name
        files['payment_backend/' + name] = source.read_text(encoding='utf-8-sig').replace('\r\n', '\n').encode()
    # Publish the reviewed product reference only. Other capability references
    # stay exactly equal to the active payment manifest.
    name = 'reference_csv/商城兑换系统/commerce_products.csv'
    files[name] = (ROOT / 'data/csv/商城兑换系统/commerce_products.csv').read_text(encoding='utf-8-sig').replace('\r\n', '\n').encode()
    package = payment_package(ROOT)
    assert package['catalog']['u_coin_per_yuan'] == 100, 'new_catalog_rate_invalid'
    products = {p['sku']: p for p in package['catalog']['products']}
    old_products = {p['sku']: p for p in audit['products']}
    for sku, product in products.items():
        old = old_products[sku]
        if sku == 'u_coin_recharge':
            assert old['amount'] == product['amount'] == 100
        elif sku in after:
            assert product['amount'] == after[sku]['price'] == old['amount'] * 5, 'new_ucoin_amount_invalid:' + sku
        else:
            assert product['amount'] * 2 == old['amount'], 'new_cash_amount_invalid:' + sku
        expected_description = old['description']
        if sku == 'special_lottery_ticket_single':
            expected_description = expected_description.replace('50元一张', '25元一张')
        if sku == 'archive_pass_monthly':
            expected_description = expected_description.replace('20元开通', '10元开通')
        for field in ('item_id', 'title', 'enabled', 'sort_order', 'purchase_limit', 'effects', 'category_id', 'product_type', 'icon'):
            assert product[field] == old[field], 'nonprice_payment_change:' + sku + ':' + field
        assert reward_values(old['grants']) == reward_values(product['grants']), 'reward_changed:' + sku
        # Keep live presentation metadata. It predates unrelated local label
        # edits; those edits are not part of a price publication.
        pricing = product['grants'].get('pricing')
        product['grants'] = copy.deepcopy(old['grants'])
        if pricing is not None:
            product['grants']['pricing'] = pricing
        product['description'] = expected_description
    package['catalog_hash'] = sha(canonical(package['catalog']))
    payment_name = '20261017-shop-half-rate100-v1'
    archive_name = '20261017-shop-half-v1'
    plan = dict(version=1, payment_baseline=audit['payment_release'], payment_manifest_sha256=audit['payment_manifest_sha256'],
                archive_baseline=audit['archive_release'], archive_manifest_sha256=audit['archive_manifest_sha256'],
                parent_bundle=audit['archive_bundle'], bundle=digest, payment_release=payment_name, archive_release=archive_name,
                catalog_hash=package['catalog_hash'], baseline_catalog_hash=audit['catalog_hash'],
                baseline_functions={s: f['sha256'] for s, f in audit['functions'].items()},
                archive_files={name: sha(raw) for name, raw in archive_files.items()},
                payment_files={name: sha(raw) for name, raw in files.items()},
                product_count=len(products), commerce_count=len(after), u_coin_per_yuan=100)
    schema = json.loads((OUT / 'remote/archive_schema.json').read_bytes())['records'][0]
    plan['archive_sync_sha256'] = schema['functions']['public.archive_sync_config(text,jsonb)']['sha256']
    plan['archive_files']['addon/data/csv/存档系统/archive_daily_rules.csv'] = sha((ROOT / 'data/csv/存档系统/archive_daily_rules.csv').read_bytes())
    archive_files['addon/data/csv/存档系统/archive_daily_rules.csv'] = (ROOT / 'data/csv/存档系统/archive_daily_rules.csv').read_bytes()
    files['manifest.json'] = json.dumps(plan['payment_files'], ensure_ascii=False, indent=2).encode() + b'\n'
    payload = {'plan.json': canonical(plan), 'payment_package.json': canonical(package)}
    payload['archive_sync_before.sql'] = schema['functions']['public.archive_sync_config(text,jsonb)']['definition'].encode()
    payload.update({'payment/' + k: v for k, v in files.items()})
    payload.update({'archive/' + k: v for k, v in archive_files.items()})
    path = OUT / 'release.tar.gz'
    with tarfile.open(path, 'w:gz') as archive:
        for name, raw in sorted(payload.items()):
            info = tarfile.TarInfo(name); info.size = len(raw); info.mode = 0o644
            archive.addfile(info, io.BytesIO(raw))
    plan['tar_sha256'] = sha(path.read_bytes())
    (OUT / 'plan.json').write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in plan.items() if not isinstance(v, dict)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
