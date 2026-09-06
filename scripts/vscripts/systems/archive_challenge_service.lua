local bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/archive_challenge_definitions")
local stats = require("config/generated/archive_challenge_stats")
local rule = require("config/generated/archive_challenge_rules").by_id.default
local context = require("systems/player_context_service")
local wave = require("systems/wave_system")
local archive = require("systems/archive_service")
local scheduler = require("core/scheduler")
local M = {}
local players, hubs, bosses = {}, {}, {}
local sequence, active = 0, false
local function valid(unit) return unit and not unit:IsNull() end
local function now() return GameRules:GetGameTime() end
local function notify(id, message)
    bus.emit(events.UI_NOTIFICATION, { player_id = id, message = message, level = "error" })
end
local function allowed(state, definition)
    return state and not state.finished and definition and definition.enabled
        and state.difficulty >= definition.min_difficulty
end
local function publish(state)
    local endless = require("systems/archive_endless_service")
    local endless_busy = endless.is_running(state.player_id)
    for _, hub in pairs(state.hubs) do
        if valid(hub) then
            for _, definition in ipairs(definitions.rows) do
                if definition.enabled and definition.building_id == hub.survival_archive_hub then
                    local ability = hub:FindAbilityByName("ability_archive_" .. definition.challenge_id)
                    if valid(ability) then
                        local unlocked = allowed(state, definition)
                        local used = state.used[definition.challenge_id] == true
                        ability:SetActivated(unlocked and not used and not state.active_boss and not endless_busy)
                        if CustomNetTables then
                            CustomNetTables:SetTableValue("survival_ability_runtime", tostring(ability:entindex()), {
                                ability_name = ability:GetAbilityName(), owner_entindex = hub:entindex(),
                                available = unlocked and not used and not state.active_boss and not endless_busy and 1 or 0, can_afford = 1,
                                status_text = endless_busy and "无尽挑战进行中" or used and "本局已挑战（每个技能仅限一次）" or not unlocked and ("需要当前关卡 N" .. definition.min_difficulty)
                                    or (state.active_boss and "请先击败当前挑战BOSS" or "可以挑战"),
                                upgrade_description = definition.description,
                                fields = { { label = "解锁条件", value = "当前关卡≥N" .. definition.min_difficulty } },
                            })
                        end
                    end
                end
            end
        end
    end
    local hub = state.hubs[2]
    local ability = valid(hub) and hub:FindAbilityByName("ability_archive_endless")
    if valid(ability) then
        local ready = not state.finished and not state.used.endless and not endless_busy and not state.active_boss
            and require("systems/archive_endless_config").group(state.difficulty) ~= nil
        ability:SetActivated(ready)
        if CustomNetTables then
            CustomNetTables:SetTableValue("survival_ability_runtime", tostring(ability:entindex()), {
                ability_name = ability:GetAbilityName(), owner_entindex = hub:entindex(), available = ready and 1 or 0, can_afford = 1,
                status_text = endless_busy and "无尽挑战进行中" or state.used.endless and "本局已开启" or state.active_boss and "请先击败当前挑战BOSS" or ready and "可以开启" or "暂不可开启",
                upgrade_description = "每波5只小怪，限时60秒，清空后立即下一波。每10波积分提高7分，首10波每波1分。每局仅可开启一次。",
            })
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
    require("systems/archive_endless_service").cancel(state.player_id, "结束存档挑战")
    remove_boss(state)
    for _, unit in pairs(state.hubs) do
        if valid(unit) then
            hubs[unit:entindex()] = nil
            context.unregister_unit(unit)
            UTIL_Remove(unit)
        end
    end
    state.hubs = {}
