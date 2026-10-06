package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local tasks, created, heroes, skills, destroyed_particles, cleared_cosmetics, deals = {}, {}, {}, {}, {}, {}, {}
local serial, particle_serial = 100, 0
local function after(_, callback, id) tasks[id] = callback; return id end
package.loaded["core/scheduler"] = { after = after, every = after,
    cancel = function(id) tasks[id] = nil end }
package.loaded["core/sound_service"] = { play = function() end }
package.loaded["systems/gameplay_phase_guard"] = { post_clear_frozen = function() return false end }
package.loaded["systems/hero_cosmetic_service"] = {
    -- Exercise lifecycle routing against the committed-declaration contract.
    -- Resource transaction details are covered by test_hero_cosmetic_mirror.
    sync_appearance = function(unit, source)
        assert(unit:IsAlive(), "dead clones must retain their last appearance")
        unit.mirror_calls = (unit.mirror_calls or 0) + 1
        if source.visual_blocked then return false end
        local declaration = assert(source.committed_visual)
        if unit.cosmetics == source and unit.mirrored_declaration == declaration then return true end
        unit.cosmetics, unit.mirrored_declaration = source, declaration
        unit.visual = { model = declaration.model, particles = {} }
        for i, particle in ipairs(declaration.particles) do unit.visual.particles[i] = particle end
        unit.visual_rebuilds = (unit.visual_rebuilds or 0) + 1
        return true
    end,
    clear = function(unit)
        assert(unit.null or unit.hidden, "hide the clone before clearing its cosmetics")
        cleared_cosmetics[unit] = true
    end,
}
package.loaded["systems/hero_base_health_service"] = { apply = function() return {} end }
local original_print = print
print = function(message)
    if tostring(message):find("%[EventBus%] handler error") then error(message) end
end

local vector = {}
vector.__index = vector
function Vector(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, vector) end
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function vector:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
function vector:Normalized() return self * (1 / self:Length2D()) end
RandomVector = function() return Vector(10, 0, 0) end
GetGroundPosition = function(position) return position end
FindClearSpaceForUnit = function() end
RollPercentage = function() return true end
DOTA_UNIT_CAP_NO_ATTACK, DAMAGE_TYPE_PURE = 0, 4
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_MOVE_GROUND = 1, 1
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 2, 4, 8
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_ANY_ORDER = 16, 0
PATTACH_WORLDORIGIN = 0
GameRules = { GetGameTime = function() return 0 end }
PlayerResource = { GetPlayer = function(_, id) return { id = id } end }
ParticleManager = {
    CreateParticle = function() particle_serial = particle_serial + 1; return particle_serial end,
    SetParticleControl = function() end, SetParticleControlForward = function() end,
    DestroyParticle = function(_, id) destroyed_particles[id] = true end,
    ReleaseParticleIndex = function() end,
}

local function unit(name, player_id)
    serial = serial + 1
    local result = { id = serial, name = name, player_id = player_id,
        health = 1000, maximum = 1000, modifiers = {}, abilities = {} }
    function result:IsNull() return self.null == true end
    function result:IsAlive() return not self.null and not self.dead end
    function result:entindex() return self.id end
    function result:GetPlayerOwnerID() return self.player_id end
    function result:GetUnitName() return self.name end
    function result:GetTeamNumber() return self.team or 2 end
    function result:GetAbsOrigin() return Vector(self.id * 10, 0, 0) end
    function result:GetForwardVector() return Vector(1, 0, 0) end
    function result:GetAbilityCount() return 0 end
    function result:FindAbilityByName(name) return self.abilities[name] end
    function result:AddAbility(name)
        local ability = { SetLevel = function() end, SetHidden = function() end,
            SetActivated = function() end, GetCastPoint = function() return 0 end }
        self.abilities[name] = ability
        return ability
    end
    function result:SetPlayerID(value) self.player_id = value end
    function result:SetOwner(value) self.owner = value end
    function result:SetHealth(value) self.health = value end
    function result:SetBaseDamageMin(value) self.damage_min = value end
    function result:SetBaseDamageMax(value) self.damage_max = value end
    function result:GetHealth() return self.health end
    function result:GetMaxHealth() return self.maximum end
    function result:FindModifierByName(name) return self.modifiers[name] end
    function result:AddNewModifier(_, _, name, params)
        self.modifiers[name] = { SetCombatSnapshot = function() end, GetStackCount = function() return 0 end,
            attack_interval = params and params.attack_interval,
            SetAttackInterval = function(self, interval) self.attack_interval = interval end }
        return self.modifiers[name]
    end
    function result:AddNoDraw() self.hidden = true end
    function result:SetAttackCapability(value) self.attack_capability = value end
    for _, name in ipairs({ "SetControllableByPlayer", "SetHullRadius", "SetBaseStrength",
        "SetBaseAgility", "SetBaseIntellect", "CalculateStatBonus",
        "SetBaseAttackTime", "CastAbilityNoTarget",
        "CastAbilityOnPosition", "SetDayTimeVisionRange", "SetNightTimeVisionRange" }) do
        result[name] = function() end
    end
    return result
