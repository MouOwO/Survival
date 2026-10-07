-- Presentation only. Inputs contain fixed sources, never accumulated growth.
local M = {}
local function n(v) return tonumber(v) or 0 end
function M.static_technology(snapshot)
    local result={}
    for key,value in pairs((snapshot.final or {}).hero or {}) do result[key]=value end
    result.attack_flat=n(result.attack_flat)-n(((snapshot.growth or {}).hero or {}).attack)
    return result
end
function M.calculate(a)
    local b,t,p,e,w,r,x = a.base,a.technology,a.permanent,a.equipment,a.weapon,a.progression,a.essence
    local result = {}
    local attr_flat = n(t.all_attributes_flat)+n(p.hero_all_attributes_flat)+n(p.hero_initial_attributes)
        + n(p.hero_attributes_per_level)*math.max(1,n(a.level))
        + n(e.all_attributes_flat)+n(r.display_all_attributes)
    local attr_multiplier = (1+n(p.hero_attribute_bonus_pct)/100)
        *(1+n(r.rebirth_level)*n(p.hero_rebirth_attribute_bonus_pct)/100)
        *(1+n(x.all_attributes_pct)/100)
    local static_intellect = 0
    for _,key in ipairs({"strength","agility","intellect"}) do
        local total = (n(b[key])+n(w["base_"..key])+attr_flat)*attr_multiplier
        result["display_"..key.."_bonus"] = total-n(b[key])
        result["display_"..key.."_pct"] = (attr_multiplier-1)*100
        if key=="intellect" then static_intellect=total end
    end
    local attack_base = n(b.attack_max)+n(b.intellect)*n(a.intellect_attack_per_point)
    local flat = n(w.base_attack_max)+n(e.attack_flat)+n(t.attack_flat)
        +n(p.hero_attack_flat)+n(p.hero_initial_attack)+n(r.attack_flat)
    local multiplier = (1+(n(t.attack_bonus_pct)+n(p.hero_attack_bonus_pct)+n(x.attack_bonus_pct))/100)
        *(tonumber(a.fixed_exclusive_multiplier) or 1)
    result.display_attack_bonus = (n(b.attack_max)+static_intellect*n(a.intellect_attack_per_point)+flat)*multiplier-attack_base
    result.display_attack_pct = (multiplier-1)*100
    local armor_base = n(a.base_armor)
    local armor = n(e.armor_flat)~=0 and n(e.armor_flat) or armor_base
    result.display_armor_bonus = (armor+n(p.hero_initial_armor)+n(p.team_hero_wall_armor_bonus))
        *(1+n(p.hero_armor_bonus_pct)/100)-armor_base
    result.display_armor_pct = n(p.hero_armor_bonus_pct)
    local bat = math.max(.1,n(a.configured_attack_time))
    local speed_pct = n(e.attack_speed_pct)+n(t.attack_speed_bonus_pct)+n(p.hero_attack_speed_bonus_pct)
    result.display_attack_speed_bonus = math.max(.01,1+speed_pct/100)/math.max(.1,n(a.final_attack_time))-1/bat
    result.display_attack_speed_pct = speed_pct
    if a.debug_attack then result.display_attack_bonus=0;result.display_attack_pct=0 end
    if a.debug_attack_speed then result.display_attack_speed_bonus=0;result.display_attack_speed_pct=0 end
    return result
end
return M
