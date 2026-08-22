package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local repository_class = require("research/research_technology_repository")
local service_class = require("research/research_technology_service")

local repository = repository_class.new({
    resolve_team = function() return 2 end,
})
local resources = { gold = 10 ^ 12, wood = 10 ^ 12 }
local reincarnation_level = 0
local spend_count = 0
local event_bus = {
    emit = function() end,
}
local service = service_class.new({
    repository = repository,
    effects = {
        Recalculate = function() return {} end,
    },
    event_bus = event_bus,
    valid_player = function(player_id) return player_id == 0 end,
    get_resources = function() return resources end,
    spend_resources = function(_, cost)
        spend_count = spend_count + 1
        resources.gold = resources.gold - cost.gold
        resources.wood = resources.wood - cost.wood
        return { ok = true }
    end,
    refund_resources = function(_, cost)
        resources.gold = resources.gold + cost.gold
        resources.wood = resources.wood + cost.wood
    end,
    get_reincarnation_level = function() return reincarnation_level end,
    get_access_state = function()
        return { research_lab = true, advanced_research_lab = true }
    end,
})

local blocked_advanced_speed = service:RequestUpgrade({
    player_id = 0,
    tech_id = "RS-02",
})
assert(blocked_advanced_speed.success == false
    and blocked_advanced_speed.error_code == "prerequisite_not_met",
    "direct service request bypassed the technology-level prerequisite")
assert(repository:GetLevel(0, "RS-02") == 0,
    "blocked technology prerequisite still changed the level")
assert(spend_count == 0,
    "blocked technology prerequisite still spent resources")

assert(repository:SetLevel(0, "RS-01", 5),
    "failed to establish prerequisite technology level")
local unlocked_advanced_speed = service:RequestUpgrade({
    player_id = 0,
    tech_id = "RS-02",
})
assert(unlocked_advanced_speed.success == true
    and repository:GetLevel(0, "RS-02") == 1,
    "technology did not unlock after reaching its prerequisite level")

local blocked_rebirth = service:RequestUpgrade({
    player_id = 0,
    tech_id = "ARS-08",
})
assert(blocked_rebirth.success == false
    and blocked_rebirth.error_code == "reincarnation_not_met",
    "direct service request bypassed the rebirth prerequisite")
assert(repository:GetLevel(0, "ARS-08") == 0,
    "blocked rebirth prerequisite still changed the level")

reincarnation_level = 3
local unlocked_rebirth = service:RequestUpgrade({
    player_id = 0,
    tech_id = "ARS-08",
})
assert(unlocked_rebirth.success == true
    and repository:GetLevel(0, "ARS-08") == 1,
    "technology did not unlock after reaching its rebirth prerequisite")

print("RESEARCH_TECHNOLOGY_PREREQUISITE_PASS")
