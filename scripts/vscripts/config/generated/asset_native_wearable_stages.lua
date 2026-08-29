-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: asset_native_wearable_stages.csv
local M = {}
M.rows = {
    { asset_id = "tower_death_templar_assassin", hero_unit_name = "npc_dota_hero_templar_assassin", body_model = "models/heroes/lanaya/lanaya.vmdl", display_name = "Templar Assassin基础外观 死亡之塔", enabled = true, notes = "死亡路线第一阶段；ItemDef仅来自本地items_game.txt的default_item" },
    { asset_id = "tower_death_nevermore_sundered_souls", hero_unit_name = "npc_dota_hero_skeleton_king", body_model = "models/heroes/wraith_king/wraith_king.vmdl", display_name = "Wraith King基础外观 碎骨重炮", enabled = true, notes = "死亡路线第二阶段；保留旧资源ID以驱动技能和弹道分支" },
    { asset_id = "tower_death_warlock_seam_ripper", hero_unit_name = "npc_dota_hero_phantom_assassin", body_model = "models/heroes/phantom_assassin/phantom_assassin.vmdl", display_name = "Phantom Assassin基础外观 死神榴弹炮", enabled = true, notes = "死亡路线第三阶段；不挂载Persona默认物品" },
    { asset_id = "tower_frost_lich_rime_lord", hero_unit_name = "npc_dota_hero_lich", body_model = "models/heroes/lich/lich.vmdl", display_name = "Lich基础外观 冰霜之塔", enabled = true, notes = "冰霜路线第一阶段" },
    { asset_id = "tower_frost_crystal_maiden_winter_raven", hero_unit_name = "npc_dota_hero_crystal_maiden", body_model = "models/heroes/crystal_maiden/crystal_maiden.vmdl", display_name = "Crystal Maiden基础外观 寒冰尖塔", enabled = true, notes = "冰霜路线第二阶段" },
    { asset_id = "tower_frost_ancient_apparition", hero_unit_name = "npc_dota_hero_ancient_apparition", body_model = "models/heroes/ancient_apparition/ancient_apparition.vmdl", display_name = "Ancient Apparition基础外观 极地方尖碑", enabled = true, notes = "冰霜路线第三阶段" },
    { asset_id = "tower_lightning_zeus_tempest", hero_unit_name = "npc_dota_hero_zuus", body_model = "models/heroes/zeus/zeus.vmdl", display_name = "Zeus基础外观 闪电塔", enabled = true, notes = "闪电路线第一阶段" },
    { asset_id = "tower_lightning_leshrac", hero_unit_name = "npc_dota_hero_leshrac", body_model = "models/heroes/leshrac/leshrac.vmdl", display_name = "Leshrac基础外观 闪电魔塔", enabled = true, notes = "闪电路线第二阶段" },
    { asset_id = "tower_lightning_razor_voidstorm", hero_unit_name = "npc_dota_hero_razor", body_model = "models/heroes/razor/razor.vmdl", display_name = "Razor基础外观 雷电扩散", enabled = true, notes = "闪电路线第三阶段" },
    { asset_id = "tower_machine_gun_sniper_occultist", hero_unit_name = "npc_dota_hero_sniper", body_model = "models/heroes/sniper/sniper.vmdl", display_name = "Sniper基础外观 机枪塔", enabled = true, notes = "机枪路线第一阶段" },
    { asset_id = "tower_machine_gun_bounty_heartless", hero_unit_name = "npc_dota_hero_bounty_hunter", body_model = "models/heroes/bounty_hunter/bounty_hunter.vmdl", display_name = "Bounty Hunter基础外观 赏金机枪", enabled = true, notes = "机枪路线第二阶段" },
    { asset_id = "tower_machine_gun_windranger_rising_gale", hero_unit_name = "npc_dota_hero_windrunner", body_model = "models/heroes/windrunner/windrunner.vmdl", display_name = "Windranger基础外观 爆矢加特林", enabled = true, notes = "机枪路线第三阶段" },
    { asset_id = "tower_multi_medusa_anamnessa", hero_unit_name = "npc_dota_hero_vengefulspirit", body_model = "models/heroes/vengeful/vengeful.vmdl", display_name = "Vengeful Spirit基础外观 多重塔", enabled = true, notes = "多重路线第一阶段" },
    { asset_id = "tower_multi_drow_dread_retribution", hero_unit_name = "npc_dota_hero_luna", body_model = "models/heroes/luna/luna.vmdl", display_name = "Luna基础外观 穿透弩炮", enabled = true, notes = "多重路线第二阶段" },
    { asset_id = "tower_multi_vengeful_shen_screeauk", hero_unit_name = "npc_dota_hero_medusa", body_model = "models/heroes/medusa/medusa.vmdl", display_name = "Medusa基础外观 炙热巨箭塔", enabled = true, notes = "多重路线第三阶段" },
    { asset_id = "tower_keeper_of_the_light", hero_unit_name = "npc_dota_hero_storm_spirit", body_model = "models/heroes/storm_spirit/storm_spirit.vmdl", display_name = "Storm Spirit基础外观 神秘之塔", enabled = true, notes = "神秘路线第一阶段；保留已有资源ID避免转职引用失效" },
    { asset_id = "tower_laser_od_blackgate", hero_unit_name = "npc_dota_hero_wisp", body_model = "models/heroes/wisp/wisp.vmdl", display_name = "Io基础外观 魔能炮", enabled = true, notes = "神秘路线第二阶段；本地经济数据无可挂载基础模型物品" },
    { asset_id = "tower_laser_death_prophet_brightshroud", hero_unit_name = "npc_dota_hero_tinker", body_model = "models/heroes/tinker/tinker.vmdl", display_name = "Tinker基础外观 魔能之眼", enabled = true, notes = "神秘路线第三阶段；激光行为继续读取tower_laser_effects.csv" },
    { asset_id = "tower_anti_air_gyro_swooping", hero_unit_name = "npc_dota_hero_gyrocopter", body_model = "models/heroes/gyro/gyro.vmdl", display_name = "Gyrocopter基础外观 防空塔", enabled = true, notes = "防空路线第一阶段" },
    { asset_id = "tower_anti_air_batrider_empiric", hero_unit_name = "npc_dota_hero_batrider", body_model = "models/heroes/batrider/batrider.vmdl", display_name = "Batrider基础外观 防空火炮", enabled = true, notes = "防空路线第二阶段" },
    { asset_id = "tower_anti_air_skywrath_empyrean", hero_unit_name = "npc_dota_hero_skywrath_mage", body_model = "models/heroes/skywrath_mage/skywrath_mage.vmdl", display_name = "Skywrath Mage基础外观 空域霸主", enabled = true, notes = "防空路线第三阶段" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["asset_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
