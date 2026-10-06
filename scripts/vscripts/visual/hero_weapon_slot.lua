local M = {}

local function live(entity)
    if entity == nil then return false end
    local ok, is_null = pcall(function() return entity:IsNull() end)
    return ok and not is_null
end

local function particle_id(value)
    return type(value) == "number" and value >= 0 and value < math.huge
        and value == math.floor(value)
end

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = deep_copy(child) end
    return result
end

local function encode(value, visiting)
    local kind = type(value)
    if kind == "nil" then return "n" end
    if kind == "string" then return "s" .. #value .. ":" .. value end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then
        assert(value == value and math.abs(value) < math.huge, "nonfinite appearance value")
        return "d" .. string.format("%.17g", value) .. ";"
    end
    assert(kind == "table", "unsupported appearance value: " .. kind)
    visiting = visiting or {}
    assert(not visiting[value], "cyclic appearance declaration")
    visiting[value] = true
    local entries = {}
    for key, child in pairs(value) do
        assert(type(key) == "string" or type(key) == "number", "unsupported appearance key")
        entries[#entries + 1] = encode(key, visiting) .. encode(child, visiting)
    end
    table.sort(entries)
    visiting[value] = nil
    return "t" .. #entries .. ":" .. table.concat(entries) .. ";"
end

-- A second boolean lets an adapter distinguish a replaced state from a new
-- Tools world. A single false is conservative: integer IDs may be reused.
local function guard(engine)
    local ok, is_current, same_world = pcall(engine.is_current)
    if not ok then return false, false end
    if same_world == nil then same_world = is_current == true end
    return is_current == true and same_world == true, same_world == true
end

local function cleanup(engine, particles, wearables)
    local errors, skipped = {}, 0
    local seen_particles, seen_entities = {}, {}
    for _, id in ipairs(particles) do
        if not seen_particles[id] then
            seen_particles[id] = true
            local _, same_world = guard(engine)
            if same_world then
                local ok, err = pcall(engine.destroy_particle, id)
                if not ok or err == false then
                    errors[#errors + 1] = "destroy_particle: " .. tostring(err)
                end
            else skipped = skipped + 1 end
        end
    end
    for _, entity in ipairs(wearables) do
        if not seen_entities[entity] then
            seen_entities[entity] = true
            local _, same_world = guard(engine)
            if same_world then
                local ok, err = pcall(engine.remove_entity, entity)
                if not ok or err == false then
                    errors[#errors + 1] = "remove_entity: " .. tostring(err)
                end
            else skipped = skipped + 1 end
        end
    end
    return { cleanup_errors = errors, cleanup_skipped_stale_world = skipped }
end

local function invoke(target, name, ...)
    local method = target and target[name]
    if type(method) ~= "function" then error("missing native method " .. name) end
    local ok, result = pcall(method, target, ...)
    if not ok or result == false then error(name .. ": " .. tostring(result)) end
    return result
end

local function attach_type(value)
    if value == nil then value = "PATTACH_ABSORIGIN_FOLLOW" end
    if type(value) == "string" then value = rawget(_G, value) end
    assert(particle_id(value), "invalid or missing particle attachment type")
    return value
end

local function world_token()
    local rules = rawget(_G, "GameRules")
    if rules and type(rules.GetGameModeEntity) == "function" then
        local ok, world = pcall(rules.GetGameModeEntity, rules)
        if ok and world ~= nil then return rules, world end
    end
    return rules, rules
end

local function remove_native(entity)
    local remove = rawget(_G, "UTIL_Remove")
    if type(remove) == "function" then
        local ok, result = pcall(remove, entity)
        if not ok or result == false then error("UTIL_Remove: " .. tostring(result)) end
    else invoke(entity, "RemoveSelf") end
end

-- The old cosmetic spawner ignored failed CP calls. Keep allocation ownership
-- here until every authored native CP and offset anchor is ready. Native
-- children load the audited snapshots; no external snapshot API is assumed.
function M.spawn_particle(hero, definition, components, is_current)
    if type(definition) ~= "table" or type(definition.path) ~= "string"
        or definition.path == "" then return nil, "particle_definition_required" end
    if definition.snapshot ~= nil and definition.snapshot ~= "" then
        return nil, "external_particle_snapshot_unsupported"
    end
    local owner = components and components[definition.owner]
    if not live(hero) or not live(owner) then return nil, "particle_owner_unavailable" end
    local manager = rawget(_G, "ParticleManager")
    if not manager then return nil, "particle_manager_unavailable" end
    for _, name in ipairs({ "CreateParticle", "DestroyParticle", "ReleaseParticleIndex" }) do
        if type(manager[name]) ~= "function" then return nil, "missing_native_method_" .. name end
    end
    local rules, world = world_token()
    local id, anchors = nil, {}
    local function same_world()
        local active_rules, active_world = world_token()
        if active_rules ~= rules or active_world ~= world then return false end
        if is_current ~= nil then
            if type(is_current) ~= "function" then return false end
            local _, active_world_ok = guard({ is_current = is_current })
            return active_world_ok
        end
        return true
    end
    local function active()
        if not same_world() then return false end
        if is_current ~= nil then return guard({ is_current = is_current }) end
        return true
    end
    local function operation(target, name, ...)
        assert(active(), "particle state changed before " .. name)
        local result = invoke(target, name, ...)
        assert(active(), "particle state changed during " .. name)
        return result
    end
    local function retire()
        -- A new Tools world may have reused the just-created integer handle.
        if not same_world() then return end
        if particle_id(id) then
            pcall(manager.DestroyParticle, manager, id, true)
            if same_world() then pcall(manager.ReleaseParticleIndex, manager, id) end
        end
        for _, anchor in ipairs(anchors) do
            if same_world() then pcall(remove_native, anchor) end
        end
    end
    local ok, err = pcall(function()
        assert(active(), "particle state unavailable before allocation")
        id = invoke(manager, "CreateParticle", definition.path, attach_type(definition.attach_type), owner)
        assert(particle_id(id), "particle allocation returned invalid ID")
        assert(active(), "particle state changed during allocation")
        local points = definition.control_points
        if points == nil then
            points = {}
            if definition.attachment_point and definition.attachment_point ~= "" then
                points[1] = { cp = 0, entity = "self", attach_type = "PATTACH_POINT_FOLLOW",
                    attachment = definition.attachment_point }
            end
        end
        assert(type(points) == "table", "invalid particle control points")
        for _, point in ipairs(points) do
            assert(type(point) == "table" and particle_id(point.cp), "invalid particle control point")
            local source = point.entity or "self"
            assert(source == "self" or source == "self_with_wearables" or source == "parent", "unknown particle CP entity")
            local target = source == "parent" and hero or owner
            assert(live(target), "particle CP entity unavailable")
            local attachment = point.attachment or ""
            assert(type(attachment) == "string", "invalid CP attachment")
            if attachment ~= "" then
                local attachment_id = operation(target, "ScriptLookupAttachment", attachment)
                assert(type(attachment_id) == "number" and attachment_id > 0, "particle attachment unavailable: " .. attachment)
            end
            local offset = point.offset
            if offset ~= nil then
                assert(type(offset) == "table" and #offset == 3, "invalid particle CP offset")
                for index = 1, 3 do
                    assert(type(offset[index]) == "number" and offset[index] == offset[index]
                        and math.abs(offset[index]) < math.huge, "invalid particle CP offset value")
                end
            end
            local attachment_type = attach_type(point.attach_type)
            if offset and (offset[1] ~= 0 or offset[2] ~= 0 or offset[3] ~= 0) then
                -- SetParticleControlEnt's origin is only a fallback, not an
                -- authored offset. A hidden native child preserves bone space.
                local model = operation(target, "GetModelName")
                assert(type(model) == "string" and model ~= "", "offset parent model unavailable")
                local spawn, vector = rawget(_G, "SpawnEntityFromTableSynchronous"), rawget(_G, "Vector")
                assert(type(spawn) == "function" and type(vector) == "function", "offset anchor APIs unavailable")
                assert(active(), "particle state changed before offset anchor allocation")
                local spawned, anchor = pcall(spawn, "prop_dynamic", { model = model })
                if spawned and anchor ~= nil then anchors[#anchors + 1] = anchor end
                assert(spawned and live(anchor), "offset anchor allocation failed")
                assert(active(), "particle state changed during offset anchor allocation")
                operation(anchor, "SetOwner", hero)
                operation(anchor, "SetParent", target, attachment)
                operation(anchor, "SetLocalOrigin", vector(offset[1], offset[2], offset[3]))
                operation(anchor, "AddNoDraw")
                target, attachment, attachment_type = anchor, "", attach_type("PATTACH_ABSORIGIN_FOLLOW")
            end
            local origin = operation(target, "GetAbsOrigin")
            assert(origin ~= nil, "particle CP origin unavailable")
            operation(manager, "SetParticleControlEnt", id, point.cp, target,
                attachment_type, attachment, origin, true)
        end
    end)
    if not ok then retire(); return nil, tostring(err) end
    return id, anchors
end

function M.snapshot(current, component_id)
    if type(current) ~= "table" then return nil end
    local component = current.components and current.components[component_id]
    local slot = current.weapon_slots and current.weapon_slots[component_id]
    local count = 0
    for _, definition in ipairs(current.particle_definitions or {}) do
        if definition.owner == component_id then count = count + 1 end
    end
    local anchors_live = true
    for _, anchor in ipairs(slot and slot.anchors or {}) do
        if not live(anchor) then anchors_live = false end
    end
    return {
        token = current, generation = current.generation,
        component_id = component_id, wearable = component, live = live(component),
        signature = slot and slot.signature or nil, key = slot and slot.key or nil,
        particle_count = count, expected_particles = slot and slot.particle_count or nil,
        anchor_count = slot and #(slot.anchors or {}) or 0, anchors_live = anchors_live,
        complete = slot ~= nil and slot.wearable == component and live(component)
            and anchors_live and count == slot.particle_count,
        busy = current.weapon_slot_transaction ~= nil,
    }
end

function M.apply(hero, current, appearance, engine)
    if type(engine) ~= "table" then return false, "engine_required" end
    for _, name in ipairs({ "spawn_wearable", "spawn_particle", "destroy_particle", "remove_entity", "is_current" }) do
        if type(engine[name]) ~= "function" then return false, "engine_missing_" .. name end
    end
    if type(current) ~= "table" or not live(hero) or current.hero ~= hero then
        return false, "hero_state_mismatch"
    end
    if not guard(engine) then return false, "stale_state" end
    if current.weapon_slot_transaction then return false, "slot_busy" end
    if type(appearance) ~= "table" or type(appearance.component_id) ~= "string"
        or appearance.component_id == "" or type(appearance.model) ~= "string"
        or appearance.model == "" then return false, "invalid_appearance" end
    if type(current.components) ~= "table" or type(current.wearables) ~= "table"
        or type(current.particles) ~= "table" or type(current.particle_definitions) ~= "table"
        or #current.particles ~= #current.particle_definitions then
        return false, "component_metadata_required"
    end
    if appearance.particles ~= nil and type(appearance.particles) ~= "table" then
        return false, "invalid_particle_definitions"
    end

    local component_id = appearance.component_id
    local desired = copy(appearance)
    desired.entity_class = desired.entity_class or "prop_dynamic"
    local definition_ok, definitions = pcall(function()
        for _, definition in ipairs(appearance.particles or {}) do
            assert(type(definition) == "table" and definition.owner == component_id,
                "particle owner must equal weapon component")
            assert(type(definition.path) == "string" and definition.path ~= "", "particle path required")
        end
        -- Validate cycles before copying declarations for immutable registration.
        encode(appearance.particles or {})
        return deep_copy(appearance.particles or {})
    end)
    if not definition_ok then return false, "invalid_particle_definitions: " .. tostring(definitions) end
    desired.particles = definitions
    local signature_ok, signature = pcall(encode, {
        key = desired.key, component_id = component_id, model = desired.model,
        entity_class = desired.entity_class, skin = desired.skin,
        material_group = desired.material_group, particles = definitions,
    })
    if not signature_ok then return false, "invalid_signature: " .. tostring(signature) end

    local original_components, original_wearables = current.components, current.wearables
    local original_particles, original_definitions = current.particles, current.particle_definitions
    local generation, old_weapon = current.generation, original_components[component_id]
    local previous = current.weapon_slots and current.weapon_slots[component_id]
    local old_anchors = previous and previous.anchors or {}
    local retired_entities = {}
    if old_weapon ~= nil then retired_entities[old_weapon] = true end
    for _, anchor in ipairs(old_anchors) do retired_entities[anchor] = true end
    local retained_particles, retained_definitions, old_particles = {}, {}, {}
    local existing_particle_ids, retired_particle_ids = {}, {}
    for index, id in ipairs(original_particles) do
        if not particle_id(id) or type(original_definitions[index]) ~= "table" then
            return false, "invalid_particle_metadata"
        end
        existing_particle_ids[id] = true
        if original_definitions[index].owner == component_id then
            old_particles[#old_particles + 1] = id
            retired_particle_ids[id] = true
        else
            retained_particles[#retained_particles + 1] = id
            retained_definitions[#retained_definitions + 1] = original_definitions[index]
        end
    end
    for _, id in ipairs(retained_particles) do
        if retired_particle_ids[id] then return false, "shared_particle_metadata" end
    end
    for _, id in ipairs(current.spawn_particles or {}) do
        existing_particle_ids[id] = true
        if retired_particle_ids[id] then return false, "shared_spawn_particle_metadata" end
    end
    for id, entity in pairs(original_components) do
        if id ~= component_id and retired_entities[entity] then return false, "shared_component_entity" end
    end
    local previous_anchors_live = true
    for _, anchor in ipairs(old_anchors) do
        if not live(anchor) then previous_anchors_live = false end
    end
    if previous and previous.signature == signature and previous.wearable == old_weapon
        and live(old_weapon) and previous_anchors_live and #old_particles == #definitions then
        if not guard(engine) then return false, "stale_state" end
        return true, "unchanged"
    end

    local token, pending_particles, pending_wearables, pending_anchors = {}, {}, {}, {}
    current.weapon_slot_transaction = token
    local function unlock()
        if current.weapon_slot_transaction == token then current.weapon_slot_transaction = nil end
    end
    local function active()
        return guard(engine) and current.hero == hero and current.generation == generation
            and current.weapon_slot_transaction == token
            and current.components == original_components and current.wearables == original_wearables
            and current.particles == original_particles and current.particle_definitions == original_definitions
    end
    local function abort(reason)
        local details = cleanup(engine, pending_particles, pending_wearables)
        unlock()
        return false, reason, details
    end

    local spawned_ok, new_weapon = pcall(engine.spawn_wearable, hero, component_id, desired.model, desired)
    if not spawned_ok then return abort("wearable_spawn_failed: " .. tostring(new_weapon)) end
    if new_weapon == nil then return abort("wearable_spawn_failed") end
    -- A broken adapter must not let rollback remove an already owned body part.
    for _, entity in pairs(original_components) do
        if entity == new_weapon then return abort("wearable_spawn_reused_owned_entity") end
    end
    for _, entity in ipairs(original_wearables) do
        if entity == new_weapon then return abort("wearable_spawn_reused_owned_entity") end
    end
    pending_wearables[1] = new_weapon
    if not live(new_weapon) then return abort("wearable_spawn_invalid") end
    if not active() then return abort("stale_state") end
    local temporary_components = copy(original_components)
    temporary_components[component_id] = new_weapon
    local pending_entities = { [new_weapon] = true }
    for _, definition in ipairs(definitions) do
        local ok, id, anchors = pcall(engine.spawn_particle, hero, definition, temporary_components)
        if not ok then return abort("particle_spawn_failed: " .. tostring(id)) end
        if not particle_id(id) then return abort("particle_spawn_invalid: " .. tostring(anchors)) end
        if existing_particle_ids[id] then return abort("particle_spawn_reused_owned_id") end
        existing_particle_ids[id] = true
        pending_particles[#pending_particles + 1] = id
        if anchors ~= nil and type(anchors) ~= "table" then return abort("particle_anchor_metadata_invalid") end
        local anchor_error
        for _, anchor in ipairs(anchors or {}) do
            local already_owned = anchor == new_weapon
            for _, entity in ipairs(original_wearables) do
                if anchor == entity then already_owned = true end
            end
            for _, entity in pairs(original_components) do
                if anchor == entity then already_owned = true end
            end
            if already_owned or pending_entities[anchor] then
                anchor_error = anchor_error or "particle_anchor_reused_owned_entity"
            else
                pending_entities[anchor] = true
                pending_anchors[#pending_anchors + 1] = anchor
                table.insert(pending_wearables, #pending_wearables, anchor)
                if not live(anchor) then anchor_error = anchor_error or "particle_anchor_invalid" end
            end
        end
        if anchor_error then return abort(anchor_error) end
        if not active() then return abort("stale_state") end
    end
    if not active() then return abort("stale_state") end

    local next_wearables, inserted = {}, false
    local function insert_slot()
        for _, anchor in ipairs(pending_anchors) do next_wearables[#next_wearables + 1] = anchor end
        next_wearables[#next_wearables + 1] = new_weapon
        inserted = true
    end
    for _, entity in ipairs(original_wearables) do
        if retired_entities[entity] then
            if not inserted then insert_slot() end
        else next_wearables[#next_wearables + 1] = entity end
    end
    if not inserted then insert_slot() end
    for index, id in ipairs(pending_particles) do
        retained_particles[#retained_particles + 1] = id
        retained_definitions[#retained_definitions + 1] = definitions[index]
    end
    local next_slots = copy(current.weapon_slots)
    next_slots[component_id] = {
        signature = signature, key = desired.key, wearable = new_weapon,
        particle_count = #definitions, model = desired.model, anchors = pending_anchors,
    }
    -- No engine call occurs between revoking the old slot and publishing every
    -- new owner. Native cleanup callbacks only observe the committed registry.
    current.components, current.wearables = temporary_components, next_wearables
    current.particles, current.particle_definitions = retained_particles, retained_definitions
    current.weapon_slots = next_slots
    pending_particles, pending_wearables = {}, {}
    local retired_wearables = {}
    for _, anchor in ipairs(old_anchors) do retired_wearables[#retired_wearables + 1] = anchor end
    if old_weapon ~= nil then retired_wearables[#retired_wearables + 1] = old_weapon end
    local details = cleanup(engine, old_particles, retired_wearables)
    unlock()
    return true, "applied", details
end

function M.clear(hero, current, component_id, engine)
    if type(engine) ~= "table" or type(engine.is_current) ~= "function"
        or type(engine.destroy_particle) ~= "function" or type(engine.remove_entity) ~= "function" then
        return false, "cleanup_engine_required"
    end
    if type(current) ~= "table" or current.hero ~= hero then return false, "hero_state_mismatch" end
    if not guard(engine) then return false, "stale_state" end
    if current.weapon_slot_transaction then return false, "slot_busy" end
    if type(component_id) ~= "string" or component_id == "" then return false, "component_required" end
    if type(current.components) ~= "table" or type(current.wearables) ~= "table"
        or type(current.particles) ~= "table" or type(current.particle_definitions) ~= "table"
        or #current.particles ~= #current.particle_definitions then return false, "component_metadata_required" end
    local weapon = current.components[component_id]
    local slot = current.weapon_slots and current.weapon_slots[component_id]
    local retired_entities, retired_wearables = {}, {}
    for _, anchor in ipairs(slot and slot.anchors or {}) do
        retired_entities[anchor] = true
        retired_wearables[#retired_wearables + 1] = anchor
    end
    if weapon ~= nil then retired_entities[weapon] = true; retired_wearables[#retired_wearables + 1] = weapon end
    for id, entity in pairs(current.components) do
        if id ~= component_id and retired_entities[entity] then return false, "shared_component_entity" end
    end
    local retained_particles, retained_definitions, retired_particles, retired_ids = {}, {}, {}, {}
    for index, id in ipairs(current.particles) do
        local definition = current.particle_definitions[index]
        if not particle_id(id) or type(definition) ~= "table" then return false, "invalid_particle_metadata" end
        if definition.owner == component_id then
            retired_particles[#retired_particles + 1] = id; retired_ids[id] = true
        else
            retained_particles[#retained_particles + 1] = id
            retained_definitions[#retained_definitions + 1] = definition
        end
    end
    for _, id in ipairs(retained_particles) do
        if retired_ids[id] then return false, "shared_particle_metadata" end
    end
    for _, id in ipairs(current.spawn_particles or {}) do
        if retired_ids[id] then return false, "shared_spawn_particle_metadata" end
    end
    if weapon == nil and slot == nil and #retired_particles == 0 then return true, "unchanged" end
    local retained_wearables = {}
    for _, entity in ipairs(current.wearables) do
        if not retired_entities[entity] then retained_wearables[#retained_wearables + 1] = entity end
    end
    local token, next_components, next_slots = {}, copy(current.components), copy(current.weapon_slots)
    current.weapon_slot_transaction = token
    next_components[component_id], next_slots[component_id] = nil, nil
    current.components, current.wearables = next_components, retained_wearables
    current.particles, current.particle_definitions = retained_particles, retained_definitions
    current.weapon_slots = next_slots
    local details = cleanup(engine, retired_particles, retired_wearables)
    if current.weapon_slot_transaction == token then current.weapon_slot_transaction = nil end
    return true, "cleared", details
end

return M
