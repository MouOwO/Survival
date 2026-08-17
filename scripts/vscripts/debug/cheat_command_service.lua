local event_bus = require("core/event_bus")
local monster_corpse_lifecycle_service = require(
    "systems/monster_corpse_lifecycle_service"
)
local events = require("core/events")
local logger = require("core/logger")
local weapon_cheats = require("debug/weapon_cheat_handlers")
local attack_speed_cheat = require("debug/attack_speed_cheat")
local wave_system = require("systems/wave_system")
local research_test = require("debug/research_technology_test")
local dev_asset_preload = require("debug/dev_asset_preload")
local health_cheat = require("debug/health_cheat")
local armor_engine_diagnostic = require("debug/armor_engine_diagnostic")
local building_system = require("systems/building_system")
local global_rules = require("config/global_rules")
local rogue_reward_service = require("systems/rogue_reward_service")

local M = {}

local ADD_MONSTER_POSITION = Vector(-1280, 1088, 64)
local ADD_MONSTER_DEFAULT_ARGS = { "1000000000", "200", "1", "1" }
local ADD_MONSTER_MOVE_SPEED = 600
local MONKEY_KING_E_SKILL = "skill_monkey_king_swiftness"
local selected_entindex_by_player = {}

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

local function notify(context, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = context.player_id,
        message = message,
        level = level or "info",
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

local function enable_dev(context)
    wave_system.set_dev_mode(true)
    local wall_ok, wall_count = building_system.enable_dev_wall_stats()
    if not wall_ok then return false, "dev_wall_stats_failed" end
    notify(context, "开发城墙强化已开启：生命"
        .. tostring(global_rules.dev_wall_health) .. "，护甲"
        .. tostring(global_rules.dev_wall_war3_armor)
        .. "（已应用 " .. tostring(wall_count) .. " 座）")
    local ok, status, snapshot = dev_asset_preload.start({
        on_dispatched = function(progress)
            notify(context, "开发模型加载请求已全部发出："
                .. tostring(progress.dispatched) .. " 个")
        end,
        on_window_complete = function(progress)
            if progress.running then
                notify(context, "10秒模型加载窗口结束：已完成 "
                    .. tostring(progress.ready + progress.failed)
                    .. "/" .. tostring(progress.total)
                    .. "，剩余资源继续后台加载")
            end
        end,
        on_complete = function(progress)
            if progress.failed > 0 then
                notify(context, "开发模型加载完成：成功 "
                    .. tostring(progress.ready) .. "，失败 "
                    .. tostring(progress.failed)
                    .. "；再次输入 dev 可重试失败项")
            else
                notify(context, "开发模型加载完成："
                    .. tostring(progress.ready) .. "/"
                    .. tostring(progress.total))
            end
        end,
    })
    if not ok then
        notify(context, "开发者模式已开启，但模型加载启动失败："
            .. tostring(status))
        return false, status
    end

    snapshot = snapshot or {}
    if status == "already_running" then
        notify(context, "开发者模式已开启：模型正在加载 "
            .. tostring(snapshot.ready + snapshot.failed)
            .. "/" .. tostring(snapshot.total))
    elseif status == "complete" then
        notify(context, "开发者模式已开启：目标模型均已加载")
    else
        notify(context, "开发者模式已开启：停止自动出怪，开始在10秒内渐进加载 "
            .. tostring(snapshot.total or 0) .. " 个测试模型")
    end
    return true
end

local function spawn_wave(context)
    local number = tonumber(context.command_suffix) or tonumber(context.args[1])
    if not number then return false, "usage: monster <wave_number>" end
    local ok, err = wave_system.debug_spawn_wave(number)
    return ok, err
end

local function add_technology(context)
    local technology_id = tostring(context.args[1] or "")
    if technology_id == "" then
        return false, "usage: addtechnology <technology_id>"
    end
    local result = event_bus.request(
        events.TECHNOLOGY_CHEAT_SET_REQUEST,
        {
            player_id = context.player_id,
            technology_id = technology_id,
        }
    )
    if not result or result.ok ~= true then
        return false, result and result.error
            or "technology_cheat_handler_missing"
    end
    notify(
        context,
        "科技已添加：" .. tostring(result.display_name)
            .. "（" .. tostring(result.technology_group)
            .. " Lv." .. tostring(result.level) .. "）"
    )
    return true
end

local function run_research_test(context)
    local ok, message = research_test.run()
    notify(context, message)
    return ok, ok and nil or message
end

local function signed_amount(context, command)
    local amount = tonumber(context.args[1])
    if not amount then
        return nil, "usage: " .. command .. " <amount>"
    end
    if amount >= 0 then
        return math.floor(amount)
    end
    return math.ceil(amount)
end

local function change_resource(context, resource_name, command)
    local amount, error_code = signed_amount(context, command)
    if amount == nil then
        return false, error_code
    end
    local changes = {
        team = context.team,
        wood = 0,
        gold = 0,
        reason = "cheat_" .. command,
    }
    changes[resource_name] = amount
    local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = changes.team,
        wood = changes.wood,
        gold = changes.gold,
        reason = changes.reason,
    })
    return result and result.ok == true,
        result and result.error or "resource_request_failed"
