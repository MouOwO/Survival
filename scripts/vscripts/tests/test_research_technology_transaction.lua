package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local Repository = require("research/research_technology_repository")
local Service = require("research/research_technology_service")
local event_names = require("research/research_event_names")

local function new_fixture(fail_effects)
    local repository = Repository.new({ resolve_team = function() return 2 end })
    local resources = { gold = 10 ^ 12, wood = 10 ^ 12 }
    local spent = 0
    local refunded = 0
    local recalculated = 0
    local level_changed = 0
    local event_bus = {
        emit = function(event_name)
            if event_name == event_names.LEVEL_CHANGED then
                level_changed = level_changed + 1
            end
        end,
    }
    local service = Service.new({
        repository = repository,
        effects = {
            Recalculate = function()
                recalculated = recalculated + 1
                if fail_effects and repository:GetLevel(0, "RS-01") > 0 then
                    error("forced_effect_failure")
                end
                return { version = recalculated }
            end,
        },
        event_bus = event_bus,
        valid_player = function(player_id) return player_id == 0 end,
        get_resources = function() return resources end,
        spend_resources = function(_, cost)
            spent = spent + 1
            resources.gold = resources.gold - cost.gold
            resources.wood = resources.wood - cost.wood
            return { ok = true }
        end,
        refund_resources = function(_, cost)
            refunded = refunded + 1
            resources.gold = resources.gold + cost.gold
            resources.wood = resources.wood + cost.wood
            return { ok = true }
        end,
        get_access_state = function()
            return { research_lab = true, advanced_research_lab = true }
        end,
    })
    return {
        repository = repository,
        resources = resources,
        service = service,
        spent = function() return spent end,
        refunded = function() return refunded end,
        recalculated = function() return recalculated end,
        level_changed = function() return level_changed end,
    }
end

local fixture = new_fixture(false)
local before_gold = fixture.resources.gold
local before_wood = fixture.resources.wood
local started = fixture.service:BeginUpgrade({ player_id = 0, tech_id = "RS-01" })
assert(started and started.success == true and started.pending == true,
    "research transaction did not start")
assert(fixture.spent() == 1,
    "research transaction did not reserve resources at start")
assert(fixture.resources.gold == before_gold - started.gold_cost
    and fixture.resources.wood == before_wood - started.wood_cost,
    "research start deducted the wrong resources")
assert(fixture.repository:GetLevel(0, "RS-01") == 0,
    "research start changed the technology level before completion")
assert(fixture.recalculated() == 0 and fixture.level_changed() == 0,
    "research start applied effects or published a level change")

local completed = fixture.service:CommitUpgrade({
    transaction_id = started.transaction_id,
})
assert(completed and completed.success == true,
    "research transaction did not commit")
assert(fixture.repository:GetLevel(0, "RS-01") == 1,
    "research completion did not increase the technology level")
assert(fixture.recalculated() == 1 and fixture.level_changed() == 1,
    "research completion did not apply effects exactly once")
local duplicate = fixture.service:CommitUpgrade({
    transaction_id = started.transaction_id,
})
assert(duplicate and duplicate.success == false
    and duplicate.error_code == "research_transaction_not_found",
    "completed research transaction could be committed twice")
assert(fixture.repository:GetLevel(0, "RS-01") == 1,
    "duplicate completion changed the technology level")

local cancellable = fixture.service:BeginUpgrade({ player_id = 0, tech_id = "RS-01" })
local reserved_gold = fixture.resources.gold
local reserved_wood = fixture.resources.wood
local rolled_back = fixture.service:RollbackUpgrade({
    transaction_id = cancellable.transaction_id,
    error_code = "test_cancelled",
})
assert(rolled_back and rolled_back.rolled_back == true,
    "research rollback did not succeed")
assert(fixture.resources.gold == reserved_gold + cancellable.gold_cost
    and fixture.resources.wood == reserved_wood + cancellable.wood_cost,
    "research rollback did not refund the reserved resources")
assert(fixture.repository:GetLevel(0, "RS-01") == 1,
    "research rollback changed the technology level")

local failing = new_fixture(true)
local failing_gold = failing.resources.gold
local failing_wood = failing.resources.wood
local failing_started = failing.service:BeginUpgrade({
    player_id = 0,
    tech_id = "RS-01",
})
local failed = failing.service:CommitUpgrade({
    transaction_id = failing_started.transaction_id,
})
assert(failed and failed.success == false
    and failed.error_code == "resource_commit_failed",
    "effect failure did not fail the research commit")
assert(failing.repository:GetLevel(0, "RS-01") == 0,
    "failed research commit did not restore the old technology level")
assert(failing.resources.gold == failing_gold
    and failing.resources.wood == failing_wood
    and failing.refunded() == 1,
    "failed research commit did not refund reserved resources")
assert(failing.level_changed() == 0,
    "failed research commit published a completed level change")

print("RESEARCH_TECHNOLOGY_TRANSACTION_PASS")