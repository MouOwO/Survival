"""Single-field products using the existing persistent gameplay-stat pipeline."""
from .catalog import PRICE_FEN

# TODO(PAYMENT_TEST_ONLY): retire these isolated test products before public launch.
PRODUCTS = (
    ('wood_100_test_50_v3', 'payment_test_initial_wood_100', '初始木材 +100', 'initial_wood',
     '永久增加初始木材 100。本局到账后补加 100 木材，新对局也享受此加成。'),
    ('gold_100_test_50_v3', 'payment_test_initial_gold_100', '初始金币 +100', 'initial_gold',
     '永久增加初始金币 100。本局到账后补加 100 金币，新对局也享受此加成。'),
    ('wall_armor_100_test_50_v3', 'payment_test_wall_armor_100', '城墙初始护甲 +100', 'wall_armor',
     '永久增加城墙护甲 100。查看城墙护甲；已建城墙也会刷新。'),
    ('wall_health_100_test_50_v3', 'payment_test_wall_health_100', '城墙初始血量 +100', 'wall_initial_health',
     '永久增加城墙生命上限 100。查看生命上限；受伤城墙保持原血量比例。'),
    ('tower_attack_100_test_50_v3', 'payment_test_tower_attack_100', '箭塔固定攻击力 +100', 'tower_attack_flat',
     '永久增加箭塔固定攻击力 100。最终攻击面板还会叠加已有科技及百分比加成。'),
)


def definitions():
    return [dict(sku=sku, item_id=item, title=title, description=description,
                 amount=PRICE_FEN, effects={field:100})
            for sku,item,title,field,description in PRODUCTS]
