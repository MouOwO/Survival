local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local building_system = require("systems/building_system")
local weapon_snapshot = require("ui/weapon_synthesis_snapshot_service")
local unit_display_names = require("config/generated/unit_display_names")
local research_events = require("research/research_event_names")
local combat_stat_projection = require("ui/combat_stat_projection")
local asset_catalog = require("config/asset_catalog")
local armor_balance = require("config/armor_balance")
local hero_summon_projection = require("systems/hero_summon_projection")
local building_batch_upgrade = require("systems/building_batch_upgrade_service")
local gold_mine_batch_upgrade = require("systems/gold_mine_batch_upgrade_service")
local tree_config = require("config/tree_config")
local research_lab_abilities = require("config/generated/research_lab_abilities")

local M = {}
local synthesis_requests = {}
local building_snapshot_sequence = 0
local selected_unit_by_player = {}

local function safe_number(entity, method_name, fallback, ...)
    local method = entity and entity[method_name]
    if type(method) ~= "function" then return fallback end
    local ok, result = pcall(method, entity, ...)
    if ok and result ~= nil then return tonumber(result) end
    return fallback
end

local function effective_attack_speed(unit)
    -- Arrow towers have a project-owned final BAT after gameplay-stats effects
    -- are applied. Prefer that cache: some engine builds keep
    -- GetAttacksPerSecond stale for one or more frames after SetBaseAttackTime,
    -- which made a freshly selected tower panel show the old speed.
    local project_speed = tonumber(unit and unit.survival_attack_speed)
    if project_speed and unit.survival_building_id == "arrow_tower" then
        return project_speed
    end
    -- 非英雄单位需要反映光环等临时 Modifier。false 表示不忽略临时攻速；
    -- 自定义英雄仍由 hero_ui_snapshot 的配置权威链路接管。
    local attacks_per_second = safe_number(
        unit,
        "GetAttacksPerSecond",
        nil,
        false
    )
    if attacks_per_second and attacks_per_second > 0 then
        return attacks_per_second
    end
    -- 兼容尚未提供 GetAttacksPerSecond 的旧引擎环境。
    local seconds_per_attack = safe_number(unit, "GetSecondsPerAttack", nil)
    if seconds_per_attack and seconds_per_attack > 0 then
        return 1 / seconds_per_attack
    end
    return project_speed
        or (1 / math.max(0.01,
            safe_number(unit, "GetBaseAttackTime", 2)))
end

local function base_damage_outgoing_pct(unit)
    if not unit or type(unit.FindAllModifiersByName) ~= "function" then return 0 end
    local ok, modifiers = pcall(
        unit.FindAllModifiersByName,
        unit,
        "modifier_survival_managed_buff"
    )
    if not ok or type(modifiers) ~= "table" then return 0 end
    local total = 0
    for _, modifier in ipairs(modifiers) do
        if modifier and not modifier:IsNull()
            and modifier.definition
            and modifier.definition.effect_type == "base_damage_outgoing_pct" then
            total = total + (tonumber(modifier.value) or 0)
        end
    end
    return total
end

