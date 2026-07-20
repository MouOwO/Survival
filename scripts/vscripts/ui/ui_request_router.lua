local event_bus = require("core/event_bus")
local events = require("core/events")
local building_system = require("systems/building_system")

local M = {}

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
    return {
        entindex = unit:entindex(),
        unit_name = unit.survival_display_name
            or (unit.GetUnitName and unit:GetUnitName()) or "",
        display_name = unit.survival_display_name
            or (unit.GetUnitName and unit:GetUnitName()) or "",
        level = tonumber(unit.survival_level)
            or safe_number(unit, "GetLevel", 1),
        attack_min = attack_min,
        attack_max = attack_max,
        armor = tonumber(unit.survival_armor)
            or safe_number(unit, "GetPhysicalArmorBaseValue", nil)
            or safe_number(unit, "GetPhysicalArmorValue", 0, false),
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
            send_to_player("ui_selected_unit_stats_snapshot", player_id, {
                success = 0,
                entindex = entindex or -1,
                error = "invalid_unit",
            })
            return
        end
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

local function publish_building_snapshot(payload)
    local player_id = tonumber(payload and payload.player_id)
    local entindex = tonumber(payload and payload.entindex)
    if not valid_player_id(player_id) or not entindex then return end
    local ok, unit = pcall(EntIndexToHScript, entindex)
    if not ok or not unit or unit:IsNull() then return end
    local snapshot = unit_combat_snapshot(unit)
    snapshot.success = 1
    snapshot.reason = payload.reason or "building_changed"
    snapshot.display_name = payload.display_name or snapshot.display_name
    snapshot.unit_name = snapshot.display_name
    snapshot.level = tonumber(payload.level) or snapshot.level
    snapshot.attack_min = tonumber(payload.attack_min) or snapshot.attack_min
    snapshot.attack_max = tonumber(payload.attack_max) or snapshot.attack_max
    snapshot.armor = tonumber(payload.armor) or snapshot.armor
    snapshot.attack_speed = tonumber(payload.attack_speed) or snapshot.attack_speed
    send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
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
        send_to_player("ui_operation_result", player_id, {
            request_id = payload.request_id or "",
            success = result and result.ok and 1 or 0,
            operation = "shop_purchase",
            entry_id = payload.entry_id or "",
            error = result and result.error or "unknown_error",
        })
    end)
end

local function building_id_for_ability(ability_name)
    local map = {
        ability_build_wall = "wall",
        ability_build_main_city = "main_city",
        ability_build_arrow_tower = "arrow_tower",
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
        if is_point_target then
            print("[SURVIVAL_CAST][SERVER] REJECT point_target_requires_client_position name="
                .. tostring(ability_name))
        elseif ok then
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
        elseif not is_point_target then
            print("[SURVIVAL_CAST][SERVER] REJECT ability_cast_rejected")
        end
        send_to_player("ui_ability_cast_result", player_id, {
            success = ok and 1 or 0,
            entindex = entindex or -1,
            ability_entindex = ability_entindex or -1,
            ability_name = ability_name,
            behavior = behavior,
            error = ok and "" or (is_point_target
                and "point_target_requires_client_position"
                or "ability_cast_rejected"),
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
    register_selected_unit_stats_request()
    register_building_snapshot_push()
    register_snapshot_request()
    register_shop_open_request()
    register_shop_close_request()
    register_shop_purchase_request()
    register_ability_cast_request()
    register_ability_cast_position_request()
    register_building_move_request()
    event_bus.subscribe(events.UI_NOTIFICATION, on_notification)
    event_bus.subscribe(events.SHOP_STATE_CHANGED, on_shop_state_changed)
end

return M
