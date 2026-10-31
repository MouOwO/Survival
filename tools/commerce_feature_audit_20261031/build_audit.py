"""Build a public SKU coverage matrix from WS4 snapshots and frozen3102 code.

One explicit pass: parse the two public catalogs once, index runtime identifier
references once, then join by SKU/field/ownership ID. No runtime timer or I/O.
Source references demonstrate wiring; they do not assert every item was bought.
"""
from pathlib import Path
import argparse,collections,csv,hashlib,json,re,sys

ROOT=Path(__file__).resolve().parents[2]
BUNDLE='d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
VIEW=Path('D:/Survival_发布候选/20261031_ws4_shop_recovery_v01_view')

SPECIAL={
 'video_p005':('通关次数双倍，仍受每日上限和幂等结算约束','systems/archive_settlement.lua','double_clear'),
 'video_p012':('持有单独解锁剑圣，不给予全局VIP','systems/hero_summon_access.lua','commerce_p012'),
 'video_p016':('2000光环/友军甲回血/敌军减甲，英雄死亡回落建造者','systems/commerce_titan_aura_service.lua','owned_source'),
 'video_p017':('每局一次传送自己的树；失败不耗次数','systems/commerce_runtime.lua',"action=='copper'"),
 'video_p018':('科技8%返还及即时研究','research/research_technology_service.lua','time_technology'),
 'video_p020':('每局一次清自身范围普通波次怪，排除Boss等','systems/commerce_runtime.lua',"action=='bomb'"),
 'video_p022':('两项基础科技各+5，仅授予一次','systems/commerce_runtime.lua',"{'RS-06','RS-08'}"),
 'video_p023':('按SSR不同种类投影','systems/commerce_effects.lua',"'ssr_collector'"),
 'video_p025':('按UR不同种类投影','systems/commerce_effects.lua',"'ur_collector'"),
 'video_p026':('D闪持有条件/位置验证/冷却；原生入口存在旁路','systems/commerce_runtime.lua',"action=='blink'"),
 'video_p032':('建造和升级即刻完成','systems/building_system.lua',"'instant_build'"),
 'video_p042':('每不同UR种类最终伤害+4%','systems/commerce_effects.lua',"'muramasa'"),
 'video_p043':('地图等级每级属性加成2.5%','systems/commerce_effects.lua',"'treasury'"),
 'video_p048':('存档/商城属性的5%独立投影；动态抽奖层遗漏','systems/commerce_effects.lua',"'longinus'"),
 'video_p061':('波次/无尽轨道炮，0.5秒一次持续10秒，范围/主人过滤','systems/commerce_runtime.lua','function M.orbital'),
 'video_p063':('波次Boss攻击减甲翻倍','systems/research_armor_reduction_service.lua',"'nano'"),
 'video_p065':('墙致命伤临时100%最大生命盾，10秒/30秒刷新','combat/damage_filter_service.lua',"'barrier'"),
 'video_p066':('巨大金矿合并名额、费用、人口和收益','systems/building_cost_quote.lua','giant_mine'),
 'video_p067':('每100条鱼属性0.05%','systems/commerce_effects.lua',"'kunpeng'"),
 'video_p068':('总通关每次最终伤害0.07%','systems/commerce_effects.lua',"'stele'"),
 'video_p075':('跟随英雄的现有武器光环特效，非新增原版资产','systems/commerce_runtime.lua','lottery_immortal_slaying_sword_array'),
 'video_p077':('转生怪伤害1.5倍；首次学新技能补重抽机会','systems/hero_skill_system.lua','commerce.skill_learned'),
 'video_p078':('10转额外5技能点；后购/后获刷新遗漏','systems/hero_progression_system.lua','commerce_nirvana_granted'),
 'video_p079':('持有解锁齐天大圣；明确不含魔法少女羁绊','systems/hero_summon_access.lua','lottery_monkey_king'),
 'video_p082':('消费资源直建七路终极塔，每人一座','systems/tower_fusion_service.lua','function M.commerce_build'),
 'video_p083':('英雄称号前缀','systems/commerce_runtime.lua','survival_commerce_title'),
 'video_p092':('主城完成赠送工人，融合继承性格/对树伤害翻倍','systems/worker_system.lua','function M.commerce_spawn_immortal'),
 'video_p094':('练功房75折/攻击属性+10%/武器双倍；两处部分实现','systems/hero_progression_system.lua',"'growth_ring'"),
 'video_p095':('拥有仙人时1~7级工人上限+1','systems/worker_system.lua','function M.refresh_commerce_capacity'),
 'video_p096':('S及以上钓鱼总概率翻倍，封顶100%','systems/fishing_service.lua',"'fishing_rod'"),
 'video_p102':('地图等级条件墙生命/每秒生命','systems/commerce_effects.lua',"'omniscience'"),
 'video_p103':('每份和严格门槛的叠加投影','systems/archive_stackable_items.lua','function M.project'),
 'video_p108':('击杀波次Boss本局攻击+2%，kill_id去重','systems/permanent_reward_effect_service.lua','commerce_assault_boss'),
 'video_p138':('地图等级条件造成伤害成长','systems/commerce_effects.lua',"'chosen'"),
 'video_p139':('在线福利每5基础收入多1，不是商城积分','systems/archive_online_rewards.lua','commerce_bonus_fifths'),
 'video_p147':('两个EX乘区及每局额外5重抽','systems/commerce_hero_privileges.lua','function M.for_player'),
 'video_p151':('牢笼/虚空之影来源20%增幅','systems/commerce_archive_source_bonus.lua','function M.project'),
 'points_welfare_zongzi':('库存上限150和最高阶段投影','systems/archive_stackable_items.lua','function M.project'),
}

