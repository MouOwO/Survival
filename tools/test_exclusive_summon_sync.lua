-- Execute the complete exclusive-passive service with mocked engine boundaries.
-- This validates combat/lifecycle behavior; cosmetic rendering has a separate test.
package.path = "scripts/vscripts/?.lua;" .. package.path

local events = require("core/events")
local definitions = require("config/hero_passive_skill_definitions").by_id
local armor_balance = require("config/armor_balance")
local RATE_MODIFIER = "modifier_hero_exclusive_summon_attack_rate"

function class(value) return value end
function IsServer() return true end
MODIFIER_PROPERTY_FIXED_ATTACK_RATE = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 4, 8
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST = 16, 0
local vector_meta = {}
vector_meta.__index = vector_meta
vector_meta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector_meta.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function Vector(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, vector_meta) end
local rate_definition = require("modifiers/modifier_hero_exclusive_summon_attack_rate")
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        (label or "value") .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end

local function fixture()
    local h = { now = 0, serial = 100, tasks = {}, heroes = {}, stats = {},
        created = {}, cosmetic_syncs = {}, cosmetic_clears = {}, requests = {},
        lifecycle = {}, world = {} }
    local handlers, subscribers, task_sequence = {}, {}, 0
    local bus = {}
    function bus.subscribe(name, callback)
        subscribers[name] = subscribers[name] or {}
        subscribers[name][#subscribers[name] + 1] = callback
        return { name = name, callback = callback }
    end
    function bus.unsubscribe(subscription)
        local bucket = subscribers[subscription and subscription.name] or {}
        for i = #bucket, 1, -1 do
            if bucket[i] == subscription.callback then table.remove(bucket, i) end
        end
    end
    function bus.emit(name, payload)
        for _, callback in ipairs(subscribers[name] or {}) do callback(payload or {}) end
    end
    function bus.request(name, payload)
        h.requests[#h.requests + 1] = { name = name, player_id = payload.player_id }
        local callback = handlers[name]
        return callback and callback(payload) or nil
    end
    function bus.handle_request(name, callback) handlers[name] = callback end
    local scheduler = {}
    function scheduler.after(delay, callback, id)
        task_sequence = task_sequence + 1
        id = id or ("test_task_" .. task_sequence)
        h.tasks[id] = { at = h.now + delay, callback = callback }
        return id
    end
    function scheduler.every(interval, callback, id)
        return scheduler.after(interval, function()
            if callback() == false then return false end
            return interval
        end, id)
    end
    function scheduler.cancel(id) h.tasks[id] = nil end
    function h.advance(target)
        local iterations = 0
        while true do
            local next_id, next_task
            for id, task in pairs(h.tasks) do
                if not next_task or task.at < next_task.at then next_id, next_task = id, task end
            end
            if not next_task or next_task.at > target + 0.000001 then break end
            iterations = iterations + 1
            assert(iterations < 10000, "Unbounded synchronization timer")
            h.tasks[next_id] = nil
            h.now = next_task.at
            local delay = next_task.callback()
            if type(delay) == "number" and delay >= 0 then
                next_task.at = h.now + delay
                h.tasks[next_id] = next_task
            end
        end
        h.now = target
    end
    function h.task_count()
        local count = 0
        for _ in pairs(h.tasks) do count = count + 1 end
        return count
    end
    function h.clear_count(unit)
        local count = 0
        for _, cleared in ipairs(h.cosmetic_clears) do
            if cleared == unit then count = count + 1 end
        end
        return count
    end
    function h.expiry_callback()
        for _, task in pairs(h.tasks) do
            if math.abs(task.at - h.now - 10) < 0.000001 then return task.callback end
        end
        error("Missing unchanged ten-second summon expiry")
    end
    function h.unit(name, player_id)
        h.serial = h.serial + 1
        local u = { index = h.serial, name = name, player_id = player_id,
            health = 100, maximum = 100, attack_min = 1, attack_max = 1,
            base_attack_time = 1, armor = 0, modifiers = {}, modifier_adds = {},
            health_writes = 0, max_health_writes = 0, damage_writes = 0,
            kill_count = 0, model = name .. ".vmdl", appearance_version = 1,
            world = h.world }
        function u:IsNull() return self.null == true end
        function u:IsAlive() return not self.dead and not self.null end
        function u:entindex() return self.index end
        function u:GetTeamNumber() return 2 end -- Both players share the same team.
        function u:GetPlayerOwnerID() return self.player_id end
        function u:GetAbsOrigin() return Vector(self.player_id * 1000, 0, 32) end
        function u:GetForwardVector() return Vector(1, 0, 0) end
        function u:GetUnitName() return self.name end
        function u:SetOwner(owner) self.owner = owner end
        function u:SetPlayerID(id) self.player_id = id end
        function u:SetControllableByPlayer(id, value) self.controller, self.controllable = id, value end
        function u:SetBaseDamageMin(value) self.attack_min = value; self.damage_writes = self.damage_writes + 1 end
        function u:SetBaseDamageMax(value) self.attack_max = value; self.damage_writes = self.damage_writes + 1 end
        function u:SetBaseAttackTime(value) self.base_attack_time = value end
        function u:GetBaseAttackTime() return self.base_attack_time end
        function u:SetPhysicalArmorBaseValue(value) self.armor = value end
        function u:SetBaseMaxHealth(value) self.base_maximum = value end
        function u:SetMaxHealth(value)
            self.maximum = value
            self.health = value -- Model the engine's possible refill during stat writes.
            self.max_health_writes = self.max_health_writes + 1
        end
        function u:GetMaxHealth() return self.maximum end
        function u:SetHealth(value) self.health = value; self.health_writes = self.health_writes + 1 end
        function u:GetHealth() return self.health end
        function u:ForceKill()
            assert(self.world == h.world, "Do not kill an old-world native handle")
            self.death_has_appearance = self.appearance_active == true
            h.lifecycle[#h.lifecycle + 1] = { action = "death", unit = self }
            self.dead = true
            self.kill_count = self.kill_count + 1
        end
        function u:AddNoDraw()
            assert(self.world == h.world, "Do not hide an old-world native handle")
            self.hidden = true
            h.lifecycle[#h.lifecycle + 1] = { action = "hide", unit = self }
        end
        function u:RemoveSelf()
            assert(self.world == h.world, "Do not remove an old-world native handle")
            self.null = true
            h.lifecycle[#h.lifecycle + 1] = { action = "remove", unit = self }
        end
        function u:FindModifierByName(name) return self.modifiers[name] end
        function u:HasModifier(name) return self.modifiers[name] ~= nil end
        function u:RemoveModifierByName(name) self.modifiers[name] = nil end
        function u:AddNewModifier(_, _, name, params)
            self.modifier_adds[name] = (self.modifier_adds[name] or 0) + 1
            local existing = self.modifiers[name]
            if existing then
                if existing.OnRefresh then existing:OnRefresh(params) end
                return existing
            end
            local modifier = params or {}
            if name == RATE_MODIFIER then
                modifier = setmetatable({ transmissions = 0 }, { __index = rate_definition })
                function modifier:SetHasCustomTransmitterData(value) self.transmits = value end
                function modifier:SendBuffRefreshToClients() self.transmissions = self.transmissions + 1 end
                function modifier:GetParent() return u end
                modifier:OnCreated(params)
            end
            self.modifiers[name] = modifier
            return modifier
        end
        function u:GetAttacksPerSecond(ignore_temporary)
            self.last_ignore_temporary = ignore_temporary
            if self.runtime_aps then return self.runtime_aps end
            local fixed = self.modifiers[RATE_MODIFIER]
            if fixed then
                assert(self.base_attack_time == 1,
                    "Drow/infernal must retain natural BAT for native animation scaling")
            end
            return fixed and (1 / fixed:GetModifierFixedAttackRate())
                or (1 / self.base_attack_time)
        end
        function u:GetSecondsPerAttack() return 1 / self:GetAttacksPerSecond(false) end
        return u
    end
    function h.hero(player_id, name, stats, runtime_aps)
        local u = h.unit(name, player_id)
        u.runtime_aps = runtime_aps
        h.heroes[player_id] = u
        h.stats[player_id] = stats
        stats.entindex, stats.player_id = u:entindex(), player_id
        u.maximum, u.health = stats.max_health, stats.max_health
        return u
    end
    function h.emit_stats(player_id, snapshot)
        bus.emit(events.HERO_COMBAT_STATS_CHANGED,
            { player_id = player_id, snapshot = snapshot or h.stats[player_id] })
    end
    function h.spawn(player_id, skill_id, stale_attributes)
        local context = { attacker = h.heroes[player_id], player_id = player_id,
            skill_id = skill_id, level = 1,
            attributes = stale_attributes or h.stats[player_id] }
        local created = h.service.runners[skill_id](context, definitions[skill_id])
        assert(created, "Initial summon should succeed")
        return h.created[#h.created], context
    end
    GameRules = { GetGameTime = function() return h.now end,
        GetGameModeEntity = function() return h.world end }
    UTIL_Remove = function(unit) unit:RemoveSelf() end
    CreateUnitByName = function(name, _, _, owner)
        local u = h.unit(name, owner.player_id)
        h.created[#h.created + 1] = u
        return u
    end
    local cosmetic = {}
    function cosmetic.sync_appearance(unit, source)
        h.cosmetic_syncs[#h.cosmetic_syncs + 1] = { unit = unit, source = source }
        unit.model, unit.appearance_version = source.model, source.appearance_version
        unit.appearance_active = true
        unit.appearance_world = h.world
        return true
    end
    function cosmetic.clear(unit)
        if unit.appearance_world ~= h.world then
            -- The real cosmetic service drops Lua ownership without issuing
            -- native removal calls against handles from a departed map.
            h.cosmetic_clears[#h.cosmetic_clears + 1] = unit
            unit.appearance_forgotten = true
            return
        end
        assert(unit.null or unit.hidden,
            "Removing mirrored appearance from a visible body exposes its base skin")
        h.lifecycle[#h.lifecycle + 1] = { action = "clear", unit = unit }
        h.cosmetic_clears[#h.cosmetic_clears + 1] = unit
        unit.appearance_active = false
        unit.model = unit.name .. ".vmdl"
    end
    package.loaded["core/scheduler"] = scheduler
    package.loaded["core/event_bus"] = bus
    package.loaded["systems/hero_cosmetic_service"] = cosmetic
    package.loaded["core/modifier_registry"] = { ensure = function(unit, name, params)
        return unit:FindModifierByName(name) or unit:AddNewModifier(unit, nil, name, params)
    end }
    package.loaded["systems/hero_exclusive_passive_service"] = nil
    h.service = require("systems/hero_exclusive_passive_service")
    h.service.sound_service = { play = function() end }
    h.service.init({ deal_group = function() error("Summon sync must not deal extra skill damage") end })
    bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function(payload)
        return { ok = h.stats[payload.player_id] ~= nil, snapshot = h.stats[payload.player_id] }
    end)
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(payload)
        return { ok = h.heroes[payload.player_id] ~= nil, unit = h.heroes[payload.player_id] }
    end)
    h.bus = bus
    return h
end

local function combat_values(minimum, maximum, speed, health, armor)
    return { attack_min = minimum, attack_max = maximum, attack_speed = speed,
        max_health = health, armor = armor, armor_unit = "war3_display", runtime_armor = 999 }
end

-- Birth must read current attributes and effective runtime speed, including addspeed.
local h = fixture()
local doom = h.hero(0, "npc_dota_hero_doom_bringer", combat_values(100, 140, 2, 1000, 50), 4)
doom.modifiers.modifier_debug_fixed_attack_rate = {
    GetModifierFixedAttackRate = function() return 0.1 end,
}
local infernal, doom_context = h.spawn(0, "skill_doom_infernal",
    combat_values(1, 2, 1, 100, 0))
near(infernal.attack_min, 100, "Live birth attack minimum")
near(infernal.attack_max, 140, "Live birth attack maximum")
near(infernal:GetAttacksPerSecond(false), 10, "addspeed overrides a stale native getter")
near(infernal.maximum, 1000, "Live birth maximum health")
near(infernal.armor, armor_balance.from_war3(50), "War3 armor mapping")
assert(infernal.owner == doom and infernal.controller == 0)
assert(#h.cosmetic_syncs == 0, "Doom must keep its infernal appearance")
assert(h.service.summon_locked(doom, "skill_doom_infernal"))
assert(not h.service.runners.skill_doom_infernal(doom_context, definitions.skill_doom_infernal),
    "Synchronization must never create another live summon")
local old_expiry = h.expiry_callback()

-- A shared timer updates changes without combat-stat events and keeps damaged HP.
infernal.health = 400
local health_writes, maximum_writes = infernal.health_writes, infernal.max_health_writes
local damage_writes = infernal.damage_writes
local rate_transmissions = infernal.modifiers[RATE_MODIFIER].transmissions
h.advance(0.3)
near(infernal.health, 400, "Unchanged synchronization cannot refill health")
assert(infernal.health_writes == health_writes and infernal.max_health_writes == maximum_writes,
    "Unchanged synchronization must not repeatedly rewrite health")
assert(infernal.damage_writes == damage_writes
    and infernal.modifiers[RATE_MODIFIER].transmissions == rate_transmissions,
    "Stable synchronization must not rewrite combat values or retransmit the fixed-rate modifier")
doom.modifiers.modifier_debug_fixed_attack_rate = nil
doom.runtime_aps = 7.5
h.stats[0].attack_min, h.stats[0].attack_max = 200, 260
h.advance(0.4)
near(infernal:GetAttacksPerSecond(false), 7.5, "Live temporary attack speed")
near(infernal.attack_min, 200, "No-event attack growth")
near(infernal.attack_max, 260, "No-event attack growth upper bound")
near(infernal.health, 400, "Attack refresh cannot heal")
assert(doom.last_ignore_temporary == false, "Runtime read must include temporary attack-speed modifiers")
h.stats[0].max_health = 2000
h.advance(0.5)
near(infernal.maximum, 2000, "Maximum-health inheritance")
near(infernal.health, 800, "Maximum-health change preserves the damaged percentage")

-- Same-team players remain isolated, and Drow follows its current appearance.
local drow = h.hero(1, "npc_dota_hero_drow_ranger", combat_values(300, 360, 1, 1500, 90), 3)
local companion = h.spawn(1, "skill_drow_companion")
near(companion:GetAttacksPerSecond(false), 3, "Drow effective attack speed")
assert(companion.owner == drow and companion.controller == 1)
assert(companion:HasModifier("modifier_survival_drow_companion_invulnerable"))
assert(companion:HasModifier("modifier_weapon_attack_tracker"))
assert(companion.model == drow.model and companion.survival_drow_max_targets == 5
    and companion.survival_drow_attack_range == 1200)
drow.appearance_version = 2
drow.model = "updated_drow_appearance.vmdl"
h.stats[1].attack_min, h.stats[1].attack_max = 350, 390
local stat_only_mirrors = #h.cosmetic_syncs
h.emit_stats(1)
near(companion.attack_min, 350, "Immediate Drow stat event")
near(infernal.attack_min, 200, "Other player's event must not modify Doom")
for index = 1, 100 do
    h.stats[1].strength = 400 + index
    h.emit_stats(1)
end
near(companion.survival_exclusive_stat_snapshot.strength, 500, "all growth stat events remain immediate")
assert(#h.cosmetic_syncs == stat_only_mirrors,
    "stat-only attacks must not trigger full appearance/model/control-point scans")
h.advance(0.6)
assert(companion.appearance_version == 2 and companion.model == drow.model,
    "Drow visual identity must follow the same source")
drow.appearance_version = 3
local commit_mirrors = #h.cosmetic_syncs
h.bus.emit(events.HERO_COSMETICS_CHANGED, { player_id = 1, unit = doom })
h.bus.emit(events.HERO_COSMETICS_CHANGED, { player_id = 0, unit = drow })
assert(#h.cosmetic_syncs == commit_mirrors, "cosmetic commits must match player and exact source")
h.bus.emit(events.HERO_COSMETICS_CHANGED, { player_id = 1, unit = drow })
assert(#h.cosmetic_syncs == commit_mirrors + 1 and companion.appearance_version == 3,
    "real appearance commits remain immediate without waiting for stat changes or polling")
local foreign_snapshot = combat_values(9999, 9999, 99, 9999, 99)
foreign_snapshot.entindex = doom:entindex()
h.emit_stats(1, foreign_snapshot)
near(companion.attack_min, 350, "Foreign entity snapshot must be ignored")

-- Keep one main attack plus the four nearest additional targets, without recursion.
local nearby, fired = {}, {}
for index = 1, 6 do
    local target, distance = h.unit("enemy", 2), index * 10
    function target:GetAbsOrigin() return Vector(1000 + distance, 0, 32) end
    nearby[#nearby + 1] = target
end
FindUnitsInRadius = function(_, _, _, radius)
    assert(radius == 1200, "Companion acquisition range must remain configured")
    return nearby
end
function companion:PerformAttack(target, orb, procs, skip_cooldown, invisible, projectile, fake, never_miss)
    assert(self.survival_next_drow_secondary == true)
    assert(not orb and not procs and skip_cooldown and not invisible
        and projectile and not fake and not never_miss)
    fired[#fired + 1] = target
end
assert(h.service.on_drow_companion_attack_fired(companion, nearby[1]))
assert(#fired == 4 and fired[1] == nearby[2] and fired[4] == nearby[5]
    and companion.survival_next_drow_secondary == nil,
    "The original five-target volley and secondary-attack guard must remain unchanged")

-- Runtime/source death and summon death are distinct. Neither revives a dead unit.
doom.dead = true
h.advance(0.8)
assert(infernal:IsAlive(), "A dead but unchanged source keeps the original remaining summon lifetime")
doom.dead = false
companion.dead = true
h.advance(0.9)
assert(not h.service.summon_locked(drow, "skill_drow_companion"))
assert(companion.dead and companion.kill_count <= 1, "Dead summon must not be healed or resurrected")
assert(companion.appearance_active and h.clear_count(companion) == 0,
    "Natural death must keep cloned cosmetics on the visible corpse")
local replacement_companion = h.spawn(1, "skill_drow_companion")
assert(replacement_companion ~= companion and replacement_companion:IsAlive())
companion.null = true -- The engine finishes removing the old corpse.
h.advance(0.95)
-- The corpse watcher may use a slower interval than combat synchronization.
h.advance(1)
assert(h.clear_count(companion) == 1 and replacement_companion.appearance_active,
    "Removing an old corpse must clear its resources exactly once, leaving the new summon dressed")

-- Replacement cleanup must bind entity identity, not only player id.
local replacement_drow = h.hero(1, "npc_dota_hero_drow_ranger", combat_values(500, 600, 4, 2000, 100), 5)
h.emit_stats(1) -- Stat publication may precede the summon event.
h.bus.emit(events.HERO_SUMMONED, { player_id = 1, unit = replacement_drow,
    entindex = replacement_drow:entindex(), hero_id = "hero_drow_ranger" })
h.advance(1.05)
assert(not replacement_companion:IsAlive(), "Replacing a hero must clear the old hero's companion")
assert(infernal:IsAlive(), "Replacing player one must not clear player zero's infernal")

-- A failed/stale expiry cannot kill a newly created summon with the same key.
infernal.dead = true
h.advance(1.1)
local new_infernal = h.spawn(0, "skill_doom_infernal")
old_expiry()
assert(new_infernal:IsAlive() and h.service.summon_locked(doom, "skill_doom_infernal"),
    "Old expiry callback must not clear a newer state")
h.advance(11.099)
assert(new_infernal:IsAlive(), "Stat refresh must preserve the original ten-second deadline")
h.advance(11.1)
assert(not new_infernal:IsAlive() and not h.service.summon_locked(doom, "skill_doom_infernal"))
assert(#h.created == 4, "No automatic respawn or changed summon count")
for _, unit in ipairs(h.created) do if unit.dead then unit.null = true end end
h.advance(11.3)
assert(h.task_count() == 0, "No synchronization/expiry tasks after all summons finish")

-- Reset and player defeat release live summons and cancel their former work.
local h2 = fixture()
local reset_hero = h2.hero(0, "npc_dota_hero_drow_ranger", combat_values(10, 20, 1, 100, 0), 2)
local reset_summon = h2.spawn(0, "skill_drow_companion")
local reset_expiry = h2.expiry_callback()
h2.service.init({ deal_group = function() end })
assert(not reset_summon:IsAlive() and h2.task_count() == 0, "Reset must release old entities and timers")
local current_summon = h2.spawn(0, "skill_drow_companion")
reset_expiry()
assert(current_summon:IsAlive(), "Previous initialization's expiry cannot kill current summon")
h2.bus.emit(events.PLAYER_DEFEATED, { player_id = 0 })
h2.advance(0.1)
assert(not current_summon:IsAlive() and not h2.service.summon_locked(reset_hero, "skill_drow_companion"))
assert(h2.task_count() == 0 and #h2.cosmetic_clears >= 2, "Defeat/reset must clear cloned appearance too")

-- Temporary engine-read failure uses the matching snapshot; cleanup stays private.
local h3 = fixture()
local first_source = h3.hero(0, "npc_dota_hero_doom_bringer", combat_values(50, 60, 2, 1000, 10), 2)
local second_source = h3.hero(1, "npc_dota_hero_drow_ranger", combat_values(70, 80, 3, 1200, 20), 3)
local first_summon = h3.spawn(0, "skill_doom_infernal")
local second_summon = h3.spawn(1, "skill_drow_companion")
function first_source:GetAttacksPerSecond() error("Transient native getter unavailable") end
h3.stats[0].attack_speed = 4
h3.advance(0.1)
near(first_summon:GetAttacksPerSecond(false), 4, "Matching snapshot fallback")
h3.bus.emit(events.PLAYER_DISCONNECTED, { player_id = 0 })
assert(not first_summon:IsAlive() and second_summon:IsAlive(),
    "Disconnect must remove only this player's summon")
second_source.null = true
h3.advance(0.2)
assert(not second_summon:IsAlive() and h3.task_count() == 0,
    "An invalid source must retire its summon and final shared timer")

-- The ten-second deadline ends combat immediately while the dressed corpse
-- remains until the engine removes it. Its cleanup cannot touch a new summon.
local h4 = fixture()
local corpse_source = h4.hero(0, "npc_dota_hero_drow_ranger",
    combat_values(100, 120, 2, 1000, 20), 2)
local expired = h4.spawn(0, "skill_drow_companion")
local expired_callback = h4.expiry_callback()
h4.advance(9.99)
assert(expired:IsAlive() and expired.appearance_active)
h4.advance(10)
assert(expired.dead and expired.kill_count == 1 and expired.death_has_appearance,
    "The full mirrored appearance must still exist when ForceKill starts the death animation")
assert(expired.appearance_active and h4.clear_count(expired) == 0 and not expired.hidden,
    "Expiry must preserve the visible corpse instead of stripping or hiding its death animation")
assert(not h4.service.summon_locked(corpse_source, "skill_drow_companion"),
    "A dressed corpse must not keep the skill locked")
local corpse_callbacks = {}
for _, task in pairs(h4.tasks) do corpse_callbacks[#corpse_callbacks + 1] = task.callback end
local successor = h4.spawn(0, "skill_drow_companion")
local previous_corpse_model = expired.model
corpse_source.model, corpse_source.appearance_version = "changed_after_death.vmdl", 2
h4.emit_stats(0)
h4.bus.emit(events.HERO_COSMETICS_CHANGED, { player_id = 0, unit = corpse_source })
assert(successor.appearance_version == 2 and expired.appearance_version == 1,
    "a cosmetic commit must immediately update the live successor without changing corpse appearance")
h4.advance(10.3)
assert(successor.appearance_version == 2 and successor.model == corpse_source.model)
assert(expired.appearance_version == 1 and expired.model == previous_corpse_model,
    "Dead summons must leave appearance synchronization while retaining their final appearance")
expired.null = true
h4.advance(11)
assert(h4.clear_count(expired) == 1 and h4.clear_count(successor) == 0
    and successor:IsAlive() and successor.appearance_active,
    "Final corpse cleanup must release only the original summon exactly once")
expired_callback()
for _, callback in ipairs(corpse_callbacks) do callback() end
assert(h4.clear_count(expired) == 1 and successor:IsAlive() and successor.appearance_active,
    "Late expiry/corpse callbacks must not clear or undress a newer summon")
h4.advance(20)
assert(successor.dead and successor.death_has_appearance and h4.clear_count(successor) == 0)
successor.null = true
h4.advance(21)
assert(h4.clear_count(successor) == 1 and h4.task_count() == 0,
    "Last corpse removal must release its resources and stop all summon work")

-- World reset must dispose both live summons and retained corpses safely, then
-- ignore callbacks already handed to the scheduler in the previous world.
local h5 = fixture()
h5.hero(0, "npc_dota_hero_drow_ranger", combat_values(10, 20, 1, 100, 0), 2)
local old_corpse = h5.spawn(0, "skill_drow_companion")
old_corpse.dead = true
h5.advance(0.1)
assert(old_corpse.appearance_active and h5.clear_count(old_corpse) == 0)
local old_live = h5.spawn(0, "skill_drow_companion")
local old_world_callbacks = {}
for _, task in pairs(h5.tasks) do old_world_callbacks[#old_world_callbacks + 1] = task.callback end
h5.service.init({ deal_group = function() end })
assert(h5.clear_count(old_corpse) == 1 and h5.clear_count(old_live) == 1
    and not old_live:IsAlive() and h5.task_count() == 0,
    "World reset must hide/remove both live and dead bodies before releasing every cloned cosmetic")
local fresh = h5.spawn(0, "skill_drow_companion")
for _, callback in ipairs(old_world_callbacks) do callback() end
assert(fresh:IsAlive() and fresh.appearance_active and h5.clear_count(fresh) == 0,
    "Old world's combat, expiry and corpse callbacks must leave the fresh world untouched")
assert(h5.clear_count(old_corpse) == 1 and h5.clear_count(old_live) == 1,
    "Late callbacks must not double release former-world cosmetics")
h5.bus.emit(events.PLAYER_DEFEATED, { player_id = 0 })
assert(not fresh:IsAlive() and h5.clear_count(fresh) == 1 and h5.task_count() == 0)

-- Some native NPC handles survive their visible death animation. A bounded
-- tail must remove the complete body before releasing its cosmetics, too.
local h6 = fixture()
h6.hero(0, "npc_dota_hero_drow_ranger", combat_values(10, 20, 1, 100, 0), 2)
local persistent_corpse = h6.spawn(0, "skill_drow_companion")
persistent_corpse.dead = true
h6.advance(0.1)
assert(persistent_corpse.appearance_active and not persistent_corpse.hidden)
h6.advance(5)
assert((persistent_corpse.hidden or persistent_corpse.null)
    and h6.clear_count(persistent_corpse) == 1 and h6.task_count() == 0,
    "A persistent corpse handle must not leak cloned props, particles or polling tasks")

-- Tools can reuse entity indexes after replacing the GameMode entity. Both
-- teardown and retained callbacks must respect that actual world boundary.
local h7 = fixture()
h7.hero(0, "npc_dota_hero_drow_ranger", combat_values(10, 20, 1, 100, 0), 2)
local departed_corpse = h7.spawn(0, "skill_drow_companion")
departed_corpse.dead = true
h7.advance(0.1)
local departed_live = h7.spawn(0, "skill_drow_companion")
local departed_callbacks, native_calls = {}, #h7.lifecycle
for _, task in pairs(h7.tasks) do departed_callbacks[#departed_callbacks + 1] = task.callback end
h7.world = {}
h7.serial = 100
h7.service.init({ deal_group = function() end })
assert(#h7.lifecycle == native_calls and departed_corpse.appearance_forgotten
    and departed_live.appearance_forgotten and h7.task_count() == 0,
    "Entering a new map must forget old ownership without mutating old native handles")
h7.hero(0, "npc_dota_hero_drow_ranger", combat_values(30, 40, 2, 200, 0), 3)
local reused_index = h7.spawn(0, "skill_drow_companion")
assert(reused_index.index == departed_corpse.index,
    "The fixture must actually recycle the old corpse's entity index")
for _, callback in ipairs(departed_callbacks) do callback() end
assert(reused_index:IsAlive() and reused_index.appearance_active
    and h7.clear_count(reused_index) == 0
    and h7.clear_count(departed_corpse) == 1 and h7.clear_count(departed_live) == 1,
    "Departed-world callbacks must neither clear the reused index nor repeat native cleanup")
h7.bus.emit(events.PLAYER_DEFEATED, { player_id = 0 })
assert(not reused_index:IsAlive() and h7.clear_count(reused_index) == 1 and h7.task_count() == 0)

-- Logical hero values must survive native int32 limits and remain independent
-- of the bounded engine cache. Test both summon types and live scale changes.
for _, skill_id in ipairs({ "skill_drow_companion", "skill_doom_infernal" }) do
    local large = fixture()
    local values = combat_values(11110000000, 22220000000, 10, 9000000000, 50)
    values.strength, values.agility, values.intellect = 19000, 20000, 21000
    large.hero(0, "source", values, 10)
    local publications = 0
    large.bus.subscribe(events.UNIT_COMBAT_STATS_CHANGED, function(payload)
        local unit = large.created[#large.created]
        assert(payload.entindex == unit:entindex()
            and unit.survival_exclusive_stat_snapshot,
            "HUD publication must follow snapshot creation for the exact entity")
        publications = publications + 1
    end)
    local summon = large.spawn(0, skill_id)
    near(summon.attack_min, 50000000, "Bounded native minimum")
    near(summon.attack_max, 100000000, "Bounded native maximum")
    near(summon.survival_exclusive_stat_snapshot.attack_min, 11110000000,
        "Unscaled logical attack")
    near(summon.survival_exclusive_stat_snapshot.agility, 20000, "Logical agility")
    near(summon.survival_exclusive_stat_snapshot.strength, 19000, "Logical strength")
    near(summon.survival_exclusive_stat_snapshot.intellect, 21000, "Logical intellect")
    local projection = require("combat/endless_stat_projection")
    near(projection.outgoing(summon, summon.attack_min, true), 11110000000,
        "Damage projection restores actual minimum")
    summon.health = 40000000
    local writes = summon.health_writes
    large.advance(0.2)
    assert(publications == 1, "Unchanged polling must not repeatedly publish stats")
    values.attack_min, values.attack_max = 4500000000000000, 9000000000000000
    values.max_health, values.agility = 18000000000, 21000
    large.emit_stats(0)
    assert(publications == 2, "Logical changes publish even when engine projection is identical")
    near(summon.attack_max, 100000000, "Updated enormous native damage stays bounded")
    near(projection.outgoing(summon, summon.attack_max, true), 9000000000000000,
        "Updated actual damage follows source")
    near(tonumber(projection.for_ui(summon, summon:GetHealth(), "health")),
        7200000000, "Logical health preserves damaged ratio when scale changes")
    near(summon.survival_exclusive_stat_snapshot.agility, 21000, "Live logical attribute update")
    assert(summon.health_writes == writes, "Scale-only change cannot refill health")
    values.attack_min, values.attack_max, values.max_health = 100, 200, 1000
    large.emit_stats(0)
    near(summon.attack_min, 100, "Returning below native cap restores ordinary damage")
    near(summon.survival_endless_attack_scale, 1, "No stale attack multiplier")
    near(summon.health, 400, "Returning below cap preserves health fraction")
    large.bus.emit(events.PLAYER_DEFEATED, { player_id = 0 })
end

print("EXCLUSIVE_SUMMON_SYNC_PASS: live logical stats and huge damage projection, fixed/runtime APS, no health refill, health ratio, Drow appearance boundary, same-team player/entity isolation, unchanged ten-second lifetime/count, dressed death/expiry, independent corpse cleanup, death/replacement/reset/defeat and stale timers")

local removed = fixture()
local deleted_source = removed.hero(0, "drow", combat_values(100, 120, 2, 1000, 0), 2)
removed.hero(1, "doom", combat_values(200, 220, 3, 2000, 0), 3)
local dead_companion = removed.spawn(0, "skill_drow_companion")
dead_companion:ForceKill(false)
removed.advance(0.1)
local live_companion = removed.spawn(0, "skill_drow_companion")
local other_infernal = removed.spawn(1, "skill_doom_infernal")
deleted_source.removed = true
removed.bus.emit(events.HERO_REMOVED, {player_id = 0, unit = deleted_source})
assert(removed.clear_count(dead_companion) == 1 and removed.clear_count(live_companion) == 1)
assert(not live_companion:IsAlive() and other_infernal:IsAlive())
removed.hero(0, "drow", combat_values(300, 320, 4, 3000, 0), 4)
local next_companion = removed.spawn(0, "skill_drow_companion")
removed.bus.emit(events.HERO_REMOVED, {player_id = 0, unit = deleted_source})
assert(next_companion:IsAlive() and next_companion.appearance_active and other_infernal:IsAlive())
print("EXCLUSIVE_SUMMON_HERO_REMOVAL_PASS invalid source, live summon+corpse retirement, player isolation, resummon, stale removal")
