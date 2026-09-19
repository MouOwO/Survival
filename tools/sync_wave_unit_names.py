"""Project wave display names from CSV into native unit IDs and localization."""
import csv
import io
import re
from pathlib import Path
import build_configs

ROOT = Path(__file__).resolve().parents[1]
BEGIN = '// BEGIN GENERATED WAVE UNIT NAMES'
END = '// END GENERATED WAVE UNIT NAMES'


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


def main():
    archetypes = read_table('monster_archetypes')
    waves = read_table('wave_definitions')
    by_id = {row['archetype_id']: row for row in archetypes[3]}
    units = {}
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
                by_id[identity].update(named)
            else:
                by_id[identity] = named
                archetypes[3].append(named)
            row = by_id[identity]
            wave['archetype_id'] = identity
        row['unit_name'] = 'npc_survival_wave_named_' + row['archetype_id']
        units[row['unit_name']] = row['display_name']
    write_table(archetypes)
    write_table(waves)
    for table in (archetypes, waves):
        build_configs.build(table[0], ROOT / 'scripts/vscripts/config/generated' / (table[0].stem + '.lua'))
    path = ROOT / 'scripts/npc/npc_units_custom.txt'
    text = path.read_text(encoding='utf-8-sig')
    template = re.search(r'"npc_survival_wave_monster"\s*(\{[^{}]*\})', text).group(1)
    block = '\n'.join([BEGIN] + [f'    "{key}"\n    {template}' for key in sorted(units)] + [END])
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


if __name__ == '__main__':
    main()
