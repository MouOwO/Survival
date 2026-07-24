local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local building_system = require("systems/building_system")
local weapon_snapshot = require("ui/weapon_synthesis_snapshot_service")
local unit_display_names = require("config/generated/unit_display_names")

local M = {}
local synthesis_requests = {}
local building_snapshot_sequence = 0
local ability_request_sequence = 0
local selected_unit_by_player = {}

local function safe_number(entity, method_name, fallback, ...)
    local method = entity and entity[method_name]
    if type(method) ~= "function" then return fallback end
    local ok, result = pcall(method, entity, ...)
    if ok and result ~= nil then return tonumber(result) end
    return fallback
end

local function unit_combat_snapshot(unit)
    local strength = safe_number(unit, "GetStrength", 0)
    local agility = safe_number(unit, "GetAgility", 0)
    local intellect = safe_number(unit, "GetIntellect", 0)
    local attack_min = tonumber(unit.survival_attack_min)
        or safe_number(unit, "GetDamageMin", nil)
    local attack_max = tonumber(unit.survival_attack_max)
        or safe_number(unit, "GetDamageMax", nil)
    if attack_min == nil then attack_min = safe_number(unit, "GetBaseDamageMin", 0) end
    if attack_max == nil then attack_max = safe_number(unit, "GetBaseDamageMax", attack_min) end
    local internal_name = (unit.GetUnitName and unit:GetUnitName()) or ""
    local configured_name = (unit_display_names.by_id or {})[internal_name]
    local display_name = unit.survival_display_name
        or (configured_name and configured_name.enabled ~= false
            and configured_name.display_name)
        or internal_name
    return {
        entindex = unit:entindex(),
        unit_name = internal_name,
        display_name = display_name,
        level = tonumber(unit.survival_level)
            or safe_number(unit, "GetLevel", 1),
        health = safe_number(unit, "GetHealth", 0),
        max_health = safe_number(unit, "GetMaxHealth", 0),
        mana = safe_number(unit, "GetMana", 0),
        max_mana = safe_number(unit, "GetMaxMana", 0),
        attack_min = attack_min,
        attack_max = attack_max,
        -- 必须读取包含 Modifier 加减值的当前有效护甲；基础护甲和配置缓存
        -- 无法反映攻击减甲科技的实时叠层。
        armor = safe_number(unit, "GetPhysicalArmorValue", nil, false)
            or tonumber(unit.survival_armor)
            or safe_number(unit, "GetPhysicalArmorBaseValue", 0),
        -- attack_speed 表示每秒攻击次数，不是 BAT，也不是 Dota 百分比攻速。
        -- 缺少显式配置时由引擎基础攻击间隔换算，默认 0.5 次/秒。
        attack_speed = tonumber(unit.survival_attack_speed)
            or (1 / math.max(0.01,
                safe_number(unit, "GetBaseAttackTime", 2))),
        attack_speed_stat = safe_number(unit, "GetAttackSpeed", 100),
        strength = strength,
        agility = agility,
        intellect = intellect,
        source = "selected_unit_runtime",
    }
end

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function source_player_id(payload)
    -- Panorama-to-server custom events inject PlayerID. Never trust a custom
    -- player_id field supplied by the client.
    return tonumber(payload and payload.PlayerID)
end

local function send_to_player(event_name, player_id, payload)
    if not valid_player_id(player_id) then return end
    local player = PlayerResource:GetPlayer(player_id)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, event_name, payload)
    end
end