end
CreateUnitByName = function(name, _, _, owner)
    local entity = unit(name, owner.player_id)
    created[#created + 1] = entity
    return entity
end
UTIL_Remove = function(entity)
    -- Model reentrant native death notifications during explicit deletion.
    bus.emit(events.ENGINE_ENTITY_KILLED, { victim = entity })
    entity.null = true
end
local target = unit("enemy", -1)
target.team = 3
FindUnitsInRadius = function() return { target } end

local monkey = require("systems/monkey_king_exclusive_service")
local blade = require("systems/blademaster_exclusive_service")
monkey.init()
blade.init()
bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(payload)
    return { ok = heroes[payload.player_id] ~= nil, unit = heroes[payload.player_id] }
end)
bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST, function(payload)
    return { ok = true, snapshot = { skills = skills[payload.player_id] or {} } }
end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function()
    return { ok = true, snapshot = { max_health = 1000, attack_min = 100, attack_max = 100,
        attack_speed = 1.4, base_attack_time = 1 / 1.4, strength = 10, agility = 10, intellect = 10 } }
end)
bus.handle_request(combat_events.DEAL_REQUEST, function(payload)
    deals[#deals + 1] = payload
    return { success = true }
end)
local function summon(player_id, hero_id)
    local hero = unit(hero_id, player_id)
    hero.survival_hero_id = hero_id
    hero.committed_visual = { model = hero_id .. "_equipped", particles = { "birth_glow" } }
    heroes[player_id] = hero
    skills[player_id] = {}
    local ids = hero_id == "hero_monkey_king"
        and { "skill_monkey_king_exclusive", "skill_monkey_king_fury", "skill_monkey_king_swiftness" }
        or { "skill_blademaster_exclusive", "skill_blademaster_agility", "skill_blademaster_mobility" }
    for _, id in ipairs(ids) do skills[player_id][#skills[player_id] + 1] = { skill_id = id, level = 1 } end
    bus.emit(events.HERO_SKILL_CHANGED, { player_id = player_id })
    local clone = created[#created]
    assert(clone and (clone.survival_monkey_king_clone or clone.survival_blademaster_clone))
    return hero, clone
end
local function removed(player_id, hero)
    heroes[player_id] = nil
    hero.null = true -- ReplaceHeroWithNoTransfer has already removed the source.
    bus.emit(events.HERO_REMOVED, { player_id = player_id, unit = hero,
        entindex = hero.id, hero_id = hero.survival_hero_id, reason = "cheat_deletehero" })
end

local h0, c0 = summon(0, "hero_monkey_king")
local h1, c1 = summon(1, "hero_monkey_king")
assert(c0.visual.model == h0.committed_visual.model and c0.visual.particles[1] == "birth_glow")
h0.committed_visual = { model = "monkey_new_staff", particles = {} }
bus.emit(events.HERO_COSMETICS_CHANGED, { player_id = 0, unit = h0, reason = "weapon_applied" })
assert(c0.visual.model == "monkey_new_staff" and #c0.visual.particles == 0)
assert(c1.visual.model == h1.committed_visual.model and c1.visual.particles[1] == "birth_glow",
    "monkey equipment event must not affect another player's clone")
assert(monkey._test.trigger_q(0, h0, target))
assert(monkey._test.trigger_q(1, h1, target))
local old_impact, other_impact
for id, impact in pairs(monkey._test.impacts()) do
    if impact.player_id == 0 then old_impact = impact else other_impact = impact end
end
local late_impact = tasks[old_impact.task]
local late_growth = assert(tasks["monkey_growth:0"])
c0.dead = true
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = c0 })
local late_respawn = assert(tasks["monkey_clone_respawn:0"])
removed(0, h0)
assert(c0.null and cleared_cosmetics[c0], "remove a dead clone and its retained cosmetics")
assert(not tasks["monkey_clone_respawn:0"] and not tasks["monkey_growth:0"])
assert(not tasks[old_impact.task] and destroyed_particles[old_impact.drop_particle])
assert(tasks[other_impact.task] and not c1.null and tasks["monkey_growth:1"],
    "other player's clone, growth and particle must remain")
assert(monkey._test.health_hits()[0] == nil)
local h0new, c0new = summon(0, "hero_monkey_king")
local count = #created
late_respawn(); late_growth(); late_impact()
assert(#created == count and not c0new.null, "old callbacks cannot respawn or delete new clones")
bus.emit(events.HERO_REMOVED, { player_id = 0, unit = h0 })
assert(not c0new.null, "stale removal must preserve replacement")
removed(0, h0new)
assert(c0new.null and cleared_cosmetics[c0new], "delete also removes a live clone")

local b0, bc0 = summon(2, "hero_blademaster")
local b1, bc1 = summon(3, "hero_blademaster")
assert(bc0.visual.model == b0.committed_visual.model and bc0.visual.particles[1] == "birth_glow")
b0.committed_visual = { model = "blade_new_sword", particles = {} }
bus.emit(events.HERO_COSMETICS_CHANGED, { player_id = 2, unit = b0, reason = "weapon_cleared" })
assert(bc0.visual.model == "blade_new_sword" and #bc0.visual.particles == 0)
assert(bc1.visual.model == b1.committed_visual.model and bc1.visual.particles[1] == "birth_glow",
    "blade equipment event must not affect another player's clone")
assert(blade._test.start_storm({ player_id = 2, attacker = b0, target = target }))
assert(blade._test.start_storm({ player_id = 3, attacker = b1, target = target }))
assert(blade._test.q_replicate({ player_id = 2, attacker = b0, target = target,
    critical = true, is_main_attack = true, final_damage = 100 }))
local b_visuals, other_visuals = {}, {}
for _, entity in ipairs(created) do
    if entity.survival_blademaster_visual_caster then
        local bucket = entity.player_id == 2 and b_visuals or other_visuals
        bucket[#bucket + 1] = entity
    end
end
assert(#b_visuals == 2 and #other_visuals == 1)
local storm_id = "blademaster_storm:2:" .. b0.id
local late_storm = assert(tasks[storm_id])
bc0.dead = true
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = bc0 })
local late_blade_respawn = assert(tasks["blademaster_clone_respawn:2"])
blade._test.growth_tick(2)
blade._test.growth_tick(3)
removed(2, b0)
assert(bc0.null and cleared_cosmetics[bc0] and not bc1.null)
assert(not tasks[storm_id] and not tasks["blademaster_clone_respawn:2"])
for _, caster in ipairs(b_visuals) do
    assert(caster.null and not tasks["blademaster_q_visual:" .. caster.id])
end
assert(not other_visuals[1].null)
assert(bus.request(events.BLADEMASTER_BONUS_STATS_GET_REQUEST, { player_id = 2 }).snapshot.attack_pct == 0)
assert(bus.request(events.BLADEMASTER_BONUS_STATS_GET_REQUEST, { player_id = 3 }).snapshot.attack_pct > 0)
local b0new, bc0new = summon(2, "hero_blademaster")
count = #created
late_blade_respawn(); late_storm()
assert(#created == count and not bc0new.null)
bc0.survival_blademaster_clone = true
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = bc0 })
assert(not tasks["blademaster_clone_respawn:2"], "late old death must not respawn the replacement clone")
bus.emit(events.HERO_REMOVED, { player_id = 2, unit = b0 })
assert(not bc0new.null)
removed(2, b0new)
assert(bc0new.null and cleared_cosmetics[bc0new])

local function verify_visual_lifecycle(player_id, hero_id, poll_id, respawn_prefix)
    local hero, clone = summon(player_id, hero_id)
    local function committed(model, particles, notify)
        hero.committed_visual = { model = model, particles = particles }
        if notify ~= false then
            bus.emit(events.HERO_COSMETICS_CHANGED, {
                player_id = player_id, unit = hero, reason = "weapon_applied",
            })
        end
    end
    local function expect(entity, model, particle_count)
        assert(entity.visual and entity.visual.model == model, hero_id .. ": wrong mirrored weapon")
        assert(#entity.visual.particles == particle_count, hero_id .. ": wrong committed particle list")
    end
    expect(clone, hero_id .. "_equipped", 1)
    local stat_only_mirrors = clone.mirror_calls
    for index = 1, 100 do
        bus.emit(events.HERO_COMBAT_STATS_CHANGED, { player_id = player_id,
            snapshot = { entindex = hero.id, max_health = 1000, attack_speed = 1.4,
                attack_min = 100 + index, attack_max = 100 + index } })
    end
    assert(clone.damage_min == 200, "all growth stat events must still reach the clone")
    assert(clone.mirror_calls == stat_only_mirrors,
        "100 stat-only attack/growth events must not scan cosmetics or particle control points")
    committed("unenchanted_weapon", {})
    expect(clone, "unenchanted_weapon", 0)
    committed("enchanted_weapon", { "weapon_glow", "weapon_trail" })
    expect(clone, "enchanted_weapon", 2)
    assert(clone.visual.particles ~= hero.committed_visual.particles,
        "clones must own their appearance instead of mutating the source")

    local calls, rebuilds = clone.mirror_calls, clone.visual_rebuilds
    bus.emit(events.HERO_COSMETICS_CHANGED, { player_id = player_id, unit = h1 })
    assert(clone.mirror_calls == calls, "wrong source entity must be ignored")
    for _ = 1, 5 do tasks[poll_id]() end
    assert(clone.mirror_calls > calls and clone.visual_rebuilds == rebuilds,
        "periodic sync must reuse the mirror API's unchanged declaration")
    committed("polled_weapon", {}, false)
    tasks[poll_id]()
    expect(clone, "polled_weapon", 0)

    hero.visual_blocked = true
    committed("pending_weapon", { "new_glow" })
    expect(clone, "polled_weapon", 0)
    hero.visual_blocked = false
    hero.dead = true
    tasks[poll_id]()
    expect(clone, "pending_weapon", 1)
    hero.dead = false
    hero.null = true
    committed("source_unavailable", {})
    tasks[poll_id]()
    expect(clone, "pending_weapon", 1)
    hero.null = false
    tasks[poll_id]()
    expect(clone, "source_unavailable", 0)

    clone.dead = true
    bus.emit(events.ENGINE_ENTITY_KILLED, { victim = clone })
    committed("respawn_weapon", { "respawn_glow" })
    tasks[poll_id]()
    expect(clone, "source_unavailable", 0)
    assert(not cleared_cosmetics[clone], "death must retain the corpse's equipment until removal")
    assert(tasks[respawn_prefix .. player_id])()
    local respawned = created[#created]
    assert(respawned ~= clone)
    expect(respawned, "respawn_weapon", 1)
    committed("respawn_plain_weapon", {})
    expect(respawned, "respawn_plain_weapon", 0)
    expect(clone, "source_unavailable", 0)
    removed(player_id, hero)
    assert(cleared_cosmetics[clone] and cleared_cosmetics[respawned],
        "deletehero must retire corpse and live clone resources")

    local replacement, new_clone = summon(player_id, hero_id)
    calls = new_clone.mirror_calls
    bus.emit(events.HERO_COSMETICS_CHANGED, { player_id = player_id, unit = hero })
    assert(new_clone.mirror_calls == calls, "late old-source cosmetics cannot alter the replacement")
    expect(new_clone, hero_id .. "_equipped", 1)
    removed(player_id, replacement)
end
verify_visual_lifecycle(4, "hero_monkey_king", "monkey_clone_sync", "monkey_clone_respawn:")
verify_visual_lifecycle(5, "hero_blademaster", "blademaster_growth", "blademaster_clone_respawn:")

local qhero, qclone = summon(6, "hero_blademaster")
assert(qclone.attack_capability == DOTA_UNIT_CAP_MELEE_ATTACK and not qclone.survival_visual_only,
    "W guardian must remain a normal combat attacker")
local before = #deals
assert(blade.trigger_clone_q(6, qclone, target, 321))
assert(#deals == before + 1 and deals[#deals].attacker == qclone
    and deals[#deals].base_damage == 321 and deals[#deals].tags.non_recursive,
    "clone critical listener must route Q through the normal damage pipeline once")
assert(not blade._test.q_replicate({ player_id = 6, attacker = qclone, target = target,
    critical = true, is_main_attack = true, final_damage = 321 }),
    "main-hero event cannot repeat a clone's Q")
assert(not blade.trigger_clone_q(3, qclone, target, 321), "another player's state cannot grant this clone Q")
assert(blade._test.start_storm({ player_id = 6, attacker = qhero, target = target }))
local evisual = created[#created]
assert(evisual ~= qclone and evisual.survival_visual_only and evisual.survival_blademaster_visual_caster
    and not evisual.survival_blademaster_clone and evisual.attack_capability == DOTA_UNIT_CAP_NO_ATTACK,
    "E native spinning visual and permanent W guardian are distinct entities")
removed(6, qhero)
assert(evisual.null and qclone.null)
assert(not blade.trigger_clone_q(6, qclone, target, 321), "retired clone cannot trigger late Q damage")
print = original_print
print("EXCLUSIVE_HERO_REMOVAL_PASS cosmetic birth/event/poll/retry/respawn, empty effects, corpses, player isolation, removal, pending impacts/storms/growth and resummon")
