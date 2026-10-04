"""Import the reviewed B batch without changing first-batch products or prices."""
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'data/csv/商城兑换系统'

def read(name):
    with (DEST / (name + '.csv')).open(encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        records = list(reader)
    return reader.fieldnames, records[0], [r for r in records[1:]]

def write(name, fields, types, records):
    with (DEST / (name + '.csv')).open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader(); writer.writerow(types); writer.writerows(records)

def main():
    audit=json.loads((ROOT/'output/video_tooltips_20260929/项目可实现性分析/audit_data.json').read_text(encoding='utf-8'))['items']
    prices={p['id']:p for p in json.loads((ROOT/'output/video_prices_20261004/reviewed_products_with_prices.json').read_text(encoding='utf-8'))}
    pf,pt,products=read('commerce_products');rf,rt,rewards=read('commerce_rewards')
    if 'ownership_quantity' not in pf: pf.append('ownership_quantity');pt['ownership_quantity']='number'
    for p in products: p.setdefault('ownership_quantity','1')
    products=[p for p in products if p['source_id'] not in {a['id'] for a in audit if a['category']=='B'}]
    keep={p['sku'] for p in products};rewards=[r for r in rewards if r['sku'] in keep]
    for a in audit:
        if a['category']!='B': continue
        p=prices[a['id']];assert len(p['prices'])==1
        price=p['prices'][0];sku='video_'+a['id'].lower();marker=a['old_id'] or 'commerce_'+a['id'].lower()
        currency={'U币':'u_coin','积分':'shop_points','金币':'shop_gold'}[price['currency']]
        quantity=100 if a['id']=='P089' else 1
        icon='custom_game/archive_items_v2/'+(a['old_id'] or 'lottery_attribute_crystal')+'.png'
        assert (ROOT/'panorama/src/images'/icon).is_file(),icon
        description=a['body']
        notes={
            'P005':'通关计数与通关信仰按2倍结算，仍受每日上限限制；成就只领取一次。',
            'P023':'SSR按永久库存中不同道具种类计数，重复份数不重复计数。',
            'P025':'UR按永久库存中不同道具种类计数，重复份数不重复计数。',
            'P042':'UR按永久库存中不同道具种类计数。',
            'P048':'提升存档和商城持久属性及其持有条件加成，不放大局内科技、装备和战斗成长。',
            'P139':'打工额外20%用于现有在线福利软妹币，每累计5点基础收入额外获得1点；不影响商城积分。',
            'P096':'钓鱼S及以上奖励的总概率翻倍，最高100%；各组内相对概率和钓鱼间隔不变。',
            'P017':'每局一次传送到自己的资源树附近，目标不可通行时不消耗次数。',
            'P020':'清场按钮每局一次，清除自身1600范围内属于自己的普通进攻怪，不清除BOSS、挑战怪和资源树。',
            'P026':'D键指向可通行且已解锁的地图位置，冷却10秒；传送失败不进入冷却。',
            'P061':'城墙处复用现有箭塔外观，攻击城墙1600范围内属于自己的怪物。',
            'P066':'首次建矿时自动建造巨大金矿，按当时全部金矿名额合并建造费用、人口、升级费用和收益；拆除后可重建。',
            'P082':'建造费用等于七条路线终极塔的基础建造和升级费用之和；每人最多一座，须选择有效空地。',
            'P090':'城墙800范围内属于自己的怪物，每秒受到自身最大生命1%的魔法伤害。',
            'P092':'主城完成后每局赠送一名仙人，复用现有伐木工模型；可用仙人融合按钮吸收附近超级伐木工并保留其性格。',
        }
        if a['id'] in notes: description+='\n本项目规则：'+notes[a['id']]
        products.append(dict(sku=sku,display_name=a['name'].replace('*','·'),category_id='item' if currency=='shop_points' else 'technology',
            product_type='single',currency=currency,price=price['reference'],purchase_limit=0 if a['id'] in ('P089','P103') else 1,
            enabled=1 if '--enable' in sys.argv else 0,sort_order=int(a['id'][1:]),icon=icon,description=description,ownership_id=marker,source_id=a['id'],
            source_current_price=price['current'],source_original_price=price['original'] or '',source_time=p['price_time'],
            price_date='2026-10-04',description_date='2026-09-29',ownership_quantity=quantity))
        fields={field:(value,label) for _,field,value,label in a['parsed']}
        if a['id']=='P018': fields.pop('technology_cost_refund_pct',None)  # refund only after completion
        if a['id'] in ('P023','P025'): fields={f:v for f,v in fields.items() if f=='starjoy_points'}
        if a['id']=='P094': fields['hero_attack_attribute_efficiency_pct']=(10,'英雄普攻属性成长效率')
        if a['id'] in ('P089','P103'): fields={'hero_basic_attack_growth':(.1*quantity,'每份英雄普攻成长')}
        for n,(field,(value,label)) in enumerate(fields.items(),1):
            rewards.append(dict(reward_id=f'{sku}_r{n}',sku=sku,reward_type='stat',target_id=field,amount=value,display_name=label,enabled=1))
    write('commerce_products',pf,pt,products);write('commerce_rewards',rf,rt,rewards)
    print(f'{len(products)} products, B batch enabled={"--enable" in sys.argv}')

if __name__=='__main__':main()
