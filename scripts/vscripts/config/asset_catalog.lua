local generated = require("config/generated/asset_catalog")
local generated_activity_modifiers = require("config/generated/asset_activity_modifiers")
local generated_bodygroups = require("config/generated/asset_bodygroups")
local generated_components = require("config/generated/asset_components")
local generated_effects = require("config/generated/asset_effects")
local generated_sounds = require("config/generated/asset_sounds")
local tower_skills = require("config/generated/tower_skill_definitions")

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = clone(nested) end
    return result
end

local M = {
    rows = clone(generated.rows or {}),
    by_id = {},
    activity_modifiers = generated_activity_modifiers.rows or {},
    bodygroups = generated_bodygroups.rows or {},
    components = generated_components.rows or {},
    effects = generated_effects.rows or {},
    sounds = generated_sounds.rows or {},
    by_model = {},
    by_particle = {},
}

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

local function append_unique(list, seen, value)
    if not nonempty(value) or seen[value] then return end
    seen[value] = true
    list[#list + 1] = value
end

local function sorted_rows(rows, key_name)
    local result = {}
    for _, row in ipairs(rows or {}) do
        if row.enabled ~= false then result[#result + 1] = row end
    end
    table.sort(result, function(a, b)
        local a_order = tonumber(a.sort_order) or math.huge
        local b_order = tonumber(b.sort_order) or math.huge
        if a_order ~= b_order then return a_order < b_order end
        return tostring(a[key_name] or "") < tostring(b[key_name] or "")
    end)
    return result
end

local function require_asset(row, source_name, row_key)
    local asset_id = tostring(row.asset_id or "")
    local asset = M.by_id[asset_id]
    if not asset then
        error(string.format(
            "%s row %s references missing asset_id %s",
            source_name,
            tostring(row[row_key]),
            asset_id
        ))
    end
    return asset
end

local function assert_unique(seen, key, message)
    if seen[key] then error(message .. ": " .. tostring(key)) end
    seen[key] = true
end

local function initialize_bundle(asset)
    asset.activity_modifiers = {}
    asset.components = {}
    asset.bodygroups = {}
    asset.effects = {}
    asset.sounds = {}
    asset.effects_by_role = {}
    asset.sounds_by_role = {}
    asset.attack = {
        launch_effects = {},
        hit_effects = {},
        sounds = {},
    }
    asset.ambient = {
        effects = {},
        sounds = {},
    }
    asset.skills = {}

    asset.attachment_models = asset.attachment_models or {}
    asset.attachment_ids = asset.attachment_ids or {}
    asset.particle_resources = asset.particle_resources or {}
    asset.environment_particles = asset.environment_particles or {}
    asset.environment_particle_owners = asset.environment_particle_owners or {}
    asset.sound_resources = asset.sound_resources or {}
    asset.sound_events = asset.sound_events or {}
end

local seen_asset_ids = {}
for _, asset in ipairs(M.rows) do
    local asset_id = tostring(asset.asset_id or "")
    assert(nonempty(asset_id), "asset_catalog contains an empty asset_id")
    assert_unique(seen_asset_ids, asset_id, "asset_catalog duplicate asset_id")
    M.by_id[asset_id] = asset
    initialize_bundle(asset)
end

local seen_activity_modifier_keys = {}
local activity_modifier_names_by_asset = {}
for _, entry in ipairs(sorted_rows(M.activity_modifiers, "modifier_key")) do
    local asset = require_asset(
        entry,
        "asset_activity_modifiers",
        "modifier_key"
    )
    local modifier_key = tostring(entry.modifier_key or "")
    local modifier_name = tostring(entry.modifier_name or "")
    assert(nonempty(modifier_key),
        "asset_activity_modifiers contains an empty modifier_key")
    assert(nonempty(modifier_name),
        "asset_activity_modifiers contains an empty modifier_name: "
            .. modifier_key)
    assert_unique(seen_activity_modifier_keys, modifier_key,
        "asset_activity_modifiers duplicate modifier_key")
    activity_modifier_names_by_asset[asset.asset_id]
        = activity_modifier_names_by_asset[asset.asset_id] or {}
    assert_unique(
        activity_modifier_names_by_asset[asset.asset_id],
        modifier_name,
        "asset_activity_modifiers duplicate modifier_name for "
            .. asset.asset_id
    )
    asset.activity_modifiers[#asset.activity_modifiers + 1] = entry
end

local seen_bodygroup_keys = {}
local bodygroup_names_by_asset = {}
for _, bodygroup in ipairs(sorted_rows(M.bodygroups, "bodygroup_key")) do
    local asset = require_asset(bodygroup, "asset_bodygroups", "bodygroup_key")
    local bodygroup_key = tostring(bodygroup.bodygroup_key or "")
    local bodygroup_name = tostring(bodygroup.bodygroup_name or "")
    assert(nonempty(bodygroup_key),
        "asset_bodygroups contains an empty bodygroup_key")
    assert(nonempty(bodygroup_name),
        "asset_bodygroups contains an empty bodygroup_name: " .. bodygroup_key)
    assert_unique(seen_bodygroup_keys, bodygroup_key,
        "asset_bodygroups duplicate bodygroup_key")
    bodygroup_names_by_asset[asset.asset_id]
        = bodygroup_names_by_asset[asset.asset_id] or {}
    assert_unique(
        bodygroup_names_by_asset[asset.asset_id],
        bodygroup_name,
        "asset_bodygroups duplicate bodygroup_name for " .. asset.asset_id
    )
    asset.bodygroups[#asset.bodygroups + 1] = bodygroup
end

local components_by_asset = {}
local seen_component_keys = {}
local component_ids_by_asset = {}
for _, component in ipairs(sorted_rows(M.components, "component_key")) do
    local asset = require_asset(component, "asset_components", "component_key")
    local component_key = tostring(component.component_key or "")
    local component_id = tostring(component.component_id or "")
    assert(nonempty(component_key), "asset_components contains an empty component_key")
    assert(nonempty(component_id), "asset_components contains an empty component_id")
    assert(nonempty(component.model_path),
        "asset_components component has no model_path: " .. component_key)
    assert_unique(seen_component_keys, component_key,
        "asset_components duplicate component_key")
    component_ids_by_asset[asset.asset_id] = component_ids_by_asset[asset.asset_id] or {}
    assert_unique(
        component_ids_by_asset[asset.asset_id],
        component_id,
        "asset_components duplicate component_id for " .. asset.asset_id
    )
    components_by_asset[asset.asset_id] = components_by_asset[asset.asset_id] or {}
    components_by_asset[asset.asset_id][#components_by_asset[asset.asset_id] + 1]
        = component
end

for asset_id, components in pairs(components_by_asset) do
    local asset = M.by_id[asset_id]
    table.sort(components, function(a, b)
        local a_order = tonumber(a.sort_order) or math.huge
        local b_order = tonumber(b.sort_order) or math.huge
        if a_order ~= b_order then return a_order < b_order end
        return tostring(a.component_key) < tostring(b.component_key)
    end)
    local entity_class
    for _, component in ipairs(components) do
        local parent_id = tostring(component.parent_component_id or "")
        if nonempty(parent_id)
            and not component_ids_by_asset[asset_id][parent_id] then
            error("asset_components parent component missing: "
                .. asset_id .. ":" .. parent_id)
        end
        local current_class = tostring(component.entity_class or "prop_dynamic")
        if entity_class and entity_class ~= current_class then
            error("asset_components mixed entity_class cannot be projected by "
                .. "the current visual service: " .. asset_id)
        end
        entity_class = current_class
        asset.components[#asset.components + 1] = component
        asset.attachment_models[#asset.attachment_models + 1] = component.model_path
        asset.attachment_ids[#asset.attachment_ids + 1] = component.component_id
    end
    asset.attachment_entity_class = entity_class or asset.attachment_entity_class
end

local valid_skill_ids = {}
for _, skill in ipairs(tower_skills.rows or {}) do
    valid_skill_ids[tostring(skill.skill_id or "")] = true
end

local function skill_bundle(asset, skill_id)
    local bundle = asset.skills[skill_id]
    if bundle then return bundle end
    bundle = {
        skill_id = skill_id,
        effects = {},
        effects_by_role = {},
        sounds = {},
        sounds_by_role = {},
    }
    asset.skills[skill_id] = bundle
    return bundle
end

local seen_effect_keys = {}
local seen_effect_orders = {}
local default_projectiles = {}
for _, effect in ipairs(sorted_rows(M.effects, "effect_key")) do
    local asset = require_asset(effect, "asset_effects", "effect_key")
    local effect_key = tostring(effect.effect_key or "")
    local effect_role = tostring(effect.effect_role or "")
    local skill_id = tostring(effect.skill_id or "")
    assert(nonempty(effect_key), "asset_effects contains an empty effect_key")
    assert(nonempty(effect.effect_id),
        "asset_effects effect has no effect_id: " .. effect_key)
    assert(nonempty(effect_role),
        "asset_effects effect has no effect_role: " .. effect_key)
    assert(nonempty(effect.particle_path),
        "asset_effects effect has no particle_path: " .. effect_key)
    assert_unique(seen_effect_keys, effect_key, "asset_effects duplicate effect_key")
    local order_key = table.concat({
        tostring(effect.asset_id),
        tostring(effect.effect_group_id or ""),
        tostring(effect.sort_order or ""),
    }, ":")
    assert_unique(seen_effect_orders, order_key,
        "asset_effects duplicate sort_order inside effect group")
    local owner_id = tostring(effect.owner_component_id or "")
    if nonempty(owner_id)
        and not (component_ids_by_asset[asset.asset_id] or {})[owner_id] then
        error("asset_effects owner component missing: "
            .. asset.asset_id .. ":" .. owner_id)
    end
    if nonempty(skill_id) and not valid_skill_ids[skill_id] then
        error("asset_effects skill_id missing from tower_skill_definitions: "
            .. skill_id)
    end

    asset.effects[#asset.effects + 1] = effect
    asset.effects_by_role[effect_role] = asset.effects_by_role[effect_role] or {}
    asset.effects_by_role[effect_role][#asset.effects_by_role[effect_role] + 1]
        = effect
    if nonempty(skill_id) then
        local bundle = skill_bundle(asset, skill_id)
        bundle.effects[#bundle.effects + 1] = effect
        bundle.effects_by_role[effect_role] = bundle.effects_by_role[effect_role]
            or {}
        bundle.effects_by_role[effect_role][#bundle.effects_by_role[effect_role] + 1]
            = effect
    elseif effect_role == "attack_projectile" then
        default_projectiles[asset.asset_id] = (default_projectiles[asset.asset_id] or 0) + 1
        if default_projectiles[asset.asset_id] > 1 then
            error("asset_effects has multiple default attack projectiles: "
                .. asset.asset_id)
        end
        asset.attack.projectile = effect.particle_path
        asset.attack.projectile_effect = effect
    elseif effect_role == "attack_launch" then
        asset.attack.launch_effects[#asset.attack.launch_effects + 1] = effect
    elseif effect_role == "attack_hit" then
        asset.attack.hit_effects[#asset.attack.hit_effects + 1] = effect
    elseif effect_role == "ambient" then
        asset.ambient.effects[#asset.ambient.effects + 1] = effect
    end
end

local seen_sound_keys = {}
local seen_sound_orders = {}
for _, sound in ipairs(sorted_rows(M.sounds, "sound_key")) do
    local asset = require_asset(sound, "asset_sounds", "sound_key")
    local sound_key = tostring(sound.sound_key or "")
    local sound_role = tostring(sound.sound_role or "")
    local skill_id = tostring(sound.skill_id or "")
    assert(nonempty(sound_key), "asset_sounds contains an empty sound_key")
    assert(nonempty(sound.sound_id),
        "asset_sounds sound has no sound_id: " .. sound_key)
    assert(nonempty(sound_role),
        "asset_sounds sound has no sound_role: " .. sound_key)
    assert(nonempty(sound.sound_resource) or nonempty(sound.sound_event),
        "asset_sounds sound has neither resource nor event: " .. sound_key)
    assert_unique(seen_sound_keys, sound_key, "asset_sounds duplicate sound_key")
    local order_key = table.concat({
        tostring(sound.asset_id),
        tostring(sound.sound_group_id or ""),
        tostring(sound.sort_order or ""),
    }, ":")
    assert_unique(seen_sound_orders, order_key,
        "asset_sounds duplicate sort_order inside sound group")
    if nonempty(skill_id) and not valid_skill_ids[skill_id] then
        error("asset_sounds skill_id missing from tower_skill_definitions: "
            .. skill_id)
    end

    asset.sounds[#asset.sounds + 1] = sound
    asset.sounds_by_role[sound_role] = asset.sounds_by_role[sound_role] or {}
    asset.sounds_by_role[sound_role][#asset.sounds_by_role[sound_role] + 1]
        = sound
    if nonempty(skill_id) then
        local bundle = skill_bundle(asset, skill_id)
        bundle.sounds[#bundle.sounds + 1] = sound
        bundle.sounds_by_role[sound_role] = bundle.sounds_by_role[sound_role]
            or {}
        bundle.sounds_by_role[sound_role][#bundle.sounds_by_role[sound_role] + 1]
            = sound
    elseif string.match(sound_role, "^attack_") then
        asset.attack.sounds[#asset.attack.sounds + 1] = sound
    elseif sound_role == "ambient_loop" then
        asset.ambient.sounds[#asset.ambient.sounds + 1] = sound
    end
end

for _, asset in ipairs(M.rows) do
    local particle_seen = {}
    local sound_resource_seen = {}
    local sound_event_seen = {}
    for _, path in ipairs(asset.particle_resources) do particle_seen[path] = true end
    for _, path in ipairs(asset.sound_resources) do sound_resource_seen[path] = true end
    for _, event_name in ipairs(asset.sound_events) do sound_event_seen[event_name] = true end
    for _, effect in ipairs(asset.effects) do
        append_unique(asset.particle_resources, particle_seen, effect.particle_path)
        if effect.effect_role == "ambient" then
            asset.environment_particles[#asset.environment_particles + 1]
                = effect.particle_path
            asset.environment_particle_owners[#asset.environment_particle_owners + 1]
                = effect.owner_component_id or ""
        end
    end
    for _, sound in ipairs(asset.sounds) do
        append_unique(asset.sound_resources, sound_resource_seen, sound.sound_resource)
        append_unique(asset.sound_events, sound_event_seen, sound.sound_event)
    end
end

for _, row in ipairs(M.rows) do
    if nonempty(row.primary_model) and M.by_model[row.primary_model] == nil then
        M.by_model[row.primary_model] = row
    end
    for _, particle_path in ipairs(row.particle_resources or {}) do
        if M.by_particle[particle_path] == nil then
            M.by_particle[particle_path] = row
        end
    end
end

function M.get(asset_id)
    local row = M.by_id[tostring(asset_id or "")]
    if row and row.enabled ~= false then return row end
    return nil
end

function M.resolve(asset_id)
    local visited = {}
    local current_id = tostring(asset_id or "")
    while nonempty(current_id) and not visited[current_id] do
        visited[current_id] = true
        local row = M.by_id[current_id]
        if row and row.enabled ~= false and nonempty(row.primary_model) then
            return row
        end
        current_id = row and row.fallback_asset_id or ""
    end
    return nil
end

function M.resolve_bundle(asset_id)
    return M.resolve(asset_id)
end

function M.model(asset_id, fallback_path)
    local row = M.resolve(asset_id)
    if row and nonempty(row.primary_model) then return row.primary_model, row end
    return fallback_path, nil
end

function M.for_model(model_path)
    return M.by_model[tostring(model_path or "")]
end

function M.for_particle(particle_path)
    return M.by_particle[tostring(particle_path or "")]
end

function M.group(load_group)
    local result = {}
    for _, row in ipairs(M.rows) do
        if row.enabled ~= false and row.load_group == load_group then
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        local a_order = tonumber(a.load_order) or math.huge
        local b_order = tonumber(b.load_order) or math.huge
        if a_order ~= b_order then return a_order < b_order end
        local a_priority = tonumber(a.priority) or 0
        local b_priority = tonumber(b.priority) or 0
        if a_priority ~= b_priority then return a_priority > b_priority end
        return tostring(a.asset_id) < tostring(b.asset_id)
    end)
    return result
end

return M