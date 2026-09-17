package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

Vector = function(x, y, z)
    return { x = x, y = y, z = z }
end
RandomInt = function(minimum)
    return minimum
end
IsInToolsMode = function()
    return true
end

local events = {
    HERO_SUMMON_GET_REQUEST = "hero_summon_get",
    HERO_SUMMON_REQUEST = "hero_summon",
    HERO_SKILL_STATE_GET_REQUEST = "hero_skill_state_get",
    HERO_SKILL_GRANT_REQUEST = "hero_skill_grant",
    HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST = "hero_combat_debug",
}
local definitions = require("config/generated/hero_skill_definitions")
local exclusive = require("config/generated/hero_exclusive_skills")

local snapshot = {
    player_id = 0,
    hero_ready = 1,
    hero_id = "hero_monkey_king",
    public_skill_count = 0,
    public_skill_capacity = 3,
    skills = {},
}
for _, row in ipairs(exclusive.rows or {}) do
    if row.hero_id == snapshot.hero_id and row.enabled ~= false
        and row.guaranteed == true then
        snapshot.skills[#snapshot.skills + 1] = {
            skill_id = row.skill_id,
            display_name = definitions.by_id[row.skill_id].display_name,
            level = 0,
            locked = 1,
        }
    end
end

local combat_payload = nil
local speed_rate = nil
local summon_payload = nil
local hero_available = false
local event_bus = {}
function event_bus.emit() end
function event_bus.request(event_name, payload)
    if event_name == events.HERO_SUMMON_GET_REQUEST then
        if hero_available then
            return { ok = true, unit = {}, hero_id = snapshot.hero_id }
        end
        return { ok = false, error = "hero_not_summoned" }
    end
    if event_name == events.HERO_SUMMON_REQUEST then
        summon_payload = payload
        hero_available = true
        return { ok = true, pending = false, hero_id = payload.hero_id }
    end
    if event_name == events.HERO_SKILL_STATE_GET_REQUEST then
        return { ok = true, snapshot = snapshot }
    end
    if event_name == events.HERO_SKILL_GRANT_REQUEST then
        assert(payload.source == "cheat_wudi", "wudi skill source mismatch")
        local definition = assert(definitions.by_id[payload.skill_id])
        local item = nil
        for _, current in ipairs(snapshot.skills) do
            if current.skill_id == payload.skill_id then item = current end
        end
        if not item then
            item = {
                skill_id = payload.skill_id,
                display_name = definition.display_name,
                level = 0,
            }
            snapshot.skills[#snapshot.skills + 1] = item
            if definition.is_public == true then
                snapshot.public_skill_count = snapshot.public_skill_count + 1
            end
        end
        item.level = math.min(
            tonumber(definition.max_level) or 1,
            (tonumber(item.level) or 0) + (tonumber(payload.levels) or 1)
        )
        item.locked = nil
        return { ok = true, snapshot = snapshot }
    end
    if event_name == events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST then
        combat_payload = payload
        return { ok = true }
    end
    return { ok = false, error = "unexpected_event:" .. tostring(event_name) }
end

package.loaded["core/event_bus"] = event_bus
package.loaded["core/events"] = events
package.loaded["core/logger"] = { info = function() end, warn = function() end }
package.loaded["debug/weapon_cheat_handlers"] = {}
package.loaded["debug/attack_speed_cheat"] = {
    set_rate = function(player_id, rate)
        assert(player_id == 0, "wudi speed player mismatch")
        speed_rate = rate
        return true
    end,
}
package.loaded["systems/wave_system"] = {}
package.loaded["debug/research_technology_test"] = {}
package.loaded["debug/dev_asset_preload"] = {}
package.loaded["debug/health_cheat"] = {}
package.loaded["debug/armor_engine_diagnostic"] = {}
package.loaded["systems/building_system"] = {}
package.loaded["config/global_rules"] = {}
package.loaded["systems/rogue_reward_service"] = {}
package.loaded["systems/fishing_service"] = {}
package.loaded["systems/player_gameplay_stats_order_service"] = {}
local scheduled = nil
package.loaded["core/scheduler"] = {
    after = function(delay, callback, task_id)
        scheduled = { delay = delay, callback = callback, task_id = task_id }
        return task_id
    end,
}

local service = require("debug/cheat_command_service")
local ok, error_code = service._test.wudi({
    player_id = 0,
    team = 2,
    args = {},
})
assert(ok == true, tostring(error_code))
assert(summon_payload and summon_payload.hero_id == "hero_monkey_king",
    "wudi did not directly summon the test hero")
assert(summon_payload.debug_bypass == true, "wudi summon did not bypass gates")
assert(scheduled and scheduled.delay == 0.05,
    "wudi did not schedule post-summon setup")
assert(scheduled.callback() == false, "wudi setup task did not finish")
assert(snapshot.public_skill_count == 3, "wudi did not fill 3 public slots")
assert(#snapshot.skills == 7, "wudi should own 4 exclusive and 3 public skills")
for _, skill in ipairs(snapshot.skills) do
    local maximum = tonumber(definitions.by_id[skill.skill_id].max_level) or 1
    assert(skill.level == maximum, skill.skill_id .. " was not maxed")
    assert(skill.locked ~= 1, skill.skill_id .. " remained locked")
end
assert(combat_payload and combat_payload.attack == 1111111111,
    "wudi attack override mismatch")
assert(combat_payload.attack_speed == 5, "wudi attack speed snapshot mismatch")
assert(speed_rate == 5, "wudi fixed attack rate mismatch")

print("WUDI_CHEAT_LUA51_PASS")