GAPS={
 'video_p026':'确认缺口：原生D绕过持有/10秒冷却；本轮专项修复；距离/蓝耗另待确认',
 'video_p078':'部分接入：10转后获得道具未随profile刷新补5技能点',
 'video_p094':'部分接入：每击属性加成来源覆盖不全，且入场门槛未折扣',
 'video_p048':'部分接入：抽奖动态条件层未进入5%增幅',
 'video_p077':'代码已接入；首次学新技能/升级旧技能口径待确认',
}


def digest(raw):return hashlib.sha256(raw).hexdigest()
def load(path):return json.loads(path.read_bytes())
def read_csv(path):
    with path.open(encoding='utf-8-sig',newline='') as stream:
        return [row for row in csv.DictReader(stream) if not next(iter(row.values())).startswith('#')]
def escaped(value):return str(value).replace('|','/').replace('\n','；')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live-snapshot',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    live=load(args.live_snapshot)
    assert live['scope']=='WS4_PUBLIC_PRODUCT_CONFIGURATION_ONLY' and live['read_only'] is True
    assert live['player_or_order_rows_read'] is False and live['identity_tokens_read'] is False
    frozen=load(ROOT/'server/bundles'/BUNDLE/'bundle.json')
    wallet=live['archive_commerce_catalog']['rows'];cash=live['cash_products']
    assert live['archive_commerce_catalog']==frozen['configs']['commerce_catalog']
    sys.path.insert(0,str(ROOT/'server'))
    from archive_backend.commerce_catalog import build_catalog
    from payment_backend.csv_catalog import build
    current_wallet=build_catalog(ROOT)['products'];current_cash=build(ROOT)['catalog']['products']
    current={row['sku']:row for row in current_wallet}
    active_wallet={row['sku']:row for row in wallet if row['enabled']}
    active_cash={row['sku']:row for row in cash if row['enabled']}
    fields={field for row in [*active_wallet.values(),*active_cash.values()] for field in row['effects']}
    references={field:[] for field in fields};source_files=source_bytes=0
    # Build one identifier index over immutable runtime source. No P-by-N scan.
    for path in sorted((VIEW/'scripts/vscripts').rglob('*.lua')):
        name=path.relative_to(VIEW/'scripts/vscripts').as_posix()
        if not name.startswith(('systems/','combat/','research/','abilities/','modifiers/','core/')):continue
        raw=path.read_bytes();text=raw.decode('utf8','replace');source_files+=1;source_bytes+=len(raw)
        for number,line in enumerate(text.splitlines(),1):
            for token in set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*',line))&fields:
                references[token].append(dict(path='scripts/vscripts/'+name,line=number))
    assert all(references.values()),'A public stat lacks a frozen runtime consumer reference'
    coverage=[]
    gap_markers={row['item_id']:GAPS[row['sku']] for row in wallet if row['sku'] in GAPS}
    for sku in sorted(set(active_wallet)|set(active_cash)):
        row=active_wallet.get(sku) or active_cash[sku]
        name=row['title'];feature=SPECIAL.get(sku);evidence=[]
        if feature:
            path=VIEW/'scripts/vscripts'/feature[1];lines=path.read_text('utf8').splitlines()
            found=[n for n,line in enumerate(lines,1) if feature[2] in line]
            assert found,(sku,feature[1],feature[2]);evidence=[dict(path='scripts/vscripts/'+feature[1],line=found[0])]
        else:
            evidence=[references[field][0] for field in sorted(row['effects'])]
        if not evidence:
            if sku=='archive_pass_monthly':proof=('server/payment_backend/upgrade_monthly_pass.sql','CREATE OR REPLACE FUNCTION payments.entitlement_days')
            elif sku=='u_coin_recharge':proof=('server/payment_backend/ucoin_recharge.py','def product(')
            elif sku in ('special_lottery_ticket_single','video_p001'):proof=('scripts/vscripts/systems/lottery_http_settlement.lua','function M.')
            else:raise AssertionError('Missing explicit non-stat capability proof: '+sku)
            lines=(ROOT/proof[0]).read_text('utf8').splitlines()
            line=next(n for n,text in enumerate(lines,1) if proof[1] in text)
            evidence=[dict(path=proof[0],line=line)]
        if sku.startswith('video_bundle_'):
            capability='礼包完整成员、共享持有、VIP条件与静态属性结算'
        elif feature:capability=feature[0]
        elif sku=='archive_pass_monthly':capability='30天签到月卡/续期，权益由支付原子交付'
        elif sku=='u_coin_recharge':capability='G币充值：1元100币；原订单冻结报价'
        elif sku=='special_lottery_ticket_single' or sku=='video_p001':capability='金色奖池券库存发放及抽奖消耗'
        else:capability='已映射的静态属性：'+', '.join(sorted(row['effects']))
        inherited=[marker for marker in row.get('grants',{}).get('items',{}) if marker in gap_markers]
        status=GAPS.get(sku,'代码/目录已接入；未逐件真实购买和实机验收')
        if inherited:status='礼包继承成员边界：'+'；'.join(gap_markers[marker] for marker in inherited)
        coverage.append(dict(sku=sku,live_title=name,development_title=(current.get(sku) or {}).get('title',name),
            ownership_id=row['item_id'],channels=[label for label,values in [('wallet',active_wallet),('cash',active_cash)] if sku in values],
            description=row['description'],effects=row['effects'],capability=capability,
            bundle_component_ownership_ids=sorted(row.get('grants',{}).get('items',{})) if sku.startswith('video_bundle_') else [],
            status=status,evidence=evidence))
    behavior=['effects','price','currency','item_id','purchase_limit','enabled','ownership_quantity']
    behavior_changes=[dict(sku=row['sku'],fields=[key for key in behavior if current[row['sku']].get(key)!=row.get(key)])
        for row in wallet if any(current[row['sku']].get(key)!=row.get(key) for key in behavior)]
    statuses=read_csv(ROOT/'data/csv/商城兑换系统/commerce_import_status.csv')
    result=dict(schema=1,scope='READ_ONLY_PUBLIC_CONFIG_AND_FROZEN_3102_STATIC_AUDIT',
        baseline_release_sequence=2026103102,archive_hash=BUNDLE,cash_catalog_hash=live['cash_catalog_hash'],
        live_snapshot_sha256=digest(args.live_snapshot.read_bytes()),live_player_rows_read=0,
        counts=dict(wallet_total=len(wallet),wallet_enabled=len(active_wallet),cash_total=len(cash),cash_enabled=len(active_cash),
            duplicate_channel_skus=len(set(active_wallet)&set(active_cash)),distinct_active_skus=len(coverage),stat_fields=len(fields),
            indexed_source_files=source_files,indexed_source_bytes=source_bytes),
        wallet_behavior_differences_from_development=behavior_changes,
        development_cash_not_published=[dict(sku=row['sku'],title=row['title'],enabled=row['enabled']) for row in current_cash if row['sku'] not in {r['sku'] for r in cash}],
        title_or_description_differences=[row['sku'] for row in wallet if any(current[row['sku']].get(key)!=row.get(key) for key in ('title','description'))],
        disabled_wallet=[dict(sku=row['sku'],title=row['title']) for row in wallet if not row['enabled']],
        disabled_cash=[dict(sku=row['sku'],title=row['title']) for row in cash if not row['enabled']],
        nonready_source_rows=[row for row in statuses if row['status']!='ready'],
        field_consumers={key:references[key] for key in sorted(references)},coverage=coverage,
        validation_limits=['Source wiring does not prove all descriptions/numbers or every gameplay edge.',
            'No real player purchase, code redemption, grants, payment, FPS or multiplayer acceptance performed.',
            'Four partial-implementation cases were independently reproduced with current and frozen3102 actual Lua modules.'])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes((json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
    print(json.dumps(dict(status='COMMERCE_FULL_COVERAGE_AUDIT_SAVED',**result['counts'],wallet_behavior_differences=len(behavior_changes),
        development_cash_not_published=result['development_cash_not_published'],sha256=digest(args.output.read_bytes())),ensure_ascii=False))


if __name__=='__main__':main()