local function apply_portrait_metadata(unit, snapshot)
    snapshot = snapshot or {}
    snapshot.model_asset_id = ""
    snapshot.portrait_unit_name = ""
    snapshot.portrait_item_def = ""

    if not unit then return snapshot end
    local asset_id = tostring(unit.survival_model_asset_id or "")
    if asset_id == "" then
        -- Monster hero visuals keep their asset identity separately from the
        -- building model_asset_id field; use it for the independent portrait
        -- ScenePanel without changing the world appearance ownership.
        asset_id = tostring(unit.survival_monster_default_wearable_asset_id or "")
    end
    local asset = asset_catalog.get(asset_id)
    if not asset then
        local hero_id = tostring(unit.survival_hero_id or "")
        if hero_id == "" then hero_id = tostring(snapshot.hero_id or "") end
        if hero_id ~= "" then
            asset_id = "hero_permanent_" .. hero_id
            asset = asset_catalog.get(asset_id)
        end
    end
    if not asset and unit.survival_monkey_king_clone == true then
        asset_id = "hero_permanent_hero_monkey_king"
        asset = asset_catalog.get(asset_id)
    end
    if not asset then return snapshot end

    snapshot.model_asset_id = tostring(asset.asset_id or asset_id or "")
    -- Native wearable tower stages, Boss hero bundles, and explicitly opted-in
    -- permanent heroes use the custom portrait ScenePanel. Their world model is
    -- intentionally independent of the portrait unit, so the client can render
    -- the standard Valve hero portrait while the selected entity keeps its
    -- decorated body in-world.
    local is_boss_portrait = asset.load_group == "monster_default_wearables"
        and tostring(asset.portrait_unit_name or "") ~= ""
    local is_split_hero_portrait = asset.asset_id
        == "hero_permanent_hero_blademaster"
        and tostring(asset.portrait_unit_name or "") ~= ""
    if asset.native_wearable_stage == nil
        and not is_boss_portrait
        and not is_split_hero_portrait then
        return snapshot
    end
    snapshot.portrait_unit_name = tostring(asset.portrait_unit_name or "")
    snapshot.portrait_item_def = tostring(asset.portrait_item_def or "")
    return snapshot
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
    -- BASEDAMAGEOUTGOING_PERCENTAGE changes attack resolution but is not
    -- guaranteed to be included in GetDamageMin/Max or project-owned caches.
    -- Apply it explicitly to the non-hero selected-unit display snapshot.
    local outgoing_pct = base_damage_outgoing_pct(unit)
    local outgoing_multiplier = math.max(0, 1 + outgoing_pct / 100)
    attack_min = attack_min * outgoing_multiplier
    attack_max = attack_max * outgoing_multiplier
    local internal_name = (unit.GetUnitName and unit:GetUnitName()) or ""
    local configured_name = (unit_display_names.by_id or {})[internal_name]
    local display_name = unit.survival_display_name
        or (configured_name and configured_name.enabled ~= false
            and configured_name.display_name)
        or internal_name
    local absolute_level = tonumber(unit.survival_level)
        or safe_number(unit, "GetLevel", 1)
    local armor_mapping_version = tonumber(unit.survival_armor_mapping_version) or 1
    local custom_war3_armor = armor_mapping_version
        == armor_balance.CUSTOM_WAR3_MAPPING_VERSION
    local runtime_armor = custom_war3_armor and 0
        or safe_number(unit, "GetPhysicalArmorValue", nil, false)
        or tonumber(unit.survival_armor)
        or safe_number(unit, "GetPhysicalArmorBaseValue", 0)
    local effective_war3_armor = custom_war3_armor
        and (tonumber(unit.survival_effective_war3_armor)
            or tonumber(unit.survival_armor)
            or tonumber(unit.survival_base_war3_armor)
            or 0)
        or nil
    return apply_portrait_metadata(unit, {
        entindex = unit:entindex(),
        unit_name = internal_name,
        display_name = display_name,
        level = absolute_level,
        absolute_level = absolute_level,
        route_level = tonumber(unit.survival_route_level) or absolute_level,
        is_resource_tree = internal_name == tree_config.unit_name and 1 or 0,
        max_level = internal_name == tree_config.unit_name
            and tonumber(tree_config.max_level) or nil,
        tower_class = unit.survival_tower_class or "",
        health = require("combat/endless_stat_projection").for_ui(unit, safe_number(unit, "GetHealth", 0), "health"),
        max_health = require("combat/endless_stat_projection").for_ui(unit, safe_number(unit, "GetMaxHealth", 0), "health"),
        health_scale = string.format("%.17g", tonumber(unit.survival_endless_health_scale) or 1),
        mana = safe_number(unit, "GetMana", 0),
        max_mana = safe_number(unit, "GetMaxMana", 0),
        attack_min = require("combat/endless_stat_projection").for_ui(unit, attack_min, "attack"),
        attack_max = require("combat/endless_stat_projection").for_ui(unit, attack_max, "attack"),
        base_damage_outgoing_pct = outgoing_pct,
        -- 必须读取包含 Modifier 加减值的当前有效护甲；基础护甲和配置缓存
        -- 无法反映攻击减甲科技的实时叠层。
        runtime_armor = runtime_armor,
        armor = effective_war3_armor,
        effective_war3_armor = effective_war3_armor,
        armor_mapping_version = armor_mapping_version,
        -- attack_speed 表示当前每秒攻击次数，不是 BAT，也不是 Dota
        -- 百分比攻速；非英雄单位必须包含光环等临时 Modifier。
        attack_speed = effective_attack_speed(unit),
        attack_speed_stat = safe_number(unit, "GetAttackSpeed", 100),
        strength = strength,
        agility = agility,
        intellect = intellect,
        source = "selected_unit_runtime",
    })
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

local CLIENT_DIAGNOSTIC_STAGES = {
    hud_ready = true,
    space_select = true,
    camera_follow_start = true,
    camera_follow_settled = true,
    camera_fallback = true,
}

local function diagnostic_value(value)
    local text = tostring(value == nil and "" or value)
    text = string.gsub(text, "[%c]", " ")
    return string.sub(text, 1, 160)
end

local function register_client_diagnostic()
    CustomGameEventManager:RegisterListener("ui_client_diagnostic", function(_, payload)
        local player_id = source_player_id(payload)
        local stage = diagnostic_value(payload and payload.stage)
        if not valid_player_id(player_id) or not CLIENT_DIAGNOSTIC_STAGES[stage] then
            return
        end
        print("[SURVIVAL_CLIENT_DIAGNOSTIC] player=" .. tostring(player_id)
            .. " stage=" .. stage
            .. " hero=" .. diagnostic_value(payload.hero)
            .. " hero_name=" .. diagnostic_value(payload.hero_name)
            .. " builder=" .. diagnostic_value(payload.builder)
            .. " entindex=" .. diagnostic_value(payload.entindex)
            .. " target=" .. diagnostic_value(payload.target)
            .. " reason=" .. diagnostic_value(payload.reason)
            .. " result=" .. diagnostic_value(payload.result)
            .. " move_camera_api=" .. diagnostic_value(payload.move_camera_api)
            .. " camera_api=" .. diagnostic_value(payload.camera_api)
            .. " camera_follow_api=" .. diagnostic_value(payload.camera_follow_api)
            .. " camera_result=" .. diagnostic_value(payload.camera_result))
    end)
