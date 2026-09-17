package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local assets = {
    wall_ready = {
        asset_id = "wall_ready",
        primary_model = "models/test/wall_ready.vmdl",
        environment_particles = { "particles/test/wall_ready.vpcf" },
        environment_particle_owners = { "armor" },
        attachment_entity_class = "prop_dynamic",
        model_scale = 0.8,
        model_yaw = 180,
        model_skin = 1,
        bodygroups = {
            { bodygroup_name = "rocks", value = 1 },
        },
        activity_modifiers = {
            { modifier_name = "less_brow" },
        },
    },
    wall_next = {
        asset_id = "wall_next",
        primary_model = "models/test/wall_next.vmdl",
        environment_particles = { "particles/test/wall_next.vpcf" },
        model_scale = 0.9,
    },
    wall_failed = {
        asset_id = "wall_failed",
        primary_model = "models/test/wall_failed.vmdl",
        environment_particles = { "particles/test/wall_failed.vpcf" },
        model_scale = 1,
    },
    tower_path = {
        asset_id = "tower_path",
        primary_model = "models/test/tower_path.vmdl",
        model_scale = 1,
        activity_modifiers = {
            { modifier_name = "abysm" },
        },
    },
    tower_death_templar_assassin = {
        asset_id = "tower_death_templar_assassin",
        primary_model = "models/heroes/lanaya/lanaya.vmdl",
        attachment_models = {},
        components = {
            {
                component_id = "death_templar_assassin_armor",
                model_path = "models/items/lanaya/templar_assasin_false_devotion_armor/templar_assasin_false_devotion_armor.vmdl",
                entity_class = "prop_dynamic",
            },
            {
                component_id = "death_templar_assassin_head",
                model_path = "models/items/lanaya/templar_assasin_false_devotion_head/templar_assasin_false_devotion_head.vmdl",
                entity_class = "prop_dynamic",
            },
            {
                component_id = "death_templar_assassin_shoulder",
                model_path = "models/items/lanaya/templar_assasin_false_devotion_shoulder/templar_assasin_false_devotion_shoulder.vmdl",
                entity_class = "prop_dynamic",
            },
            {
                component_id = "death_templar_assassin_weapon",
                model_path = "models/items/lanaya/templar_assasin_false_devotion_weapon/templar_assasin_false_devotion_weapon.vmdl",
                entity_class = "prop_dynamic",
            },
        },
        model_scale = 1,
    },
    test_component_bundle = {
        asset_id = "test_component_bundle",
        primary_model = "models/test/component_bundle.vmdl",
        default_sequence = "idle",
        attachment_entity_class = "prop_dynamic",
        attachment_ids = { "back", "head", "arms", "shoulder", "weapon" },
        attachment_models = {
            "models/test/component_back.vmdl",
            "models/test/component_head.vmdl",
            "models/test/component_arms.vmdl",
            "models/test/component_shoulder.vmdl",
            "models/test/component_weapon.vmdl",
        },
        model_scale = 1,
    },
}

local preload_states = {
    wall_ready = "ready",
    wall_next = "loading",
    wall_failed = "loading",
    tower_path = "loading",
    tower_death_templar_assassin = "ready",
    test_component_bundle = "ready",
}
local callbacks = {}

