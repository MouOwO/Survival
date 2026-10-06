package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local now, tables = 0, {}
GameRules = {GetGameTime = function() return now end}
Vector = function(x,y,z) return {x=x,y=y,z=z} end
CustomNetTables = {SetTableValue = function(_, name, key, value)
    tables[name] = tables[name] or {}; tables[name][key] = value
end}
package.loaded["systems/destination_validation_service"] = {
    is_constrained_hero = function() return true end,
    validate = function() return true end,
}
local boundary = require("systems/hero_boundary_guard_service")
local choices = require("systems/hero_skill_choice_service")
local ui = require("ui/combat_stats_ui_service")
local hero_by_player = {}
local function unit(index)
    return {IsNull = function(self) return self.removed == true end,
        IsAlive = function() return true end,
        entindex = function() return index end,
        GetAbsOrigin = function() return Vector(0,0,0) end}
end
bus.reset(); scheduler.clear()
bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST, function(payload)
    return {ok=true, snapshot={hero_ready = hero_by_player[payload.player_id] and 1 or 0,
        hero_id="hero_monkey_king", public_skill_count=0, public_skill_capacity=3, skills={}}}
end)
bus.handle_request(events.HERO_SKILL_POOL_DRAW_REQUEST, function()
    return {ok=true, candidates={{skill_id="proto_flame_burst"}}}
end)
ui.init(); choices.init(); boundary.init()
local first, other = unit(101), unit(102)
hero_by_player[0], hero_by_player[1] = first, other
bus.emit(events.HERO_SUMMONED,{player_id=0, unit=first})
bus.emit(events.HERO_SUMMONED,{player_id=1, unit=other})
for player_id=0,1 do
    local result = bus.request(events.HERO_SKILL_CHOICE_CREATE_REQUEST,
        {player_id=player_id, trigger_level=2})
    assert(result and result.ok)
end
assert(boundary._tracked_for_test()[first] and boundary._tracked_for_test()[other])
assert(tables.survival_combat_debug.player_0.entindex == 101)
local old_choice = tables.survival_hero_skill_choice.player_0.choice_token
first.removed = true; hero_by_player[0] = nil
bus.emit(events.HERO_REMOVED, {player_id=0, unit=first, entindex=101})
assert(not boundary._tracked_for_test()[first] and boundary._tracked_for_test()[other])
assert(tables.survival_combat_debug.player_0.entindex == -1)
assert(tables.survival_combat_debug.player_1.entindex == 102)
assert(tables.survival_hero_skill_choice.player_0.pending == 0)
assert(tables.survival_hero_skill_choice.player_1.pending == 1)
local result = bus.request(events.HERO_SKILL_CHOICE_SELECT_REQUEST,
    {player_id=0, choice_token=old_choice, skill_id="proto_flame_burst"})
assert(result and not result.ok and result.error == "skill_choice_not_pending")

-- A queued reward retry must not regenerate a dialog after removal/resummon.
bus.emit(events.HERO_SKILL_REWARD_REQUEST,{player_id=0, trigger_level=2,
    effect={effect_type="grant_random_skill_or_upgrade"}})
assert(scheduler.task_count() == 2, "fixture expects boundary timer and reward retry")
bus.emit(events.HERO_REMOVED,{player_id=0,unit=first,entindex=101})
assert(scheduler.task_count() == 1)
local again=unit(103);hero_by_player[0]=again
bus.emit(events.HERO_SUMMONED,{player_id=0,unit=again})
now=1;scheduler.think()
assert(tables.survival_hero_skill_choice.player_0.pending == 0)
assert(tables.survival_combat_debug.player_0.entindex == 103)
assert(boundary._tracked_for_test()[again])
local renewed = bus.request(events.HERO_SKILL_CHOICE_CREATE_REQUEST,
    {player_id=0, trigger_level=2})
assert(renewed and renewed.ok)
bus.emit(events.HERO_REMOVED,{player_id=0,unit=first,entindex=101})
assert(tables.survival_combat_debug.player_0.entindex == 103 and boundary._tracked_for_test()[again])
assert(tables.survival_hero_skill_choice.player_0.choice_token == renewed.choice_token,
    "stale removal must not dismiss a replacement hero's reward choice")
print("HERO_REMOVED_UI_LIFECYCLE_PASS: boundary/debug/skill choice cleanup, canceled retries, player isolation, resummon")