end

local function hero_ui_snapshot(player_id, entindex, unit)
    local snapshot_player_id = player_id
    local is_monkey_clone = unit and unit.survival_monkey_king_clone == true
    if is_monkey_clone and unit.GetPlayerOwnerID then
        snapshot_player_id = tonumber(unit:GetPlayerOwnerID())
    end
    local result = event_bus.request(
        events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = snapshot_player_id }
    )
    if not result or not result.ok or not result.snapshot
        or (not is_monkey_clone
            and tonumber(result.snapshot.entindex) ~= tonumber(entindex)) then
        return nil
    end
    local snapshot = {}
    for key, value in pairs(result.snapshot) do snapshot[key] = value end
    if is_monkey_clone then
        snapshot.entindex = entindex
        snapshot.max_health = unit.GetMaxHealth
            and unit:GetMaxHealth() or snapshot.max_health
        snapshot.attack_speed = tonumber(unit.survival_attack_speed)
            or snapshot.attack_speed
        snapshot.armor = 10
        snapshot.runtime_armor = unit.GetPhysicalArmorValue
            and unit:GetPhysicalArmorValue(false) or snapshot.runtime_armor
        snapshot.unit_name = unit.GetUnitName
            and unit:GetUnitName() or snapshot.unit_name
        snapshot.display_name = unit.survival_display_name
            or snapshot.display_name
    end
    -- The hero combat snapshot is authoritative and internally consistent.
    -- Never replace one field with a transient engine-frame value here: doing
    -- so made request responses alternate between projected armor and zero
    -- while the regular NetTable still contained the stable hero snapshot.
    return combat_stat_projection.for_ui(apply_portrait_metadata(unit, snapshot))
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
        local snapshot = hero_ui_snapshot(player_id, entindex, unit)
        if snapshot then
            snapshot.success = 1
            snapshot.source = "hero_combat_stat_service"
            send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
            return
        end
        local snapshot = combat_stat_projection.for_ui(unit_combat_snapshot(unit))
        snapshot.success = 1
        send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
    end)
end

local function publish_selected_tree_snapshot(payload)
    local entindex = tonumber(payload and payload.entindex)
    if not entindex then return end
    local ok, unit = pcall(EntIndexToHScript, entindex)
    if not ok or not unit or unit:IsNull() then return end
    for player_id, selected_entindex in pairs(selected_unit_by_player) do
        if tonumber(selected_entindex) == entindex and valid_player_id(player_id) then
            local snapshot = combat_stat_projection.for_ui(unit_combat_snapshot(unit))
            snapshot.success = 1
            snapshot.reason = payload.reason or "tree_changed"
            snapshot.push_phase = "immediate"
            send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
        end
    end
end

local function register_selected_tree_snapshot_push()
    event_bus.subscribe(events.TREE_CHANGED, publish_selected_tree_snapshot)
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
            local snapshot = hero_ui_snapshot(player_id, entindex, unit)
                or combat_stat_projection.for_ui(unit_combat_snapshot(unit))
            -- Hero snapshots intentionally own stable equipment armor, but
            -- temporary armor debuffs must show the same effective engine armor
            -- used by damage resolution without replacing other authoritative
            -- hero fields.
            local reason = tostring(payload.reason or "")
            if reason:match("^poison_cloud_armor_")
                or reason == "research_armor_reduction" then
                local custom_war3_armor = tonumber(
                    unit.survival_armor_mapping_version
                ) == armor_balance.CUSTOM_WAR3_MAPPING_VERSION
                if custom_war3_armor then
                    -- Custom War3 targets deliberately keep native armor at
                    -- zero. Their effective project-owned value is the one
                    -- used by damage resolution and must remain authoritative.
                    snapshot.runtime_armor = 0
                    snapshot.armor = tonumber(
                        unit.survival_effective_war3_armor
                    ) or tonumber(unit.survival_war3_armor) or 0
                    snapshot.effective_war3_armor = snapshot.armor
                else
                    local runtime_armor = safe_number(
                        unit, "GetPhysicalArmorValue", nil, false
                    )
                    snapshot.runtime_armor = runtime_armor
                    snapshot.armor = armor_balance.to_war3(runtime_armor)
                end
                snapshot.armor_unit = "war3_display"
                snapshot.stat_units_version = 2
            end
            snapshot.success = 1
            snapshot.reason = payload.reason or "unit_combat_stats_changed"
            snapshot.push_phase = "immediate"
            send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)
        end
    end
