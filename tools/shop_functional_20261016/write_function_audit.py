"""Record the reviewed scope; deliberately does not edit game configuration."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VIDEO = ROOT / 'design_refs/shop_catalog_20261016/video'
OUT = ROOT / 'design_refs/shop_functional_20261016/audit'
OUT.mkdir(parents=True, exist_ok=True)
with (ROOT/'design_refs/shop_catalog_20261016/未导入商品与原因.csv').open(encoding='utf-8-sig', newline='') as f:
    previous = list(csv.DictReader(f))
reviewed = json.loads((VIDEO/'catalog_reviewed.json').read_text(encoding='utf-8-sig'))
video_items = {x['source_id']: x for x in reviewed['all_products'] if x.get('source_id')}
new = {x['source_id']: x for x in json.loads((VIDEO/'new_items_reviewed.json').read_text(encoding='utf-8-sig'))['items']}

reasons = {
    'P002': ('preserve_currency_policy', '普通抽奖券目前仅玩法产出；不因本轮功能补录更改付费售卖策略。视频存在800U币/100积分两个渠道，不能默认为折扣。'),
    'P003': ('requires_map_experience_design', '当前地图等级按有效在线时长成长，没有4000点地图经验与在线秒数的正式换算、50级门槛、每天3次消耗链。'),
    'P009': ('requires_craftsman_system', '缺匠神经验/等级/磨刀石消耗/薪火奖励链，50个必须按实际消耗品定义。'),
    'P010': ('requires_craftsman_system', '同P009；不能把购买即写经验字段等同完整可使用磨刀石。'),
    'P034': ('requires_map_experience_design', '2750地图经验、21级门槛和每日10次，缺与有效在线时长系统的正式换算与消耗行为。'),
    'P035': ('requires_map_experience_design', '180地图经验、等级/每日10次使用规则及转换未定义。'),
    'P036': ('requires_expiring_progression_entitlement', '30天地图经验+50%需要可续期权限、可靠时间结算；不能填永久stat代替。'),
    'P039': ('external_platform_blocked', 'KK平台宠物探险/平台地图积分无本项目服务或平台奖励接口；无法通过本地加数字实现外部权限。'),
    'P040': ('requires_map_experience_design', '1050地图经验、11至20级、每日10次，缺正式经验转换和使用链。'),
    'P044': ('requires_persistent_equipment', '存档装备属性额外20%依赖永久装备来源与实例；不能把所有存档奖励或局内武器乘1.2冒充原效果。'),
    'P059': ('requires_persistent_equipment', '日保底双传说词条存档装备缺永久装备实例、词条随机、每日领取及去重持久化。'),
    'P060': ('requires_hero_and_equipment_mechanic', '龙骑尖兵进化外观与塔融合进英雄机制均缺；当前终极塔融合方向不同。'),
    'P073': ('requires_auto_training_and_mode_design', '自动训练可挂现有worker_training_queue_service，但没有自动训练开关/缺钱暂停/解锁事件重试；天狱信仰+30%与当前全模式固定通关信仰不等同，不能偷换为全模式倍率。'),
    'P074': ('requires_magic_equipment', '每10波发魔导器并光明版进阶依赖未有魔导器/装备规则，发普通局内物品不等同原效果。'),
    'P080': ('requires_treasure_reroll_definition', '每次获得宝物时重随机/魔法卡与当前肉鸽免费重抽并非同一机制。'),
    'P081': ('requires_magic_equipment', '十转发丹、吞噬魔导器、保存属性及去重，缺配套魔导器实例系统。'),
    'P093': ('requires_exact_starting_equipment', '468秒实看是成长之剑+烈焰之甲；项目只有成长之剑和铁甲。若做明确改写名称的本项目版可新增，不能不告知地把烈焰之甲换铁甲；塔每次造成伤害成长也不能只监听普通攻击。'),
    'P115': ('requires_magic_card_system', '视频神赐精粹=开局魔法卡+1，旧近名神赐精神=金矿最终产量+3，不能当同一商品。'),
    'P141': ('missing_recorded_description', '仅SSR/名称/永久/2388积分有证据，录屏未悬停，不能编造效果。'),
    'P142': ('missing_recorded_description', '同P141；未出现可核准的效果说明。'),
    'P143': ('missing_recorded_description', '同P141；未出现可核准的效果说明。'),
    'P144': ('missing_recorded_description', '同P141；未出现可核准的效果说明。'),
    'P148': ('requires_persistent_equipment', '已有双传说词条存档装备额外两个传奇词条，缺装备实例/随机词条/写存档完整链。静态数值可做但不足以上架原商品。'),
    'P149': ('current_early_clear_contract_incompatible', '原功能提前挑战-180秒/提前通关难度系数-50%。当前提前通关只有全局60秒冷却，request_early_final无player_id且无提前难度系数；减180秒归零并使个人权益扩散团队。墙致命周边眩晕还需半径、触发与存活规则，暂不可宣称整品。'),
    'P150': ('requires_pet_affixes_and_treasure_reroll', '宠物额外2词条与每局宝物重抽5次缺完整机制；原文英雄攻击全属性+60%不可擅改固定60。'),
}
cosmetic_only = {'P006','P007','P008','P047','P064','P091','P146'}
new_heroes = {'P041','P062','P076','P085','P145'}
for sid in cosmetic_only:
    reasons[sid] = ('cosmetic_product_excluded_this_scope', '视频主体为城墙/英雄/翅膀/宠物皮肤，本轮不导入皮肤商品；附带数值可以在单独明确功能版中实现，但不可继续承诺未绑定外观。')
for sid in new_heroes:
    reasons[sid] = ('requires_missing_hero_and_skills', '角色/专属技能或羁绊未正式接入；不能只发基础属性，或改用相近英雄模型，就声称对应英雄商品完整可用。')

parameters = {
    'P028': {
        'decision':'implement_functional_edition', 'canonical_ownership':'commerce_p028',
        'regular_price':23800, 'currency':'u_coin',
        'stats':{'lumberjack_efficiency':2,'wood_per_second':3,'gold_per_second':2,'gold_mine_efficiency_pct':10,'gold_mine_build_cap':1,'starjoy_points':238},
        'observed_frame':'t120000.jpg',
        'description_contract':'熟练工头·永久（功能版）；以上逐项动态效果；购买后自动激活。功能版不包含农民外观，和新手礼包共用持有记录。',
        'reason':'新手礼包唯一被阻塞成员P028。去掉农民皮肤承诺，保留已核准全部数值即可启用整包；P018/P020/P032已实现。'
    },
    'P016': {
        'decision':'implement_functional_edition', 'canonical_ownership':'commerce_p016',
        'regular_price':29800, 'currency':'u_coin',
        'aura':{'radius':2000,'friendly_armor':100,'friendly_flat_health_regen_per_second':1000,'enemy_armor_reduction':30},
        'stats':{'starjoy_points':298}, 'observed_frame':'t111000.jpg',
        'description_contract':'泰坦护盾·永久（功能版）；以自有建筑师为中心2000范围的友方护甲/固定回血和敌方减甲，明确同商品光环不叠加及离开恢复；不包含腾龙光环皮肤。',
        'reason':'须真正范围光环、友敌筛选、生命周期处理，不得把100护甲/1000回血直接永久加给全场。'
    },
    'P079': {
        'decision':'implement_functional_edition', 'canonical_ownership':'lottery_monkey_king',
        'regular_price':5000, 'currency':'shop_points',
        'stats':{'map_level':1,'hero_attack_armor_reduction':10,'hero_basic_attack_growth':10,'hero_attribute_growth':10,'hero_attack_bonus_pct':10,'hero_attribute_bonus_pct':10,'hero_final_damage_bonus_pct':10,'starjoy_points':200},
        'observed_frame':'t435000.jpg',
        'description_contract':'齐天大圣·永久（功能版）；以上数值和解锁本项目现有齐天大圣；不包含魔法少女羁绊、不额外承诺开局一转。',
        'reason':'hero_summon_access已识别lottery_monkey_king；复用既有身份避免重复购买/重复全局VIP。旧玩家已存属性及旧lottery配置不改。',
        'native_test':'tools/shop_functional_20261016/test_monkey_ownership.lua', 'native_test_groups_passed':9,
        'summon_cost_review':'hero_summon_system.validate/summon无资源扣减；仍校验自有祭坛或建筑师、当前未召、有效位置与资源加载。'
    },
    'P147': {
        'decision':'implement_complete_after_new_consumers_verified', 'canonical_ownership':'commerce_p147',
        'regular_price':5000, 'currency':'shop_points',
        'stats':{'hero_attack_armor_reduction':25,'hero_basic_attack_growth':25,'hero_attribute_growth':25,'hero_attack_bonus_pct':25,'hero_attribute_bonus_pct':25,'hero_final_damage_bonus_pct':25,'hero_attack_armor_reduction_pct':8,'hero_attack_attribute_efficiency_pct':8},
        'new_mechanics':{'independent_attribute_ex_pct':8,'independent_final_damage_ex_pct':8,'hero_skill_rerolls_once_per_match':5},
        'observed_frame':'t320000.jpg',
        'consumer_candidates':['hero_combat_stat_service:gameplay_attribute_multiplier','hero_combat_stat_service:survival_gameplay_final_damage_pct','hero_skill_choice_service:rerolls_by_player/select_request/profile_changed/HERO_SUMMONED'],
        'reason':'源tooltip完整、无新模型/外部平台/未知装备系统依赖。EX独立乘区须与普通25%分别计算；5次重抽须每局一次、重连/反复profile刷新不重发、pure不穿透。'
    }
}
entries=[]
for old in previous:
    sid=old['审阅ID']; item=video_items.get(sid,{})
    if sid in parameters:
        entry={'source_id':sid,'name':old['商品名称'],**parameters[sid]}
    else:
        decision,reason=reasons[sid]
        entry={'source_id':sid,'name':old['商品名称'],'decision':decision,'reason':reason}
    entry['previous_status']=old['状态']
    entry['source_evidence']=item.get('evidence_frame')
    entry['previous_recorded_reason']=old['未导入原因']
    if sid in new: entry['recorded_full_effect_text']=new[sid].get('full_effect_text')
    entries.append(entry)

report={
    'scope':'只读商品功能审计，正式配置由主代理接入；不是部署完成清单。',
    'review_date':'2026-10-16', 'previous_missing_count':len(previous),
    'actually_viewed_frames':['t111000.jpg','t120000.jpg','t435000.jpg','t468000.jpg','t320000.jpg','t330000.jpg'],
    'rules':['沿用现有正式价格，不同步视频8折促销。','不改变普通抽奖券/地图经验货币策略。','有完整功能和消费者验证才上架；不以基础数值冒充缺失装备/英雄系统。','本项目功能版必须删除未接入皮肤及羁绊承诺，说明文本如实。'],
    'recommend_implement':['P028','video_bundle_b003','P016','P079','P147'],
    'entries':entries,
    'source_paths':['design_refs/shop_catalog_20261016/video/new_items_reviewed.json','design_refs/shop_catalog_20261016/video/transcript.txt','data/csv/商城兑换系统/commerce_import_status.csv','data/csv/抽奖系统/lottery_item_definitions.csv'],
    'known_existing_wrong_text':[{'id':'lottery_monkey_king','detail':'旧lottery配置描述错误写了解锁魔法少女，并有与视频不一致的旧三围20/羁绊30等。为免变更旧玩家已存属性，本轮不改旧奖励；新商城商品独立stat按新核准值，复用持有ID。'}]
}
(OUT/'functional_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
lines=['# 商城非皮肤功能复查','',report['scope'],'','已实际查看六张关键帧；此前未导入41个单品逐一给出结果。','',
       '本轮推荐：熟练工头功能版、恢复新手礼包、泰坦护盾功能版、齐天大圣功能版；悲叹之种在独立EX倍率和每局重抽接口验证后可完整导入。现有正式价格保持不变。','',
       '齐天大圣解锁沿用 `lottery_monkey_king`；生产访问检查原生Lua 9组通过，没有额外全局VIP或玩家间越权。召唤过程本身不扣资源，仍遵守祭坛/建筑师、英雄唯一、有效位置和加载条件。','',
       '| ID | 商品 | 本轮判断 |','|---|---|---|']
for e in entries:
    lines.append('|'+e['source_id']+'|'+e['name']+'|'+e.get('reason','').replace('|','/')+'|')
lines += ['', '精确参数、源帧和接口位置见 `functional_audit.json`。', '',
          'P149天之锁的原版提前挑战规则与当前全局60秒提前通关机制不兼容，不能简单减180秒；P073天道傀儡的天狱信仰与现有全模式通关固定信仰也不等价，暂不上架冒充原版。',
          '本审计不修改正式配置，不更改旧lottery存档数值；缺说明4个SSR、外部KK探险及不存在的装备/英雄系统均有明确原因。','']
(OUT/'functional_audit.md').write_text('\n'.join(lines),encoding='utf8')
print(json.dumps({'reviewed':len(entries),'recommended':report['recommend_implement'],'output':str(OUT.relative_to(ROOT))},ensure_ascii=False))
