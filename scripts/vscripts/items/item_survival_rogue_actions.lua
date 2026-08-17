local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")

item_survival_rogue_nuclear_bomb = class({})
local function is_protected_monster(unit)
    return unit.survival_is_boss == true
        or unit.survival_boss_role ~= nil
        or unit.survival_monster_role == "wave_leader"
        or unit.survival_monster_role == "assault_boss"
        or unit.survival_monster_role == "boss"
        or unit:HasModifier("modifier_boss")
end

function item_survival_rogue_nuclear_bomb:OnSpellStart()
    if self.survival_nuclear_started == true then return end
    self.survival_nuclear_started = true
    if self.SetActivated then self:SetActivated(false) end

    local targets = {}
    for _, unit in ipairs(Entities:FindAllByClassname("npc_dota_creature") or {}) do
        if unit and not unit:IsNull() and unit:IsAlive()
            and unit:GetTeamNumber() == DOTA_TEAM_BADGUYS
            and (unit.survival_is_wave_monster == true
                or unit.survival_is_challenge_monster == true)
            and not is_protected_monster(unit) then
            targets[#targets + 1] = unit
        end
    end

    local item = self
    local caster = self:GetCaster()
    local next_target = 1
    local batch_size = math.max(1,
        math.floor(tonumber(self.survival_nuclear_batch_size) or 1))
    local interval = math.max(0.01,
        tonumber(self.survival_nuclear_batch_interval) or 0.05)
    local task_id = "rogue_nuclear_bomb:" .. tostring(
        self.entindex and self:entindex() or self
    )

    scheduler.after(interval, function()
        local last_target = math.min(#targets, next_target + batch_size - 1)
        for index = next_target, last_target do
            local unit = targets[index]
            if unit and not unit:IsNull() and unit:IsAlive()
                and unit:GetTeamNumber() == DOTA_TEAM_BADGUYS
                and (unit.survival_is_wave_monster == true
                    or unit.survival_is_challenge_monster == true)
                and not is_protected_monster(unit) then
                unit:ForceKill(false)
            end
        end
        next_target = last_target + 1
        if next_target <= #targets then return interval end
        if caster and not caster:IsNull() and item and not item:IsNull() then
            caster:RemoveItem(item)
        end
        return false
    end, task_id)
end