end

local function on_hero_combat_stats_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    local snapshot = payload and payload.snapshot
    if not valid_player_id(player_id) or type(snapshot) ~= "table" then return end
    local selected_entindex = tonumber(selected_unit_by_player[player_id])
    if selected_entindex ~= tonumber(snapshot.entindex) then return end
    local ok, unit = pcall(EntIndexToHScript, selected_entindex)
    if not ok or not unit or unit:IsNull() then return end
    local decorated = {}
    for key, value in pairs(snapshot) do decorated[key] = value end
    apply_portrait_metadata(unit, decorated)
    local projected = combat_stat_projection.for_ui(decorated)
    projected.success = 1
    projected.reason = payload.reason or snapshot.reason
        or "hero_combat_stats_changed"
    projected.push_phase = "immediate"
    send_to_player("ui_selected_unit_stats_snapshot", player_id, projected)
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
    snapshot.absolute_level = tonumber(payload.absolute_level)
        or snapshot.level
    snapshot.route_level = tonumber(payload.route_level)
        or snapshot.route_level
    snapshot.tower_class = payload.tower_class or snapshot.tower_class
    snapshot.attack_min = tonumber(payload.attack_min) or snapshot.attack_min
    snapshot.attack_max = tonumber(payload.attack_max) or snapshot.attack_max
    snapshot.runtime_armor = tonumber(payload.runtime_armor)
        or tonumber(payload.armor)
        or snapshot.runtime_armor
    snapshot.attack_speed = tonumber(payload.attack_speed) or snapshot.attack_speed
    snapshot.push_phase = phase or "immediate"
    snapshot = combat_stat_projection.for_ui(snapshot)
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

local function register_difficulty_select_request()
    CustomGameEventManager:RegisterListener(
        "ui_difficulty_select_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then return end
            local result, request_error = event_bus.request(
                events.WAVE_DIFFICULTY_SET_REQUEST,
                {
                    difficulty_id = tostring(
                        payload and payload.difficulty_id or ""
                    ),
                    player_id = player_id,
                }
            )
            send_to_player("ui_difficulty_select_result", player_id, {
                success = result and result.ok and 1 or 0,
                difficulty_id = result and result.difficulty_id or "",
                total_waves = result and result.total_waves or 0,
                error = result and result.error or request_error or "",
            })
        end
    )
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
            source_entindex = tonumber(payload.source_entindex),
        })
        local encounter_started = result and result.ok
            and result.grant_result
            and tostring(result.grant_result.encounter_id or "") ~= ""
        local focus_hero_entindex = -1
        local camera_target = result and result.grant_result
            and result.grant_result.camera_target or {}
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
            focus_target_x = tonumber(camera_target.x),
            focus_target_y = tonumber(camera_target.y),
            focus_target_z = tonumber(camera_target.z),
        })
    end)
end

local function register_shop_auto_research_toggle_request()
    CustomGameEventManager:RegisterListener(
        "ui_shop_auto_research_toggle_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then return end
            local result = event_bus.request(
                events.SHOP_AUTO_RESEARCH_TOGGLE_REQUEST,
                {
                    player_id = player_id,
                    technology_group = tostring(payload.technology_group or ""),
                    source_entindex = tonumber(payload.source_entindex),
                }
            )
            send_to_player("ui_operation_result", player_id, {
                request_id = payload.request_id or "",
                success = result and result.ok and 1 or 0,
                operation = "shop_auto_research_toggle",
                enabled = result and result.enabled and 1 or 0,
                error = result and result.error or "auto_research_toggle_failed",
            })
        end
    )
end

