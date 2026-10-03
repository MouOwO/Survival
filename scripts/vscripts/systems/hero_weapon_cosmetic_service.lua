local bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local cosmetics = require("config/generated/hero_weapon_cosmetics")
local effects = require("config/generated/hero_weapon_cosmetic_effects")
local control_points = require("config/generated/hero_weapon_cosmetic_control_points")

local M = {}
local states, appearances = {}, {}
local resetting = false

local function player_id(value)
    local id = tonumber(value)
    if id and id >= 0 and id < math.huge and id == math.floor(id) then return id end
end

local function valid(unit)
    return unit and not unit:IsNull()
end

local function owner_matches(unit, id)
    if not valid(unit) then return false end
    local owner = tonumber(unit.survival_player_id)
    if owner == nil and unit.GetPlayerOwnerID then owner = tonumber(unit:GetPlayerOwnerID()) end
    return owner == id
end

local function state(id)
    if not states[id] then states[id] = { content_id = "" } end
    return states[id]
end

local function cosmetic_service()
    return require("systems/hero_cosmetic_service")
end

local function hero_identity(payload)
    local id = payload.unit.survival_hero_id or payload.hero_id
    if id and appearances[tostring(id) .. ":default"] then return tostring(id) end
    if type(payload.unit.GetUnitName) == "function" then
        local name = payload.unit:GetUnitName()
        if name == "npc_dota_hero_monkey_king" then return "hero_monkey_king" end
        if name == "npc_dota_hero_juggernaut" then return "hero_blademaster" end
    end
end

local function desired(current)
    local weapon = weapons.by_id[current.content_id]
    local series = weapon and weapon.equipment_slot == "main_hand" and weapon.series_id
    if series == "growth_sword" then series = "default" end
    return appearances[tostring(current.hero_id) .. ":" .. tostring(series)]
        or appearances[tostring(current.hero_id) .. ":default"]
end

local function sync_equipment(current, id)
    local result = bus.request(events.WEAPON_EQUIPMENT_GET_REQUEST, { player_id = id })
    if result and result.ok ~= false and result.snapshot then
        current.content_id = tostring(result.snapshot.main_hand_content_id or "")
    end
end

local function clear_slot(current)
    local hero, appearance = current.hero, current.appearance
    local token = current.slot_token
    current.hero, current.appearance, current.slot_token = nil, nil, nil
    if hero and appearance then
        cosmetic_service().clear_weapon(hero, appearance.component_id, token)
    end
end

local function reconcile(current)
    if resetting or current.unavailable or not valid(current.hero) then return end
    -- Normal death preserves the weapon, just like the other skin components.
    if not current.hero:IsAlive() then return end
    local loaded, model = pcall(current.hero.GetModelName, current.hero)
    if not loaded or type(model) ~= "string" or model == "" then return end
    local appearance = desired(current)
    if not appearance then return end
    local service = cosmetic_service()
    local slot = service.weapon_snapshot(current.hero, appearance.component_id)
    if current.appearance == appearance and slot and slot.complete
        and slot.key == appearance.key and slot.token == current.slot_token then return end
    local hero = current.hero
    local ok, applied, reason = pcall(service.apply_weapon, hero, appearance)
    if current.unavailable or current.hero ~= hero then
        -- A defeat/replacement callback can arrive while the slot transaction
        -- owns its lock. Retire its committed result once the call unlocks.
        service.clear_weapon(hero, appearance.component_id, slot and slot.token)
        return
    end
    if ok and applied then
        current.appearance, current.error = appearance, nil
        slot = service.weapon_snapshot(current.hero, appearance.component_id)
        current.slot_token = slot and slot.token
    else
        current.error = tostring(ok and reason or applied)
    end
end

function M.on_equipped(payload)
    local id = player_id(payload.player_id)
    if not id or payload.slot ~= "main_hand" then return end
    local current = state(id)
    if current.unavailable then return end
    current.content_id = tostring(payload.content_id or "")
    reconcile(current)
end

function M.on_hero_summoned(payload)
    local id = player_id(payload.player_id)
    if not id or not owner_matches(payload.unit, id) then return end
    local current = state(id)
    if current.unavailable then return end
    if current.hero ~= payload.unit then clear_slot(current) end
    current.hero, current.hero_id = payload.unit, hero_identity(payload)
    sync_equipment(current, id)
    reconcile(current)
end

function M.on_unavailable(payload)
    local id = player_id(payload.player_id)
    if not id then return end
    local current = state(id)
    current.unavailable = true
    clear_slot(current)
end

function M.poll()
    for _, current in pairs(states) do reconcile(current) end
end

function M.precache(context)
    local seen = {}
    local function precache(kind, path)
        if path and path ~= "" and not seen[kind .. ":" .. path] then
            PrecacheResource(kind, path, context)
            seen[kind .. ":" .. path] = true
        end
    end
    for _, row in ipairs(cosmetics.rows) do
        if row.enabled ~= false then precache("model", row.model) end
    end
    for _, row in ipairs(effects.rows) do
        if row.enabled ~= false then precache("particle", row.path) end
    end
end

function M.reset(same_world)
    resetting = true
    if not same_world then states = {} end
    appearances = {}
    for _, row in ipairs(cosmetics.rows) do
        if row.enabled ~= false then
            local appearance = { key = row.cosmetic_id, hero_id = row.hero_id,
                series_id = row.series_id, component_id = row.component_id,
                item_def = row.item_def, display_name = row.display_name,
                model = row.model, entity_class = row.entity_class,
                skin = row.skin, material_group = row.material_group, particles = {} }
            for _, effect in ipairs(effects.rows) do
                if effect.enabled ~= false and effect.cosmetic_id == row.cosmetic_id then
                    local particle = { id = effect.effect_id, path = effect.path,
                        owner = row.component_id, attach_type = effect.attach_type,
                        control_points = {} }
                    for _, binding in ipairs(control_points.rows) do
                        if binding.enabled ~= false and binding.effect_id == effect.effect_id then
                            local offset
                            if binding.offset then
                                offset = {}
                                for index, value in ipairs(binding.offset) do
                                    -- CSV list values are strings; keep invalid
                                    -- values intact so the strict slot rejects them.
                                    offset[index] = tonumber(value) or value
                                end
                            end
                            particle.control_points[#particle.control_points + 1] = {
                                cp = binding.cp, entity = binding.entity,
                                attach_type = binding.attach_type,
                                attachment = binding.attachment, offset = offset }
                        end
                    end
                    appearance.particles[#appearance.particles + 1] = particle
                end
            end
            appearances[row.cosmetic_id] = appearance
        end
    end
    if same_world then
        for id, current in pairs(states) do
            if not current.unavailable then sync_equipment(current, id) end
        end
    end
    resetting = false
end

function M.debug_snapshot(id)
    local current = states[player_id(id)]
    if not current then return nil end
    local appearance = current.appearance
    local slot = valid(current.hero) and appearance
        and cosmetic_service().weapon_snapshot(current.hero, appearance.component_id)
    return { hero_id = current.hero_id, content_id = current.content_id,
        hero = valid(current.hero) and current.hero:entindex() or -1,
        cosmetic_id = appearance and appearance.key, series_id = appearance and appearance.series_id,
        item_def = appearance and appearance.item_def, model = appearance and appearance.model,
        skin = appearance and appearance.skin, material_group = appearance and appearance.material_group,
        unavailable = current.unavailable == true, error = current.error, slot = slot }
end

return M