end

local function add_gold(context)
    return change_resource(context, "gold", "addgold")
end

local function add_wood(context)
    return change_resource(context, "wood", "addwood")
end

local function summoned_hero(player_id)
    local result = event_bus.request(
        events.HERO_SUMMON_GET_REQUEST,
        { player_id = player_id }
    )
    local unit = result and result.ok and result.unit or nil
    if not unit or unit:IsNull() then return nil end
    return unit
end

local function add_hero_combat_bonus(context, command, modifier_name, label)
    local amount = tonumber(context.args[1])
    if not amount or amount ~= amount
        or amount == math.huge or amount == -math.huge then
        return false, "usage: " .. command .. " <amount>"
    end
    local hero = summoned_hero(context.player_id)
    if not hero then return false, "hero_not_summoned" end

    local modifier = hero:FindModifierByName(modifier_name)
    if modifier and modifier.AddBonus then
        modifier:AddBonus(amount)
    else
        modifier = hero:AddNewModifier(
            hero, nil, modifier_name, { bonus = amount }
        )
    end
    if not modifier then return false, modifier_name .. "_failed" end

    if hero.CalculateStatBonus then hero:CalculateStatBonus(true) end
    notify(context, string.format(
        "英雄%s %+.1f，作弊累计值 %.1f",
        label, amount, modifier.GetBonus and modifier:GetBonus() or amount
    ))
    return true
end

local function add_attack(context)
    return add_hero_combat_bonus(
        context, "addattack", "modifier_debug_attack_bonus", "攻击力"
    )
end

local function add_armor(context)
    return add_hero_combat_bonus(
        context, "addarmor", "modifier_debug_armor_bonus", "护甲"
    )
end

local function change_hero_health(context)
    if #context.args ~= 1 then
        return false, "usage: blood <+amount|-amount|+percent%|-percent%>"
    end
    local hero = summoned_hero(context.player_id)
    if not hero then return false, "hero_not_summoned" end
    local result, error_code = health_cheat.apply(hero, context.args[1])
    if not result then return false, error_code end
    notify(context, string.format(
        "英雄生命 %.1f -> %.1f / %.1f（实际变化 %+.1f）",
        result.before, result.after, result.maximum, result.delta
    ))
    logger.info("CheatCommand", string.format(
        "blood player=%s entindex=%s before=%.1f after=%.1f max=%.1f delta=%+.1f",
        tostring(context.player_id), tostring(hero:entindex()),
        result.before, result.after, result.maximum, result.delta
    ))
    return true
end

local function finite_number(value)
    local number = tonumber(value)
    if not number or number ~= number
        or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function attack_flag(value)
    local normalized = string.lower(trim(value))
    if normalized == "1" or normalized == "true"
        or normalized == "yes" or normalized == "on"
        or normalized == "是" then
        return true
    end
    if normalized == "0" or normalized == "false"
        or normalized == "no" or normalized == "off"
        or normalized == "否" then
        return false
    end
    return nil
end

