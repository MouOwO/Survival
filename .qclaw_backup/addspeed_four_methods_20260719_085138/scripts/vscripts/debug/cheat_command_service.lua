local event_bus = require("core/event_bus")
local events = require("core/events")
local logger = require("core/logger")
local weapon_cheats = require("debug/weapon_cheat_handlers")
local attack_speed_cheat = require("debug/attack_speed_cheat")

local M = {}

local RESOURCE_AMOUNT = 100000

local HERO_ALIASES = {
    axe = "hero_axe",
    slark = "hero_slark",
    juggernaut = "hero_juggernaut",
    jugg = "hero_juggernaut",
    monkey = "hero_monkey_king",
    monkeyking = "hero_monkey_king",
    mk = "hero_monkey_king",
    blade = "hero_blademaster",
    blademaster = "hero_blademaster",
    sword = "hero_blademaster",
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function words(text)
    local result = {}
    for word in string.gmatch(trim(text), "%S+") do
        table.insert(result, string.lower(word))
    end
    return result
end

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function resolve_player_id(keys)
    local player_id = tonumber(
        keys and (keys.playerid or keys.player_id or keys.PlayerID)
    )
    if valid_player_id(player_id) then
        return player_id
    end

    local user_id = tonumber(keys and keys.userid)
    if user_id and PlayerResource.GetPlayerIDForUserID then
        local ok, resolved = pcall(function()
            return PlayerResource:GetPlayerIDForUserID(user_id)
        end)
        if ok and valid_player_id(resolved) then
            return resolved
        end
    end
    return nil
end

local function notify(context, message)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = context.player_id,
        message = message,
        level = "info",
    })
end

local function show_shop(context)
    local player = PlayerResource:GetPlayer(context.player_id)
    if not player then
        return false, "player_handle_unavailable"
    end
    CustomGameEventManager:Send_ServerToPlayer(
        player,
        "ui_shop_debug_show",
        { source = "cheat_command_service" }
    )
    return true
end

local function add_resource(context)
    local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = context.team,
        wood = RESOURCE_AMOUNT,
        gold = RESOURCE_AMOUNT,
        reason = "cheat_addresource",
    })
    return result and result.ok == true,
        result and result.error or "resource_request_failed"
end

local function set_vip(context)
    local value = tonumber(context.args[1])
    if value ~= 0 and value ~= 1 then
        return false, "usage: setvip 0|1"
    end
    local result = event_bus.request(
        events.PLAYER_ENTITLEMENT_SET_REQUEST,
        {
            player_id = context.player_id,
            entitlement_id = "vip",
            unlocked = value == 1,
            reason = "cheat_setvip",
        }
    )
    return result and result.ok == true,
        result and result.error or "entitlement_request_failed"
end

local function summon_hero(context)
    local alias = tostring(context.args[1] or "")
    local hero_id = HERO_ALIASES[alias] or alias
    if hero_id == "" then
        return false,
            "usage: summonhero axe|slark|jugg|monkey|blade"
    end
    local result = event_bus.request(events.HERO_SUMMON_REQUEST, {
        player_id = context.player_id,
        hero_id = hero_id,
        reason = "cheat_summonhero",
    })
    return result and result.ok == true,
        result and result.error or "hero_summon_failed"
end

local function spawn_boss(context)
    local level = tonumber(context.args[1]) or 0
    if level < 0 or level > 10 then
        return false, "usage: spawnboss 0-10"
    end
    local encounter_id = level == 0
        and "encounter_wild_boss"
        or string.format("encounter_rebirth_%02d", level)
    local result = event_bus.request(
        events.MONSTER_ENCOUNTER_START_REQUEST,
        {
            encounter_id = encounter_id,
            player_id = context.player_id,
            team = context.team,
        }
    )
    return result and result.ok == true,
        result and result.error or "encounter_request_failed"
end

local function skill_offer(context)
    local result = event_bus.request(
        events.HERO_SKILL_CHOICE_CREATE_REQUEST,
        {
            player_id = context.player_id,
            source = "cheat_skilloffer",
            trigger_level = tonumber(context.args[1]) or 2,
        }
    )
    if not result or not result.ok then
        return false, result and result.error or "skill_offer_failed"
    end
    local names = {}
    for index, item in ipairs(result.candidates or {}) do
        table.insert(
            names,
            tostring(index) .. ":" .. tostring(item.display_name)
        )
    end
    notify(context, "技能候选 " .. table.concat(names, " | "))
    return true
end

local function skill_choose(context)
    local index = tonumber(context.args[1])
    if not index then
        return false, "usage: skillchoose 1|2|3"
    end
    local pending = event_bus.request(
        events.HERO_SKILL_CHOICE_GET_REQUEST,
        { player_id = context.player_id }
    )
    local snapshot = pending and pending.snapshot or nil
    local candidate = snapshot
        and snapshot.candidates
        and snapshot.candidates[index] or nil
    if not candidate then
        return false, "skill_choice_index_invalid"
    end
    local result = event_bus.request(
        events.HERO_SKILL_CHOICE_SELECT_REQUEST,
        {
            player_id = context.player_id,
            choice_token = snapshot.choice_token,
            skill_id = candidate.skill_id,
        }
    )
    return result and result.ok == true,
        result and result.error or "skill_choose_failed"
end

local function list_skills(context)
    local result = event_bus.request(
        events.HERO_SKILL_STATE_GET_REQUEST,
        { player_id = context.player_id }
    )
    if not result or not result.ok then
        return false, result and result.error or "skill_state_failed"
    end
    local names = {}
    for _, item in ipairs(result.snapshot.skills or {}) do
        table.insert(
            names,
            tostring(item.display_name)
                .. " Lv." .. tostring(item.level)
        )
    end
    notify(
        context,
        "技能 "
        .. tostring(result.snapshot.skill_count)
        .. "/" .. tostring(result.snapshot.skill_capacity)
        .. " " .. table.concat(names, " | ")
    )
    return true
end

local COMMANDS = {
    shopshow = show_shop,
    addresource = add_resource,
    addspeed = attack_speed_cheat.execute,
    setvip = set_vip,
    summonhero = summon_hero,
    spawnboss = spawn_boss,
    skilloffer = skill_offer,
    skillchoose = skill_choose,
    skills = list_skills,
    givegrowthsword = weapon_cheats.give_growth_sword,
    givehammer = weapon_cheats.give_forging_hammer,
    weapongrow = weapon_cheats.grow_weapon,
    weaponstats = weapon_cheats.weapon_stats,
}

local function on_player_chat(keys)
    local args = words(keys and keys.text)
    local command = string.gsub(args[1] or "", "^%-", "")
    local handler = COMMANDS[command]
    if not handler then
        return
    end

    local player_id = resolve_player_id(keys)
    if not valid_player_id(player_id) then
        logger.warn(
            "CheatCommand",
            command .. " has no valid player"
        )
        return
    end

    table.remove(args, 1)
    local ok, error_code = handler({
        player_id = player_id,
        team = PlayerResource:GetTeam(player_id),
        args = args,
    })
    if ok then
        logger.info("CheatCommand", command .. " executed")
    else
        logger.warn(
            "CheatCommand",
            command .. " failed: " .. tostring(error_code)
        )
    end
end

function M.init()
    attack_speed_cheat.init()
    ListenToGameEvent("player_chat", on_player_chat, nil)
    logger.info(
        "CheatCommand",
        "ready: resource, hero, skill, weapon growth"
    )
end

return M
