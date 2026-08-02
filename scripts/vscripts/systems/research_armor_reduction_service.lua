local event_bus = require("core/event_bus")
local events = require("core/events")
local technology_stat_manager = require("systems/technology_stat_manager")

local M = {}
local hit_count_by_target = {}
local callback_count = 0

print("[RESEARCH_ARMOR_SERVICE_LOAD] version=20260801_upstream_diagnostic")

local DIAGNOSTIC_MILESTONES = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [10] = true,
    [25] = true,
    [50] = true,
    [100] = true,
    [250] = true,
    [500] = true,
}

local function valid_unit(unit)
    return unit and not unit:IsNull()
end

local function safe_call(entity, method_name, fallback, ...)
    local method = entity and entity[method_name]
    if type(method) ~= "function" then return fallback end
    local ok, value = pcall(method, entity, ...)
    if not ok or value == nil then return fallback end
    return value
end

local function target_key(target)
    return tostring(safe_call(target, "entindex", target))
end

local function on_main_attack_landed(payload)
    callback_count = callback_count + 1
    local player_id = tonumber(payload and payload.player_id)
    local attacker = payload and payload.attacker
    local target = payload and payload.target
    local diagnostic = callback_count <= 5
    if diagnostic then
        print(string.format(
            "[RESEARCH_ARMOR_EVENT] callback=%s player_raw=%s player=%s "
                .. "attacker=%s target=%s",
            tostring(callback_count),
            tostring(payload and payload.player_id),
            tostring(player_id),
            tostring(safe_call(attacker, "entindex", -1)),
            tostring(safe_call(target, "entindex", -1))
        ))
    end
    local reject_reason = nil
    if player_id == nil then
        reject_reason = "invalid_player"
    elseif not valid_unit(attacker) then
        reject_reason = "invalid_attacker"
    elseif not valid_unit(target) then
        reject_reason = "invalid_target"
    elseif target:GetTeamNumber() == attacker:GetTeamNumber() then
        reject_reason = "friendly_target"
    end
    if reject_reason then
        if diagnostic then
            print(string.format(
                "[RESEARCH_ARMOR_REJECT] callback=%s reason=%s",
                tostring(callback_count),
                reject_reason
            ))
        end
        return
    end
    local technology = technology_stat_manager.get(player_id)
    local reduction = tonumber(
        technology and technology.final and technology.final.hero
            and technology.final.hero.armor_reduction_per_attack
    ) or 0
    if reduction <= 0 then
        if diagnostic then
            print(string.format(
                "[RESEARCH_ARMOR_REJECT] callback=%s reason=reduction_not_positive "
                    .. "player=%s technology=%s final=%s hero=%s reduction=%s",
                tostring(callback_count),
                tostring(player_id),
                tostring(technology ~= nil),
                tostring(technology and technology.final ~= nil),
                tostring(technology and technology.final
                    and technology.final.hero ~= nil),
                tostring(reduction)
            ))
        end
        return
    end
    local key = target_key(target)
    local hit_count = (tonumber(hit_count_by_target[key]) or 0) + 1
    hit_count_by_target[key] = hit_count
    local armor_before = safe_call(
        target,
        "GetPhysicalArmorValue",
        "unavailable",
        false
    )
    local add_ok, modifier_or_error = pcall(
        target.AddNewModifier,
        target,
        attacker,
        nil,
        "modifier_research_armor_reduction",
        {
            armor_reduction_per_attack = reduction,
            diagnostic_hit = hit_count,
        }
    )
    if not add_ok or modifier_or_error == nil then
        print(string.format(
            "[RESEARCH_ARMOR_APPLY_FAILED] hit=%s player=%s attacker=%s "
                .. "target=%s reduction=%s armor_before=%s add_ok=%s result=%s",
            tostring(hit_count),
            tostring(player_id),
            tostring(safe_call(attacker, "entindex", -1)),
            tostring(safe_call(target, "entindex", -1)),
            tostring(reduction),
            tostring(armor_before),
            tostring(add_ok),
            tostring(modifier_or_error)
        ))
        return
    end
    if DIAGNOSTIC_MILESTONES[hit_count] then
        print(string.format(
            "[RESEARCH_ARMOR_APPLY] hit=%s player=%s attacker=%s target=%s "
                .. "reduction=%s armor_before=%s stack=%s effective_immediate=%s",
            tostring(hit_count),
            tostring(player_id),
            tostring(safe_call(attacker, "entindex", -1)),
            tostring(safe_call(target, "entindex", -1)),
            tostring(reduction),
            tostring(armor_before),
            tostring(safe_call(modifier_or_error, "GetStackCount", "unavailable")),
            tostring(safe_call(
                target,
                "GetPhysicalArmorValue",
                "unavailable",
                false
            ))
        ))
    end
end

function M.init()
    hit_count_by_target = {}
    callback_count = 0
    local subscription = event_bus.subscribe(
        events.HERO_MAIN_ATTACK_LANDED,
        on_main_attack_landed
    )
    print(string.format(
        "[RESEARCH_ARMOR_SERVICE_INIT] event=%s subscribed=%s token=%s",
        tostring(events.HERO_MAIN_ATTACK_LANDED),
        tostring(subscription ~= nil),
        tostring(subscription and subscription.token)
    ))
end

M._test = { on_main_attack_landed = on_main_attack_landed }

return M
