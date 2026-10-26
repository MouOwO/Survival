"""Import the complementary v3 workbook and human JSON without reapplying corrections."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/balance/human_spec_v3'
MODE_IDS = {'常规': 'standard', '极寒': 'cold', '丰饶': 'rich', '纯净': 'pure',
            '天灾': 'scourge', '归墟': 'ruins', '天域': 'celestial'}
SHEETS = {'modes': '模式与难度', 'counts': '数量与间隔', 'spawns': '出怪类型',
          'attack_bosses': '进攻BOSS', 'challenge_building': '挑战建筑', 'rooms': '四房',
          'rebirth_bosses': '转生BOSS', 'special_bosses': '特殊BOSS', 'save_challenges': '存档挑战',
          'void_shadows': '虚空之影', 'overrides': '修正表', 'unlock': '解锁条件',
          'examples': '示例', 'tianzai_combo': '天灾首怪与精英', 'special_rotation': '特殊轮换怪',
          'special_rotation_health_overrides': '轮换怪血量修正'}


def equal(left, right):
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return math.isclose(left, right, rel_tol=2e-14, abs_tol=1e-12)
    return left == right


def lua(value, depth=0):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        assert math.isfinite(value)
        return repr(value)
    pairs = list(enumerate(value, 1)) if isinstance(value, list) else list(value.items())
    if not pairs:
        return '{}'
    entries = ['[' + lua(key) + '] = ' + lua(child, depth + 1) for key, child in pairs]
    if all(not isinstance(child, (dict, list)) for _, child in pairs):
        return '{ ' + ', '.join(entries) + ' }'
    indent = '    ' * (depth + 1)
    return '{\n' + indent + (',\n' + indent).join(entries) + ',\n' + '    ' * depth + '}'


def base(row, name_key):
    result = {'name': row[name_key], 'health': row['基础HP'], 'war3_armor': row['基础护甲'],
              'attack': row['基础攻击']}
    if '攻击间隔' in row:
        result['attack_interval'] = row['攻击间隔']
    if '数量' in row:
        result['count'] = row['数量']
    return result


def count_rule(row):
    condition = row['难度条件']
    result = {'mode_id': MODE_IDS[row['模式']], 'min_difficulty': 1, 'max_difficulty': 50,
              'min_wave': 1, 'max_wave': 30, 'count': row['数量'], 'spawn_interval': row['间隔']}
    if condition.startswith('第'):
        numbers = [int(value) for value in re.findall(r'\d+', condition)]
        result['min_wave'] = numbers[0]
        result['max_wave'] = numbers[1] if len(numbers) > 1 else 30
    else:
        numbers = [int(value) for value in re.findall(r'N(\d+)', condition)]
        assert numbers, f'Unknown count range: {condition}'
        result['min_difficulty'] = numbers[0]
        result['max_difficulty'] = numbers[1] if len(numbers) > 1 else 50
    return result


def rotation_health_overrides(rows, modes, rotation_modes):
    """Scope confirmed final HP to an existing mode, difficulty and rotation slot."""
    result, identities = [], set()
    columns = {'模式', '难度', '波次', '轮换位置', '最终HP', '证据'}
    for row in rows:
        assert set(row) == columns, 'Invalid rotation health override columns'
        mode_id = MODE_IDS.get(row['模式'])
        assert mode_id in modes, 'Invalid rotation health override mode'
        for field in ('难度', '波次', '轮换位置'):
            value = row[field]
            assert type(value) in (int, float) and math.isfinite(value) \
                and value == int(value) and value > 0, f'Invalid rotation health override {field}'
        difficulty, wave, position = (int(row[field]) for field in ('难度', '波次', '轮换位置'))
        mode = modes[mode_id].get(difficulty)
        assert mode is not None, 'Invalid rotation health override difficulty'
        assert wave <= mode['total_waves'], 'Invalid rotation health override wave'
        assert mode_id in rotation_modes.get((wave, position), set()), \
            'Invalid rotation health override rotation slot'
        health = row['最终HP']
        assert type(health) in (int, float) and math.isfinite(health) and health > 0, \
            'Invalid rotation health override health'
        assert isinstance(row['证据'], str) and row['证据'].strip(), \
            'Missing rotation health override evidence'
        identity = (mode_id, difficulty, wave, position)
        assert identity not in identities, 'Duplicate rotation health override'
        identities.add(identity)
        result.append({'mode_id': mode_id, 'difficulty': difficulty, 'wave_number': wave,
                       'position': position, 'health': health, 'evidence': row['证据']})
    return result


def load(json_path, workbook_path):
    raw = json.loads(json_path.read_text(encoding='utf-8-sig'))
    workbook = openpyxl.load_workbook(workbook_path, read_only=True, data_only=True)
    sheets = {}
    try:
        for sheet in workbook:
            rows = [list(row) for row in sheet.iter_rows(values_only=True) if any(cell is not None for cell in row)]
            sheets[sheet.title] = [dict(zip(rows[0], row)) for row in rows[1:]]
    finally:
        workbook.close()
    comparisons = 0
    for key, title in SHEETS.items():
        assert len(raw[key]) == len(sheets[title]), f'Conflicting row counts: {key}'
        for number, (json_row, excel_row) in enumerate(zip(raw[key], sheets[title]), 2):
            assert json_row.keys() == excel_row.keys(), f'Conflicting columns: {title}:{number}'
            for column in json_row:
                assert equal(json_row[column], excel_row[column]), f'Conflicting sources: {title}:{number}:{column}'
                comparisons += 1
    modes = {}
    for row in raw['modes']:
        modes.setdefault(MODE_IDS[row['模式']], {})[row['难度']] = {
            'hp_multiplier': row['HP倍率'], 'armor_multiplier': row['护甲倍率'],
            'challenge_hp_multiplier': row['挑战HP倍率'], 'challenge_armor_multiplier': row['挑战护甲倍率'],
            'total_waves': row['波次上限'], 'max_difficulty': row['模式最高难度']}
    waves = {}
    for row in sheets['波次小怪基础值']:
        waves[row['波次']] = dict(base(row, '小怪名称'), flying=row['是否飞行'] == '是')
    assert set(waves) == set(range(1, 31)), 'Workbook must supply all thirty wave bases'
    attack_bosses = {row['波次']: base(row, '首领') for row in raw['attack_bosses']}
    rotation, rotation_modes = {}, {}
    for row in raw['special_rotation']:
        position = 3 if '第3只' in row['出现规则'] else 2
        rotation.setdefault(row['波次'], []).append(dict(base(row, '特殊怪'), position=position, evidence=row['证据']))
        rotation_modes[(row['波次'], position)] = {MODE_IDS[name] for name in row['适用模式'].split('/')}
    health_overrides = rotation_health_overrides(raw['special_rotation_health_overrides'], modes, rotation_modes)
    archive = [{'name': row['挑战名称'], 'boss': row['BOSS'], 'health': row['最终HP'],
                'war3_armor': row['最终护甲'], 'attack': row['最终攻击'], 'attack_speed': row['攻速'],
                'count': row['数量'], 'scale': row['倍率scale'], 'evidence': row['验证状态']}
               for row in raw['save_challenges']]
    return {
        'version': 3,
        'sources': {'json': json_path.name, 'workbook': workbook_path.name,
                    'json_sha256': hashlib.sha256(json_path.read_bytes()).hexdigest(),
                    'workbook_sha256': hashlib.sha256(workbook_path.read_bytes()).hexdigest(),
                    'cross_checked_cells': comparisons, 'workbook_only_wave_bases': len(waves)},
        'modes': modes, 'waves': waves, 'attack_bosses': attack_bosses, 'special_rotation': rotation,
        'special_rotation_health_overrides': health_overrides,
        'rooms': [base(row, '房间') for row in raw['rooms']],
        'rebirth_bosses': [base(row, '转生BOSS') for row in raw['rebirth_bosses']],
        'special_bosses': [base(row, 'BOSS') for row in raw['special_bosses']],
        'save_challenges': archive,
        'building_challenges': [{'name': row['技能'], 'fixed_health': row['固定HP'],
                                 'health_coefficient': row['HP系数'], 'fixed_attack': row['固定攻击'],
                                 'attack_coefficient': row['攻击系数']} for row in raw['challenge_building']],
        'counts': [count_rule(row) for row in raw['counts']],
        'spawn_rules': raw['spawns'], 'unlock_rules': raw['unlock'],
        'corrections_already_included': raw['overrides'], 'examples': raw['examples'],
        'source_notes': sheets['说明'],
        'release_modes': ['standard', 'cold', 'rich', 'pure'],
        'count_includes_attack_boss': True,
    }


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--json', type=Path, default=SOURCE / 'human_spec.json')
    parser.add_argument('--xlsx', type=Path, default=SOURCE / '接入规格_人话版_v3.xlsx')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = load(args.json, args.xlsx)
    outputs = {
        SOURCE / 'normalized.json': json.dumps(result, ensure_ascii=False, indent=2) + '\n',
        ROOT / 'scripts/vscripts/config/generated/human_monster_spec.lua':
            '-- Generated by tools/import_human_monster_spec.py from BOTH v3 inputs.\n'
            '-- Values already include the source correction table; never apply it again.\nreturn ' + lua(result) + '\n',
    }
    for file, text in outputs.items():
        if args.check:
            assert file.read_text(encoding='utf-8') == text, f'Out of date: {file.relative_to(ROOT)}'
        else:
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text, encoding='utf-8', newline='\n')
    print(json.dumps({'ok': True, 'sources': result['sources'], 'mode_rows': sum(map(len, result['modes'].values())),
                      'wave_bases': len(result['waves']), 'archive_rows': len(result['save_challenges'])}, ensure_ascii=False))


if __name__ == '__main__':
    main()
