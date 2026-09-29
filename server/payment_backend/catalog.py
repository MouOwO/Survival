"""Server-owned test products. Prices are fen; previous receipts stay immutable."""
from decimal import Decimal

# TODO(PAYMENT_TEST_ONLY): replace test prices/catalog and disable reset/repurchase
# before public release. Never infer production purchase eligibility from inventory alone.
PRODUCTS = (
    ('monkey_test_50_v2', 'lottery_monkey_king', '齐天大圣', '解锁齐天大圣召唤；获得该存档道具的已实现属性。'),
    ('wall_test_50_v2', 'lottery_nitride_alloy_wall', '氮化合金护墙', '提升城墙护甲、生命加成和成长属性。'),
    ('data_test_50_v2', 'lottery_data_unit', '数据单元', '提升金矿、伐木效率和每秒资源收益。'),
    ('turret_test_50_v2', 'lottery_pulse_conduction_turret', '脉冲传导炮台', '提升箭塔攻速、伤害和攻击成长。'),
    ('implant_test_50_v2', 'lottery_cybernetic_implant', '义体插件', '提升英雄属性成长、攻击加成和最终伤害。'),
)
DEFAULT_SKU = PRODUCTS[0][0]
PRICE_FEN = 5000


def definitions(bundle):
    items = {row['item_id']: row for row in bundle['lottery_item_definitions']['rows']}
    result = []
    for sku, item_id, title, description in PRODUCTS:
        row = items[item_id]
        if row.get('enabled') is False or row['max_owned'] != 1:
            raise RuntimeError('payment_reward_definition_invalid')
        effects = dict(zip(row['effect_ids'], row['effect_values']))
        if len(effects) != len(row['effect_ids']) or not effects:
            raise RuntimeError('payment_reward_effects_invalid')
        if 'map_level' in effects:
            for effect in bundle['map_level_effect_rules']['rows']:
                if effect.get('enabled') is not False:
                    key = effect['target_field_id']
                    effects[key] = float(Decimal(str(effects.get(key, 0))) +
                        Decimal(str(effects['map_level'])) * Decimal(str(effect['value_per_level'])))
        result.append({'sku': sku, 'item_id': item_id, 'title': title,
            'description': description, 'amount': PRICE_FEN, 'effects': effects})
    return result