local function register_selected_unit_stats_request()
    CustomGameEventManager:RegisterListener("ui_selected_unit_stats_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local entindex = tonumber(payload and payload.entindex)
        local ok, unit = pcall(EntIndexToHScript, entindex or -1)
        if not ok or not unit or unit:IsNull() then
            selected_unit_by_player[player_id] = nil
            send_to_player("ui_selected_unit_stats_snapshot", player_id, {
                success = 0,
                entindex = entindex or -1,
                error = "invalid_unit",
            })
            return
        end
        selected_unit_by_player[player_id] = entindex
        -- 英雄的攻击/属性可能还叠加武器成长和专属投影，必须优先使用
        -- hero_combat_stat_service 的权威快照，不能再用引擎临时值覆盖它。
        local hero_result = event_bus.request(
            events.HERO_COMBAT_STATS_GET_REQUEST,
            { player_id = player_id }
        )
        if hero_result and hero_result.ok and hero_result.snapshot
            and tonumber(hero_result.snapshot.entindex) == entindex then
            local snapshot = {}
            for key, value in pairs(hero_result.snapshot) do snapshot[key] = value end
            snapshot.success = 1
            snapshot.source = "hero_combat_stat_service"
            send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
            return
        end
        local snapshot = unit_combat_snapshot(unit)
        snapshot.success = 1
        send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
    end)
end

local function on_unit_combat_stats_changed(payload)
    local entindex = tonumber(payload and payload.entindex)
    local unit = payload and payload.unit
    if not entindex then return end
    if not unit or unit:IsNull() then
        local ok, resolved = pcall(EntIndexToHScript, entindex)
        if not ok or not resolved or resolved:IsNull() then return end
        unit = resolved
    end
    for player_id, selected_entindex in pairs(selected_unit_by_player) do
        if tonumber(selected_entindex) == entindex and valid_player_id(player_id) then
            local snapshot = unit_combat_snapshot(unit)
            snapshot.success = 1
            snapshot.reason = payload.reason or "unit_combat_stats_changed"
            snapshot.push_phase = "immediate"
            send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
        end
    end
end

local function send_building_snapshot(payload, phase)
    local player_id = tonumber(payload and payload.player_id)
    local entindex = tonumber(payload and payload.entindex)
    if not valid_player_id(player_id) or not entindex then return end
    local ok, unit = pcall(EntIndexToHScript, entindex)
    if not ok or not unit or unit:IsNull() then return end
    local snapshot = unit_combat_snapshot(unit)
    building_snapshot_sequence = building_snapshot_sequence + 1
    snapshot.success = 1
    snapshot.refresh_sequence = building_snapshot_sequence
    snapshot.reason = payload.reason or "building_changed"
    snapshot.display_name = payload.display_name or snapshot.display_name
    snapshot.unit_name = snapshot.display_name
    snapshot.level = tonumber(payload.level) or snapshot.level
    snapshot.attack_min = tonumber(payload.attack_min) or snapshot.attack_min
    snapshot.attack_max = tonumber(payload.attack_max) or snapshot.attack_max
    snapshot.armor = tonumber(payload.armor) or snapshot.armor
    snapshot.attack_speed = tonumber(payload.attack_speed) or snapshot.attack_speed
    snapshot.push_phase = phase or "immediate"
    print(string.format(
        "[SURVIVAL_STATS][SERVER] BUILDING_PUSH player=%s unit=%s phase=%s sequence=%s level=%s attack=%s-%s armor=%s",
        tostring(player_id), tostring(entindex), tostring(snapshot.push_phase),
        tostring(snapshot.refresh_sequence), tostring(snapshot.level),
        tostring(snapshot.attack_min), tostring(snapshot.attack_max),
        tostring(snapshot.armor)
    ))
    send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
end

local function publish_building_snapshot(payload)
    send_building_snapshot(payload, "immediate")
    local entindex = tonumber(payload and payload.entindex)
    if not entindex then return end
    local delayed_payload = {}
    for key, value in pairs(payload) do delayed_payload[key] = value end
    scheduler.after(0.15, function()
        send_building_snapshot(delayed_payload, "delayed")
    end, "building_snapshot_refresh_" .. tostring(entindex))
end

local function register_building_snapshot_push()
    event_bus.subscribe(events.BUILDING_CHANGED, publish_building_snapshot)
end

