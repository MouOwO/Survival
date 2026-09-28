local buildings = require("config/buildings_config")
local routes = require("config/tower_route_config")
local M = {}
-- Presentation only: never write combat values back to the unit.
function M.apply(unit, snapshot)
    if not unit then return snapshot end
    local raw = tostring(unit.survival_building_id or "")
    if raw == "" and unit.GetUnitName then raw = tostring(unit:GetUnitName()) end
    local id = raw:gsub("^building_", "")
    local definition = buildings[raw] or buildings[id] or buildings["building_" .. id]
    if not definition then return snapshot end
    snapshot.building_id = id
    local level = tonumber(unit.survival_level) or tonumber(snapshot.level) or 1
    local row = (definition.levels or {})[level] or {}
    local stats = {attack_pct=tonumber((unit.survival_hud_stat_bonuses or {}).attack_pct) or 0,
        armor_pct=tonumber((unit.survival_hud_stat_bonuses or {}).armor_pct) or 0,
        health_pct=tonumber((unit.survival_hud_stat_bonuses or {}).health_pct) or 0}
    local static = unit.survival_hud_stat_bonuses or {}
    for key,value in pairs(static) do stats[key]=tonumber(value) or 0 end
    if id == "wall" then
        stats.health_base = tonumber(row.health)
        stats.armor_base = tonumber(unit.survival_base_war3_armor)
            or tonumber(row.war3_armor or row.armor)
        stats.health_bonus = tonumber(static.health_bonus) or 0
        stats.armor_bonus = tonumber(static.armor_bonus) or 0
    elseif id == "arrow_tower" then
        local route = routes.current({level=level,tower_class=unit.survival_tower_class}) or {}
        stats.attack_base = tonumber(unit.survival_hud_base_attack)
            or tonumber(route.base_attack_damage)
        stats.attack_bonus = tonumber(static.attack_bonus) or 0
        for _,key in ipairs({"attack_flat","attack_technology_flat","attack_technology_pct","attack_permanent_flat","attack_permanent_pct"}) do
            stats[key] = tonumber(static[key]) or 0
        end
        -- These are fixed talent modifiers. The separate kill/wave and hit
        -- growth modifiers are deliberately absent from the allowlist.
        local fixed_pct = 0
        if unit.FindModifierByName then
            for _, name in ipairs({"modifier_rogue_base_tower_attack", "modifier_rogue_tower_attack_projection",
                "modifier_rogue_weakening_attack"}) do
                local modifier = unit:FindModifierByName(name)
                if modifier and modifier.GetModifierBaseDamageOutgoing_Percentage then
                    local ok, value = pcall(modifier.GetModifierBaseDamageOutgoing_Percentage, modifier)
                    if ok then fixed_pct = fixed_pct + (tonumber(value) or 0) end
                end
            end
        end
        stats.attack_talent_pct = fixed_pct
        stats.attack_pct = ((1+stats.attack_pct/100)*math.max(0,1+fixed_pct/100)-1)*100
        if stats.attack_base then
            stats.attack_bonus = (stats.attack_base + stats.attack_bonus) * math.max(0,1+fixed_pct/100)-stats.attack_base
        end
    end
    snapshot.building_stat_details = stats
    return snapshot
end
return M