package.loaded["config/asset_catalog"] = {
    model = function(asset_id, fallback_path)
        local asset = assets[asset_id]
        return asset and asset.primary_model or fallback_path, asset
    end,
    resolve = function(asset_id) return assets[asset_id] end,
    for_model = function(model_path)
        for _, asset in pairs(assets) do
            if asset.primary_model == model_path then return asset end
        end
        return nil
    end,
}
package.loaded["systems/asset_preload_service"] = {
    STATE = {
        FAILED = "failed",
        RETIRED = "retired",
    },
    is_ready = function(asset_id) return preload_states[asset_id] == "ready" end,
    status = function(asset_id)
        return { status = preload_states[asset_id] or "not_requested" }
    end,
    queue = function(asset_id, options)
        callbacks[asset_id] = options
        return true, preload_states[asset_id]
    end,
}
local info_logs = {}
local warning_logs = {}
package.loaded["core/logger"] = {
    info = function(scope, message)
        info_logs[#info_logs + 1] = scope .. ":" .. message
    end,
    warn = function(scope, message)
        warning_logs[#warning_logs + 1] = scope .. ":" .. message
    end,
}

local created_particles = {}
local created_particle_owners = {}
local destroyed_particles = {}
local spawned_attachments = {}
local spawned_attachment_classes = {}
local spawned_attachment_data = {}
local fail_wearable_spawn = false
local fail_attachment_model = nil
SpawnEntityFromTableSynchronous = function(entity_class, data)
    spawned_attachment_classes[#spawned_attachment_classes + 1] = entity_class
    spawned_attachment_data[#spawned_attachment_data + 1] = data
    if entity_class == "dota_item_wearable" and fail_wearable_spawn then
        error("simulated unsupported wearable entity")
    end
    if data.model == fail_attachment_model then
        error("simulated attachment resource failure")
    end
    local attachment = { model = data.model, entity_class = entity_class }
    function attachment:IsNull() return false end
    function attachment:SetOwner(owner) self.owner = owner end
    function attachment:FollowEntity(owner, bone_merge)
        self.following = owner
        self.bone_merge = bone_merge
    end
    function attachment:SetSkin(skin) self.skin = skin end
    function attachment:SetSolid(solid) self.solid = solid end
    spawned_attachments[#spawned_attachments + 1] = attachment
    return attachment
end
UTIL_Remove = function(attachment) attachment.removed = true end
assets.wall_ready.attachment_models = { "models/test/wall_ready_attachment.vmdl" }
assets.wall_ready.attachment_ids = { "armor" }
ParticleManager = {
    CreateParticle = function(_, path, _, owner)
        local id = #created_particles + 1
        created_particles[id] = path
        created_particle_owners[id] = owner
        return id
    end,
    DestroyParticle = function(_, id) destroyed_particles[id] = true end,
    ReleaseParticleIndex = function() end,
}
PATTACH_ABSORIGIN_FOLLOW = 1

local unit = {
    model = "models/test/original.vmdl",
    original_model = "models/test/original.vmdl",
    scale = 1,
    skin = 0,
    survival_model_asset_id = "wall_original",
}
function unit:IsNull() return false end
function unit:entindex() return 77 end
function unit:SetModel(path) self.model = path end
function unit:SetOriginalModel(path) self.original_model = path end
function unit:SetModelScale(scale) self.scale = scale end
function unit:SetAngles(pitch, yaw, roll)
    self.angles = { pitch = pitch, yaw = yaw, roll = roll }
    self.angle_updates = (self.angle_updates or 0) + 1
end
function unit:SetSkin(skin) self.skin = skin end
function unit:SetRenderAlpha(alpha) self.render_alpha = alpha end
function unit:RemoveNoDraw() self.no_draw_removed = true end
function unit:ResetSequenceInfo()
    self.sequence_info_resets = (self.sequence_info_resets or 0) + 1
end
function unit:ResetSequence(sequence) self.sequence = sequence end
function unit:SetPlaybackRate(rate) self.playback_rate = rate end
function unit:SetBodygroupByName(name, value)
    self.bodygroups = self.bodygroups or {}
    self.bodygroups[name] = value
end
function unit:AddActivityModifier(modifier_name)
    self.activity_modifiers = self.activity_modifiers or {}
    self.activity_modifiers[#self.activity_modifiers + 1] = modifier_name
end
function unit:ClearActivityModifiers()
    self.activity_modifier_clears = (self.activity_modifier_clears or 0) + 1
    self.activity_modifiers = {}
end

package.loaded["systems/building_visual_service"] = nil
local visual = require("systems/building_visual_service")

local ok, status = visual.apply(unit, { model_asset_id = "wall_ready" })
assert(ok and status == "wall_ready", "ready wall model was not applied")
assert(unit.model == assets.wall_ready.primary_model, "ready wall model path mismatch")
assert(unit.scale == 0.8, "ready wall model scale mismatch")
assert(unit.angles and unit.angles.pitch == 0 and unit.angles.yaw == 180
        and unit.angles.roll == 0,
    "ready wall model yaw mismatch")
assert(unit.skin == 1, "ready wall model skin mismatch")
assert(unit.sequence_info_resets == 1 and unit.sequence == "idle"
        and unit.playback_rate == 1,
    "main-model animation state was not reset to the configured idle sequence")
assert(spawned_attachments[1] and spawned_attachments[1].skin == 1,
    "ready wall attachment skin mismatch")
assert(spawned_attachment_classes[1] == "prop_dynamic",
    "configured prop_dynamic attachment class was not used")
assert(spawned_attachment_data[1].solid == "0"
        and spawned_attachment_data[1].spawnflags == "256"
        and spawned_attachment_data[1].DisableBoneFollowers == "1",
    "cosmetic attachment did not start collision-free or disable bone followers")
assert(spawned_attachments[1].solid == 0,
    "cosmetic attachment did not enforce SOLID_NONE after spawning")
assert(spawned_attachments[1].following == unit
        and spawned_attachments[1].bone_merge == true,
    "attachment did not use bone-merged unit following")
assert(created_particles[1] == assets.wall_ready.environment_particles[1],
    "ready wall ambient particle was not created")
assert(created_particle_owners[1] == spawned_attachments[1],
    "ready wall ambient particle did not attach to its named component")
assert(unit.bodygroups.rocks == 1,
    "configured main-model bodygroup was not applied")
assert(#unit.activity_modifiers == 1
        and unit.activity_modifiers[1] == "less_brow",
    "configured activity modifier was not applied")

local angle_updates = unit.angle_updates
ok, status = visual.apply(unit, {
    model_asset_id = "wall_ready",
    model_scale = 1.6,
    model_yaw = 180,
})
assert(ok and status == "wall_ready" and unit.scale == 1.6,
    "wall visual data did not override the asset model scale")
assert(unit.angles and unit.angles.yaw == 180
        and unit.angle_updates == angle_updates + 1,
    "reapplying wall yaw was not absolute and idempotent")
assert(unit.activity_modifier_clears == nil
        and #unit.activity_modifiers == 1
        and unit.activity_modifiers[1] == "less_brow",
    "reapplying activity modifiers was not idempotent")

assets.wall_ready.attachment_entity_class = "dota_item_wearable"
fail_wearable_spawn = true
ok, status = visual.apply(unit, { model_asset_id = "wall_ready" })
fail_wearable_spawn = false
assets.wall_ready.attachment_entity_class = "prop_dynamic"
assert(ok and status == "wall_ready",
    "unsupported wearable attachment did not use the safe fallback")
assert(spawned_attachment_classes[#spawned_attachment_classes - 1]
        == "dota_item_wearable"
        and spawned_attachment_classes[#spawned_attachment_classes]
        == "prop_dynamic",
    "wearable attachment failure did not fall back to prop_dynamic")

ok, status = visual.apply(unit, { model_asset_id = "wall_next" })
assert(ok and status == "loading", "loading wall model was not queued")
assert(unit.model == assets.wall_ready.primary_model,
    "loading wall replaced the current model before it was ready")
assert(unit.survival_pending_model_asset_id == "wall_next",
    "loading wall did not record pending asset metadata")

preload_states.wall_next = "ready"
callbacks.wall_next.on_ready()
assert(unit.model == assets.wall_next.primary_model,
    "ready callback did not apply the queued wall model")
assert(#unit.activity_modifiers == 0,
    "switching bundles retained the previous activity modifier")
assert(unit.bodygroups.rocks == 0,
    "previous main-model bodygroup was not reset on model switch")
assert(unit.survival_model_asset_id == "wall_next",
    "ready callback did not commit the queued asset ID")
assert(destroyed_particles[1] == true,
    "wall model switch did not clear the previous ambient particle")

ok, status = visual.apply(unit, { model_asset_id = "wall_failed" })
assert(ok and status == "loading", "failing wall model was not queued")
callbacks.wall_failed.on_failed("test")
assert(unit.model == assets.wall_next.primary_model,
    "failed preload changed the currently rendered wall model")
assert(unit.survival_model_asset_id == "wall_next",
    "failed preload did not restore the previous wall asset ID")
assert(unit.survival_pending_model_asset_id == nil,
    "failed preload left stale pending metadata")

ok, status = visual.apply(unit, {
    model_name = assets.tower_path.primary_model,
})
assert(ok and status == "loading",
    "registered legacy model path was not queued through its asset ID")
assert(unit.model == assets.wall_next.primary_model,
    "registered model path changed the unit before its preload was ready")
assert(unit.survival_pending_model_asset_id == "tower_path",
    "registered model path did not retain its resolved pending asset ID")

preload_states.tower_path = "ready"
callbacks.tower_path.on_ready()
assert(unit.model == assets.tower_path.primary_model,
    "registered model path was not applied after its preload became ready")
assert(unit.survival_model_asset_id == "tower_path",
    "registered model path did not commit its resolved asset ID")
assert(#unit.activity_modifiers == 1
        and unit.activity_modifiers[1] == "abysm",
    "registered model path omitted its activity modifier")

visual.clear(unit)
assert(destroyed_particles[2] == true,
    "wall visual cleanup did not destroy the current ambient particle")
assert(#unit.activity_modifiers == 0,
    "wall visual cleanup did not clear its activity modifier")

local add_activity_modifier = unit.AddActivityModifier
local clear_activity_modifiers = unit.ClearActivityModifiers
unit.AddActivityModifier = nil
unit.ClearActivityModifiers = nil
ok, status = visual.apply(unit, { model_asset_id = "wall_ready" })
assert(ok and status == "wall_ready",
    "missing activity-modifier APIs prevented the visual bundle from applying")
unit.AddActivityModifier = add_activity_modifier
ok, status = visual.apply(unit, { model_asset_id = "wall_ready" })
assert(ok and status == "wall_ready" and #unit.activity_modifiers == 0,
    "partially available activity-modifier APIs did not use the safe fallback")
unit.AddActivityModifier = add_activity_modifier
unit.ClearActivityModifiers = clear_activity_modifiers

local attachment_start = #spawned_attachments
local attachment_call_start = #spawned_attachment_data
local sequence_resets_before_native_tower = unit.sequence_info_resets
unit.survival_native_wearable_hide_mode = "render_alpha"
unit.survival_native_wearable_original_alpha = 211
unit.render_alpha = 0
ok, status = visual.apply(unit, {
    model_asset_id = "tower_death_templar_assassin",
})
assert(ok and status == "tower_death_templar_assassin",
    "Death Tower visual bundle was not applied")
assert(unit.model == "models/heroes/lanaya/lanaya.vmdl",
    "Death Tower did not apply the Templar Assassin body model")
assert(unit.sequence_info_resets == sequence_resets_before_native_tower + 1
        and unit.sequence == "idle"
        and unit.playback_rate == 1,
    "hero tower body did not reset to its configured idle sequence")
assert(#spawned_attachments == attachment_start + 4
        and #spawned_attachment_data == attachment_call_start + 4,
    "Death Tower did not attach all four Darkblade Adept components")
for index = attachment_start + 1, attachment_start + 4 do
    assert(spawned_attachments[index].entity_class == "prop_dynamic"
            and spawned_attachments[index].owner == unit
            and spawned_attachments[index].following == unit
            and spawned_attachments[index].bone_merge == true,
        "Death Tower component does not follow the original Building")
end
assert(unit.render_alpha == 211
        and unit.survival_native_wearable_hide_mode == nil,
    "original Building visibility was not restored from carrier state")

Convars = {
    GetBool = function(_, name)
        return name == "survival_model_appearance_debug"
    end,
}
local component_start = #spawned_attachments
for refresh = 1, 10 do
    ok, status = visual.apply(unit, {
        model_asset_id = "test_component_bundle",
    })
    assert(ok and status == "test_component_bundle",
        "component appearance refresh failed at iteration " .. refresh)
    local live = 0
    for index = component_start + 1, #spawned_attachments do
        if not spawned_attachments[index].removed then live = live + 1 end
    end
    assert(live == 5,
        "component appearance refresh left duplicate wearables at iteration "
            .. refresh .. ": " .. live)
end
assert(info_logs[#info_logs]
        and info_logs[#info_logs]:find("Appearance:unit=unknown", 1, true)
        and info_logs[#info_logs]:find(
            "appearance=test_component_bundle", 1, true)
        and info_logs[#info_logs]:find("wearables=5 status=ok", 1, true),
    "controlled appearance success log was not emitted")

local original_weapon_model = assets.test_component_bundle.attachment_models[5]
assets.test_component_bundle.attachment_models[5]
    = "models/test/component_weapon_failed.vmdl"
fail_attachment_model = assets.test_component_bundle.attachment_models[5]
ok, status = visual.apply(unit, {
    model_asset_id = "test_component_bundle",
})
assert(not ok and status == "attachment_failed:weapon",
    "partial component appearance did not return the failed slot")
local live_after_failure = 0
for index = component_start + 1, #spawned_attachments do
    if not spawned_attachments[index].removed then
        live_after_failure = live_after_failure + 1
    end
end
assert(live_after_failure == 5,
    "partial component appearance did not preserve the last valid wearable set")
assert(unit.survival_model_asset_id == "test_component_bundle"
        and unit.survival_applied_model_path
            == "models/test/component_bundle.vmdl",
    "partial component appearance discarded the last committed identity")
assert(warning_logs[#warning_logs]
        and warning_logs[#warning_logs]:find(
            "AppearanceWarning:unit=77", 1, true)
        and warning_logs[#warning_logs]:find("slot=weapon", 1, true)
        and warning_logs[#warning_logs]:find(
            "reason=entity_create_failed", 1, true),
    "partial component appearance did not emit a structured warning")

fail_attachment_model = nil
assets.test_component_bundle.attachment_models[5] = original_weapon_model
ok, status = visual.apply(unit, {
    model_asset_id = "test_component_bundle",
})
assert(ok and status == "test_component_bundle",
    "component appearance did not recover after a component failure")
visual.clear(unit)
for index = component_start + 1, #spawned_attachments do
    assert(spawned_attachments[index].removed,
        "component appearance clear left a wearable entity")
end

print("BUILDING_VISUAL_SERVICE_PASS")
