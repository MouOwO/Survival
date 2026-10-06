-- SIMULATION: production CSV profiles + event bus, mocked particles/scheduler.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local tasks, now, serial = {}, 0, 0
package.loaded["core/scheduler"] = {
    after = function(delay, callback, id)
        serial = serial + 1
        id = id or tostring(serial)
        tasks[id] = { callback = callback, at = now + delay }
        return id
    end,
    every = function(_, callback, id)
        tasks[id] = { callback = callback, recurring = true }
        return id
    end,
    cancel = function(id) tasks[id] = nil end,
}
GameRules = { GetGameTime = function() return now end }
Vector = function(x, y, z) return { x = x, y = y, z = z } end
PATTACH_ABSORIGIN_FOLLOW, PATTACH_POINT_FOLLOW, PATTACH_WORLDORIGIN = 1, 2, 3
local particles, next_particle, reenter_destroy = {}, 0, nil
ParticleManager = {
    CreateParticle = function(_, path, attach, unit)
        next_particle = next_particle + 1
        particles[next_particle] = { path = path, attach = attach, unit = unit, cp = {} }
        return next_particle
    end,
    SetParticleControl = function(_, id, cp, value) particles[id].cp[cp] = value end,
    SetParticleControlEnt = function(_, id, _, unit, _, anchor)
        particles[id].unit, particles[id].anchor = unit, anchor
    end,
    DestroyParticle = function(_, id)
        assert(not particles[id].destroyed, "particle destroyed twice")
        particles[id].destroyed = true
        if reenter_destroy then
            local callback = reenter_destroy
            reenter_destroy = nil
            callback()
        end
    end,
    ReleaseParticleIndex = function(_, id)
        assert(particles[id].destroyed, "bounded effects must be destroyed first")
        assert(not particles[id].released, "particle released twice")
        particles[id].released = true
    end,
}
local function unit(id, pid, attachments)
    local u = { id = id, survival_player_id = pid, attachments = attachments or {},
        model_name = "models/heroes/juggernaut/juggernaut.vmdl" }
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return not self.dead end
    function u:entindex() return self.id end
    function u:GetPlayerOwnerID() return self.survival_player_id end
    function u:GetAbsOrigin() return Vector(self.id, 0, 384) end
    function u:GetModelName() return self.model_name end
    function u:ScriptLookupAttachment(name)
        local index = self.attachments[name]
        return type(index) == "number" and index or (index and 1 or 0)
    end
    return u
end
local equipped = {}
bus.handle_request(events.WEAPON_EQUIPMENT_GET_REQUEST, function(payload)
    return { snapshot = { main_hand_content_id = equipped[payload.player_id] or "" } }
end)
local service = require("systems/weapon_visual_service")
local precached = {}
PrecacheResource = function(_, path) precached[path] = true end
service.precache({})
assert(precached["particles/survival/weapons/weapon_glow.vpcf"])
service.init()
local a, b = unit(10, 0, { attach_attack1 = true }), unit(11, 1)
local function equip(pid, content, slot)
    if not slot or slot == "main_hand" then equipped[pid] = content end
    bus.emit(events.WEAPON_EQUIPPED_CHANGED, {
        player_id = pid, content_id = content, slot = slot or "main_hand",
    })
end
local function summon(u, pid)
    bus.emit(events.HERO_SUMMONED, { player_id = pid, unit = u })
end
local function count(u)
    local total = 0
    for _, p in pairs(particles) do
        if not p.destroyed and (not u or p.unit == u) then total = total + 1 end
    end
    return total
end
equip(0, "weapon_growth_sword_01")
assert(count() == 0, "no summoned hero means no world-origin junk")
summon(a, "0")
assert(count(a) == 2 and service.debug_snapshot(0).anchor == "attach_attack1")
local initial = next_particle
equip(0, "weapon_growth_sword_01")
assert(next_particle == initial, "duplicate equip must not rebuild")
equip(0, "equipment_burning_blade_max", "accessory")
assert(next_particle == initial, "accessory must not replace main-hand visual")
local low_radius = particles[1].cp[1].x
equip(0, "weapon_growth_sword_max")
assert(particles[next_particle - 1].cp[1].x > low_radius)
assert(particles[next_particle - 1].cp[1].x == 10, "stage99 must normalize to maximum")
equip(1, "weapon_ice_blade_max")
summon(b, 1)
assert(count(b) == 3 and service.debug_snapshot(1).anchor == nil)
summon(b, 0)
assert(service.debug_snapshot(0).hero == a.id, "cross-player hero binding rejected")
local before_b = count(b)
equip(0, "weapon_epic_icefire_06")
assert(count(a) == 3 and count(b) == before_b)
assert(particles[next_particle - 2].cp[1].x == 25, "stage0-based epic chain reaches max")
local target = unit(99, 2)
local function hit(attacker, pid, secondary)
    bus.emit(events.HERO_MAIN_ATTACK_LANDED, {
        player_id = pid, attacker = attacker, target = target,
        is_main_attack = not secondary, is_multishot_secondary = secondary,
    })
