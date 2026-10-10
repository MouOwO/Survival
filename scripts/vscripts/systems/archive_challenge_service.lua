local bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/archive_challenge_definitions")
local stats = require("config/generated/archive_challenge_stats")
local rule = require("config/generated/archive_challenge_rules").by_id.default
local context = require("systems/player_context_service")
local wave = require("systems/wave_system")
local archive = require("systems/archive_service")
local scheduler = require("core/scheduler")
local hub_placement = require("systems/archive_hub_placement")
local M = {}
local players, hubs, bosses = {}, {}, {}
local sequence, active = 0, false
local deadline, ended, expired = nil, false, false
local TIMER_ID = "archive_challenge_phase_timer"
local SAVE_TIMER_ID = "archive_challenge_save_barrier"
local settling, winner_sent = false, false
local function valid(unit) return unit and not unit:IsNull() end
local function now() return GameRules:GetGameTime() end
function M.phase_snapshot()
    return {active = active and 1 or 0, ended = ended and 1 or 0,
        saving = settling and 1 or 0,
        expired = (expired or (active and deadline and now() >= deadline)) and 1 or 0,
        deadline = deadline or 0,
        remaining_seconds = active and deadline and math.max(0, math.ceil(deadline - now())) or 0}
end
local function publish_phase()
    bus.emit("archive.challenge_timer_changed", M.phase_snapshot())
end
local function notify(id, message)
    bus.emit(events.UI_NOTIFICATION, { player_id = id, message = message, level = "error" })
end
local function allowed(state, definition)
    return state and not state.finished and definition and definition.enabled
        and state.difficulty >= definition.min_difficulty
end
-- One authority serves the archive publisher and generic HUD refreshes.
-- Complete identity lets event-driven and native HUD painting agree.
function M.ability_runtime(caster, ability_name)
    local runtime = {ability_name = ability_name, archive_challenge = 1,
        available = 0, prerequisite_met = 0, can_afford = 1,
        cost_wood = 0, cost_gold = 0, resource_version = 0,
        status_text = "挑战状态同步中"}
    if not valid(caster) then return runtime end
    runtime.owner_entindex = caster:entindex()
    local ability = caster:FindAbilityByName(ability_name)
    if valid(ability) and ability.entindex then runtime.ability_entindex = ability:entindex() end
    local hub = hubs[runtime.owner_entindex]
    local state = hub and hub.unit == caster and hub.state or nil
    if not state or players[state.player_id] ~= state then return runtime end
    runtime.player_id = state.player_id
    local ready = active and not ended and not state.finished
        and (not deadline or now() < deadline)
    local busy = require("systems/archive_endless_service").is_running(state.player_id)
    local boss = valid(state.active_boss) and state.active_boss:IsAlive()
    local challenge_id = tostring(ability_name):match("^ability_archive_(.+)$")
    local definition = challenge_id and definitions.by_id[challenge_id]
    if challenge_id == "endless" and hub.index == 2 then
        runtime.display_name = "开启无尽挑战"
        runtime.upgrade_description = "每波5只小怪，限时60秒，清空后立即下一波。每10波积分提高7分，首10波每波1分。每局仅可开启一次。"
        ready = ready and not state.used.endless and not busy and not boss
            and require("systems/archive_endless_config").group(state.difficulty) ~= nil
        runtime.status_text = busy and "无尽挑战进行中" or state.used.endless and "本局已开启"
            or boss and "请先击败当前挑战BOSS" or ready and "可以开启" or "暂不可开启"
    elseif challenge_id == "finish" and hub.index == 3 then
        runtime.display_name = "结束存档挑战"
        runtime.upgrade_description = "结束自己的挑战；所有玩家结束后胜利结算。未击败的BOSS不会获得奖励。"
        runtime.status_text = ready and "可以结束挑战" or "挑战已结束"
    elseif definition and definition.building_id == hub.index then
        local unlocked = allowed(state, definition)
        local used = state.used[challenge_id] == true
        ready = ready and unlocked and not used and not boss and not busy
        runtime.display_name = definition.display_name
        runtime.upgrade_description = definition.description
        runtime.icon_name = definition.ability_icon
        runtime.fields = {{label = "解锁条件", value = "当前关卡≥N" .. definition.min_difficulty}}
        runtime.status_text = busy and "无尽挑战进行中" or used and "本局已挑战（每个技能仅限一次）"
            or not unlocked and ("需要当前关卡 N" .. definition.min_difficulty)
            or boss and "请先击败当前挑战BOSS" or "可以挑战"
    else
        ready = false
        runtime.status_text = "挑战入口无效"
    end
    if not active or ended or state.finished or (deadline and now() >= deadline) then
        runtime.status_text = "挑战已结束"
    end
    runtime.available, runtime.prerequisite_met = ready and 1 or 0, ready and 1 or 0
    return runtime