local function register_research_requests()
    CustomGameEventManager:RegisterListener(
        "ui_research_snapshot_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then return end
            event_bus.request(research_events.CLIENT_SNAPSHOT_REQUESTED, {
                player_id = player_id,
            })
        end
    )
    CustomGameEventManager:RegisterListener(
        "ui_research_upgrade_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then return end
            local result = event_bus.request(research_events.UPGRADE_REQUESTED, {
                player_id = player_id,
                tech_id = tostring(payload.tech_id or ""),
            })
            send_to_player("ui_research_upgrade_result", player_id, result or {
                success = false,
                error_code = "resource_commit_failed",
            })
        end
    )
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
        ability_build_advanced_research_lab = "building_advanced_research_lab",
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
        local owner_id = unit_valid
            and (tonumber(unit.survival_player_id) or unit:GetPlayerOwnerID())
            or -999
        local caster_matches = ability_valid and ability:GetCaster() == unit
        local behavior = ability_valid and ability:GetBehaviorInt() or -1
        local is_point_target = ability_valid
            and bit.band(behavior, DOTA_ABILITY_BEHAVIOR_POINT) ~= 0
        local hero_quickcast = ability_name
            == "ability_survival_hero_ball_lightning"
        print(string.format("[SURVIVAL_CAST][SERVER] POINT_CHECK name=%s building=%s unit_valid=%s ability_valid=%s caster_matches=%s owner=%s point=%s",
            tostring(ability_name), tostring(building_id), tostring(unit_valid), tostring(ability_valid),
            tostring(caster_matches), tostring(owner_id), tostring(is_point_target)))
        if hero_quickcast then
            local hero_ability_matches = unit_valid and ability_valid
                and unit:FindAbilityByName(ability_name) == ability
            local can_cast = hero_ability_matches and caster_matches
                and owner_id == player_id and is_point_target
                and unit:IsAlive() and ability:IsActivated()
                and not ability:IsHidden() and ability:IsFullyCastable()
            if not can_cast then
                print("[SURVIVAL_CAST][SERVER] POINT_REJECT hero_quickcast_validation")
                send_to_player("ui_ability_cast_result", player_id, {
                    success = 0, entindex = entindex or -1,
                    ability_entindex = ability_entindex or -1,
                    ability_name = ability_name, behavior = behavior,
                    error = "hero_quickcast_rejected",
                })
                return
            end
            local origin = unit:GetAbsOrigin()
            local delta = Vector(x, y, z) - origin
            delta.z = 0
            local distance = delta:Length2D()
            local target = Vector(x, y, z)
            if distance > 800 then
                target = origin + delta:Normalized() * 800
            end
            target.z = GetGroundHeight(target, unit)
            unit:CastAbilityOnPosition(target, ability, player_id)
            print("[SURVIVAL_CAST][SERVER] POINT_HERO_CAST_ISSUED name="
                .. tostring(ability_name))
            send_to_player("ui_ability_cast_result", player_id, {
                success = 1, entindex = entindex,
                ability_entindex = ability_entindex,
                ability_name = ability_name, behavior = behavior, error = "",
            })
            return
        end
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
        local result = event_bus.request(events.BUILD_REQUEST, {
            caster = unit,
            building_id = building_id,
            position = position,
            source_ability = ability,
        })
        if result and result.ok then
            ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))
        end
        print("[SURVIVAL_CAST][SERVER] POINT_BUILD_REQUESTED building=" .. tostring(building_id))
        send_to_player("ui_ability_cast_result", player_id, {
            success = result and result.ok and 1 or 0,
            entindex = entindex, ability_entindex = ability_entindex,
            ability_name = ability_name, behavior = behavior,
            error = result and result.ok and ""
                or (result and result.error or "build_request_failed"),
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
        local owner_id = unit_valid
            and (tonumber(unit.survival_player_id) or unit:GetPlayerOwnerID())
            or -999
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
        local tower_fusion_matches = ability_name == "ability_tower_fusion"
            and unit_valid and ability_valid
            and unit:FindAbilityByName(ability_name) == ability
        local building_upgrade_action = ({
            ability_upgrade_wall = true,
            ability_upgrade_city = true,
            ability_upgrade_farm = true,
        })[ability_name] == true
        local building_upgrade_ability_matches = building_upgrade_action
            and unit_valid and ability_valid
            and unit:FindAbilityByName(ability_name) == ability
        local gold_mine_actions = {
            ability_upgrade_gold_mine = "level",
            ability_upgrade_gold_mine_efficiency = "efficiency",
            ability_upgrade_gold_mine_crit = "crit",
            ability_gold_mine_auto_upgrade = "auto_start",
            ability_gold_mine_stop_auto_upgrade = "auto_stop",
        }
        local gold_mine_action = gold_mine_actions[ability_name]
        local gold_mine_ability_matches = gold_mine_action and unit_valid
            and ability_valid and unit:FindAbilityByName(ability_name) == ability
        local summon_hero_id = hero_summon_projection
            .hero_id_for_summon_ability(ability_name)
        local altar_summon_matches = summon_hero_id ~= nil and unit_valid
            and ability_valid and unit.survival_building_id == "hero_altar"
            and unit:FindAbilityByName(ability_name) == ability
        local challenge_auto_matches = ability_name == "ability_challenge_auto_summon"
            and unit_valid and ability_valid
            and unit.survival_building_id == "building_challenge"
            and unit:FindAbilityByName(ability_name) == ability
        local rogue_builder_matches = ability_name == "ability_survival_rogue_reward"
            and unit_valid and ability_valid
            and unit.survival_building_id == "builder"
            and unit:FindAbilityByName(ability_name) == ability
        local research_upgrade = research_lab_abilities.by_id[ability_name]
        local research_ability_matches = research_upgrade ~= nil and unit_valid
            and ability_valid and unit:FindAbilityByName(ability_name) == ability
        local handled_directly = false
        local direct_result_required = false
        local direct_result = nil
        local direct_error = nil
        local direct_cooldown_started = false
        if tower_ability_matches and owner_matches and not passive
            and not is_point_target and tower_upgrade_mode then
            -- Dynamic Lua abilities on npc_dota_creature buildings do not
            -- reliably enter OnSpellStart through CastAbilityNoTarget. Route
            -- tower UI actions straight to the authoritative building system;
            -- ownership/ability validation above and resource/level validation
            -- in building_upgrade_system remain unchanged.
            handled_directly = true
            direct_result_required = true
            if not ability:IsActivated() or ability:IsHidden()
                or not ability:IsFullyCastable() then
                direct_result = { ok = false, error = "防御塔升级技能当前不可用" }
            else
                direct_result = building_batch_upgrade.execute({
                    player_id = player_id,
                    primary = unit,
                    primary_ability = ability,
                    ability_name = ability_name,
                    selected_entindexes = payload.selected_entindexes,
                })
                print("[SURVIVAL_CAST][SERVER] TOWER_BATCH_UPGRADE_DISPATCHED mode="
                    .. tostring(tower_upgrade_mode) .. " success="
                    .. tostring(direct_result and direct_result.success_count or 0)
                    .. " skipped=" .. tostring(direct_result and direct_result.skipped_count or 0))
            end
        elseif building_upgrade_ability_matches and owner_matches
            and not passive and not is_point_target then
            handled_directly = true
            direct_result_required = true
            if not ability:IsActivated() or ability:IsHidden()
                or not ability:IsFullyCastable() then
                direct_result = { ok = false, error = "建筑升级技能当前不可用" }
            else
                direct_result = building_batch_upgrade.execute({
                    player_id = player_id,
                    primary = unit,
                    primary_ability = ability,
                    ability_name = ability_name,
                    selected_entindexes = payload.selected_entindexes,
                })
                print("[SURVIVAL_CAST][SERVER] BUILDING_BATCH_UPGRADE_DISPATCHED name="
                    .. tostring(ability_name) .. " success="
                    .. tostring(direct_result and direct_result.success_count or 0)
                    .. " skipped=" .. tostring(direct_result and direct_result.skipped_count or 0))
            end
        elseif tower_ability_matches and owner_matches and not passive
            and not is_point_target and tower_class_index and tower_class_index >= 1
            and tower_class_index <= 7 then
            handled_directly = true
            direct_result_required = true
            if not ability:IsActivated() or ability:IsHidden()
                or not ability:IsFullyCastable() then
                direct_result = { ok = false, error = "防御塔转职技能当前不可用" }
            else
                ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))
                direct_cooldown_started = true
                local request = {
                    tower = unit,
                    class_index = tower_class_index,
                    source_ability = ability,
                }
                direct_result = event_bus.request(events.TOWER_CLASS_REQUEST, request)
                    or request.result
                    or { ok = false, error = "防御塔转职无响应" }
                print("[SURVIVAL_CAST][SERVER] TOWER_CLASS_DISPATCHED index="
                    .. tostring(tower_class_index))
            end
        elseif tower_fusion_matches and owner_matches and not passive
            and not is_point_target then
            -- Dynamic Lua abilities on npc_dota_creature towers may accept the
            -- cast order without reliably entering OnSpellStart. Dispatch the
            -- same authoritative fusion request directly after server checks.
            handled_directly = true
            direct_result_required = true
            if not ability:IsActivated() or ability:IsHidden()
                or not ability:IsFullyCastable() then
                direct_result = { ok = false, error = "七塔合一技能当前不可用" }
            else
                direct_result = event_bus.request(events.TOWER_FUSION_REQUEST, {
                    caster = unit,
                    ability = ability,
                    source = "ui_ability_cast_request",
                }) or { ok = false, error = "七塔合一请求无响应" }
            end
            print("[SURVIVAL_CAST][SERVER] TOWER_FUSION_DISPATCHED unit="
                .. tostring(entindex) .. " ok="
                .. tostring(direct_result and direct_result.ok == true)
                .. " error="
                .. tostring(direct_result and direct_result.error or ""))
        elseif gold_mine_ability_matches and owner_matches and not passive
            and not is_point_target then
            handled_directly = true
            direct_result_required = true
            direct_result = gold_mine_batch_upgrade.execute({
                player_id = player_id,
                primary = unit,
                primary_ability = ability,
                ability_name = ability_name,
                selected_entindexes = payload.selected_entindexes,
            })
            print("[SURVIVAL_CAST][SERVER] GOLD_MINE_BATCH_DISPATCHED action="
                .. tostring(gold_mine_action) .. " ok="
                .. tostring(direct_result and direct_result.ok == true)
                .. " success="
                .. tostring(direct_result and direct_result.success_count or 0)
                .. " unchanged="
                .. tostring(direct_result and direct_result.unchanged_count or 0)
                .. " skipped="
                .. tostring(direct_result and direct_result.skipped_count or 0))
        elseif rogue_builder_matches and owner_matches and not passive
            and not is_point_target then
            handled_directly = true
            direct_result_required = true
            print("[SURVIVAL_CAST][SERVER] ROGUE_REWARD_BEGIN player="
                .. tostring(player_id) .. " unit=" .. tostring(entindex)
                .. " ability=" .. tostring(ability_entindex))
            if not ability:IsActivated() or ability:IsHidden()
                or unit:FindAbilityByName(ability_name) ~= ability then
                direct_result = { ok = false, error = "rogue_reward_unavailable" }
            else
                direct_result = event_bus.request(events.ROGUE_REWARD_OPEN_REQUEST, {
                    player_id = player_id, source = "builder",
                }) or { ok = false, error = "rogue_reward_unhandled" }
            end
            print("[SURVIVAL_CAST][SERVER] ROGUE_REWARD_END ok="
                .. tostring(direct_result and direct_result.ok == true)
                .. " error=" .. tostring(direct_result and direct_result.error or ""))
        elseif challenge_auto_matches and owner_matches and not passive
            and not is_point_target then
            handled_directly = true
            direct_result_required = true
            if not ability:IsActivated() or ability:IsHidden() then
                direct_result = { ok = false, error = "自动召唤技能当前不可用" }
            else
                local enabled = ability:GetToggleState() ~= true
                direct_result, direct_error = event_bus.request(
                    events.BUILDING_CHALLENGE_AUTO_REQUEST,
                    {
                        building = unit,
                        building_entindex = entindex,
                        enabled = enabled,
                    }
                )
                if direct_result and direct_result.ok == true
                    and ability:GetToggleState() ~= enabled then
                    ability.survival_reverting_toggle = true
                    ability:ToggleAbility()
                end
            end
            print("[SURVIVAL_CAST][SERVER] CHALLENGE_AUTO_DISPATCHED enabled="
                .. tostring(direct_result and direct_result.enabled) .. " ok="
                .. tostring(direct_result and direct_result.ok == true))
        elseif research_ability_matches and owner_matches and not passive
            and not is_point_target then
            handled_directly = true
            direct_result_required = true
            local building = event_bus.request(events.BUILDING_QUERY_REQUEST, {
                entindex = unit:entindex(),
            })
            if not building
                or building.building_id ~= research_upgrade.building_id
                or tonumber(building.player_id) ~= player_id
                or not ability:IsActivated() or ability:IsHidden()
                or not ability:IsFullyCastable() then
                direct_result = { ok = false, error = "research_source_invalid" }
            else
                direct_result = event_bus.request(
                    events.TECHNOLOGY_PURCHASE_NEXT_REQUEST,
                    {
                        player_id = player_id,
                        technology_group = research_upgrade.technology_group,
                        source_entindex = unit:entindex(),
                        source = "research_lab_ability",
                    }
                ) or { ok = false, error = "research_request_unhandled" }
            end
            print("[SURVIVAL_CAST][SERVER] RESEARCH_DISPATCHED group="
                .. tostring(research_upgrade.technology_group) .. " ok="
                .. tostring(direct_result and direct_result.ok == true))
        elseif altar_summon_matches and owner_matches and not passive
            and not is_point_target then
            -- Creature-based altar abilities can accept an order without
            -- reliably entering OnSpellStart. Dispatch the same authoritative
            -- request used by hero_summon_ability_factory.
            handled_directly = true
            direct_result_required = true
            if not ability:IsActivated() or ability:IsHidden()
                or not ability:IsFullyCastable() then
                direct_result = { ok = false, error = "英雄召唤技能当前不可用" }
            else
                ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))
                direct_cooldown_started = true
                direct_result, direct_error = event_bus.request(
                    events.HERO_SUMMON_REQUEST,
                    {
                        player_id = player_id,
                        hero_id = summon_hero_id,
                        source = "altar_ui_ability",
                        on_completed = function(final_result)
                            if final_result and final_result.ok then return end
                            if ability and not ability:IsNull() then
                                ability:EndCooldown()
                            end
                            local final_message = final_result
                                and final_result.error or nil
                            if final_message and not string.find(final_message,
                                    "^hero_resource_load_failed:") then
                                event_bus.emit(events.UI_NOTIFICATION, {
                                    player_id = player_id,
                                    message = final_message,
                                    level = "error",
                                })
                            end
                        end,
                    }
                )
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
            print("[SURVIVAL_CAST][SERVER] ALTAR_SUMMON_DISPATCHED hero="
                .. tostring(summon_hero_id) .. " ok=" .. tostring(succeeded)
                .. " error=" .. tostring(message or ""))
        end
        if direct_result_required and direct_cooldown_started
            and (not direct_result or direct_result.ok ~= true) then
            ability:EndCooldown()
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
        if not ok and error_code == "building_not_found" then
            local result = event_bus.request(events.TOWER_FUSION_MOVE_REQUEST, {
                player_id = player_id,
                entindex = tonumber(payload.entindex),
                position = Vector(x, y, z),
            })
            ok = result and result.ok == true
            error_code = result and result.error or "ultimate_tower_not_found"
        end
        send_to_player("ui_building_move_result", player_id, {
            success = ok and 1 or 0,
            error = error_code or "",
            entindex = tonumber(payload.entindex) or -1,
        })
    end)