end
local before_hit = next_particle
hit(a, 0, true); hit(b, 0, false)
assert(next_particle == before_hit, "no secondary or wrong-owner extra impacts")
hit(a, 0, false)
assert(next_particle == before_hit + 1)
assert(particles[next_particle].cp[3].x == target.id,
    "native impact CP3 must follow target rather than world origin")
assert(particles[next_particle].cp[1].x == 100,
    "Liquid Fire impact receives explicit visual radius")
hit(a, 0, false)
assert(next_particle == before_hit + 1, "impact rate limited")
now = 0.5
hit(a, 0, false)
assert(next_particle == before_hit + 2)
equip(0, "")
assert(count(a) == 0, "unequip cleans ambient and pending impact effects")
b.dead = true
tasks.weapon_visual_lifecycle.callback()
assert(count(b) == 0, "death cleanup")
b.dead = false
tasks.weapon_visual_lifecycle.callback()
assert(count(b) == 3, "same-unit revive restores current visual once")
tasks.weapon_visual_lifecycle.callback()
assert(count(b) == 3)
local replacement = unit(12, 1, { attach_weapon = true })
summon(replacement, 1)
assert(count(b) == 0 and count(replacement) == 3)
replacement.removed = true
tasks.weapon_visual_lifecycle.callback()
assert(count() == 0, "deleted entity cleanup")
-- Hot init cannot duplicate side effects or unsubscribe another owner.
service.init()
equipped[0] = "weapon_legend_abyss_10"
summon(a, 0)
assert(count(a) == 3)
local max_glow = particles[next_particle - 2].cp[1].x
assert(max_glow == 30)
service.init()
assert(count() == 0)
-- Engine callbacks can re-enter death cleanup while clearing an old layer.
summon(a, 0)
a.dead = true
reenter_destroy = function() tasks.weapon_visual_lifecycle.callback() end
tasks.weapon_visual_lifecycle.callback()
assert(count() == 0, "clear must revoke handles before calling engine")
a.dead = false
tasks.weapon_visual_lifecycle.callback()
assert(count(a) == 3)
-- A new world reused one integer handle for another module's particle.
local reused = next_particle
for _, p in pairs(particles) do p.destroyed = true end
particles[reused] = { unit = target, cp = {} }
local new_world = {}
GameRules.GetGameModeEntity = function() return new_world end
service.init()
assert(not particles[reused].destroyed,
    "new world init must not destroy an integer handle owned by another module")
-- A Tools preview shares production profile application but has independent
-- ownership and cannot equip a weapon or replace a player's visual state.
IsServer = function() return true end
IsInToolsMode = function() return false end
local preview_hero = unit(40, 0, { attach_attack1 = true })
local handle, reason = service.preview(preview_hero, "weapon_growth_sword_max")
assert(not handle and reason == "tools_server_required")
IsInToolsMode = function() return true end
handle, reason = service.preview(preview_hero, "equipment_burning_blade_max")
assert(not handle and reason == "enabled_main_hand_profile_required")
assert(not service.debug_snapshot(0), "preview did not register player zero")
summon(a, 0)
local live_snapshot = service.debug_snapshot(0)
assert(not service.preview(a, "weapon_growth_sword_max"), "live equipment owner is protected")
local equipment_events, summon_events = 0, 0
bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, function() equipment_events = equipment_events + 1 end)
bus.subscribe(events.HERO_SUMMONED, function() summon_events = summon_events + 1 end)
handle, reason = service.preview(preview_hero, "weapon_legend_abyss_10")
assert(handle and reason == "ready")
local preview_status = handle:status()
assert(preview_status.active and preview_status.particle_count == 3
    and preview_status.anchor == "attach_attack1" and preview_status.progress == 1)
local preview_glow = particles[preview_status.particle_ids[1]]
assert(preview_glow.cp[1].x == 30 and preview_glow.cp[1].z == 0.6,
    "preview must use authoritative max-stage radius and alpha")
assert(service.debug_snapshot(0).hero == live_snapshot.hero
    and service.debug_snapshot(0).content_id == live_snapshot.content_id)