end
local function publish(state)
    for _, hub in pairs(state.hubs) do
        if valid(hub) then
            local count = 0
            local function update(name)
                local ability = hub:FindAbilityByName(name)
                if not valid(ability) then return end
                count = count + 1
                local runtime = M.ability_runtime(hub, name)
                local ready = runtime.available == 1
                if not ability.IsActivated or ability:IsActivated() ~= ready then ability:SetActivated(ready) end
                ability.survival_runtime_disabled = not ready or nil
                runtime.engine_level = ability.GetLevel and ability:GetLevel() or 1
                runtime.engine_activated = ready and 1 or 0
                runtime.passive = 0
                if CustomNetTables and runtime.ability_entindex then
                    CustomNetTables:SetTableValue("survival_ability_runtime", tostring(runtime.ability_entindex), runtime)
                end
            end
            for _, definition in ipairs(definitions.rows) do
                if definition.enabled and definition.building_id == hub.survival_archive_hub then
                    update("ability_archive_" .. definition.challenge_id)
                end
            end
            if hub.survival_archive_hub == 2 then update("ability_archive_endless") end
            if hub.survival_archive_hub == 3 then update("ability_archive_finish") end
            if CustomNetTables then
                CustomNetTables:SetTableValue("survival_ability_runtime", "unit:" .. tostring(hub:entindex()), {
                    owner_entindex = hub:entindex(),
                    ability_count = hub.GetAbilityCount and hub:GetAbilityCount() or count,
                })
            end
        end
    end
end
local function remove_boss(state)
    local unit = state.active_boss
    if valid(unit) then
        bosses[unit:entindex()] = nil
        require("systems/monster_hero_visual_service").clear(unit)
        UTIL_Remove(unit)
    end
    state.active_boss = nil
end
local function cleanup(state)
    scheduler.cancel("archive_hubs_retry:" .. state.player_id)
    require("systems/archive_endless_service").cancel(state.player_id, "结束存档挑战")
    remove_boss(state)
    for _, unit in pairs(state.hubs) do
        if valid(unit) then
            local unit_index = unit:entindex()
            bus.emit(events.BUILDING_DESTROYED, {unit = unit, entindex = unit_index,
                building_id = "archive_challenge", player_id = state.player_id,
                team = DOTA_TEAM_GOODGUYS})
            -- These hubs can also be discovered by generic runtime refreshes.
            -- Clear both its owner registry and the archive's direct rows.
            if CustomNetTables then
                local function retire(name)
                    local ability = unit:FindAbilityByName(name)
                    if valid(ability) and ability.entindex then
                        CustomNetTables:SetTableValue("survival_ability_runtime", tostring(ability:entindex()), {
                            removed = 1, owner_entindex = unit_index, ability_entindex = ability:entindex(),
                        })
                    end
                end
                for _, definition in ipairs(definitions.rows) do
                    if definition.enabled and definition.building_id == unit.survival_archive_hub then
                        retire("ability_archive_" .. definition.challenge_id)
                    end
                end
                if unit.survival_archive_hub == 2 then retire("ability_archive_endless") end
                if unit.survival_archive_hub == 3 then retire("ability_archive_finish") end
                CustomNetTables:SetTableValue("survival_ability_runtime", "unit:" .. tostring(unit_index), {
                    removed = 1, owner_entindex = unit_index, ability_count = 0,
                })
            end
            require("systems/challenge_guardian_visual_service").clear(unit)
            hubs[unit:entindex()] = nil
            context.unregister_unit(unit)
            UTIL_Remove(unit)
        end
    end
    state.hubs = {}
end
local function finish_when_saved()
    for id in pairs(players) do
        if archive.has_pending(id) then return true end
    end
    if not winner_sent then
        winner_sent, settling = true, false
        publish_phase()
        GameRules:SetGameWinner(DOTA_TEAM_GOODGUYS)
    end
    return false