end

local function register_arrow_tower_destroy_request()
    CustomGameEventManager:RegisterListener(
        "ui_arrow_tower_destroy_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then return end
            local ok, error_code = building_system.destroy_arrow_tower_for_player(
                player_id,
                tonumber(payload.entindex)
            )
            if not ok and error_code == "tower_not_owned" then
                local result = event_bus.request(
                    events.TOWER_FUSION_DESTROY_REQUEST,
                    {
                        player_id = player_id,
                        entindex = tonumber(payload.entindex),
                    }
                )
                ok = result and result.ok == true
                error_code = result and result.error or "ultimate_tower_not_found"
            end
            send_to_player("ui_arrow_tower_destroy_result", player_id, {
                success = ok and 1 or 0,
                error = error_code or "",
                entindex = tonumber(payload.entindex) or -1,
            })
        end
    )
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
    local notification = {
        message = payload.message or "",
        level = payload.level or "info",
    }
    if payload.audience == "all" then
        CustomGameEventManager:Send_ServerToAllClients(
            "ui_notification", notification
        )
        return
    end
    send_to_player("ui_notification", payload.player_id, notification)
end

local function register_rogue_reward_requests()
    CustomGameEventManager:RegisterListener("ui_rogue_reward_select", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        event_bus.request(events.ROGUE_REWARD_SELECT_REQUEST, {
            player_id = player_id,
            token = tostring(payload and payload.token or ""),
            card_id = tostring(payload and payload.card_id or ""),
        })
    end)
    CustomGameEventManager:RegisterListener("ui_rogue_reward_reroll", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        event_bus.request(events.ROGUE_REWARD_REROLL_REQUEST, {
            player_id = player_id,
            token = tostring(payload and payload.token or ""),
        })
    end)
