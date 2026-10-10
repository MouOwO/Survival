-- Ownership-dependent effects are projected, never repeatedly written to saves.
local M = {}
local frame_profiles={}
local ids = {
    double_clear='commerce_p005', blademaster='commerce_p012', copper_axe='commerce_p017',
    time_technology='commerce_p018', saw='commerce_p020', lumberyard='commerce_p022',
    ssr_collector='commerce_p023', ur_collector='commerce_p025', teleporter='commerce_p026',
    instant_build='commerce_p032', muramasa='commerce_p042', treasury='commerce_p043',
    longinus='commerce_p048', orbital='lottery_orbital_cannon_core', nano='lottery_nano_cluster',
    barrier='lottery_dimensional_barrier', giant_mine='lottery_fallen_sky_mine',
    kunpeng='lottery_mountain_sea_kunpeng', stele='lottery_reincarnation_immortal_stele',
    sky_seal='lottery_sky_turning_seal', nirvana='lottery_immortal_nirvana',
    tower_seal='lottery_heaven_reaching_tower_seal', sovereign='lottery_sovereign_under_heaven',
    ember='lottery_ember_of_legacy', flame_wall='lottery_flame_wall', immortal='lottery_lumber_immortal',
    growth_ring='lottery_endless_growth_ring', lumber_fury='lottery_lumber_fury',
    fishing_rod='lottery_supreme_fishing_rod', omniscience='lottery_omniscience_blessing',
    time_orb='lottery_time_orb', chosen='lottery_chosen_hero', diary='lottery_struggle_diary',
}
function M.count(save, key)
    local n=tonumber(((save or {}).content_inventory or {})[ids[key] or key]) or 0
    return n==n and n<math.huge and math.max(0,math.floor(n)) or 0
end
function M.has(save,key) return M.count(save,key)>0 end
function M.owned(player_id,key)
    player_id=tonumber(player_id)
    if not player_id then return false end
    local profiles=require('systems/player_profile_service')
    if type(profiles.get_content_inventory_count)=='function' then
        return (profiles.get_content_inventory_count(player_id,ids[key] or key) or 0)>0
    end
    -- Compatibility with independent layouts/tests that supply the old service.
    local now=GameRules and GameRules.GetGameTime and GameRules:GetGameTime()
    local cached=now and frame_profiles[player_id]
    local profile
    if cached and cached.time==now then profile=cached.profile
    else
        profile=profiles.get_profile(player_id)
        if now then frame_profiles[player_id]={time=now,profile=profile} end
    end
    return profile and M.has(profile.save,key) or false
end
function M.invalidate(player_id) frame_profiles[tonumber(player_id)]=nil end
local tiers={
    {10,'hero_attributes_per_second',100},{50,'hero_attribute_growth',5},
    {100,'hero_final_damage_bonus_pct',10},{200,'hero_attack_bonus_pct',30},
    {300,'hero_attribute_bonus_pct',30},{400,'hero_attack_armor_reduction',30},
    {600,'hero_attribute_growth',40},{800,'hero_final_damage_bonus_pct',120},
    {1000,'hero_attack_armor_reduction',50},{1500,'hero_attribute_growth',80},
}
function M.project(save, base)
    save=save or {};base=base or {};local result={}
    local function add(field,n) result[field]=(result[field] or 0)+n end
    local level=math.max(0,tonumber(base.map_level) or 0)
    if M.has(save,'treasury') then add('hero_attribute_bonus_pct',level*2.5) end
    if M.has(save,'omniscience') then add('wall_health_bonus_pct',level);add('wall_health_per_second',level*5) end
    if M.has(save,'chosen') then
        for _,f in ipairs({'hero_damage_attack_growth','hero_attributes_per_damage','tower_damage_attack_growth'}) do add(f,level*.3) end
    end
    local ssr,ur=0,0
    for _,item in ipairs(require('config/generated/lottery_item_definitions').rows) do
        if M.count(save,item.item_id)>0 then
            if item.quality=='ssr' then ssr=ssr+1 elseif item.quality=='ur' then ur=ur+1 end
        end
    end
    if M.has(save,'ssr_collector') then
        for f,n in pairs({wall_health_bonus_pct=3,wall_armor=10,hero_damage_attack_growth=1,
            hero_attributes_per_damage=1,hero_attack_armor_reduction=.5,hero_attribute_bonus_pct=1}) do add(f,n*ssr) end
    end
    if M.has(save,'ur_collector') then
        for _,f in ipairs({'hero_attack_bonus_pct','hero_attribute_bonus_pct','hero_final_damage_bonus_pct','hero_health_bonus_pct','hero_armor_bonus_pct'}) do add(f,ur) end
    end
    if M.has(save,'muramasa') then add('hero_final_damage_bonus_pct',ur*4) end
    if M.has(save,'kunpeng') then
        local total=0
        for _,n in pairs(save.fishing_inventory or {}) do total=total+math.max(0,tonumber(n) or 0) end
        add('hero_attribute_bonus_pct',math.floor(total/100)*.05)
    end
    if M.has(save,'stele') then
        local total=0
        for _,n in pairs((save.archive or {}).clear_counts or {}) do total=total+math.max(0,tonumber(n) or 0) end
        add('hero_final_damage_bonus_pct',total*.07)
    end
    local count=M.count(save,'ember')
    for _,t in ipairs(tiers) do if count>t[1] then add(t[2],t[3]) end end
    -- base consists exclusively of persisted archive/shop effects. Runtime
    -- research, weapons and per-match growth are added after this projection.
    if M.has(save,'longinus') then
        for _,f in ipairs({'hero_attribute_bonus_pct','hero_attribute_growth','hero_final_damage_bonus_pct'}) do
            add(f,((tonumber(base[f]) or 0)+(result[f] or 0))*.05)
        end
    end
    return result
end
M.ids=ids
function M.shield(state, damage, health, maximum, now)
    state=state or {};damage=math.max(0,damage)
    if now>=(state.expires or 0) then state.remaining=0 end
    if damage>=health and now>=(state.ready_at or 0) and (state.remaining or 0)<=0 then
        state.remaining=maximum;state.expires=now+10;state.ready_at=now+30
    end
    local absorbed=math.min(damage,state.remaining or 0)
    state.remaining=(state.remaining or 0)-absorbed
    return damage-absorbed,state
end
return M
