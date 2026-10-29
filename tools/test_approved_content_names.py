"""Check approved display names and preserve the pre-change gameplay contract.

Pass --baseline <commit> to compare all CSV identities, numeric fields, conditions,
effect arrays and the excluded hunt/cage groups against the task's initial code.
"""
from pathlib import Path
import argparse
import csv
import io
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROSE = {'name', 'display_name', 'description', 'notes', 'listed_stats', 'recipe_summary',
         'unlock_text', 'currency_name', 'display_text', 'tooltip', 'title', 'category_name',
         'item_type', 'source_target', 'source_name', 'reward_name', 'product_name', 'item_name',
         'pool_name', 'label'}


def records(raw):
    try:
        text = raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        text = raw.decode('gb18030')
    rows = list(csv.reader(io.StringIO(text, newline='')))
    header = rows[0]
    return header, [dict(zip(header, values)) for values in rows[1:]
                    if values and values[0] and not values[0].startswith('#')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline')
    args = parser.parse_args()
    plan = json.loads((ROOT / 'data/presentation/approved_names_20261030.json').read_text(encoding='utf8'))
    checked_names = 0
    for filename, key, targets in [
        ('archive_categories.csv', 'category_id', plan['category_names']),
        ('archive_daily_limits.csv', 'limit_id', plan['daily_names']),
        ('archive_social_items.csv', 'entry_id', plan['names']),
        ('archive_work_items.csv', 'item_id', plan['names']),
        ('archive_building_items.csv', 'item_id', plan['names']),
        ('archive_challenge_definitions.csv', 'challenge_id', plan['names']),
        ('lottery_item_definitions.csv', 'item_id', plan['names']),
        ('commerce_products.csv', 'sku', plan['offer_names']),
        ('payment_products.csv', 'sku', plan['offer_names']),
    ]:
        path = next((ROOT / 'data/csv').rglob(filename))
        _, rows = records(path.read_bytes())
        for row in rows:
            if row.get(key) not in targets:
                continue
            assert row['display_name'] == targets[row[key]], (filename, row[key], row['display_name'], targets[row[key]])
            checked_names += 1

    resource = json.loads((ROOT / 'data/ui/item_resources.json').read_text(encoding='utf8'))
    by_id = {row['id']: row for row in resource['items']}
    for prefix in ('ex', 'wife'):
        for number in range(1, 41):
            identity = f'{prefix}_{number:02}'
            row = by_id[identity]
            assert row['name'] == plan['names'][identity]
            assert row['uri'] == f's2r://panorama/images/custom_game/collection_original_v1/{identity}.vtex'
            assert (ROOT / (row['uri'][6:] + '_c')).is_file(), identity
    for number in range(1, 6):
        assert by_id[f'concubine_{number:02}']['uri'] == by_id[f'wife_{number:02}']['uri']

    protected_rows = gameplay_cells = csv_count = 0
    if args.baseline:
        def previous(path):
            return subprocess.check_output(['git', 'show', args.baseline + ':' + path.relative_to(ROOT).as_posix()], cwd=ROOT)
        for path in (ROOT / 'data/csv').rglob('*.csv'):
            old_header, old_rows = records(previous(path))
            header, rows = records(path.read_bytes())
            if path.name == 'archive_benefit_rewards.csv':
                assert len(rows) == len(old_rows) + 1
                rows = [row for row in rows if row.get('reward_id') != 'public_beta_login']
            else:
                assert header == old_header, ('header_changed', path)
            assert len(rows) == len(old_rows), ('row_count_changed', path)
            for old, new in zip(old_rows, rows):
                identity = old[old_header[0]]
                excluded = (path.name in ('archive_cage_items.csv', 'archive_fragment_definitions.csv')
                            or path.name == 'archive_challenge_definitions.csv' and identity in plan['preserved']['challenge_ids']
                            or path.name == 'archive_daily_limits.csv' and identity in plan['preserved']['daily_limit_ids'])
                if excluded:
                    assert old == new, ('excluded_row_changed', path.name, identity)
                    protected_rows += 1
                for key in old_header:
                    if key not in PROSE:
                        assert old.get(key, '') == new.get(key, ''), ('gameplay_field_changed', path.name, identity, key, old.get(key), new.get(key))
                        gameplay_cells += 1
            csv_count += 1
        before_resources = json.loads(subprocess.check_output(['git', 'show', args.baseline + ':data/ui/item_resources.json'], cwd=ROOT).decode('utf-8-sig'))
        old = {row['id']: row for row in before_resources['items']}
        assert set(by_id) == set(old), 'resource_id_set_changed'
        replacement_ids = {f'{p}_{i:02}' for p, end in [('ex', 40), ('wife', 40), ('concubine', 5)] for i in range(1, end + 1)}
        for identity, row in by_id.items():
            if identity not in replacement_ids:
                assert row['uri'] == old[identity]['uri'], ('unrelated_art_changed', identity)
    print(json.dumps({'status': 'PASS', 'approved_name_rows': checked_names, 'portraits': 80,
                      'portrait_aliases': 5, 'baseline_csv_count': csv_count, 'preserved_rows': protected_rows,
                      'unchanged_gameplay_cells': gameplay_cells}, ensure_ascii=False))


if __name__ == '__main__':
    main()