end
local function end_phase(timed_out)
    if ended then return end
    require("systems/gameplay_phase_guard").freeze_for_settlement()
    active, ended, expired = false, true, timed_out == true
    scheduler.cancel(TIMER_ID)
    -- Mark everyone finished before removing monsters; late death events cannot award rewards.
    for _, state in pairs(players) do state.finished = true end
    for _, state in pairs(players) do
        local ok, reason = pcall(cleanup, state)
        if not ok then print("[ArchiveChallenge] final cleanup failed: " .. tostring(reason)) end
    end
    settling = true
    if archive.begin_finalization then archive.begin_finalization() end
    publish_phase()
    if finish_when_saved() then
        for id in pairs(players) do
            bus.emit(events.UI_NOTIFICATION, {player_id=id, level="info",
                message="挑战已结束，正在保存奖励。保存成功后自动结算，请勿退出。"})
        end
        -- Never abandon an earned reward because of a timer. The archive queue
        -- keeps its original idempotency keys and retries failed/slow writes.
        scheduler.every(0.25, finish_when_saved, SAVE_TIMER_ID)
    end
end
local function expire_if_due()
    if active and deadline and now() >= deadline then end_phase(true); return true end
    return expired
end
local function ensure_hub_abilities(unit, index)
    for _, definition in ipairs(definitions.rows) do
        if definition.enabled and definition.building_id == index then
            local name = "ability_archive_" .. definition.challenge_id
            local ability = unit:FindAbilityByName(name) or unit:AddAbility(name)
            if valid(ability) and (not ability.GetLevel or ability:GetLevel() < 1) then ability:SetLevel(1) end
        end
    end
    if index == 2 then
        local endless = unit:FindAbilityByName("ability_archive_endless") or unit:AddAbility("ability_archive_endless")
        if valid(endless) and (not endless.GetLevel or endless:GetLevel() < 1) then endless:SetLevel(1) end
    end
    if index == 3 then
        local finish = unit:FindAbilityByName("ability_archive_finish")
            or unit:AddAbility("ability_archive_finish")
        if valid(finish) and (not finish.GetLevel or finish:GetLevel() < 1) then finish:SetLevel(1) end
    end
end
local function hub_model(index)
    return rule["building_model_" .. tostring(index)] or rule.building_model
end
local function create_hubs(state)
    if state.finished then return end
    for index = 1, 3 do
        if not valid(state.hubs[index]) then
            local position, source = hub_placement.resolve(state.player_id, index, rule, context, wave, hubs)
            if not position then return false, source end
            print(string.format("[ArchiveChallenge] hub_creating player=%s slot=%s source=%s position=%s",
                tostring(state.player_id), tostring(index), tostring(source), tostring(position)))
            local unit = CreateUnitByName("npc_archive_challenge_" .. index, position, false, nil, nil, DOTA_TEAM_GOODGUYS)
            if not valid(unit) then return false, "hub_unit_create_failed:" .. index end
            -- Keep ownership immediately, even if later setup fails and retries.
            state.hubs[index] = unit
            hubs[unit:entindex()] = { state = state, unit = unit, index = index, position = position }
            print(string.format("[ArchiveChallenge] hub_created player=%s slot=%s source=%s entindex=%s position=%s",
                tostring(state.player_id), tostring(index), tostring(source), tostring(unit:entindex()), tostring(position)))
        end
        local unit = state.hubs[index]
        if not unit.survival_archive_hub_ready then
            unit.survival_archive_hub = index
            unit.survival_display_name = "存档挑战" .. index
            unit:SetControllableByPlayer(state.player_id, true)
            context.register_unit(state.player_id, unit, "archive_challenge")
            unit:SetModel(hub_model(index))
            unit:SetOriginalModel(hub_model(index))
            unit:SetModelScale(rule.building_model_scale)
            unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
            unit:AddNewModifier(unit, nil, "modifier_building_no_health_bar", {})
            if AddFOWViewer then AddFOWViewer(DOTA_TEAM_GOODGUYS, unit:GetAbsOrigin(), 600,
                math.max(1, (deadline or now() + 1800) - now()), false) end
        end
        require("systems/challenge_guardian_visual_service").apply(state.hubs[index])
        ensure_hub_abilities(state.hubs[index], index)
        unit.survival_archive_hub_ready = true
    end
    publish(state)
    return true
