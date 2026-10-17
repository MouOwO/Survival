"""Project wave display names from CSV into native unit IDs and localization."""
import csv
import io
import re
import math
import json
import argparse
from pathlib import Path
import build_configs

ROOT = Path(__file__).resolve().parents[1]
BEGIN = '// BEGIN GENERATED WAVE UNIT NAMES'
END = '// END GENERATED WAVE UNIT NAMES'
RANGE_BEGIN = '// BEGIN GENERATED FORMAL WAVE RANGE ALIASES'
RANGE_END = '// END GENERATED FORMAL WAVE RANGE ALIASES'

# Model activities are selected with these tags, not just ACT_DOTA_RUN.
# Match Valve's npc_dota_hero_abyssal_underlord movement thresholds. Without
# walk/run the body can select a loadout sequence and slide during navigation.
MOVEMENT_ACTIVITIES = {
    'models/heroes/abyssal_underlord/abyssal_underlord_v2.vmdl': (
        ('walk', '0'), ('run', '395'),
    ),
}


def with_movement_activities(body, model):
    activities = MOVEMENT_ACTIVITIES.get(model)
    if not activities:
        return body
    fields = '\n'.join(f'            "{tag}" "{speed}"' for tag, speed in activities)
    declaration = '\n        "MovementSpeedActivityModifiers"\n        {\n' + fields + '\n        }\n'
    return body.rstrip()[:-1] + declaration + '    }'


def read_table(name):
    path = ROOT / 'data/csv/怪物与波次系统' / (name + '.csv')
    lines = path.read_text(encoding='utf-8-sig').splitlines()
    reader = csv.DictReader(line for line in lines if not line.startswith('#'))
    return path, lines, reader.fieldnames, list(reader)


def write_table(table):
    path, lines, fields, rows = table
    by_id = {row[fields[0]]: row for row in rows}
    result = []
    for index, line in enumerate(lines):
        if index == 0 or line.startswith('#') or not line:
            result.append(line)
            continue
        key = next(csv.reader([line]))[0]
        row = by_id.pop(key)
        previous = dict(zip(fields, next(csv.reader([line]))))
        result.append(line if row == previous else serialize(fields, row))
    result.extend(serialize(fields, row) for row in by_id.values())
    path.write_text('\n'.join(result) + '\n', encoding='utf-8')


def serialize(fields, row):
    out = io.StringIO()
    csv.writer(out, lineterminator='').writerow([row.get(field, '') for field in fields])
    return out.getvalue()


def replace_block(text, block):
    return re.sub(re.escape(BEGIN) + r'[\s\S]*?' + re.escape(END), lambda m: block, text)


