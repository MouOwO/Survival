-- Audit the native-AS sources that underpin the explicit BAT-only policy.
-- New positive enemy sources must revoke/update the policy before shipping.
package.path=(arg[1] and arg[1].."/scripts/vscripts/?.lua;" or "").."scripts/vscripts/?.lua;"..package.path
local NEGATIVE_BUFFS = {
    debuff_polar_attack_slow = true,
    debuff_airspace_attack_slow = true,
    debuff_hero_ice_cone_attack_slow = true,
}
local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
local function audited_sources(config)
    if type(config.buffs) ~= "table" or type(config.rogue_effects) ~= "table"
        or type(config.rogue_params) ~= "table" then return false end
    local seen, effects, values = {}, 0, 0
    for _, row in ipairs(config.buffs) do
        if type(row) ~= "table" then return false end
        if row.enabled ~= false and (row.effect_type == "attack_speed_pct"
            or row.effect_type == "attack_speed_bonus") then
            if not NEGATIVE_BUFFS[row.buff_id] or seen[row.buff_id]
                or row.effect_type ~= "attack_speed_pct" or row.polarity ~= "negative"
                or not finite(row.default_value) or row.default_value > 0 then return false end
            seen[row.buff_id] = true
        end
    end
    for id in pairs(NEGATIVE_BUFFS) do if not seen[id] then return false end end
    for _, row in ipairs(config.rogue_effects) do
        if type(row) ~= "table" then return false end
        if row.enabled ~= false and row.effect_type == "wall_attacker_attack_speed_pct" then
            if row.effect_id ~= "frozen_wall_slow" or row.target_selector ~= "matching_enemy"
                or row.owner_scope ~= "player" then return false end
            effects = effects + 1
        end
    end
    for _, row in ipairs(config.rogue_params) do
        if type(row) ~= "table" then return false end
        if row.enabled ~= false and row.effect_id == "frozen_wall_slow"
            and row.param_name == "value" then
            if row.value_type ~= "number" or not finite(row.number_value)
                or row.number_value > 0 then return false end
            values = values + 1
        end
    end
    return effects == 1 and values == 1
end

local config={buffs=require("config/generated/buff_definitions").rows,
    rogue_effects=require("config/generated/rogue_reward_effects").rows,
    rogue_params=require("config/generated/rogue_reward_effect_params").rows}
assert(audited_sources(config),"BAT-only contract invalidated: re-audit new enemy native-AS writers")
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
for id in pairs(NEGATIVE_BUFFS) do
    local changed=copy(config)
    for _,row in ipairs(changed.buffs) do if row.buff_id==id then row.default_value=10 end end
    assert(not audited_sources(changed),"guard catches positive native buff "..id)
end
local changed=copy(config)
changed.buffs[#changed.buffs+1]={buff_id="future_frenzy",effect_type="attack_speed_pct",polarity="positive",default_value=100}
assert(not audited_sources(changed),"new native-AS effect requires audit")
changed=copy(config)
for _,row in ipairs(changed.rogue_params) do
    if row.effect_id=="frozen_wall_slow" and row.param_name=="value" then row.number_value=50 end
end
assert(not audited_sources(changed),"positive wall-attacker speed caught")
changed=copy(config)
changed.rogue_effects[#changed.rogue_effects+1]={effect_id="future_enemy",effect_type="wall_attacker_attack_speed_pct"}
assert(not audited_sources(changed),"new enemy speed effect requires audit")
print("WAVE_NATIVE_ATTACK_CAP_SOURCES_PASS current negative-only sources and six deliberate future regressions")
