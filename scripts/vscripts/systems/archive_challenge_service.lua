local bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/archive_challenge_definitions")
local actions = require("config/generated/archive_challenge_actions")
local stats = require("config/generated/archive_challenge_stats")
local rule = require("config/generated/archive_challenge_rules").by_id.default
local context = require("systems/player_context_service")
local wave = require("systems/wave_system")
local archive = require("systems/archive_service")
local cooperative_rewards = require("systems/archive_cooperative_reward_service")
local scheduler = require("core/scheduler")
local hub_placement = require("systems/archive_hub_placement")
local model_scale = require("visual/model_scale")
local daily_limits = require("systems/archive_daily_limits")
local calendar = require("systems/archive_calendar")
local M = {}
local players, hubs, bosses = {}, {}, {}
local published_runtime = {}
local sequence, active = 0, false
local deadline, ended, expired = nil, false, false
local TIMER_ID = "archive_challenge_phase_timer"
local SAVE_TIMER_ID = "archive_challenge_save_barrier"
local DAILY_TIMER_ID = "archive_challenge_daily_rollover"
local settling, winner_sent = false, false
local finalization_started = false
local function valid(unit) return unit and not unit:IsNull() end
local function now() return GameRules:GetGameTime() end
function M.phase_snapshot(payload)
    local state = payload and players[tonumber(payload.player_id)]
    return {active = active and 1 or 0, ended = ended and 1 or 0,
        player_finished = state and state.finished and 1 or 0,
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
local function challenge_running(state, challenge_id)
    local group = state.active_groups and state.active_groups[challenge_id]
    return group and (not group.committed or group.remaining > 0) or false
end
local function same_runtime(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not same_runtime(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function write_runtime(key, value)
    if not CustomNetTables or same_runtime(published_runtime[key], value) then return end
    CustomNetTables:SetTableValue("survival_ability_runtime", key, value)
    published_runtime[key] = value
end
local function action_allowed(state, action)
    if not allowed(state, action) then return false end
    return action.action_id ~= "tower_solo"
        or state.mode == "cold" or state.mode == "scourge"
end
local function hub_actions(index, callback)
    for _, action in ipairs(actions.rows) do
        if action.enabled and action.building_id == index then callback(action) end
    end
end
local function reward_eligibility(state, definition)
    local profiles = require("systems/player_profile_service")
    local profile = type(profiles.get_account_profile) == "function" and profiles.get_account_profile(state.player_id)
        or type(profiles.get_profile) == "function" and profiles.get_profile(state.player_id)
    local save = profile and profile.save and profile.save.archive or {}
    return require("systems/archive_challenge_reward_eligibility").check(save, definition)
end
local function daily_quota(player_id, key)
    if require("debug/mode_unlock_test").is_enabled() then return nil end
    if not key then return nil end
    local profiles = require("systems/player_profile_service")
    if type(profiles.get_daily_limit) == "function" then return profiles.get_daily_limit(player_id, key) end
    local profile = type(profiles.get_account_profile) == "function" and profiles.get_account_profile(player_id)
        or type(profiles.get_profile) == "function" and profiles.get_profile(player_id)
    if not profile then return nil end
    local summary = daily_limits.snapshot(profile)
    return summary and summary.by_key and summary.by_key[key] or nil
end
local function capped(quota)
    return quota and (quota.capped == true or tonumber(quota.capped) == 1
        or tonumber(quota.remaining) == 0) or false
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
    local challenge_id = tostring(ability_name):match("^ability_archive_(.+)$")
    local definition = challenge_id and definitions.by_id[challenge_id]
    local action = challenge_id and actions.by_id[challenge_id]
    local quota
    if action and action.building_id == hub.index then
        local unlocked = action_allowed(state, action)
        runtime.slot_order = action.slot_order
        runtime.display_name, runtime.upgrade_description = action.display_name, action.description
        runtime.icon_name = action.ability_icon
        runtime.fields = {{label = "解锁条件", value = action.unlock_text or "通关后可用"}}
        ready = ready and unlocked
        if challenge_id == "endless" or challenge_id == "tower_solo" then
            local used = state.used[challenge_id == "tower_solo" and "tower" or "endless"]
            quota = daily_quota(state.player_id, "endless")
            ready = ready and not used and not busy
                and require("systems/archive_endless_config").group(state.difficulty, state.mode) ~= nil
            runtime.status_text = busy and "无尽／通天塔挑战进行中" or used and "本局已开启"
                or not unlocked and (action.unlock_text or "尚未解锁")
                or ready and "可以开启" or "暂不可开启"
        elseif challenge_id == "endless_skip" then
            local step = require("systems/archive_endless_service").skip_step(state.player_id)
            ready = ready and step < 20
            runtime.fields[#runtime.fields + 1] = {label = "每波步长", value = tostring(step)}
            runtime.status_text = not unlocked and (action.unlock_text or "尚未解锁")
                or step >= 20 and "已选择最大步长20，不能退回" or "点击增加后续波次步长"
        else
            runtime.status_text = ready and "返回自己的英雄，保留挑战阶段" or "挑战已结束"
        end
    elseif challenge_id == "finish" then
        runtime.display_name = "结束存档挑战"
        runtime.upgrade_description = "结束自己的挑战；所有玩家结束后胜利结算。未击败的BOSS不会获得奖励。"
        runtime.status_text = ready and "可以结束挑战" or "挑战已结束"
    elseif definition and definition.building_id == hub.index then
        quota = daily_quota(state.player_id, daily_limits.challenge_key(definition))
        local unlocked = allowed(state, definition)
        local used = state.used[challenge_id] == true
        local running = challenge_running(state, challenge_id)
        local group = state.active_groups and state.active_groups[challenge_id]
        ready = ready and unlocked and not used and not running
        runtime.challenge_active = running and 1 or 0
        runtime.challenge_remaining = group and group.remaining or 0
        runtime.display_name = definition.display_name
        runtime.slot_order = definition.slot_order
        runtime.upgrade_description = definition.description
        runtime.icon_name = definition.ability_icon
        runtime.fields = {{label = "解锁条件", value = definition.unlock_text or ("N" .. definition.min_difficulty .. "解锁")}}
        local eligible, reward_reason = reward_eligibility(state, definition)
        if not eligible then
            runtime.fields[#runtime.fields + 1] = {label = "奖励条件", value = reward_reason}
        end
        runtime.status_text = running and "该挑战进行中" or used and "本局已挑战（每个技能仅限一次）"
            or not unlocked and (definition.unlock_text or ("N" .. definition.min_difficulty .. "解锁"))
            or not eligible and "可以挑战，但尚不满足奖励条件" or "可以挑战"
    else
        ready = false
        runtime.status_text = "挑战入口无效"
    end
    if quota then
        runtime.daily_key, runtime.daily_earned, runtime.daily_limit = quota.key, quota.earned, quota.limit
        runtime.daily_remaining, runtime.daily_capped = quota.remaining, capped(quota) and 1 or 0
        if capped(quota) then ready = false; runtime.status_text = "今日奖励已达上限" end
    end
    if not active or ended or state.finished or (deadline and now() >= deadline) then
        runtime.status_text = "挑战已结束"
    elseif not cooperative_rewards.matches_session(state.mode, state.difficulty) then
        ready = false
        runtime.status_text = "本局模式或难度已变化，挑战不可用"
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
                    write_runtime(tostring(runtime.ability_entindex), runtime)
                end
            end
            for _, definition in ipairs(definitions.rows) do
                if definition.enabled and definition.building_id == hub.survival_archive_hub then
                    update("ability_archive_" .. definition.challenge_id)
                end
            end
            hub_actions(hub.survival_archive_hub, function(action) update(action.ability_name) end)
            if CustomNetTables then
                write_runtime("unit:" .. tostring(hub:entindex()), {
                    owner_entindex = hub:entindex(),
                    ability_count = hub.GetAbilityCount and hub:GetAbilityCount() or count,
                })
            end
        end
    end
end
local function watch_daily_rollover()
    local previous_day = tostring(calendar.day())
    scheduler.every(5, function()
        if not active or ended then return false end
        local current_day = tostring(calendar.day())
        if current_day == previous_day then return end
        previous_day = current_day
        for _, state in pairs(players) do
            if not state.finished then publish(state) end
        end
    end, DAILY_TIMER_ID)
end
local function retire_boss(unit)
    if not valid(unit) then return end
    bosses[unit:entindex()] = nil
    unit.survival_wave_cleanup = true
    pcall(require("systems/monster_hero_visual_service").clear, unit)
    if UTIL_Remove then pcall(UTIL_Remove, unit) end
end
local function remove_group(state, challenge_id, expected)
    local group = state.active_groups and state.active_groups[challenge_id]
    if not group or expected and group ~= expected then return end
    -- Detach before native removals: their reentrant deaths must never settle
    -- this group or remove another concurrently running challenge.
    state.active_groups[challenge_id] = nil
    for id, unit in pairs(group.units) do
        bosses[id] = nil
        retire_boss(unit)
    end
    group.units, group.remaining = {}, 0
end
local function remove_bosses(state)
    for challenge_id, group in pairs(state.active_groups or {}) do remove_group(state, challenge_id, group) end
end
local function cleanup(state)
    scheduler.cancel("archive_hubs_retry:" .. state.player_id)
    require("systems/archive_endless_service").cancel(state.player_id, "结束存档挑战")
    remove_bosses(state)
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
                        local key = tostring(ability:entindex())
                        write_runtime(key, {
                            removed = 1, owner_entindex = unit_index, ability_entindex = ability:entindex(),
                        })
                        published_runtime[key] = nil
                    end
                end
                for _, definition in ipairs(definitions.rows) do
                    if definition.enabled and definition.building_id == unit.survival_archive_hub then
                        retire("ability_archive_" .. definition.challenge_id)
                    end
                end
                hub_actions(unit.survival_archive_hub, function(action) retire(action.ability_name) end)
                local key = "unit:" .. tostring(unit_index)
                write_runtime(key, {
                    removed = 1, owner_entindex = unit_index, ability_count = 0,
                })
                published_runtime[key] = nil
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
    -- Do not close archive enqueue while a team event has yet to hand off an
    -- account intent (e.g. an unexpected pre-enqueue provider exception).
    if cooperative_rewards.has_pending() then return true end
    if not finalization_started then
        finalization_started = true
        if archive.begin_finalization then archive.begin_finalization() end
    end
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
    scheduler.cancel(DAILY_TIMER_ID)
    -- Mark everyone finished before removing monsters; late death events cannot award rewards.
    for _, state in pairs(players) do state.finished = true end
    for _, state in pairs(players) do
        local ok, reason = pcall(cleanup, state)
        if not ok then print("[ArchiveChallenge] final cleanup failed: " .. tostring(reason)) end
    end
    settling = true
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
    hub_actions(index, function(action)
        local ability = unit:FindAbilityByName(action.ability_name) or unit:AddAbility(action.ability_name)
        if valid(ability) and (not ability.GetLevel or ability:GetLevel() < 1) then ability:SetLevel(1) end
    end)
end
local function hub_model(index)
    return rule["building_model_" .. tostring(index)] or index == 4 and rule.building_model_3 or rule.building_model
end
local function create_hubs(state)
    if state.finished then return end
    for index = 1, tonumber(rule.building_count) or 4 do
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
            model_scale.apply(unit, rule.building_model_scale, "archive_challenge")
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
    local rewards_ready, rewards_error = cooperative_rewards.begin(payload.player_ids, payload.difficulty_id)
    if not rewards_ready then
        print("[ArchiveChallenge] reward admission failed: " .. tostring(rewards_error))
        return {ok = false, error = rewards_error, keep_running = false}
    end
    local setup = package.loaded["systems/match_setup_service"]
    local mode = setup and type(setup.get_mode) == "function" and setup.get_mode() or "standard"
    active = true
    watch_daily_rollover()
    print("[ArchiveChallenge] begin difficulty=" .. tostring(payload.difficulty_id)
        .. " players=" .. tostring(#payload.player_ids))
    deadline = now() + (tonumber(rule.phase_duration_seconds) or 1800)
    scheduler.after(math.max(0, deadline-now()), function()
        if active then expire_if_due() end
    end, TIMER_ID)
    publish_phase()
    for _, id in ipairs(payload.player_ids) do
        local state = { player_id = id, difficulty_id = payload.difficulty_id,
            difficulty = difficulty, mode = mode, hubs = {}, cooldowns = {}, used = {}, active_groups = {}, finished = false }
        players[id] = state
        ensure_hubs(state)
        bus.emit(events.UI_NOTIFICATION, { player_id = id, level = "info",
            message = "通关成功！出生点附近已开放四座存档建筑，限时30分钟；顶部可提前结束自己的挑战。" })
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
    if not cooperative_rewards.matches_session(state.mode, state.difficulty) then
        return false, "本局模式或难度已变化，挑战不可用"
    end
    if state.used[challenge_id] then return false, "本局已挑战，每个技能只能挑战一次" end
    if context.owner_player_id(caster) ~= state.player_id then return false, "挑战建筑不属于当前玩家" end
    if not allowed(state, definition) then return false, "需要当前关卡≥N" .. definition.min_difficulty end
    if challenge_running(state, challenge_id) then return false, "该挑战正在生成或进行中" end
    if (state.cooldowns[challenge_id] or 0) > now() then return false, "挑战冷却中" end
    if capped(daily_quota(state.player_id, daily_limits.challenge_key(definition))) then
        publish(state)
        return false, "今日奖励已达上限"
    end
    -- Archived combat values are final for every difficulty. Keep movement,
    -- range and other existing fields from the original per-entry definition.
    local baseline = stats.by_id[challenge_id .. "_" .. state.difficulty_id]
        or stats.by_id[challenge_id .. "_N1"]
    local authored = require("config/human_challenge_balance").archive(challenge_id, state.difficulty_id)
    local row = baseline
    if authored then
        row = {}
        for field, value in pairs(baseline or {}) do row[field] = value end
        for field, value in pairs(authored) do row[field] = value end
    end
    if not row or not row.enabled then return false, "挑战属性尚未配置" end
    sequence = sequence + 1
    local count = math.max(1, math.floor(tonumber(row.count) or 1))
    local group = {units = {}, remaining = 0, challenge_id = challenge_id, sequence = sequence}
    state.active_groups[challenge_id] = group
    local function abort(reason)
        remove_group(state, challenge_id, group)
        if active and not state.finished then publish(state) end
        return false, reason
    end
    for _ = 1, count do
        local spawn_ok, unit, reason = pcall(wave.spawn_challenge_monster, row, {
            unit_name = "npc_survival_wave_monster", model_path = definition.model_path,
            default_wearable_asset_id = definition.default_wearable_asset_id,
            model_scale = definition.model_scale, movement_type = "ground", attack_type = "melee",
            move_speed = row.move_speed, attack_range = row.attack_range,
        }, state.player_id)
        if not spawn_ok or not valid(unit) then
            return abort(spawn_ok and (reason or "BOSS生成失败") or "BOSS生成失败，请重试")
        end
        if not active or ended or state.finished or players[state.player_id] ~= state
            or state.active_groups[challenge_id] ~= group then
            retire_boss(unit)
            return abort("挑战阶段已结束")
        end
        group.units[unit:entindex()] = unit
        group.remaining = group.remaining + 1
        bosses[unit:entindex()] = {state = state, unit = unit, group = group,
            challenge_id = challenge_id, sequence = group.sequence}
        local ready = pcall(function()
            if unit.SetDeathXP then unit:SetDeathXP(0) end
            if unit.SetMinimumGoldBounty then unit:SetMinimumGoldBounty(0) end
            if unit.SetMaximumGoldBounty then unit:SetMaximumGoldBounty(0) end
            if unit.SetBaseMagicalResistanceValue then unit:SetBaseMagicalResistanceValue(row.magic_resistance) end
            unit.survival_display_name = definition.display_name
        end)
        if not ready then return abort("怪物初始化失败，请重试") end
        if unit.IsAlive and not unit:IsAlive() then
            return abort("怪物生成时已失效，请重试")
        end
    end
    if not active or ended or state.finished or players[state.player_id] ~= state
        or state.active_groups[challenge_id] ~= group or not valid(ability) then
        return abort("挑战阶段已结束")
    end
    group.committed = true
    state.used[challenge_id] = true
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
    -- Cosmetic teardown must not interrupt authoritative group retirement.
    pcall(require("systems/monster_hero_visual_service").on_death, meta.unit)
    local group = meta.group
    if not group or meta.state.active_groups[meta.challenge_id] ~= group then return end
    group.units[id] = nil
    group.remaining = group.remaining - 1
    if group.remaining > 0 or not group.committed then
        publish(meta.state)
        return
    end
    meta.state.active_groups[meta.challenge_id] = nil
    local result = cooperative_rewards.record_challenge(meta.state.player_id, meta.challenge_id,
        meta.sequence, meta.state.difficulty_id)
    if not result or not result.ok then
        notify(meta.state.player_id, "挑战完成，奖励派发未能接收：" .. tostring(result and result.error))
    end
    publish(meta.state)
end
local function finish_if_all()
    for _, state in pairs(players) do if not state.finished then return end end
    end_phase(false)
end
function M.finish_player(player_id, automatic)
    if expire_if_due() then return false, "挑战阶段时间已到" end
    local state = players[player_id]
    if not active or not state or state.finished then return false, "挑战已结束" end
    if not automatic and archive.has_pending(state.player_id) then return false, "奖励正在保存，请稍后结束" end
    state.finished = true
    cleanup(state)
    finish_if_all()
    return true
end
function M.finish(caster)
    local hub = valid(caster) and hubs[caster:entindex()]
    if not hub or hub.unit ~= caster or context.owner_player_id(caster) ~= hub.state.player_id then
        return false, "结束入口无效"
    end
    return M.finish_player(hub.state.player_id)
end
local function action_hub(caster, ability, action_id)
    local hub = valid(caster) and hubs[caster:entindex()]
    local action = actions.by_id[action_id]
    if not active or not hub or hub.unit ~= caster or not valid(ability)
        or ability:GetCaster() ~= caster or not action or not action.enabled
        or ability:GetAbilityName() ~= action.ability_name or hub.index ~= action.building_id
        or hub.state.finished or context.owner_player_id(caster) ~= hub.state.player_id then
        return nil, "挑战入口无效"
    end
    if not cooperative_rewards.matches_session(hub.state.mode, hub.state.difficulty) then
        return nil, "本局模式或难度已变化，挑战不可用"
    end
    if not action_allowed(hub.state, action) then return nil, action.unlock_text or "尚未解锁" end
    return hub
end
function M.start_endless(caster, ability, variant)
    if expire_if_due() then return false, "挑战阶段时间已到" end
    local hub, reason = action_hub(caster, ability, variant == "tower" and "tower_solo" or "endless")
    if not hub then return false, reason end
    local state = hub.state
    if state.finished or context.owner_player_id(caster) ~= state.player_id then return false, "无尽入口不可用" end
    local used_key = variant == "tower" and "tower" or "endless"
    if state.used[used_key] then return false, "本局已开启该挑战" end
    if capped(daily_quota(state.player_id, "endless")) then
        publish(state)
        return false, "今日奖励已达上限"
    end
    local ok, reason = require("systems/archive_endless_service").start(state.player_id, state.difficulty, variant)
    if ok then state.used[used_key] = true end
    publish(state)
    return ok, reason
end
function M.skip_endless(caster, ability)
    if expire_if_due() then return false, "挑战阶段时间已到" end
    local hub, reason = action_hub(caster, ability, "endless_skip")
    if not hub then return false, reason end
    local ok, result = require("systems/archive_endless_service").cycle_skip(hub.state.player_id)
    publish(hub.state)
    return ok, result
end
function M.cast(ability, challenge_id)
    local caster = ability:GetCaster()
    local ok, reason
    if challenge_id == "finish" then ok, reason = M.finish(caster)
    elseif challenge_id == "endless" then ok, reason = M.start_endless(caster, ability)
    elseif challenge_id == "tower_solo" then ok, reason = M.start_endless(caster, ability, "tower")
    elseif challenge_id == "endless_skip" then ok, reason = M.skip_endless(caster, ability)
    else ok, reason = M.summon(caster, challenge_id, ability) end
    if not ok then
        if valid(ability) then ability:EndCooldown() end
        local owner = valid(caster) and context.owner_player_id(caster)
        if owner then notify(owner, tostring(reason)) end
    end
end
function M.precache(precache_context)
    local seen = {}
    local function add(path)
        if not seen[path] then PrecacheResource("model", path, precache_context); seen[path] = true end
    end
    for index = 1, tonumber(rule.building_count) or 4 do
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
    cooperative_rewards.init()
    players, hubs, bosses = {}, {}, {}
    published_runtime = {}
    sequence, active = 0, false
    deadline, ended, expired = nil, false, false
    settling, winner_sent = false, false
    finalization_started = false
    scheduler.cancel(SAVE_TIMER_ID)
    scheduler.cancel(TIMER_ID)
    scheduler.cancel(DAILY_TIMER_ID)
    bus.handle_request("archive.challenge_state", M.phase_snapshot)
    require("systems/archive_endless_service").init(function(id)
        if players[id] then publish(players[id]) end
    end, function(id, variant)
        if variant == "tower" then M.finish_player(id, true) end
    end)
    if CustomGameEventManager and CustomGameEventManager.RegisterListener then
        CustomGameEventManager:RegisterListener("survival_archive_finish", function(_, payload)
            -- Dota injects PlayerID. A client-supplied player_id/owner is ignored.
            local id = tonumber(payload and payload.PlayerID)
            if not id or id ~= math.floor(id) or not players[id] then return end
            local ok, reason = M.finish_player(id)
            if not ok then notify(id, reason) end
        end)
    end
    bus.handle_request("archive.challenge_begin", M.begin)
    bus.subscribe(events.ENGINE_ENTITY_KILLED, killed)
    bus.subscribe(events.PLAYER_PROFILE_CHANGED, function(payload)
        local state = players[tonumber(payload and payload.player_id)]
        if state and active and not state.finished then publish(state) end
    end)
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