local function add_monster(context)
    local args = context.args
    if #args == 0 then args = ADD_MONSTER_DEFAULT_ARGS end
    local health = finite_number(args[1])
    local armor = finite_number(args[2])
    local can_attack = attack_flag(args[3])
    local attack = finite_number(args[4])
    if not health or health <= 0 or not armor or can_attack == nil
        or not attack or attack < 0 then
        return false,
            "usage: addmonster <health> <armor> <true|false> <attack>"
    end
    local hero = nil
    if can_attack then
        hero = summoned_hero(context.player_id)
    end
    health = math.max(1, math.floor(health))
    local unit = CreateUnitByName(
        "npc_survival_wave_monster", ADD_MONSTER_POSITION, true,
        nil, nil, DOTA_TEAM_BADGUYS
    )
    if not unit or unit:IsNull() then return false, "unit_create_failed" end
    FindClearSpaceForUnit(unit, ADD_MONSTER_POSITION, true)
    monster_corpse_lifecycle_service.track(unit, "debug")
    unit:SetBaseMaxHealth(health)
    unit:SetMaxHealth(health)
    unit:SetHealth(health)
    unit:SetPhysicalArmorBaseValue(armor)
    attack = math.floor(attack)
    unit:SetBaseDamageMin(attack)
    unit:SetBaseDamageMax(attack)
    if can_attack then
        unit:SetBaseMoveSpeed(ADD_MONSTER_MOVE_SPEED)
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
        unit:SetAttackCapability(DOTA_UNIT_CAP_MELEE_ATTACK)
        unit:AddNewModifier(
            unit, nil, "modifier_debug_move_speed_cap", {}
        )
        if hero then
            if unit.SetAcquisitionRange then unit:SetAcquisitionRange(0) end
            local home = unit:GetAbsOrigin()
            unit:AddNewModifier(unit, nil, "modifier_practice_monster_ai", {
                hero_entindex = hero:entindex(),
                home_x = home.x,
                home_y = home.y,
                home_z = home.z,
                aggro_radius = 700,
                leash_radius = 1200,
            })
        end
    else
        unit:SetBaseMoveSpeed(0)
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
        unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    end
    notify(context, string.format(
        "测试怪已生成：生命 %d，护甲 %.1f，攻击力 %d，移速 %d，%s",
        health, armor, attack, can_attack and ADD_MONSTER_MOVE_SPEED or 0,
        can_attack and hero and "会攻击英雄"
            or can_attack and "有攻击能力（当前未召唤英雄）"
            or "不会攻击英雄"
    ))
    logger.info("CheatCommand", string.format(
        "addmonster entindex=%d health=%d armor=%.1f can_attack=%s attack=%d move_speed=%d position=(%.1f,%.1f,%.1f)",
        unit:entindex(), health, armor, tostring(can_attack), attack,
        can_attack and ADD_MONSTER_MOVE_SPEED or 0,
        unit:GetAbsOrigin().x, unit:GetAbsOrigin().y, unit:GetAbsOrigin().z
    ))
    return true
end

local function run_armor_engine_diagnostic(context)
    if not wave_system.is_dev_mode() then
        return false, "dev_mode_required: run dev first"
    end
    local ok, result_or_error = armor_engine_diagnostic.run({
        player_id = context.player_id,
        origin = ADD_MONSTER_POSITION,
    })
    if not ok then return false, result_or_error end
    notify(context, string.format(
        "护甲引擎诊断已启动：%d 个护甲档位，%d 个伤害样本；请查看控制台 ARMOR_ENGINE_DIAGNOSTIC",
        result_or_error.armor_count,
        result_or_error.case_count
    ))
    return true
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

local function add_test_hero(context)
    local function finish_test_environment(result)
        if not result or result.ok ~= true then
            notify(context, "英雄自动召唤失败："
                .. tostring(result and result.error or "unknown"), "error")
            return false
        end
        local resources = event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = context.team,
            wood = 100000000,
            gold = 100000000,
            reason = "cheat_addhero_test_resources",
        })
        if not resources or not resources.ok then return false end
        local unlocked = event_bus.request(events.SHOP_DEBUG_UNLOCK_REQUEST, {
            player_id = context.player_id,
            unlocked = true,
        })
        if not unlocked or not unlocked.ok then return false end
        show_shop(context)
        notify(context, "测试环境已就绪：齐天大圣、金币1亿、木材1亿、商城全解锁")
        print(string.format(
            "[CHEAT_ADDHERO_READY] player=%s team=%s hero=hero_monkey_king gold=%s wood=%s shop_unlocked=true",
            tostring(context.player_id), tostring(context.team),
            tostring(resources.snapshot and resources.snapshot.gold or ""),
            tostring(resources.snapshot and resources.snapshot.wood or "")))
        return true
    end

    local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
        player_id = context.player_id,
    })
    if not summoned or not summoned.ok then
        summoned = event_bus.request(events.HERO_SUMMON_REQUEST, {
            player_id = context.player_id,
            hero_id = "hero_monkey_king",
            reason = "cheat_addhero",
            debug_bypass = true,
            on_completed = finish_test_environment,
        })
        if not summoned or not summoned.ok then
            return false, summoned and summoned.error or "hero_summon_failed"
        end
    elseif summoned.hero_id ~= "hero_monkey_king" then
        return false, "another_hero_already_summoned"
    end

    if summoned.pending == true then
        notify(context, "齐天大圣资源正在准备，完成后自动开启测试环境")
        return true
    end
    if not finish_test_environment(summoned) then
        return false, "test_environment_setup_failed"
    end
    return true
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