end

local function register_lottery_requests()
    CustomGameEventManager:RegisterListener("ui_lottery_snapshot_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local result = event_bus.request(events.LOTTERY_SNAPSHOT_REQUEST, {
            player_id = player_id,
            pool_id = tostring(payload and payload.pool_id or "map"),
        })
        send_to_player("ui_lottery_snapshot", player_id, result and result.snapshot or {
            ok = false, error = result and result.error or "lottery_snapshot_failed",
        })
    end)
    CustomGameEventManager:RegisterListener("ui_lottery_draw_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local result = event_bus.request(events.LOTTERY_DRAW_REQUEST, {
            player_id = player_id,
            pool_id = tostring(payload and payload.pool_id or "map"),
            count = tonumber(payload and payload.count) or 1,
            request_id = tostring(payload and payload.request_id or ""),
        }) or { ok = false, error = "lottery_draw_failed" }
        send_to_player("ui_lottery_result", player_id, result)
    end)
    CustomGameEventManager:RegisterListener("ui_lottery_exchange_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local result = event_bus.request(events.LOTTERY_EXCHANGE_REQUEST, {
            player_id = player_id,
            pool_id = tostring(payload and payload.pool_id or "map"),
            item_id = tostring(payload and payload.item_id or ""),
            request_id = tostring(payload and payload.request_id or ""),
        }) or { ok = false, error = "lottery_exchange_failed" }
        send_to_player("ui_lottery_exchange_result", player_id, result)
    end)