assert(not service.preview(preview_hero, "weapon_growth_sword_max"), "no duplicate preview per hero")
preview_hero.dead = true
tasks.weapon_visual_lifecycle.callback()
assert(handle:status().particle_count == 0, "preview death cleanup shares production lifecycle")
preview_hero.dead = false
tasks.weapon_visual_lifecycle.callback()
assert(handle:status().particle_count == 3)
handle:dispose(); handle:dispose()
assert(not handle:status().active and count(preview_hero) == 0)
assert(count(a) == 3 and equipment_events == 0 and summon_events == 0,
    "fixture never emits gameplay equipment or summon events")
handle = assert(service.preview(preview_hero, "weapon_ice_blade_max"))
service.init()
assert(not handle:status().active and count(preview_hero) == 0, "hot init cleans preview ownership")
handle:dispose()
handle = assert(service.preview(preview_hero, "weapon_frost_blade_max"))
local stale_preview_particle = handle:status().particle_ids[1]
for _, p in pairs(particles) do p.destroyed = true end
particles[stale_preview_particle] = { unit = target, cp = {} }
new_world = {}
handle:dispose()
assert(not particles[stale_preview_particle].destroyed, "stale handle dispose cannot affect a new world")
service.init()
handle:dispose()
assert(not particles[stale_preview_particle].destroyed, "new world init discards stale preview handles")

-- Production failure paths must clean partial effects and permit recovery.
local native_create = ParticleManager.CreateParticle
local native_control = ParticleManager.SetParticleControl
local native_destroy = ParticleManager.DestroyParticle
local native_release = ParticleManager.ReleaseParticleIndex
local failed_layer = next_particle + 2
ParticleManager.SetParticleControl = function(self, id, cp, value)
    if id == failed_layer then error("injected second-layer control failure") end
    return native_control(self, id, cp, value)
end
equipped[0] = "weapon_legend_abyss_10"
summon(a, 0)
assert(count(a) == 0 and service.debug_snapshot(0).particle_count == 0,
    "failed second layer rolls back all layers instead of leaving a partial visual")
assert(particles[failed_layer].released and particles[failed_layer-1].released)
ParticleManager.SetParticleControl = native_control
tasks.weapon_visual_lifecycle.callback()
assert(count(a) == 3, "production lifecycle retries a rolled-back visual")

local layer_ids = {next_particle-2, next_particle-1, next_particle}
ParticleManager.DestroyParticle = function(self, id, immediate)
    native_destroy(self, id, immediate)
    if id == layer_ids[1] then error("injected destroy failure") end
end
ParticleManager.ReleaseParticleIndex = function(self, id)
    native_release(self, id)
    if id == layer_ids[2] then error("injected release failure") end
end
equip(0, "")
for _, id in ipairs(layer_ids) do
    assert(particles[id].destroyed and particles[id].released,
        "one failed cleanup call must not skip release or strand later handles")
end
ParticleManager.DestroyParticle = native_destroy
ParticleManager.ReleaseParticleIndex = native_release
ParticleManager.CreateParticle = function() return -1 end
equip(0, "weapon_legend_abyss_10")
assert(count(a) == 0 and service.debug_snapshot(0).particle_count == 0,
    "invalid CreateParticle result is rejected without owning an invalid ID")
ParticleManager.CreateParticle = native_create
tasks.weapon_visual_lifecycle.callback()
assert(count(a) == 3)

-- Impacts own their handle before CP configuration and use the same safe
-- disposal both on failure and on their scheduled finite lifetime.
local failed_impact = next_particle + 1
ParticleManager.SetParticleControl = function(self, id, cp, value)
    if id == failed_impact and cp == 3 then error("injected impact CP3 failure") end
    return native_control(self, id, cp, value)
end
now = now + 2
hit(a, 0, false)
assert(particles[failed_impact].destroyed and particles[failed_impact].released
    and count(a) == 3, "failed impact configuration cannot leak its allocated handle")
for key in pairs(tasks) do assert(key == "weapon_visual_lifecycle", "failed impact leaves no expiry task") end
ParticleManager.SetParticleControl = native_control
now = now + 2
hit(a, 0, false)
local expiring = next_particle
local expiry_key, expiry
for key, task in pairs(tasks) do
    if key ~= "weapon_visual_lifecycle" then expiry_key, expiry = key, task end
end
assert(expiry)
ParticleManager.DestroyParticle = function(self, id, immediate)
    native_destroy(self, id, immediate)
    if id == expiring then error("injected expiry destroy failure") end
end
expiry.callback()
assert(particles[expiring].released and count(a) == 3,
    "expiry attempts Release even when Destroy throws")
tasks[expiry_key] = nil
ParticleManager.DestroyParticle = native_destroy