local function find_owned_skill(snapshot, skill_id)
    for _, item in ipairs(snapshot and snapshot.skills or {}) do
        if tostring(item.skill_id or "") == skill_id then
            return item
        end
    end
    return nil
end

local function add_test_skill(context)
    local skill_id = tostring(context.args[1] or "")
    if skill_id ~= "" then
        local current = event_bus.request(
            events.HERO_SKILL_STATE_GET_REQUEST,
            { player_id = context.player_id }
        )
        if not current or not current.ok
            or not current.snapshot
            or current.snapshot.hero_ready ~= 1 then
            return false, current and current.error or "combat_hero_not_ready"
        end
        local owned = find_owned_skill(current.snapshot, skill_id)
        if owned then
            notify(
                context,
                tostring(owned.display_name or skill_id)
                    .. " 已拥有，当前 Lv." .. tostring(owned.level or 1)
            )
            return true
        end
        local result = event_bus.request(
            events.HERO_SKILL_GRANT_REQUEST,
            {
                player_id = context.player_id,
                skill_id = skill_id,
                levels = 1,
                source = "cheat_addskill",
            }
        )
        if not result or not result.ok then
            return false, result and result.error or "skill_grant_failed"
        end
        local granted = find_owned_skill(result.snapshot, skill_id)
        notify(
            context,
            "已获得技能："
                .. tostring(granted and granted.display_name or skill_id)
                .. " Lv." .. tostring(result.level or 1)
        )
        return true
    end

    local result = event_bus.request(
        events.HERO_SKILL_POINT_SET_REQUEST,
        { player_id = context.player_id, points = 10 }
    )
    if not result or not result.ok then
        return false, result and result.error or "skill_points_set_failed"
    end
    notify(context, "技能点已设置为 10")
    return true
end

local function unlock_skill(context)
    local slot = string.lower(tostring(context.args[1] or ""))
    if slot ~= "e" then return false, "usage: unlock e" end
    local current = event_bus.request(
        events.HERO_SKILL_STATE_GET_REQUEST,
        { player_id = context.player_id }
    )
    local snapshot = current and current.snapshot
    if not current or not current.ok or not snapshot
        or snapshot.hero_ready ~= 1 then
        return false, current and current.error or "combat_hero_not_ready"
    end
    if snapshot.hero_id ~= "hero_monkey_king" then
        return false, "unlock_e_requires_monkey_king"
    end
    local owned = find_owned_skill(snapshot, MONKEY_KING_E_SKILL)
    if owned and owned.locked ~= 1 and (tonumber(owned.level) or 0) > 0 then
        notify(context, "齐天大圣 E 已解锁")
        return true
    end
    local result = event_bus.request(events.HERO_SKILL_GRANT_REQUEST, {
        player_id = context.player_id,
        skill_id = MONKEY_KING_E_SKILL,
        levels = 1,
        source = "cheat_unlock_e",
    })
    if not result or not result.ok then
        return false, result and result.error or "unlock_e_failed"
    end
    notify(context, "已解锁齐天大圣 E：齐天")
    return true
end

local function pass_rebirth(context)
    local requested = tonumber(context.command_suffix)
    if not requested then return false, "rebirth_level_invalid" end
    local progression = event_bus.request(
        events.HERO_PROGRESSION_GET_REQUEST,
        { player_id = context.player_id }
    )
    if not progression or not progression.ok then
        return false, progression and progression.error or "progression_get_failed"
    end
    local current = tonumber(progression.snapshot.rebirth_level) or 0
    if requested ~= current + 1 then
        return false, "rebirth_must_be_next"
    end
    local result = event_bus.request(events.MONSTER_REWARD_GRANT_REQUEST, {
        player_id = context.player_id,
        team = context.team,
        reward_profile_id = string.format("reward_rebirth_%02d", requested),
        encounter_id = "cheat_pass_" .. tostring(requested),
    })
    if not result or not result.ok then
        return false, result and result.error or "rebirth_reward_failed"
    end
    notify(context, "已通过第 " .. tostring(requested) .. " 转")
    return true
end

local function scale_selected_wall(context)
    local multiplier = tonumber(context.args[1])
    if not multiplier then
        return false, "scale_number_required"
    end
    local entindex = selected_entindex_by_player[context.player_id]
    local ok, radius_or_error, base_radius = building_system.set_wall_hull_scale(
        context.player_id,
        entindex,
        multiplier
    )
    if not ok then return false, radius_or_error end
    notify(context, string.format(
        "城墙碰撞倍率 %.2f：基础 %.0f，当前 %.0f",
        multiplier,
        base_radius,
        radius_or_error
    ))
    return true