local function register_snapshot_request()
    CustomGameEventManager:RegisterListener("ui_request_full_snapshot", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        event_bus.emit(events.UI_SNAPSHOT_REQUESTED, {
            player_id = player_id,
            request_id = payload.request_id,
        })
        send_to_player("ui_operation_result", player_id, {
            request_id = payload.request_id or "",
            success = 1,
            operation = "full_snapshot",
        })
    end)
end

local function register_shop_open_request()
    CustomGameEventManager:RegisterListener("ui_shop_open_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local result = event_bus.request(events.SHOP_OPEN_REQUEST, {
            player_id = player_id,
            request_id = payload.request_id,
            known_sequence = tonumber(payload.known_sequence) or 0,
            mode = payload.mode,
            source_entindex = tonumber(payload.source_entindex),
        })
        if result and result.ok and result.snapshot then
            send_to_player("ui_shop_snapshot", player_id, result.snapshot)
            return
        end
        send_to_player("ui_operation_result", player_id, {
            request_id = payload.request_id or "",
            success = 0,
            operation = "shop_open",
            error = result and result.error or "shop_snapshot_failed",
        })
    end)
end

local function register_shop_close_request()
    CustomGameEventManager:RegisterListener("ui_shop_close_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        event_bus.request(events.SHOP_CLOSE_REQUEST, {
            player_id = player_id,
            request_id = payload.request_id,
        })
    end)
end

local function register_shop_purchase_request()
    CustomGameEventManager:RegisterListener("ui_shop_purchase_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local result = event_bus.request(events.SHOP_PURCHASE_REQUEST, {
            player_id = player_id,
            entry_id = tostring(payload.entry_id or ""),
            request_id = payload.request_id,
        })
        local encounter_started = result and result.ok
            and result.grant_result
            and tostring(result.grant_result.encounter_id or "") ~= ""
        local focus_hero_entindex = -1
        if encounter_started then
            local summon = event_bus.request(
                events.HERO_SUMMON_GET_REQUEST,
                { player_id = player_id }
            )
            local hero = summon and summon.unit or nil
            if hero and not hero:IsNull() then
                focus_hero_entindex = hero:entindex()
            end
        end
        send_to_player("ui_operation_result", player_id, {
            request_id = payload.request_id or "",
            success = result and result.ok and 1 or 0,
            operation = "shop_purchase",
            entry_id = payload.entry_id or "",
            error = result and result.error or "unknown_error",
            close_shop_and_focus_hero = encounter_started and 1 or 0,
            focus_hero_entindex = focus_hero_entindex,
        })
    end)
end

local function synthesis_result(player_id, request_id, recipe_id, result)
    send_to_player("ui_weapon_synthesis_result", player_id, {
        request_id = request_id,
        recipe_id = recipe_id,
        success = result and result.ok and 1 or 0,
        error = result and result.error or "synthesis_unknown_error",
        result_content_id = result and result.result_content_id or "",
    })
end

local function register_weapon_synthesis_request()
    CustomGameEventManager:RegisterListener(
        "ui_weapon_synthesis_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            local request_id = tostring(payload and payload.request_id or "")
            local recipe_id = tostring(payload and payload.recipe_id or "")
            if not valid_player_id(player_id) then return end
            if request_id == "" or #request_id > 96 then
                synthesis_result(player_id, request_id, recipe_id,
                    { ok = false, error = "synthesis_request_id_invalid" })
                return
            end
            if recipe_id == "" or #recipe_id > 128 then
                synthesis_result(player_id, request_id, recipe_id,
                    { ok = false, error = "synthesis_recipe_id_invalid" })
                return
            end
            synthesis_requests[player_id] = synthesis_requests[player_id] or {}
            if synthesis_requests[player_id][request_id] then
                synthesis_result(player_id, request_id, recipe_id,
                    { ok = false, error = "synthesis_duplicate_request" })
                return
            end
            synthesis_requests[player_id][request_id] = true
            local result = event_bus.request(events.WEAPON_SYNTHESIS_REQUEST, {
                player_id = player_id,
                recipe_id = recipe_id,
                request_id = request_id,
            })
            synthesis_result(player_id, request_id, recipe_id, result)
            weapon_snapshot.publish_player(player_id, "synthesis_result")
        end
    )
