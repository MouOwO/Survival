"""Reproduce the reviewed ticket-only bundle without switching live pointers.

Only the listed CSV fields are accepted. The baseline's reducers, all unrelated
configurations, cash economics, previous compatibility rules, and item IDs stay
byte-equivalent. The single parent compatibility rule never upgrades mutations.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
BASE = '0763266ab8d30552fe16b69b5f78c12e073509f525d6b6ad007db34163901b3e'
EXPECTED = 'bbaf4162a941449082f4c5ddcb6d02b056db54a656e08e681d4cae4adbdccf6d'
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle, read_csv

TABLES = {
    'lottery_pool_definitions': ('抽奖系统', 'cultivation', {'ticket_content_id', 'description', 'pool_group'}),
    'lottery_currency_definitions': ('抽奖系统', 'special_lottery_ticket', {'notes'}),
    'commerce_products': ('商城兑换系统', 'video_p001', {'display_name'}),
    'commerce_import_status': ('商城兑换系统', 'P001', {'display_name', 'implementation_notes'}),
}


def overlay_table(old, new, identity, allowed):
    assert old['key'] == new['key'], 'table_identity_changed'
    key = old['key']
    a, b = ({row[key]: row for row in config['rows']} for config in (old, new))
    assert a.keys() == b.keys(), 'table_rows_changed'
    for row_id, row in a.items():
        fields = {field for field in row.keys() | b[row_id].keys() if row.get(field) != b[row_id].get(field)}
        assert not fields or (row_id == identity and fields <= allowed), 'unrelated_table_field_changed'
    return copy.deepcopy(new)


def prepare(base_directory, destination, root=ROOT):
    base = Bundle(base_directory)
    assert base.hash == BASE, 'unreviewed_parent_bundle'
    data = json.loads((base.directory / 'bundle.json').read_bytes())
    result = copy.deepcopy(data)
    for name, (folder, identity, allowed) in TABLES.items():
        source = root / 'data/csv' / folder / (name + '.csv')
        result['configs'][name] = overlay_table(data['configs'][name], read_csv(source), identity, allowed)
        result['csv_hashes'][source.relative_to(root).as_posix()] = hashlib.sha256(source.read_bytes().replace(b'\r\n', b'\n')).hexdigest()
    old = next(row for row in result['configs']['commerce_catalog']['rows'] if row['sku'] == 'video_p001')
    assert old['title'] == '红色抽奖券' and old['price'] == 600 and old['grants']['items'] == {'special_lottery_ticket': 1}, 'ticket_product_baseline_changed'
    old['title'] = '金色抽奖券'
    rules = result['compatible_config_hashes']
    assert BASE not in rules, 'parent_compatibility_exists'
    rules[BASE] = dict(commands=sorted({kind for rule in rules.values() for kind in rule['commands']}), upgrade_commands=[])
    assert result['sources'] == data['sources'], 'settlement_sources_changed'
    raw = json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == EXPECTED, 'reviewed_candidate_digest_changed'
    output = destination / digest
    files = {'bundle.json': raw, **{name: source.encode() for name, source in result['sources'].items()}}
    for name, content in files.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            assert target.read_bytes() == content, 'immutable_candidate_changed'
        else:
            target.write_bytes(content)
    assert Bundle(output).hash == digest
    return dict(ok=True, base=BASE, bundle=digest, directory=str(output), switched_live_pointer=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-bundle', type=Path, default=ROOT / 'server/bundles' / BASE)
    parser.add_argument('--output', type=Path, default=ROOT / 'tmp/tooltip_ticket_20261021/currency_candidate/bundles')
    args = parser.parse_args()
    print(json.dumps(prepare(args.base_bundle, args.output), ensure_ascii=False))
