"""Restore the ten encounter names in original-map order, without changing stats."""
import csv
import json
import re
from pathlib import Path
import build_configs

ROOT = Path(__file__).resolve().parents[1]


def restore():
    reference = json.loads((ROOT / 'data/balance/original_map_20261025/reference.json').read_text('utf8'))
    originals = sorted((row for row in reference['nonwave_units'] if row['class'] == 'ten_commandments'), key=lambda row: row['order'])
    assert [row['order'] for row in originals] == list(range(1, 11))
    assert len({row['name'] for row in originals}) == 10
    names = {'ten_sin_%02d' % row['order']: row['name'] for row in originals}
    source = next((ROOT / 'data/csv').rglob('monster_archetypes.csv'))
    lines = source.read_text('utf-8-sig').splitlines(True)
    headers = next(csv.reader([lines[0]])); key_column = headers.index('archetype_id'); name_column = headers.index('display_name')
    found = set()
    for index, line in enumerate(lines[1:], 1):
        values = next(csv.reader([line]))
        if values and values[key_column] in names:
            key = values[key_column]; assert key not in found; found.add(key)
            # These two cells are plain CSV text. Preserve every other column.
            fields = line.split(','); assert fields[name_column] == values[name_column]
            fields[name_column] = names[key]; lines[index] = ','.join(fields)
    assert found == names.keys()
    source.write_text(''.join(lines), encoding='utf8', newline='\n')
    build_configs.build(source, ROOT / 'scripts/vscripts/config/generated/monster_archetypes.lua')
    for relative in ['resource/addon_schinese.txt', 'resource/localization/addon_schinese.txt']:
        path = ROOT / relative; text = path.read_text('utf8')
        for key, name in names.items():
            token = 'npc_survival_named_' + key
            text, count = re.subn(r'("' + token + r'"\s+")[^"]*(")', lambda match: match[1] + name + match[2], text)
            assert count == 1, token
        path.write_text(text, encoding='utf8', newline='\n')
    print(json.dumps({'status': 'PASS', 'names': names}, ensure_ascii=True))


if __name__ == '__main__':
    restore()