def sync_native_range_aliases():
    """Add isolated formal aliases; never rewrite shared archetype CSV names.

    Native units are exact copies of the generated named bodies except their
    base range. Existing names remain the practice/challenge authority.
    """
    from build_wave_monster_cosmetics import parse_kv
    archetypes = read_table('monster_archetypes')[3]
    waves = read_table('wave_definitions')[3]
    formal = {row['archetype_id'] for row in waves if row.get('enabled') == '1'}
    names = {}
    for row in archetypes:
        names.setdefault(row.get('unit_name'), []).append(row)
    npc_path = ROOT / 'scripts/npc/npc_units_custom.txt'
    original = npc_path.read_bytes()
    text = original.decode('utf-8-sig')
    npc = parse_kv(text)['DOTAUnits']
    aliases, contracts = [], []
    for row in archetypes:
        if row['archetype_id'] not in formal or row.get('enabled') != '1':
            continue
        source_name = row.get('unit_name', '')
        if len(names.get(source_name, [])) != 1:
            continue  # never guess a shared-name combat contract
        try:
            reach = float(row.get('attack_range') or 128)
            if not math.isfinite(reach) or reach <= 0:
                continue
            reach = max(0, math.floor(reach))
            source = npc[source_name]
            matches = float(source.get('AttackRange', 'nan')) == reach
        except (ValueError, KeyError, TypeError):
            continue
        if matches:
            contracts.append((row['archetype_id'], source_name, source_name, reach, False))
            continue
        if not re.fullmatch(r'[a-z0-9_]+', row['archetype_id']):
            raise ValueError('invalid formal alias archetype ID')
        # Brace-depth scanning preserves nested native locomotion tags exactly.
        match = re.search(r'"' + re.escape(source_name) + r'"\s*\{', text)
        if not match:
            raise ValueError('formal source native body missing: ' + source_name)
        start, depth, end = match.end() - 1, 0, None
        for index in range(start, len(text)):
            if text[index] == '{': depth += 1
            elif text[index] == '}':
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is None:
            raise ValueError('unclosed formal source body: ' + source_name)
        body, count = re.subn(r'("AttackRange"\s*)"[^"]*"',
                             lambda m: m[1] + '"' + str(reach) + '"', text[start:end])
        if count != 1:
            raise ValueError('nonunique native base range: ' + source_name)
        alias = 'npc_survival_range_' + row['archetype_id']
        unmanaged = re.sub(re.escape(RANGE_BEGIN) + r'[\s\S]*?' + re.escape(RANGE_END), '', text)
        if re.search(r'"' + re.escape(alias) + r'"\s*\{', unmanaged):
            raise ValueError('formal alias collides with unmanaged unit: ' + alias)
        parsed = parse_kv('"DOTAUnits" { "' + alias + '" ' + body + ' }')['DOTAUnits'][alias]
        expected = dict(source, AttackRange=str(reach))
        if parsed != expected:
            raise ValueError('alias changed fields beyond AttackRange: ' + alias)
        aliases.append((row['archetype_id'], source_name, alias, reach,
                        row['display_name'], body))
        contracts.append((row['archetype_id'], source_name, alias, reach, True))
    aliases.sort()
    def update(path, block, tokens=False):
        raw = path.read_bytes()
        value = raw.decode('utf-8-sig')
        pattern = re.escape(RANGE_BEGIN) + r'[\s\S]*?' + re.escape(RANGE_END)
        if RANGE_BEGIN in value:
            value = re.sub(pattern, lambda m: block, value)
        elif tokens:
            value = re.sub(r'("Tokens"\s*\{)', lambda m: m[0] + '\n' + block, value, count=1)
        else:
            close = value.rfind('}')
            value = value[:close] + '\n' + block + '\n' + value[close:]
        data = value.encode('utf-8')
        if raw.startswith(b'\xef\xbb\xbf'): data = b'\xef\xbb\xbf' + data
        if data != raw: path.write_bytes(data)
    block = '\n'.join([RANGE_BEGIN] + [f'    "{alias}"\n    {body}'
        for _, _, alias, _, _, body in aliases] + [RANGE_END])
    update(npc_path, block)
    for relative in ('resource/addon_schinese.txt', 'resource/localization/addon_schinese.txt'):
        tokens = [f'        "{alias}" {json.dumps(name, ensure_ascii=False)}'
                  for _, _, alias, _, name, _ in aliases]
        update(ROOT / relative, '\n'.join([RANGE_BEGIN] + tokens + [RANGE_END]), True)
    lines = ['-- Generated formal-only native base-range aliases; original CSV names stay authoritative.',
             f'return {{ schema = "formal_native_range_v1", roster_count = {len(contracts)}, alias_count = {len(aliases)}, by_id = {{']
    for identity, source_name, alias, reach, is_alias in sorted(contracts):
        lines.append('    [' + json.dumps(identity) + '] = { source_unit_name = '
            + json.dumps(source_name) + ', unit_name = ' + json.dumps(alias)
            + ', attack_range = ' + str(reach) + ', alias = ' + str(is_alias).lower() + ' },')
    lines.append('} }\n')
    manifest = ROOT / 'scripts/vscripts/config/generated/wave_native_range_aliases.lua'
    manifest.parent.mkdir(parents=True, exist_ok=True)
    content = '\n'.join(lines).encode('utf-8')
    if not manifest.exists() or manifest.read_bytes() != content: manifest.write_bytes(content)
    print(f'FORMAL_NATIVE_RANGE_ALIASES_SYNCED aliases={len(aliases)} original_names_unchanged=1')
    return len(aliases)


