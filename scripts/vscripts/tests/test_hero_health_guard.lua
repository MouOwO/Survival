package.path = "./scripts/vscripts/?.lua;./scripts/vscripts/?/init.lua;" .. package.path

local guard = require("core/hero_health_guard")

local function unit(health, maximum, alive)
    local result = { health = health, maximum = maximum, alive = alive ~= false }
    function result:IsNull() return false end
    function result:IsAlive() return self.alive end
    function result:GetHealth() return self.health end
    function result:GetMaxHealth() return self.maximum end
    function result:SetHealth(value) self.health = value end
    return result
end

local damaged = unit(420, 1000)
guard.preserve_current(damaged, function()
    damaged.maximum = 1500
    damaged.health = 1500 -- simulate CalculateStatBonus incorrectly filling health
end)
assert(damaged.health == 420, "damaged hero was healed by stat refresh")

-- Reproduce the reported sequence: the hero is hit, stands still through a
-- modifier/stat refresh, then receives a second hit and refresh. Each refresh
-- must preserve the newest damaged value rather than an older/full value.
local consecutive = unit(1000, 1000)
consecutive.health = 800
guard.preserve_current(consecutive, function()
    consecutive.maximum = 1100
    consecutive.health = 1100
end)
assert(consecutive.health == 800, "first-hit refresh refilled the hero")
consecutive.health = 600
guard.preserve_current(consecutive, function()
    consecutive.maximum = 1200
    consecutive.health = 1200
end)
assert(consecutive.health == 600, "second-hit refresh refilled the hero")

local clamped = unit(900, 1000)
guard.preserve_current(clamped, function()
    clamped.maximum = 700
    clamped.health = 700
end)
assert(clamped.health == 700, "health must clamp when maximum decreases")

local naturally_lower = unit(400, 1000)
guard.preserve_current(naturally_lower, function()
    naturally_lower.health = 350
end)
assert(naturally_lower.health == 350, "health guard must never heal newer damage")

local explicit = unit(500, 1000)
explicit.health = 1000
guard.protect_value(explicit, 500, "unit_test")
assert(explicit.health == 500, "explicit protection must undo a refill")

local dead = unit(0, 1000, false)
guard.preserve_current(dead, function() dead.health = 1000 end)
assert(dead.health == 1000, "death/respawn initialization must remain engine-owned")

local full_buyer = unit(1000, 1000)
guard.preserve_missing(full_buyer, function()
    full_buyer.maximum = 6000
    full_buyer.health = 6000
end, "equipment_purchase_test")
assert(full_buyer.health == 6000, "full hero must remain full after max-health purchase")

local damaged_buyer = unit(600, 1000)
guard.preserve_missing(damaged_buyer, function()
    damaged_buyer.maximum = 6000
    damaged_buyer.health = 6000
end, "equipment_purchase_test")
assert(damaged_buyer.health == 5600,
    "max-health purchase must preserve the amount of health already missing")

local scheduled = {}
local previous_game_rules = GameRules
local previous_scheduler = package.loaded["core/scheduler"]
GameRules = { GetGameTime = function() return 0 end }
package.loaded["core/scheduler"] = {
    after = function(_, callback)
        scheduled[#scheduled + 1] = callback
    end,
}
local lifesteal = unit(500, 1000)
guard.protect_value(lifesteal, 500, "lifesteal_regression")
guard.allow_healing(lifesteal)
lifesteal.health = 1000
for _, callback in ipairs(scheduled) do callback() end
assert(lifesteal.health == 1000,
    "legitimate lifesteal must invalidate deferred health rollback")
GameRules = previous_game_rules
package.loaded["core/scheduler"] = previous_scheduler

print("HERO_HEALTH_GUARD_PASS")