end
local function ensure_hub_abilities(unit, index)
    for _, definition in ipairs(definitions.rows) do
        if definition.enabled and definition.building_id == index then
            local name = "ability_archive_" .. definition.challenge_id
            local ability = unit:FindAbilityByName(name) or unit:AddAbility(name)
            if valid(ability) then ability:SetLevel(1) end
        end
    end
    if index == 2 then
        local endless = unit:FindAbilityByName("ability_archive_endless") or unit:AddAbility("ability_archive_endless")
        if valid(endless) then endless:SetLevel(1) end
    end
    if index == 3 then
        local finish = unit:FindAbilityByName("ability_archive_finish")
            or unit:AddAbility("ability_archive_finish")
        if valid(finish) then finish:SetLevel(1) end
    end
end
local function create_hubs(state)
    if state.finished then return end
    local channel = wave.get_player_spawn_marker(state.player_id)
    if not valid(channel) then return false end
    local origin = channel:GetAbsOrigin()
    for index = 1, 3 do
        if not valid(state.hubs[index]) then
            local position = Vector(origin.x + (index - 2) * rule.building_spacing,
                origin.y + rule.building_offset_y, origin.z)
            local unit = CreateUnitByName("npc_archive_challenge_" .. index, position, true, nil, nil, DOTA_TEAM_GOODGUYS)
            if not valid(unit) then return false end
            unit.survival_archive_hub = index
            unit.survival_display_name = "存档挑战" .. index
            unit:SetControllableByPlayer(state.player_id, true)
            context.register_unit(state.player_id, unit, "archive_challenge")
            unit:SetModel(rule.building_model)
            unit:SetOriginalModel(rule.building_model)
            unit:SetModelScale(rule.building_model_scale)
            unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
            state.hubs[index] = unit
            hubs[unit:entindex()] = { state = state, unit = unit, index = index }
        end
        ensure_hub_abilities(state.hubs[index], index)
    end
    publish(state)
    return true
end
local function ensure_hubs(state)
    local ok, ready = pcall(create_hubs, state)
    if ok and ready then return true end
    print("[ArchiveChallenge] hubs pending player=" .. tostring(state.player_id)
        .. " error=" .. tostring(ok and "spawn_marker_missing" or ready))
    scheduler.every(1, function()
        if not active or state.finished then return false end
        local retry_ok, retry_ready = pcall(create_hubs, state)
        if retry_ok and retry_ready then return false end
        return true
    end, "archive_hubs_retry:" .. state.player_id)
    return false
end
function M.begin(payload)
    local difficulty = tonumber(tostring(payload.difficulty_id):match("[Nn](%d+)")) or 0
    if difficulty < rule.building_unlock_difficulty then return { ok = true, keep_running = false } end
    if active then
        for _, state in pairs(players) do ensure_hubs(state) end
        return { ok = true, keep_running = true }
    end
    if not payload.player_ids or #payload.player_ids == 0 then return { ok = false } end
    active = true
    for _, id in ipairs(payload.player_ids) do
        local state = { player_id = id, difficulty_id = payload.difficulty_id,
            difficulty = difficulty, hubs = {}, cooldowns = {}, used = {}, finished = false }
        players[id] = state
        ensure_hubs(state)
        bus.emit(events.UI_NOTIFICATION, { player_id = id, level = "info",
            message = "通关成功！出怪口旁已开放存档挑战，完成后可在存档挑战3结束本局。" })
    end
    return { ok = true, keep_running = true }
end
function M.summon(caster, challenge_id, ability)
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
    local unit = payload and payload.victim
    local id = tonumber(payload and payload.victim_entindex) or (valid(unit) and unit:entindex())
    local meta = id and bosses[id]
    if not meta or (unit and meta.unit ~= unit) then return end
    bosses[id] = nil
    meta.state.active_boss = nil
    require("systems/monster_hero_visual_service").on_death(meta.unit)
    archive.record_challenge(meta.state.player_id, meta.challenge_id, meta.sequence, meta.state.difficulty_id)
    publish(meta.state)
end
local function finish_if_all()
    for _, state in pairs(players) do if not state.finished then return end end
    active = false
    GameRules:SetGameWinner(DOTA_TEAM_GOODGUYS)
end
function M.finish(caster)
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
    add(rule.building_model)
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
