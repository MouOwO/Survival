"""Build the archive CSV contract from the reviewed, permanent video manifest.

No video/OCR dependencies, game launch, rewards, publishing or global config build.
--check is read-only and reports drift; default writes only the four owned CSVs.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'data/balance/archive_video_20261029.json'
CSV_ROOT = ROOT / 'data/csv/存档系统'
DEF_FIELDS = 'challenge_id building_id slot_order display_name min_difficulty reward_kind reward_key model_path model_scale ability_icon cooldown_seconds enabled description default_wearable_asset_id unlock_text reward_requirement_pool reward_requirement_count'.split()
DEF_TYPES = 'string number number string number string string string number string number boolean string string string string number'.split()
ACTION_FIELDS = 'action_id ability_name building_id slot_order display_name min_difficulty unlock_text ability_icon cooldown_seconds enabled description'.split()
ACTION_TYPES = 'string string number number string number string string number boolean string'.split()
STATS_FIELDS = 'stats_id challenge_id difficulty_id health attack war3_armor attack_speed move_speed attack_range magic_resistance enabled notes count'.split()
STATS_TYPES = 'string string string number number number number number number number boolean string number'.split()
RULE_FIELDS = 'rule_id building_unlock_difficulty building_spacing building_offset_y building_model building_model_scale base_fragment_daily_limit pass_fragment_daily_limit cage_daily_limit pass_cage_daily_limit cage_drop_count pass_cage_extra_count day_timezone_offset final_boss_shadow_drops_enabled building_model_1 building_model_2 building_model_3 phase_duration_seconds building_anchor building_count building_model_4'.split()
RULE_TYPES = 'string number number number string number number number number number number number number boolean string string string number string number string'.split()


def load_manifest(path=MANIFEST):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def validate(manifest):
    challenges = manifest['challenges']
    actions = manifest['actions']
    occupied = set()
    ids = set()
    assert manifest['rules']['building_count'] == 4
    for row in [*challenges, *actions]:
        key = row.get('challenge_id') or row['action_id']
        assert key not in ids, f'duplicate entry id: {key}'
        ids.add(key)
        position = (row['building_id'], row['slot_order'])
        assert 1 <= position[0] <= 4 and 1 <= position[1] <= 12, position
        assert position not in occupied, f'conflicting archive grid slot: {position}'
        occupied.add(position)
        assert row['description'], f'missing full tooltip: {key}'
        assert isinstance(row['unlock_text'], str)
    for row in challenges:
        key = row['challenge_id']
        assert row['min_difficulty'] >= 1
        if row['reward_requirement_pool']:
            assert row['reward_requirement_count'] == 100
            assert row['evidence']['reward_requirement_comparison'] == 'strictly_greater_than'
        for attribute in ['health', 'attack', 'war3_armor', 'attack_speed']:
            assert row['stats'][attribute] > 0, (key, attribute)
            assert row['stat_evidence'][attribute]['source'], (key, attribute)
        assert not row['stat_evidence']['health'].get('observed_in_attached_video', False)
        assert not row['stat_evidence']['war3_armor'].get('observed_in_attached_video', False)
    assert len(challenges) == 36 and len(actions) == 7
    assert len(occupied) == 43, 'five unused grid slots must remain free'
    assert (4, 8) not in occupied, 'Pal feature explicitly removed by user'
    assert 'pet' not in ids


def csv_text(fields, kinds, rows, chinese):
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\n')
    writer.writerow(fields)
    writer.writerow(['#中文表头:' + chinese[0], *chinese[1:]])
    writer.writerow(['#types:' + kinds[0], *kinds[1:]])
    for row in rows:
        writer.writerow([row.get(field, '') for field in fields])
    return output.getvalue()


def outputs(manifest):
    validate(manifest)
    stats = []
    for row in manifest['challenges']:
        for difficulty in range(1, 11):
            stats.append(dict(stats_id=f'{row["challenge_id"]}_N{difficulty}',
                              challenge_id=row['challenge_id'], difficulty_id=f'N{difficulty}',
                              **row['stats'], enabled=1, notes=row['stats_notes']))
    return {
        'archive_challenge_definitions.csv': csv_text(DEF_FIELDS, DEF_TYPES, manifest['challenges'],
            ['挑战ID','建筑序号','绝对技能格位1至12','技能名称','最低难度','奖励种类','奖励ID或品质','模型','模型缩放','技能图标','冷却秒','启用','完整说明','饰品资源ID','解锁条件显示','奖励前置累计池','奖励前置次数严格大于']),
        'archive_challenge_actions.csv': csv_text(ACTION_FIELDS, ACTION_TYPES, manifest['actions'],
            ['入口ID','技能名称','建筑序号','绝对技能格位1至12','显示名称','最低难度','解锁条件显示','技能图标','冷却秒','启用','完整说明']),
        'archive_challenge_stats.csv': csv_text(STATS_FIELDS, STATS_TYPES, stats,
            ['属性ID','挑战ID','兼容难度键','固定生命','固定攻击','固定魔兽护甲','每秒攻击次数','移速','攻击距离','魔抗百分比','启用','属性来源与不可见边界','怪物数量']),
        'archive_challenge_rules.csv': csv_text(RULE_FIELDS, RULE_TYPES, [manifest['rules']],
            ['规则ID','建筑最低难度','建筑落点搜索间距','距波次传送门四向偏移','建筑模型','建筑缩放','碎片日上限','通行证碎片日上限','牢笼材料日总上限','通行证牢笼日上限','牢笼掉落件数','通行证额外牢笼件数','日重置时区秒差','保留普通最终BOSS虚空掉落','挑战建筑1模型','挑战建筑2模型','挑战建筑3模型','挑战阶段时限秒','建筑落点锚点','建筑数量','挑战建筑4模型']),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = outputs(load_manifest())
    drift = []
    for name, body in expected.items():
        path = CSV_ROOT / name
        if args.check:
            if not path.exists() or path.read_bytes() != body.encode('utf8'):
                drift.append(name)
        else:
            path.write_bytes(body.encode('utf8'))
    if drift:
        print('ARCHIVE_VIDEO_CONFIG_DRIFT: ' + ', '.join(drift))
        return 1
    print(f'ARCHIVE_VIDEO_CONFIG_{"CHECK" if args.check else "BUILD"}_PASS: 36 challenges, 7 actions, fixed N1-N10 compatibility rows, 4 buildings; Pal excluded')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