end

local function on_shop_state_changed(payload)
    if not payload or not payload.snapshot then return end
    send_to_player("ui_shop_snapshot", payload.player_id, payload.snapshot)
end

local function on_lottery_changed(payload)
    if not payload or not payload.snapshot then return end
    send_to_player("ui_lottery_snapshot", payload.player_id, payload.snapshot)
end

function M.init()
    synthesis_requests = {}
    building_snapshot_sequence = 0
    selected_unit_by_player = {}
    register_client_diagnostic()
    register_selected_unit_stats_request()
    register_selected_tree_snapshot_push()
    register_building_snapshot_push()
    register_snapshot_request()
    register_difficulty_select_request()
    register_shop_open_request()
    register_shop_close_request()
    register_shop_purchase_request()
    register_shop_auto_research_toggle_request()
    register_research_requests()
    register_weapon_synthesis_request()
    register_weapon_snapshot_request()
    register_ability_cast_request()
    register_ability_cast_position_request()
    register_building_move_request()
    register_arrow_tower_destroy_request()
    register_return_home_request()
    register_rogue_reward_requests()
    register_lottery_requests()
    event_bus.subscribe(events.UNIT_COMBAT_STATS_CHANGED, on_unit_combat_stats_changed)
    event_bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, on_hero_combat_stats_changed)
    event_bus.subscribe(events.UI_NOTIFICATION, on_notification)
    event_bus.subscribe(events.SHOP_STATE_CHANGED, on_shop_state_changed)
    event_bus.subscribe(events.LOTTERY_CHANGED, on_lottery_changed)
end

M._test = {
    apply_portrait_metadata = apply_portrait_metadata,
    on_notification = on_notification,
}

return M
