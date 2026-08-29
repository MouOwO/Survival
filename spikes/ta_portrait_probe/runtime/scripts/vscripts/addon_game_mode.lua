local config = require("ta_portrait_probe_runtime_config")

if TAPortraitProbe == nil then
    TAPortraitProbe = class({})
end

local VALID_VISUAL_RESULTS = {
    PASS = true,
    PARENTING_VISIBLE_BONE_MERGE_FAIL = true,
    RENDER_FAIL = true,
}

local function valid_entity(entity)
    if not entity then return false end
    if type(entity.IsNull) == "function" then
        local ok, is_null = pcall(entity.IsNull, entity)
        if not ok or is_null then return false end
    end
    if type(IsValidEntity) == "function" then
        local ok, is_valid = pcall(IsValidEntity, entity)
        if ok and not is_valid then return false end
    end
    return true
end

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then return false, nil end
    return pcall(method, target, ...)
end

local function call_succeeded(call_ok, result)
    return call_ok and result ~= false
end

local function remove_entity(entity)
    if not valid_entity(entity) then return end
    if type(UTIL_Remove) == "function" then
        pcall(UTIL_Remove, entity)
    else
        safe_call(entity, "RemoveSelf")
    end
end

local function vector_string(value)
    return string.format(
        "%.6f %.6f %.6f",
        tonumber(value and value.x) or 0,
        tonumber(value and value.y) or 0,
        tonumber(value and value.z) or 0
    )
end

local function entity_index(entity)
    local ok, index = safe_call(entity, "entindex")
    if not ok then return -1 end
    return tonumber(index) or -1
end

local function validate_entity(entity, expected_class, label)
    if not valid_entity(entity) then return false, label .. "_invalid" end
    local class_ok, class_name = safe_call(entity, "GetClassname")
    if not class_ok or class_name ~= expected_class then
        return false, label .. "_class_invalid:" .. tostring(class_name)
    end
    if entity_index(entity) <= 0 then return false, label .. "_entindex_invalid" end
    return true, "ok"
end

local function spawn_entity(entity_class, values)
    local ok, entity = pcall(
        SpawnEntityFromTableSynchronous,
        entity_class,
        values
    )
    if not ok or not valid_entity(entity) then return nil end
    return entity
end

local function apply_body_animation(body, sequence_name)
    local lookup_ok, sequence_index = safe_call(body, "LookupSequence", sequence_name)
    sequence_index = tonumber(sequence_index)
    if not lookup_ok or not sequence_index or sequence_index < 0 then
        return false, "sequence_lookup_failed"
    end

    local reset_ok, reset_result = safe_call(body, "ResetSequence", sequence_name)
    if not call_succeeded(reset_ok, reset_result) then
        return false, "sequence_reset_failed"
    end
    safe_call(body, "ResetSequenceInfo")
    safe_call(body, "SetCycle", 0)
    local playback_ok, playback_result = safe_call(body, "SetPlaybackRate", 1)
    if not call_succeeded(playback_ok, playback_result) then
        return false, "playback_rate_failed"
    end
    return true, sequence_index
end

