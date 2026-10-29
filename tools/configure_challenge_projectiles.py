"""Synchronize the five reviewed challenge attacks across CSV, Lua and native KV."""
from pathlib import Path
import argparse
import csv
import io
import json
import re
import tempfile

from build_configs import build

ROOT = Path(__file__).resolve().parents[1]


def configure(check=False):
    manifest = json.loads((ROOT / 'art/effects/challenge_projectiles/manifest.json').read_text('utf-8'))
    recipes = manifest['recipes']
    source = ROOT / 'data/csv/怪物与波次系统/monster_archetypes.csv'
    rows = list(csv.reader(io.StringIO(source.read_text('utf-8-sig'))))
    headers = rows[0]
    policy = 'native_attack_presentation_policy'
    if policy not in headers:
        headers.append(policy)
        for row in rows[1:]:
            if row:
                row.append('原生远程表现策略（ranged_v1启用原生射程与弹速兼容）' if row[0].startswith('#中文')
                           else 'string' if row[0].startswith('#types:') else '')
    by_id = {r[0]: r for r in rows[1:] if r and not r[0].startswith('#')}
    units = {}
    for archetype_id, recipe in recipes.items():
        row = by_id[archetype_id]
        for key, value in dict(native_attack_presentation_policy='ranged_v1',
                               attack_type='ranged', attack_range=recipe['attack_range'],
                               projectile_model=recipe['projectile'], projectile_speed=recipe['projectile_speed']).items():
            row[headers.index(key)] = str(value)
        units[row[headers.index('unit_name')]] = recipe
    text = io.StringIO(newline='')
    csv.writer(text, lineterminator='\n').writerows(rows)
    csv_text = text.getvalue()
    native = ROOT / 'scripts/npc/npc_units_custom.txt'
    native_text = native.read_text('utf-8')
    for unit, recipe in units.items():
        pattern = re.compile(r'("' + re.escape(unit) + r'"\s*\{)(.*?)(\n    \})', re.S)
        matches = list(pattern.finditer(native_text))
        assert len(matches) == 1, unit
        match = matches[0]
        body = match[2]
        for key, value in dict(AttackCapabilities='DOTA_UNIT_CAP_RANGED_ATTACK',
                               AttackRange=recipe['attack_range'], ProjectileModel=recipe['projectile'],
                               ProjectileSpeed=recipe['projectile_speed']).items():
            field = re.compile(r'("' + key + r'"\s*)"[^"]*"')
            if field.search(body):
                body, count = field.subn(lambda m: m[1] + '"' + str(value) + '"', body)
                assert count == 1, (unit, key)
            else:
                body += '\n        "' + key + '" "' + str(value) + '"'
        native_text = native_text[:match.start(2)] + body + native_text[match.end(2):]
    generated = ROOT / 'scripts/vscripts/config/generated/monster_archetypes.lua'
    if check:
        assert source.read_text('utf-8-sig') == csv_text, 'CSV out of date'
        assert native.read_text('utf-8') == native_text, 'Native KV out of date'
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / generated.name
            build(source, target)
            assert generated.read_text('utf-8') == target.read_text('utf-8'), 'Generated Lua out of date'
    else:
        source.write_text(csv_text, encoding='utf-8', newline='\n')
        native.write_text(native_text, encoding='utf-8', newline='\n')
        build(source, generated)
    print(json.dumps({'ok': True, 'check': check, 'archetypes': len(recipes), 'native_units': len(units)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    configure(parser.parse_args().check)