-- Tools must report a failed production refresh, never a ready zero-layer
-- handle. Its error cleanup cannot alter the real player's healthy effects.
ParticleManager.CreateParticle = function() error("injected preview allocation failure") end
local failed_handle, failure_reason = service.preview(preview_hero, "weapon_ice_blade_max")
assert(not failed_handle and string.find(failure_reason, "preview_apply_failed", 1, true))
assert(count(a) == 3 and count(preview_hero) == 0)
ParticleManager.CreateParticle = native_create
local recovered = assert(service.preview(preview_hero, "weapon_ice_blade_max"))
recovered:dispose()
service.init()
assert(count(a) == 0 and count(preview_hero) == 0)

-- Real native spawns can have no model for their first few engine frames.
-- Do not trust attachment lookup until a model exists, then rebind only when
-- that model or its selected attachment actually changes.
a.model_name = ""
a.attachments = { attach_hitloc = 3 }
local native_lookup = a.ScriptLookupAttachment
local lookups_without_model = 0
a.ScriptLookupAttachment = function(self, name)
    if self.model_name == "" then lookups_without_model = lookups_without_model + 1 end
    return native_lookup(self, name)
end
local before_async = next_particle
summon(a, 0)
for _ = 1, 4 do tasks.weapon_visual_lifecycle.callback() end
assert(next_particle == before_async and lookups_without_model == 0
    and service.debug_snapshot(0).binding_state == "waiting_for_model",
    "empty model defers all attachment lookup and particle allocation")
a.model_name = "models/heroes/juggernaut/juggernaut.vmdl"
tasks.weapon_visual_lifecycle.callback()
assert(count(a) == 3 and next_particle == before_async + 3
    and service.debug_snapshot(0).anchor == "attach_hitloc")
a.attachments.attach_sword = 2
tasks.weapon_visual_lifecycle.callback()
assert(count(a) == 3 and service.debug_snapshot(0).anchor == "attach_sword"
    and service.debug_snapshot(0).anchor_index == 2,
    "native Juggernaut sword attachment takes precedence over torso hitloc")
local ready_serial = next_particle
for _ = 1, 8 do tasks.weapon_visual_lifecycle.callback() end
assert(next_particle == ready_serial, "stable model/attachment never rebuilds every poll")
a.attachments.attach_attack1 = 7
tasks.weapon_visual_lifecycle.callback()
assert(next_particle == ready_serial + 3 and count(a) == 3
    and service.debug_snapshot(0).anchor == "attach_attack1",
    "late weapon attachment replaces the earlier hit-location binding once")
ready_serial = next_particle
a.attachments.attach_attack1 = 8
tasks.weapon_visual_lifecycle.callback()
assert(next_particle == ready_serial + 3 and service.debug_snapshot(0).anchor_index == 8,
    "same attachment name with a new bone index also refreshes")
ready_serial = next_particle
a.model_name = "models/items/juggernaut/custom_body.vmdl"
tasks.weapon_visual_lifecycle.callback()
assert(next_particle == ready_serial + 3 and count(a) == 3,
    "a cosmetic model swap rebinds even when attachment name/index is unchanged")
a.model_name = ""
tasks.weapon_visual_lifecycle.callback()
assert(count(a) == 0, "temporary empty model retires old attachment effects")
a.model_name = "models/heroes/juggernaut/juggernaut.vmdl"
a.attachments = {}
tasks.weapon_visual_lifecycle.callback()
assert(count(a) == 3 and service.debug_snapshot(0).anchor == nil,
    "ready model with no compatible attachment uses the bounded origin fallback")
preview_hero.model_name = ""
local delayed_preview, pending_reason = service.preview(preview_hero, "weapon_ice_blade_max")
assert(delayed_preview and pending_reason == "waiting_for_model"
    and delayed_preview:status().particle_count == 0)
preview_hero.model_name = "models/heroes/juggernaut/juggernaut.vmdl"
tasks.weapon_visual_lifecycle.callback()
assert(delayed_preview:status().binding_state == "ready" and count(preview_hero) == 3,
    "Tools preview shares automatic deferred model binding")
delayed_preview:dispose()
service.init()
assert(count(a) == 0 and count(preview_hero) == 0)
print("WEAPON_VISUAL_SERVICE_PASS ownership/main_hand/stage99/stage0/impact_cooldown/lifecycle/reinit/isolated_preview")
print("WEAPON_VISUAL_FAILURE_PASS partial rollback, invalid allocation, independent cleanup, impact CP failure, expiry release, preview recovery")
print("WEAPON_VISUAL_MODEL_BINDING_PASS async model, late attachment, bone index change, cosmetic swap, stable reuse, delayed preview")