end

local function register_weapon_snapshot_request()
    CustomGameEventManager:RegisterListener(
        "ui_weapon_snapshot_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then return end
            weapon_snapshot.publish_player(player_id, "client_request")
        end
    )
end

local function building_id_for_ability(ability_name)
    local map = {
        ability_build_wall = "wall",
        ability_build_main_city = "main_city",
        ability_build_arrow_tower = "arrow_tower",
        ability_build_research_lab = "building_research_lab",
        ability_build_gold_mine = "gold_mine",
        ability_build_hero_altar = "hero_altar",
    }
    return map[ability_name]
end

local function register_ability_cast_position_request()
    print("[SURVIVAL_CAST][SERVER] point listener registered v20260720_2325")
    CustomGameEventManager:RegisterListener("ui_ability_cast_position_request", function(_, payload)
        local player_id = source_player_id(payload)
        local entindex = tonumber(payload and payload.entindex)
        local ability_entindex = tonumber(payload and payload.ability_entindex)
        local x, y, z = tonumber(payload and payload.x), tonumber(payload and payload.y), tonumber(payload and payload.z)
        print(string.format("[SURVIVAL_CAST][SERVER] POINT_RECV player=%s unit=%s ability=%s pos=(%s,%s,%s)",
            tostring(player_id), tostring(entindex), tostring(ability_entindex), tostring(x), tostring(y), tostring(z)))
        if not valid_player_id(player_id) then
            print("[SURVIVAL_CAST][SERVER] POINT_REJECT invalid_player")
            return
        end
        if not x or not y or not z then
            print("[SURVIVAL_CAST][SERVER] POINT_REJECT invalid_position")
            send_to_player("ui_ability_cast_result", player_id, {
                success = 0, entindex = entindex or -1,
                ability_entindex = ability_entindex or -1,
                error = "invalid_position",
            })
            return
        end
        local unit = entindex and EntIndexToHScript(entindex) or nil
        local ability = ability_entindex and EntIndexToHScript(ability_entindex) or nil
        local unit_valid = unit ~= nil and not unit:IsNull()
        local ability_valid = ability ~= nil and not ability:IsNull()
        local ability_name = ability_valid and ability:GetAbilityName() or ""
        local building_id = building_id_for_ability(ability_name)
        local owner_id = unit_valid and unit:GetPlayerOwnerID() or -999
        local caster_matches = ability_valid and ability:GetCaster() == unit
        local behavior = ability_valid and ability:GetBehaviorInt() or -1
        local is_point_target = ability_valid
            and bit.band(behavior, DOTA_ABILITY_BEHAVIOR_POINT) ~= 0
        print(string.format("[SURVIVAL_CAST][SERVER] POINT_CHECK name=%s building=%s unit_valid=%s ability_valid=%s caster_matches=%s owner=%s point=%s",
            tostring(ability_name), tostring(building_id), tostring(unit_valid), tostring(ability_valid),
            tostring(caster_matches), tostring(owner_id), tostring(is_point_target)))
        if not unit_valid or not ability_valid or not building_id
            or not caster_matches or owner_id ~= player_id or not is_point_target then
            print("[SURVIVAL_CAST][SERVER] POINT_REJECT validation")
            return
        end
        local position = Vector(x, y, z)
        local check = event_bus.request(events.BUILD_CAN_PLACE_REQUEST, {
            caster = unit,
            building_id = building_id,
            position = position,
        })
        print("[SURVIVAL_CAST][SERVER] POINT_VALIDATE ok=" .. tostring(check and check.ok)
            .. " error=" .. tostring(check and check.error or ""))
        if not check or not check.ok then
            send_to_player("ui_ability_cast_result", player_id, {
                success = 0, entindex = entindex, ability_entindex = ability_entindex,
                ability_name = ability_name, behavior = behavior,
                error = check and check.error or "build_validation_failed",
            })
            return
        end
        event_bus.emit(events.BUILD_REQUEST, {
            caster = unit,
            building_id = building_id,
            position = position,
        })
        print("[SURVIVAL_CAST][SERVER] POINT_BUILD_EMITTED building=" .. tostring(building_id))
        send_to_player("ui_ability_cast_result", player_id, {
            success = 1, entindex = entindex, ability_entindex = ability_entindex,
            ability_name = ability_name, behavior = behavior, error = "",
        })
    end)