end

local function scale_monsters(context)
    local multiplier = finite_number(context.args[1])
    if not multiplier or multiplier <= 0 then
        return false, "usage: scalemonster <positive_number>"
    end
    local ok, result_or_error = wave_system.set_monster_hull_scale(multiplier)
    if not ok then return false, result_or_error end
    local result = result_or_error
    local base_text = result.applied > 0 and string.format(
        "原生Hull %.1f~%.1f，当前Hull %.1f~%.1f",
        result.base_min,
        result.base_max,
        result.radius_min,
        result.radius_max
    ) or "当前没有存活波次怪，倍率将应用于之后生成的怪物"
    notify(context, string.format(
        "怪物碰撞倍率 %.3f：已应用 %d，失败 %d；%s",
        result.multiplier,
        result.applied,
        result.failed,
        base_text
    ))
    logger.info("CheatCommand", string.format(
        "scalemonster multiplier=%.6f applied=%d failed=%d base=%s~%s radius=%s~%s",
        result.multiplier,
        result.applied,
        result.failed,
        tostring(result.base_min),
        tostring(result.base_max),
        tostring(result.radius_min),
        tostring(result.radius_max)
    ))
    return true
end

local function show_rogue_offer(context)
    if #context.args ~= 3 then
        return false, "usage: rogue <card_id1> <card_id2> <card_id3>"
    end
    local result = rogue_reward_service.debug_offer(
        context.player_id,
        { context.args[1], context.args[2], context.args[3] }
    )
    if not result or not result.ok then
        return false, result and result.error or "rogue_debug_offer_failed"
    end
    return true
end

local function on_scale_selection_changed(_, payload)
    local player_id = tonumber(payload and payload.PlayerID)
    if not valid_player_id(player_id) then return end
    selected_entindex_by_player[player_id] = tonumber(payload.entindex) or -1
end

local COMMANDS = {
    dev = enable_dev,
    shopshow = show_shop,
    addgold = add_gold,
    addwood = add_wood,
    addhero = add_test_hero,
    addattack = add_attack,
    addarmor = add_armor,
    blood = change_hero_health,
    addmonster = add_monster,
    armortest = run_armor_engine_diagnostic,
    addtechnology = add_technology,
    research_test = run_research_test,
    monster = spawn_wave,
    addspeed = attack_speed_cheat.execute,
    setvip = set_vip,
    summonhero = summon_hero,
    spawnboss = spawn_boss,
    skilloffer = skill_offer,
    skillchoose = skill_choose,
    skills = list_skills,
    addskill = add_test_skill,
    unlock = unlock_skill,
    additem = weapon_cheats.add_item,
    items = weapon_cheats.list_items,
    givegrowthsword = weapon_cheats.give_growth_sword,
    givehammer = weapon_cheats.give_forging_hammer,
    weapongrow = weapon_cheats.grow_weapon,
    weaponstats = weapon_cheats.weapon_stats,
    attack40b = weapon_cheats.set_attack_40b,
    attackreset = weapon_cheats.reset_attack,
    scale = scale_selected_wall,
    scalemonster = scale_monsters,
    rogue = show_rogue_offer,
}

local function on_player_chat(keys)
    local args = words(keys and keys.text)
    local command = string.gsub(args[1] or "", "^%-", "")
    local handler = COMMANDS[command]
    local command_suffix = nil
    local monster_number = string.match(command, "^monster(%d+)$")
    if monster_number then
        handler = spawn_wave
        command_suffix = monster_number
    end
    local pass_number = string.match(command, "^pass(%d+)$")
    if pass_number then
        handler = pass_rebirth
        command_suffix = pass_number
    end
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
        command_suffix = command_suffix,
    })
    if ok then
        logger.info("CheatCommand", command .. " executed")
    else
        logger.warn(
            "CheatCommand",
            command .. " failed: " .. tostring(error_code)
        )
        notify({ player_id = player_id },
            "命令执行失败：" .. tostring(error_code), "error")
    end
end

function M.init()
    selected_entindex_by_player = {}
    attack_speed_cheat.init()
    ListenToGameEvent("player_chat", on_player_chat, nil)
    CustomGameEventManager:RegisterListener(
        "survival_scale_selection_changed",
        on_scale_selection_changed
    )
    logger.info(
        "CheatCommand",
        "ready: addhero, addskill, unlock e, blood, armortest, research_test, addtechnology, monster, rogue, items, hero, skill, weapon growth"
    )
end

M._test = {
    unlock_skill = unlock_skill,
    show_rogue_offer = show_rogue_offer,
}

return M
