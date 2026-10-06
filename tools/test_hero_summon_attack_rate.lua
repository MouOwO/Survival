package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) return value end
IsServer = function() return true end
MODIFIER_PROPERTY_FIXED_ATTACK_RATE = 40
local name = "modifier_hero_exclusive_summon_attack_rate"
local modifier_class = require("modifiers/" .. name)
local rate = require("systems/hero_summon_attack_rate")
local function near(actual, expected)
    assert(actual and math.abs(actual - expected) < 1e-8,
        tostring(actual) .. " ~= " .. tostring(expected))
end
local function summon()
    local unit = {modifiers = {}, additions = 0, bat_writes = 0, bat = 1}
    function unit:IsNull() return self.removed == true end
    function unit:FindModifierByName(key) return self.modifiers[key] end
    function unit:SetBaseAttackTime(value) self.bat = value; self.bat_writes = self.bat_writes + 1 end
    function unit:AddNewModifier(caster, _, key, params)
        assert(caster and key == name)
        self.additions = self.additions + 1
        if self.fail_modifier then return nil end
        local mod = setmetatable({sent = 0, refreshes = 0}, {__index = modifier_class})
        function mod:SetHasCustomTransmitterData() end
        function mod:SendBuffRefreshToClients() self.sent = self.sent + 1 end
        function mod:ForceRefresh() self.refreshes = self.refreshes + 1; self:OnRefresh({}) end
        mod:OnCreated(params)
        self.modifiers[key] = mod
        return mod
    end
    return unit
end
local source = {runtime_aps = 1.4, modifiers = {}}
function source:IsNull() return self.removed == true end
function source:FindModifierByName(key) return self.modifiers[key] end
function source:GetAttacksPerSecond(ignore_temporary)
    assert(ignore_temporary == false)
    return self.runtime_aps
end
local unit = summon()
near(rate.apply(unit, source, 1), 1.4)
assert(unit.bat == 1 and unit.bat_writes == 0,
    "preserve native BAT so fixed rate can scale the attack animation")
source.modifiers.modifier_debug_fixed_attack_rate = {
    GetModifierFixedAttackRate = function() return 0.1 end,
}
-- Native cached source getter can still be stale during addspeed. The fixed
-- source interval and the summon modifier must both become 0.1 seconds.
near(rate.current(source, 1), 10)
local aps, interval = rate.apply(unit, source, 1)
near(aps, 10); near(interval, 0.1)
local mod = unit.modifiers[name]
near(mod:GetModifierFixedAttackRate(), 0.1)
near(mod:AddCustomTransmitterData().attack_interval, 0.1)
assert(mod.refreshes == 1)
local sent, writes = mod.sent, unit.bat_writes
for _ = 1, 20 do near(rate.apply(unit, source, 1), 10) end
assert(mod.sent == sent and mod.refreshes == 1 and unit.bat_writes == writes,
    "unchanged polling must not reset attack state")
near(rate.apply(unit, source, 1, 50), 5)
source.modifiers.modifier_debug_fixed_attack_rate = nil
source.runtime_aps = 2.5
near(rate.apply(unit, source, 10), 2.5)
unit.modifiers[name] = nil
near(rate.apply(unit, source, 10), 2.5)
assert(unit.additions == 2, "the next synchronization restores a missing rate modifier")
source.runtime_aps = 500
near(rate.apply(unit, source, 1), 100)
source.modifiers.modifier_debug_fixed_attack_rate = {
    GetModifierFixedAttackRate = function() return 0 / 0 end,
}
source.runtime_aps = 4
near(rate.current(source, 10), 4)
source.removed = true
near(rate.apply(unit, source, 7), 7)
assert(unit.bat == 1 and unit.bat_writes == 0,
    "rate changes must never replace native BAT with the fixed interval")
local seconds_source = {GetSecondsPerAttack = function(_, ignore)
    assert(ignore == false); return 0.25
end}
near(rate.current(seconds_source, 1), 4)
local failed = summon(); failed.fail_modifier = true
local result, _, reason = rate.apply(failed, nil, 10)
assert(result == nil and reason == "attack_rate_modifier_failed"
    and failed.survival_attack_speed == nil and failed.bat_writes == 0,
    "failed actual application must not report success through the display cache")
unit.removed = true
assert(rate.apply(unit, source, 10) == nil)
print("HERO_SUMMON_ATTACK_RATE_PASS source fixed/native rate, actual modifier, refresh, no repeated attack resets, inheritance, removed modifiers, fallback, clamp and failure")