end

local function register_ability_cast_request()
    print("[SURVIVAL_CAST][SERVER] listener registered v20260720_2252")
    CustomGameEventManager:RegisterListener("ui_ability_cast_request", function(_, payload)
        local player_id = source_player_id(payload)
        local entindex = tonumber(payload and payload.entindex)
        local ability_entindex = tonumber(payload and payload.ability_entindex)
        print(string.format(
            "[SURVIVAL_CAST][SERVER] RECV player=%s unit=%s ability=%s",
            tostring(player_id), tostring(entindex), tostring(ability_entindex)
        ))
        if not valid_player_id(player_id) then
            print("[SURVIVAL_CAST][SERVER] REJECT invalid_player")
            return
        end
        local unit = entindex and EntIndexToHScript(entindex) or nil
        local ability = ability_entindex and EntIndexToHScript(ability_entindex) or nil
        local unit_valid = unit ~= nil and not unit:IsNull()
        local ability_valid = ability ~= nil and not ability:IsNull()
        local ability_name = ability_valid and ability:GetAbilityName() or ""
        local caster_matches = ability_valid and ability:GetCaster() == unit
        local owner_id = unit_valid and unit:GetPlayerOwnerID() or -999
        -- 当前 Dota API 没有对应的 PlayerResource 控制权查询方法。
        -- 这里使用实体所有权作为服务端校验，避免无效 API 中断 Lua。
        local owner_matches = owner_id == player_id
        local passive = ability_valid and ability:IsPassive() or false
        local behavior = ability_valid and ability:GetBehaviorInt() or -1
        print(string.format(
            "[SURVIVAL_CAST][SERVER] CHECK name=%s unit_valid=%s ability_valid=%s caster_matches=%s owner=%s owner_matches=%s passive=%s behavior=%s level=%s cooldown=%s castable=%s",
            tostring(ability_name), tostring(unit_valid), tostring(ability_valid),
            tostring(caster_matches), tostring(owner_id), tostring(owner_matches),
            tostring(passive), tostring(behavior), tostring(ability_valid and ability:GetLevel() or -1),
            tostring(ability_valid and ability:GetCooldownTimeRemaining() or -1),
            tostring(ability_valid and ability:IsFullyCastable() or false)
        ))
        local is_point_target = ability_valid
            and bit.band(behavior, DOTA_ABILITY_BEHAVIOR_POINT) ~= 0
        local ok = unit_valid and ability_valid and caster_matches
            and owner_matches and not passive and not is_point_target
        local tower_upgrade_mode = ({
            ability_upgrade_tower = "one",
            ability_upgrade_tower_lv01 = "one",
            ability_upgrade_tower_max = "max",
        })[ability_name]
        local tower_class_index = tonumber(string.match(
            ability_name,
            "^ability_tower_class_(%d+)$"
        ))
        local tower_action = tower_upgrade_mode ~= nil or tower_class_index ~= nil
        local tower_ability_matches = tower_action and unit_valid
            and ability_valid and unit:FindAbilityByName(ability_name) == ability
        local gold_mine_actions = {
            ability_upgrade_gold_mine = "level",
            ability_upgrade_gold_mine_efficiency = "efficiency",
            ability_upgrade_gold_mine_crit = "crit",
            ability_gold_mine_auto_upgrade = "auto",
            ability_gold_mine_stop_auto_upgrade = "auto",
        }
        local gold_mine_action = gold_mine_actions[ability_name]
        local gold_mine_ability_matches = gold_mine_action and unit_valid
            and ability_valid and unit:FindAbilityByName(ability_name) == ability
        local handled_directly = false
        local direct_result_required = false
        local direct_result = nil
        local direct_error = nil
        if tower_ability_matches and owner_matches and not passive
            and not is_point_target and tower_upgrade_mode then
            -- Dynamic Lua abilities on npc_dota_creature buildings do not
            -- reliably enter OnSpellStart through CastAbilityNoTarget. Route
            -- tower UI actions straight to the authoritative building system;
            -- ownership/ability validation above and resource/level validation
            -- in building_upgrade_system remain unchanged.
            event_bus.emit(events.BUILDING_UPGRADE_REQUEST, {
                building = unit,
                upgrade_mode = tower_upgrade_mode,
            })
            handled_directly = true
            print("[SURVIVAL_CAST][SERVER] TOWER_UPGRADE_DISPATCHED mode="
                .. tostring(tower_upgrade_mode))
        elseif tower_ability_matches and owner_matches and not passive
            and not is_point_target and tower_class_index and tower_class_index >= 1
            and tower_class_index <= 7 then
            event_bus.emit(events.TOWER_CLASS_REQUEST, {
                tower = unit,
                class_index = tower_class_index,
            })
            handled_directly = true
            print("[SURVIVAL_CAST][SERVER] TOWER_CLASS_DISPATCHED index="
                .. tostring(tower_class_index))
        elseif gold_mine_ability_matches and owner_matches and not passive
            and not is_point_target then
            handled_directly = true
            direct_result_required = true
            if not ability:IsActivated() or ability:IsHidden() then
                direct_result = { ok = false, error = "金矿技能当前不可用" }
            else
                ability_request_sequence = ability_request_sequence + 1
                if gold_mine_action == "level" then
                    direct_result, direct_error = event_bus.request(
                        events.GOLD_MINE_LEVEL_UPGRADE_REQUEST,
                        { entindex = entindex }
                    )
                elseif gold_mine_action == "efficiency"
                    or gold_mine_action == "crit" then
                    local group = gold_mine_action == "efficiency"
                        and "gold_mine_efficiency" or "gold_mine_crit"
                    direct_result, direct_error = event_bus.request(
                        events.TECHNOLOGY_PURCHASE_NEXT_REQUEST,
                        {
                            player_id = player_id,
                            technology_group = group,
                            source = "gold_mine_ability",
                            entindex = entindex,
                            request_id = "gold_mine_ui_" .. tostring(entindex)
                                .. "_" .. tostring(ability_request_sequence),
                        }
                    )
                else
                    direct_result, direct_error = event_bus.request(
                        events.GOLD_MINE_AUTO_UPGRADE_REQUEST,
                        { entindex = entindex }
                    )
                end
            end
            local succeeded = direct_result and direct_result.ok == true
            local message = direct_result
                and (direct_result.error or direct_result.message)
                or direct_error
            if message and message ~= "" then
                event_bus.emit(events.UI_NOTIFICATION, {
                    player_id = player_id,
                    message = message,
                    level = succeeded and "info" or "error",
                })
            end
            print("[SURVIVAL_CAST][SERVER] GOLD_MINE_DISPATCHED action="
                .. tostring(gold_mine_action) .. " ok=" .. tostring(succeeded)
                .. " error=" .. tostring(message or ""))
        end
        if is_point_target then
            print("[SURVIVAL_CAST][SERVER] REJECT point_target_requires_client_position name="
                .. tostring(ability_name))
        elseif ok and not handled_directly then
            -- 这里只处理无目标技能；点目标技能必须由客户端先进入选点模式。
            unit:CastAbilityNoTarget(ability, player_id)
            print("[SURVIVAL_CAST][SERVER] CAST_ISSUED name=" .. tostring(ability_name))
            GameRules:GetGameModeEntity():SetContextThink(
                "survival_cast_diag_" .. tostring(ability_entindex),
                function()
                    if ability and not ability:IsNull() then
                        print("[SURVIVAL_CAST][SERVER] AFTER name=" .. tostring(ability_name)
                            .. " cooldown=" .. tostring(ability:GetCooldownTimeRemaining())
                            .. " phase=" .. tostring(ability:IsInAbilityPhase()))
                    end
                    return nil
                end,
                0.10
            )
        elseif not is_point_target and not handled_directly then
            print("[SURVIVAL_CAST][SERVER] REJECT ability_cast_rejected")
        end
        local request_accepted
        if direct_result_required then
            request_accepted = direct_result ~= nil and direct_result.ok == true
        elseif handled_directly then
            request_accepted = true
        else
            request_accepted = ok
        end
        local response_error = ""
        if not request_accepted then
            response_error = direct_result and direct_result.error
                or direct_error
                or (is_point_target and "point_target_requires_client_position"
                    or "ability_cast_rejected")
        end
        send_to_player("ui_ability_cast_result", player_id, {
            success = request_accepted and 1 or 0,
            entindex = entindex or -1,
            ability_entindex = ability_entindex or -1,
            ability_name = ability_name,
            behavior = behavior,
            error = response_error,
        })
    end)