def main():
    archetypes = read_table('monster_archetypes')
    waves = read_table('wave_definitions')
    by_id = {row['archetype_id']: row for row in archetypes[3]}
    units = {}
    models = {}
    combat = {}
    for wave in waves[3]:
        row = by_id[wave['archetype_id']]
        boss = wave['member_role'] == 'assault_boss' or wave['is_boss'] == '1'
        if boss:
            # Shared source models occur at several wave numbers. Keep their combat/visual
            # fields intact in per-wave copies so native name tokens remain unambiguous.
            base_id = re.sub(r'_wave_name_\d+$', '', row['archetype_id'])
            source = by_id[base_id]
            wave_number = int(wave['wave_number'])
            identity = base_id + '_wave_name_' + str(wave_number)
            named = dict(source, archetype_id=identity, display_name=f'波次{wave_number}BOSS')
            if identity in by_id:
                # Per-wave outfits may intentionally differ from the generic boss.
                # Preserve those visual columns while refreshing shared combat data.
                for field in ('model_path', 'normal_flying_model_path',
                              'model_asset_id', 'default_wearable_asset_id'):
                    named[field] = by_id[identity].get(field, named.get(field, ''))
                by_id[identity].update(named)
            else:
                by_id[identity] = named
                archetypes[3].append(named)
            row = by_id[identity]
            wave['archetype_id'] = identity
        row['unit_name'] = 'npc_survival_wave_named_' + row['archetype_id']
        units[row['unit_name']] = row['display_name']
        models[row['unit_name']] = row['model_path']
        combat[row['unit_name']] = row
    write_table(archetypes)
    write_table(waves)
    for table in (archetypes, waves):
        build_configs.build(table[0], ROOT / 'scripts/vscripts/config/generated' / (table[0].stem + '.lua'))
    path = ROOT / 'scripts/npc/npc_units_custom.txt'
    text = path.read_text(encoding='utf-8-sig')
    template = re.search(r'"npc_survival_wave_monster"\s*(\{[^{}]*\})', text).group(1)
    definitions = []
    for key in sorted(units):
        # Spawn with the matching skeleton so the native movement graph initializes
        # correctly; copying the generic Undying model requires a late body swap.
        body = re.sub(r'("Model"\s*)"[^"]+"', lambda m: m[1] + '"' + models[key] + '"', template)
        body = with_movement_activities(body, models[key])
        row = combat[key]
        if row.get('projectile_model') == 'particles/units/heroes/hero_winter_wyvern/winter_wyvern_base_attack.vpcf':
            body = re.sub(r'("AttackCapabilities"\s*)"[^"]+"', lambda m: m[1] + '"DOTA_UNIT_CAP_RANGED_ATTACK"', body)
            body = re.sub(r'("AttackRange"\s*)"[^"]+"', lambda m: m[1] + '"' + row['attack_range'] + '"', body)
            fields = '\n'.join('        "' + name + '" "' + value + '"' for name, value in (
                ('ProjectileModel', row['projectile_model']), ('ProjectileSpeed', row['projectile_speed']),
                ('AttackAnimationPoint', '0.25')))
            body = body.rstrip()[:-1] + fields + '\n    }'
        definitions.append(f'    "{key}"\n    {body}')
    block = '\n'.join([BEGIN] + definitions + [END])
    if BEGIN in text:
        text = replace_block(text, block)
    else:
        close = text.rfind('}')
        text = text[:close] + '\n' + block + '\n' + text[close:]
    path.write_text(text, encoding='utf-8')
    for relative in ('resource/addon_schinese.txt', 'resource/localization/addon_schinese.txt'):
        path = ROOT / relative
        text = path.read_text(encoding='utf-8-sig')
        tokens = [f'        "{key}" "{value.replace(chr(34), chr(92)+chr(34))}"' for key, value in sorted(units.items())]
        block = '\n'.join([BEGIN] + tokens + [END])
        if BEGIN in text:
            text = replace_block(text, block)
        else:
            text = re.sub(r'("Tokens"\s*\{)', lambda m: m[0] + '\n' + block + '\n', text, count=1)
        path.write_text(text, encoding='utf-8')
    print(f'WAVE_NAMES_SYNCED units={len(units)}')
    sync_native_range_aliases()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-range-aliases-only', action='store_true',
                        help='Update only additive formal range aliases/manifest/locales; leave original CSV and named KV untouched')
    options = parser.parse_args()
    if options.native_range_aliases_only:
        sync_native_range_aliases()
    else:
        main()