function Precache(context)
    local models = { config.body.model }
    for _, wearable in ipairs(config.wearables or {}) do
        models[#models + 1] = wearable.model
    end
    for _, model_path in ipairs(models) do
        local ok = pcall(PrecacheResource, "model", model_path, context)
        if not ok then
            print("[TA_PORTRAIT_PROBE_RUNTIME] PRECACHE_FAIL model="
                .. tostring(model_path))
        end
    end
end

function Activate()
    GameRules.TAPortraitProbe = TAPortraitProbe()
    GameRules.TAPortraitProbe:InitGameMode()
end

function TAPortraitProbe:_PublishRuntimeState(success, status, detail)
    local body_index = valid_entity(self.body) and entity_index(self.body) or -1
    CustomNetTables:SetTableValue("ta_portrait_probe", "runtime", {
        success = success and 1 or 0,
        status = tostring(status or "unknown"),
        detail = tostring(detail or ""),
        body_entindex = body_index,
        wearable_count = #(self.wearables or {}),
        visual_verdict = "pending",
    })
end

function TAPortraitProbe:ClearRuntimeScene(reason)
    for index = #(self.wearables or {}), 1, -1 do
        remove_entity(self.wearables[index])
    end
    self.wearables = {}
    remove_entity(self.body)
    self.body = nil
    self.runtime_initialized = false
    if reason then
        print("[TA_PORTRAIT_PROBE_RUNTIME] CLEANUP reason=" .. tostring(reason))
    end
end

function TAPortraitProbe:_RemoveStaleNamedEntities()
    if not Entities or type(Entities.FindByName) ~= "function" then return end
    local names = { config.body.targetname }
    for _, wearable in ipairs(config.wearables or {}) do
        names[#names + 1] = wearable.targetname
    end
    for _, targetname in ipairs(names) do
        local found = {}
        local cursor = nil
        while true do
            cursor = Entities:FindByName(cursor, targetname)
            if not cursor then break end
            found[#found + 1] = cursor
        end
        for _, entity in ipairs(found) do remove_entity(entity) end
    end
end

function TAPortraitProbe:_FailInitialization(status, detail)
    self:ClearRuntimeScene("initialization_failed")
    self.initialization_in_progress = false
    self:_PublishRuntimeState(false, status, detail)
    print("[TA_PORTRAIT_PROBE_RUNTIME] FAIL status=" .. tostring(status)
        .. " detail=" .. tostring(detail))
    return false
end

function TAPortraitProbe:_SpawnBody()
    local body = spawn_entity("prop_dynamic", {
        targetname = config.body.targetname,
        model = config.body.model,
        DefaultAnim = config.body.sequence,
        origin = vector_string(config.body.origin),
        angles = vector_string(config.body.angles),
        solid = "0",
        spawnflags = "256",
        DisableBoneFollowers = "1",
    })
    local valid, reason = validate_entity(body, "prop_dynamic", "body")
    if not valid then
        remove_entity(body)
        return nil, reason
    end

    safe_call(body, "SetModel", config.body.model)
    safe_call(body, "SetOriginalModel", config.body.model)
    safe_call(body, "SetModelScale", tonumber(config.body.model_scale) or 1)
    safe_call(body, "SetAbsOrigin", Vector(
        config.body.origin.x,
        config.body.origin.y,
        config.body.origin.z
    ))
    safe_call(body, "SetAngles",
        config.body.angles.x,
        config.body.angles.y,
        config.body.angles.z)
    safe_call(body, "SetSolid", rawget(_G, "SOLID_NONE") or 0)
    return body, "ok"
end

function TAPortraitProbe:_SpawnWearable(body, definition)
    local wearable = spawn_entity(definition.entity_class, {
        targetname = definition.targetname,
        model = definition.model,
        origin = vector_string(config.body.origin),
        angles = vector_string(config.body.angles),
        solid = "0",
        spawnflags = "256",
        DisableBoneFollowers = "1",
    })
    local valid, reason = validate_entity(
        wearable,
        definition.entity_class,
        "wearable_" .. tostring(definition.id)
    )
    if not valid then
        remove_entity(wearable)
        return nil, reason
    end

    safe_call(wearable, "SetModel", definition.model)
    safe_call(wearable, "SetOriginalModel", definition.model)
    safe_call(wearable, "SetModelScale", tonumber(definition.model_scale) or 1)
    safe_call(wearable, "SetSolid", rawget(_G, "SOLID_NONE") or 0)

    local owner_ok, owner_result = safe_call(wearable, "SetOwner", body)
    if not call_succeeded(owner_ok, owner_result) then
        remove_entity(wearable)
        return nil, "set_owner_failed:" .. tostring(definition.id)
    end
    local follow_ok, follow_result = safe_call(wearable, "FollowEntity", body, true)
    if not call_succeeded(follow_ok, follow_result) then
        remove_entity(wearable)
        return nil, "follow_entity_failed:" .. tostring(definition.id)
    end

    print("[TA_PORTRAIT_PROBE_RUNTIME] ATTACHED component="
        .. tostring(definition.id) .. " entity=" .. tostring(entity_index(wearable))
        .. " owner_result=" .. tostring(owner_result)
        .. " follow_result=" .. tostring(follow_result))
    return wearable, "ok"
end

function TAPortraitProbe:InitializeRuntimeScene()
    if self.runtime_initialized and valid_entity(self.body) then
        print("[TA_PORTRAIT_PROBE_RUNTIME] DUPLICATE_INIT_IGNORED body="
            .. tostring(entity_index(self.body)))
        self:_PublishRuntimeState(true, "ready_visual_check_required", "duplicate_init")
        return true
    end
    if self.initialization_in_progress then
        print("[TA_PORTRAIT_PROBE_RUNTIME] DUPLICATE_INIT_IN_PROGRESS")
        return false
    end

    self.initialization_in_progress = true
    self:ClearRuntimeScene(nil)
    self:_RemoveStaleNamedEntities()

    local body, body_reason = self:_SpawnBody()
    if not body then
        return self:_FailInitialization("body_spawn_failed", body_reason)
    end
    self.body = body

    local animation_ok, animation_result = apply_body_animation(
        body,
        config.body.sequence
    )
    if not animation_ok then
        return self:_FailInitialization("body_animation_failed", animation_result)
    end
    print("[TA_PORTRAIT_PROBE_RUNTIME] BODY_ANIMATION_APPLIED sequence="
        .. tostring(config.body.sequence) .. " index=" .. tostring(animation_result))

    for _, definition in ipairs(config.wearables or {}) do
        local wearable, wearable_reason = self:_SpawnWearable(body, definition)
        if not wearable then
            return self:_FailInitialization("wearable_attach_failed", wearable_reason)
        end
        self.wearables[#self.wearables + 1] = wearable
    end

    self.initialization_in_progress = false
    self.runtime_initialized = true
    self:_PublishRuntimeState(true, "ready_visual_check_required", "")
    print("[TA_PORTRAIT_PROBE_RUNTIME] READY body=" .. tostring(entity_index(body))
        .. " wearables=" .. tostring(#self.wearables)
        .. " visual_verdict=pending")
    return true
end

function TAPortraitProbe:OnGameRulesStateChange()
    if GameRules:State_Get() == DOTA_GAMERULES_STATE_POST_GAME then
        self:ClearRuntimeScene("post_game")
        self:_PublishRuntimeState(false, "cleaned_up", "post_game")
    end
end

function TAPortraitProbe:OnVisualResult(_source_index, payload)
    local result = tostring(payload and payload.result or "")
    if not VALID_VISUAL_RESULTS[result] then
        print("[TA_PORTRAIT_PROBE_VISUAL_VERDICT] REJECTED result=" .. result)
        return
    end
    local player_id = tonumber(payload and payload.PlayerID) or -1
    print("[TA_PORTRAIT_PROBE_VISUAL_VERDICT] result=" .. result
        .. " player=" .. tostring(player_id)
        .. " runtime_ready=" .. tostring(self.runtime_initialized == true))
end

function TAPortraitProbe:InitGameMode()
    if self.bootstrap_registered then
        print("[TA_PORTRAIT_PROBE_RUNTIME] DUPLICATE_BOOTSTRAP_IGNORED")
        return
    end
    self.bootstrap_registered = true
    self.wearables = {}

    ListenToGameEvent(
        "game_rules_state_change",
        Dynamic_Wrap(TAPortraitProbe, "OnGameRulesStateChange"),
        self
    )
    CustomGameEventManager:RegisterListener(
        "ta_portrait_probe_record_result",
        function(source_index, payload)
            self:OnVisualResult(source_index, payload)
        end
    )

    local game_mode = GameRules:GetGameModeEntity()
    game_mode:SetContextThink("ta_portrait_probe_runtime_initialize", function()
        self:InitializeRuntimeScene()
        return nil
    end, 0)
    print("[TA_PORTRAIT_PROBE] isolated runtime addon loaded")
end