end

local function register_building_move_request()
    CustomGameEventManager:RegisterListener("ui_building_move_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
        if not x or not y or not z then
            send_to_player("ui_building_move_result", player_id, {
                success = 0, error = "invalid_position",
            })
            return
        end
        local ok, error_code = building_system.relocate_for_player(
            player_id,
            tonumber(payload.entindex),
            Vector(x, y, z)
        )
        send_to_player("ui_building_move_result", player_id, {
            success = ok and 1 or 0,
            error = error_code or "",
            entindex = tonumber(payload.entindex) or -1,
        })
    end)
end

local function register_return_home_request()
    CustomGameEventManager:RegisterListener("ui_return_home_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
            player_id = player_id,
        })
        local result = { ok = false, error = "hero_not_summoned" }
        if summoned and summoned.ok and summoned.unit
            and not summoned.unit:IsNull() and summoned.unit:IsAlive() then
            local ability = summoned.unit:FindAbilityByName(
                "ability_survival_return_home"
            )
            if ability and not ability:IsNull() and ability:IsFullyCastable() then
                summoned.unit:CastAbilityNoTarget(ability, player_id)
                result = { ok = true }
            else
                result = { ok = false, error = "return_home_not_ready" }
            end
        end
        if not result.ok and result.error == "hero_not_summoned" then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = "尚未召唤英雄",
                level = "error",
            })
        elseif not result.ok and result.error == "return_home_not_ready" then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = "回城技能尚未就绪",
                level = "error",
            })
        end
        send_to_player("ui_return_home_result", player_id, {
            success = result.ok and 1 or 0,
            error = result.error or "",
        })
    end)
end

local function on_notification(payload)
    send_to_player("ui_notification", payload.player_id, {
        message = payload.message or "",
        level = payload.level or "info",
    })
end

local function on_shop_state_changed(payload)
    if not payload or not payload.snapshot then return end
    send_to_player("ui_shop_snapshot", payload.player_id, payload.snapshot)
end

function M.init()
    synthesis_requests = {}
    building_snapshot_sequence = 0
    ability_request_sequence = 0
    selected_unit_by_player = {}
    register_selected_unit_stats_request()
    register_building_snapshot_push()
    register_snapshot_request()
    register_shop_open_request()
    register_shop_close_request()
    register_shop_purchase_request()
    register_weapon_synthesis_request()
    register_weapon_snapshot_request()
    register_ability_cast_request()
    register_ability_cast_position_request()
    register_building_move_request()
    register_return_home_request()
    event_bus.subscribe(events.UNIT_COMBAT_STATS_CHANGED, on_unit_combat_stats_changed)
    event_bus.subscribe(events.UI_NOTIFICATION, on_notification)
    event_bus.subscribe(events.SHOP_STATE_CHANGED, on_shop_state_changed)
end

return M
