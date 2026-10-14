local event_bus = require("core/event_bus")
local events = require("core/events")
local M = {}

-- Return logical damage. The receiving tower converts to its native scale.
function M.calculate(player_id, pct)
    pct = tonumber(pct) or 0
    if pct <= 0 then return 0 end
    local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST,
        { player_id = player_id }) or {}
    local hero = summoned.unit or summoned.hero
    if hero and not hero:IsNull() and hero.GetAverageTrueAttackDamage then
        local ok, value = pcall(hero.GetAverageTrueAttackDamage, hero, hero)
        local attack = ok and tonumber(value)
        if attack and attack == attack and attack >= 0 and attack < math.huge then
            -- True native attack includes morale and training gains, which are
            -- absent from the authored combat snapshot. Restore scaling once.
            return attack * math.max(1, tonumber(hero.survival_endless_attack_scale) or 1)
                * pct / 100
        end
    end
    local result = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = player_id }) or {}
    local stats = result.snapshot or {}
    local minimum = tonumber(stats.attack_min) or 0
    local maximum = tonumber(stats.attack_max) or minimum
    return (minimum + maximum) * 0.5 * pct / 100
end

return M