end
local function ensure_hubs(state)
    local ok, ready, reason = pcall(create_hubs, state)
    if ok and ready then return true end
    print("[ArchiveChallenge] hubs pending player=" .. tostring(state.player_id)
        .. " error=" .. tostring(ok and reason or ready))
    scheduler.every(1, function()
        if not active or state.finished then return false end
        local retry_ok, retry_ready = pcall(create_hubs, state)
        if retry_ok and retry_ready then return false end
        return true
    end, "archive_hubs_retry:" .. state.player_id)
    return false
end
function M.begin(payload)
    if ended then return {ok = true, keep_running = false} end
    local difficulty = tonumber(tostring(payload.difficulty_id):match("[Nn](%d+)")) or 0
    if difficulty < rule.building_unlock_difficulty then return { ok = true, keep_running = false } end
    if active then
        for _, state in pairs(players) do ensure_hubs(state) end
        return { ok = true, keep_running = true }
    end
    if not payload.player_ids or #payload.player_ids == 0 then return { ok = false } end
    active = true
    print("[ArchiveChallenge] begin difficulty=" .. tostring(payload.difficulty_id)
        .. " players=" .. tostring(#payload.player_ids))
    deadline = now() + (tonumber(rule.phase_duration_seconds) or 1800)
    scheduler.after(math.max(0, deadline-now()), function()
        if active then expire_if_due() end
    end, TIMER_ID)
    publish_phase()
    for _, id in ipairs(payload.player_ids) do
        local state = { player_id = id, difficulty_id = payload.difficulty_id,
            difficulty = difficulty, hubs = {}, cooldowns = {}, used = {}, finished = false }
        players[id] = state
        ensure_hubs(state)
        bus.emit(events.UI_NOTIFICATION, { player_id = id, level = "info",
            message = "通关成功！存档挑战限时30分钟，到时自动结束；也可在存档挑战3提前结束。" })
    end
    return { ok = true, keep_running = true }
end
function M.summon(caster, challenge_id, ability)
    if expire_if_due() then return false, "挑战阶段时间已到" end
    local hub = valid(caster) and hubs[caster:entindex()]
    local definition = definitions.by_id[challenge_id]
    if not active or not hub or hub.unit ~= caster or not valid(ability)
        or ability:GetCaster() ~= caster or not definition
        or ability:GetAbilityName() ~= "ability_archive_" .. challenge_id
        or hub.index ~= definition.building_id then return false, "挑战入口无效" end
    local state = hub.state
    if require("systems/archive_endless_service").is_running(state.player_id) then return false, "请先完成无尽挑战" end
    if state.used[challenge_id] then return false, "本局已挑战，每个技能只能挑战一次" end
    if context.owner_player_id(caster) ~= state.player_id then return false, "挑战建筑不属于当前玩家" end
    if not allowed(state, definition) then return false, "需要当前关卡≥N" .. definition.min_difficulty end
    if valid(state.active_boss) and state.active_boss:IsAlive() then return false, "请先击败当前挑战BOSS" end
    if (state.cooldowns[challenge_id] or 0) > now() then return false, "挑战冷却中" end
    local row = stats.by_id[challenge_id .. "_" .. state.difficulty_id]
    if not row or not row.enabled then return false, "挑战属性尚未配置" end
    local unit, reason = wave.spawn_challenge_monster(row, {
        unit_name = "npc_survival_wave_monster", model_path = definition.model_path,
        default_wearable_asset_id = definition.default_wearable_asset_id,
        model_scale = definition.model_scale, movement_type = "ground", attack_type = "melee",
        move_speed = row.move_speed, attack_range = row.attack_range,
    }, state.player_id)
    if not valid(unit) then return false, reason or "BOSS生成失败" end
    state.used[challenge_id] = true
    if unit.SetDeathXP then unit:SetDeathXP(0) end
    if unit.SetMinimumGoldBounty then unit:SetMinimumGoldBounty(0) end
    if unit.SetMaximumGoldBounty then unit:SetMaximumGoldBounty(0) end
    if unit.SetBaseMagicalResistanceValue then unit:SetBaseMagicalResistanceValue(row.magic_resistance) end
    unit.survival_display_name = definition.display_name
    sequence = sequence + 1
    state.active_boss = unit
    bosses[unit:entindex()] = { state = state, unit = unit, challenge_id = challenge_id, sequence = sequence }
    state.cooldowns[challenge_id] = now() + definition.cooldown_seconds
    ability:StartCooldown(definition.cooldown_seconds)
    publish(state)
    return true
end
local function killed(payload)
    if not active or expire_if_due() then return end
    local unit = payload and payload.victim
    local id = tonumber(payload and payload.victim_entindex) or (valid(unit) and unit:entindex())
    local meta = id and bosses[id]
    if not meta or meta.state.finished or (unit and meta.unit ~= unit) then return end
    bosses[id] = nil
    meta.state.active_boss = nil
    require("systems/monster_hero_visual_service").on_death(meta.unit)
    archive.record_challenge(meta.state.player_id, meta.challenge_id, meta.sequence, meta.state.difficulty_id)
    publish(meta.state)
end
local function finish_if_all()
    for _, state in pairs(players) do if not state.finished then return end end
    end_phase(false)
end
function M.finish(caster)
    if expire_if_due() then return false, "挑战阶段时间已到" end
    local hub = valid(caster) and hubs[caster:entindex()]
    if not active or not hub or hub.index ~= 3 then return false, "结束入口无效" end
    local state = hub.state
    if archive.has_pending(state.player_id) then return false, "奖励正在保存，请稍后结束" end
    state.finished = true
    cleanup(state)
    finish_if_all()
    return true
end
function M.start_endless(caster, ability)
    if expire_if_due() then return false, "挑战阶段时间已到" end
    local hub = valid(caster) and hubs[caster:entindex()]
    if not active or not hub or hub.unit ~= caster or hub.index ~= 2 or not valid(ability)
        or ability:GetCaster() ~= caster or ability:GetAbilityName() ~= "ability_archive_endless" then return false, "无尽入口无效" end
    local state = hub.state
    if state.finished or context.owner_player_id(caster) ~= state.player_id then return false, "无尽入口不可用" end
    if state.used.endless then return false, "本局已开启无尽挑战" end
    if state.active_boss then return false, "请先击败当前挑战BOSS" end
    local ok, reason = require("systems/archive_endless_service").start(state.player_id, state.difficulty)
    if ok then state.used.endless = true end
    publish(state)
    return ok, reason
end
function M.cast(ability, challenge_id)
    local caster = ability:GetCaster()
    local ok, reason
    if challenge_id == "finish" then ok, reason = M.finish(caster)
    elseif challenge_id == "endless" then ok, reason = M.start_endless(caster, ability)
    else ok, reason = M.summon(caster, challenge_id, ability) end
    if not ok then
        ability:EndCooldown()
        local owner = valid(caster) and context.owner_player_id(caster)
        if owner then notify(owner, tostring(reason)) end
    end
end
function M.precache(precache_context)
    local seen = {}
    local function add(path)
        if not seen[path] then PrecacheResource("model", path, precache_context); seen[path] = true end
    end
    for index = 1, 3 do
        add(hub_model(index))
        if PrecacheUnitByNameSync then PrecacheUnitByNameSync("npc_archive_challenge_" .. index, precache_context) end
    end
    add(require("systems/archive_endless_config").rules.model_path)
    local catalog = require("config/asset_catalog")
    for _, row in ipairs(definitions.rows) do
        if row.enabled then
            add(row.model_path)
            local asset = catalog.resolve(row.default_wearable_asset_id)
            if asset then
                add(asset.primary_model)
                for _, component in ipairs(asset.components or {}) do add(component.model_path) end
                for _, effect in ipairs(asset.effects or {}) do
                    if effect.enabled ~= false and not seen[effect.particle_path] then
                        PrecacheResource("particle", effect.particle_path, precache_context)
                        seen[effect.particle_path] = true
                    end
                end
            end
        end
    end
end
function M.init()
    players, hubs, bosses = {}, {}, {}
    sequence, active = 0, false
    deadline, ended, expired = nil, false, false
    settling, winner_sent = false, false
    scheduler.cancel(SAVE_TIMER_ID)
    scheduler.cancel(TIMER_ID)
    bus.handle_request("archive.challenge_state", M.phase_snapshot)
    require("systems/archive_endless_service").init(function(id)
        if players[id] then publish(players[id]) end
    end)
    bus.handle_request("archive.challenge_begin", M.begin)
    bus.subscribe(events.ENGINE_ENTITY_KILLED, killed)
    bus.subscribe(events.PLAYER_DISCONNECTED, function(payload)
        local state = players[tonumber(payload.player_id)]
        if not state then return end
        state.finished = true
        cleanup(state)
        if active then finish_if_all() end
    end)
end
M._test = { players = function() return players end }
return M
