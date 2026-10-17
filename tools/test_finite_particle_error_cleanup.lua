-- Full production modules; only native APIs are mocked. No extracted source seam.
package.path = "scripts/vscripts/?.lua;" .. package.path
local output = print
local cases, assertions = 0, 0
local function check(condition, message)
    assertions = assertions + 1
    assert(condition, message)
end
local paths = {
    triggered = "particles/units/heroes/hero_warlock/warlock_rain_of_chaos_explosion.vpcf",
    wall = "particles/units/heroes/hero_rattletrap/rattletrap_cog_attack_impact.vpcf",
    gold_efficiency = "particles/units/heroes/hero_omniknight/omniknight_purification.vpcf",
    gold_crit = "particles/units/heroes/hero_phantom_assassin/phantom_assassin_crit_impact.vpcf",
    axe = "particles/units/heroes/hero_axe/axe_attack_blur_counterhelix.vpcf",
    flame = "particles/units/heroes/hero_lina/lina_spell_light_strike_array.vpcf",
    poison = "particles/basic_explosion/basic_explosion.vpcf",
}
local invalid_values = {
    {name = "nil"}, {name = "negative", value = -1},
    {name = "false", value = false}, {name = "string", value = "particle"},
    {name = "nan", value = 0 / 0}, {name = "fraction", value = 0.5},
    {name = "infinite", value = math.huge},
}
local function reset_modules()
    local names = {}
    for name in pairs(package.loaded) do
        if name:match("^systems/") or name:match("^core/")
            or name:match("^combat/") or name:match("^config/")
            or name:match("^visual/") then names[#names + 1] = name end
    end
    for _, name in ipairs(names) do package.loaded[name] = nil end
end
local function harness(kind, fault, real_proxy)
    reset_modules()
    local h = {kind = kind, fault = fault or {}, real_proxy = real_proxy,
        clock = 100, logs = {}, particles = {}, deals = {}, proc_events = {},
        native_calls = {}, creates = 0, sounds = 0, serial = 0}
    Vector = function(x, y, z) return {x = x, y = y, z = z or 0} end
    PATTACH_WORLDORIGIN, PATTACH_ABSORIGIN_FOLLOW = 0, 1
    DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 2, 4
    DOTA_UNIT_TARGET_FLAG_NONE, DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 0, 8
    FIND_ANY_ORDER, FIND_CLOSEST = 0, 1
    DAMAGE_TYPE_MAGICAL, DAMAGE_TYPE_PURE = 2, 4
    GameRules = {GetGameTime = function() return h.clock end,
        GetGameModeEntity = function(self) return self end}
    PlayerResource = nil
    CustomGameEventManager = {RegisterListener = function() end}
    RandomFloat = function() return 0 end
    print = function(message) h.logs[#h.logs + 1] = tostring(message) end
    local function unit(id, team, x)
        return {alive = true, IsNull = function() return false end,
            IsAlive = function(self) return self.alive end,
            entindex = function() return id end,
            GetTeamNumber = function() return team end,
            GetAbsOrigin = function() return Vector(x or 0, 0, 64) end,
            GetHullRadius = function() return 24 end,
            FindAbilityByName = function() return nil end,
            EmitSound = function() h.sounds = h.sounds + 1 end}
    end
    h.unit = unit
    h.attacker, h.target = unit(1, 2, -200), unit(2, 3, 0)
    h.enemies = {unit(3, 3, 40), unit(4, 3, 50)}
    FindUnitsInRadius = function() return h.enemies end
    h.particles[700000] = {path = "unrelated_owned_particle", destroys = 0,
        releases = 0, owned = true, controls = {}}
    local next_id = 0
    local manager = {}
    function manager:CreateParticle(path, attach, owner)
        if path == paths[kind] then
            h.creates = h.creates + 1
            if h.fault.kind == "create" then error("injected_create_error", 0) end
            if h.fault.kind == "invalid" then return h.fault.value end
        end
        local id = next_id
        next_id = next_id + 1
        h.particles[id] = {path = path, attach = attach, owner = owner,
            destroys = 0, releases = 0, owned = true, controls = {}, writes = {}}
        if path == paths[kind] then h.last_id = id end
        return id
    end
    function manager:SetParticleControl(id, cp, position)
        h.native_calls[#h.native_calls + 1] = {method = "control", id = id}
        local particle = h.particles[id]
        if not particle then error("invalid_particle_handle", 0) end
        particle.writes[cp] = (particle.writes[cp] or 0) + 1
        if particle.path == paths[kind] and h.fault.control == cp then
            if h.fault.replace_manager then ParticleManager = h.other_manager end
            error("injected_control_error", 0)
        end
        particle.controls[cp] = position
    end
    function manager:DestroyParticle(id, immediate)
        h.native_calls[#h.native_calls + 1] = {method = "destroy", id = id}
        local particle = assert(h.particles[id], "destroy must target an owned native ID")
        particle.destroys = particle.destroys + 1
        particle.immediate = immediate
        check(immediate == true, "failed finite effects must stop immediately")
        check(particle.destroys == 1, "finite particle destruction must not repeat")
        if particle.path == paths[kind] and h.fault.destroy then
            error("injected_destroy_error", 0)
        end
    end
    function manager:ReleaseParticleIndex(id)
        h.native_calls[#h.native_calls + 1] = {method = "release", id = id}
        local particle = assert(h.particles[id], "release must target an owned native ID")
        particle.releases = particle.releases + 1
        particle.owned = false -- Model the native side effect preceding an exception.
        check(particle.releases == 1, "released IDs must never be released again")
        if particle.path == paths[kind] and h.fault.release then
            error("injected_release_error", 0)
        end
    end
    h.other_calls = 0
    h.other_manager = setmetatable({}, {__index = function()
        return function() h.other_calls = h.other_calls + 1; error("wrong_manager", 0) end
    end})
    ParticleManager, h.manager = manager, manager
    if not real_proxy then
        package.loaded["systems/combat_effect_visibility"] = {manager = function() return manager end}
    else
        h.visibility = require("systems/combat_effect_visibility")
        h.visibility.init()
    end
    h.bus, h.events = require("core/event_bus"), require("core/events")
    local combat_events = require("combat/combat_events")
    h.bus.handle_request(h.events.HERO_COMBAT_STATS_GET_REQUEST, function()
        return {snapshot = {strength = 10, agility = 20, intellect = 30}}
    end)
    h.bus.handle_request(combat_events.DEAL_REQUEST, function(payload)
        h.deals[#h.deals + 1] = payload
        return {success = true}
    end)
    local skill = kind == "axe" and "skill_axe_counter_helix"
        or kind == "poison" and "proto_poison_cloud" or "proto_flame_burst"
    h.bus.handle_request(h.events.HERO_SKILL_STATE_GET_REQUEST, function()
        return {snapshot = {skills = {{skill_id = skill, level = kind == "poison" and 5 or 1}}}}
    end)
    h.bus.handle_request(h.events.EQUIPMENT_EFFECT_SNAPSHOT_GET_REQUEST, function()
        return {snapshot = {enabled = true, sources = {{source_id = "finite_regression",
            effects = {{effect_type = "proc_attribute_damage", value = {
                probability = 100, multiplier = 2.5, range = 500, internal_cooldown = 0}}}}}}}
    end)
    h.bus.subscribe(h.events.HERO_PASSIVE_SKILL_TRIGGERED, function(p) h.proc_events[#h.proc_events + 1] = p end)
    h.bus.subscribe(h.events.EQUIPMENT_PROC_TRIGGERED, function(p) h.proc_events[#h.proc_events + 1] = p end)
    local function attack()
        h.serial = h.serial + 1
        h.bus.emit(h.events.HERO_MAIN_ATTACK_LANDED, {player_id = 0, attacker = h.attacker,
            target = h.target, record = h.serial, attack_id = "finite:" .. h.serial,
            is_main_attack = true})
    end
    if kind == "triggered" then
        require("systems/triggered_proc_service").init()
        h.invoke = attack
    elseif kind == "wall" then
        local wall = require("systems/wall_hit_effect")
        h.wall = unit(9, 2, 0)
        h.invoke = function() h.clock = h.clock + 0.1; return wall.play(h.wall, h.attacker) end
    elseif kind == "gold_efficiency" or kind == "gold_crit" then
        local gold = require("systems/gold_mine_research_visual")
        h.invoke = function() return gold.play(h.attacker,
            kind == "gold_efficiency" and "gold_mine_efficiency" or "gold_mine_crit") end
    else
        h.hero = require("systems/hero_passive_skill_service")
        local sound = {play = function() h.sounds = h.sounds + 1 end, reset = function() end}
        h.hero.sound_service = sound
        require("systems/hero_exclusive_passive_service").sound_service = sound
        h.hero.init()
        if kind == "poison" then
            attack() -- Create the real level-5 persistent cloud through the public event.
            h.cloud = h.particles[0]
            check(h.cloud and h.cloud.owned and h.cloud.destroys == 0, "poison fixture owns its persistent cloud")
            h.target.alive = false
            h.invoke = function() h.bus.emit(h.events.ENGINE_ENTITY_KILLED, {victim = h.target}) end
        else h.invoke = attack end
    end
    h.baseline = h.visibility and h.visibility.debug_snapshot()
    return h
end
local function verify(kind, fault, real_proxy)
    local h = harness(kind, fault, real_proxy)
    local ok, err = pcall(h.invoke)
    local failing_control = h.fault.control ~= nil
    local direct = kind == "wall" or kind == "gold_efficiency" or kind == "gold_crit"
    local invalid = h.fault.kind == "invalid"
    local creating_failed = h.fault.kind == "create" or (real_proxy and invalid)
    local expected_error = direct and (creating_failed or invalid or failing_control or h.fault.release)
    check(ok ~= not not expected_error, "public API exception behavior changed: " .. kind)
    if expected_error then
        local expected = failing_control and "injected_control_error"
            or h.fault.kind == "create" and "injected_create_error"
            or invalid and "invalid_particle_handle" or "injected_release_error"
        check(tostring(err):find(expected, 1, true), "cleanup must preserve the original error")
    end
    local axe_stopped = kind == "axe" and not creating_failed
        and (failing_control or invalid or h.fault.release)
    local damage_count = (kind == "triggered" or kind == "flame" or kind == "poison"
        or (kind == "axe" and not axe_stopped)) and 2 or 0
    check(#h.deals == damage_count, "visual faults must preserve prior damage count: " .. kind)
    local base_damage = kind == "triggered" and 150 or kind == "flame" and 240
        or kind == "poison" and 180 or 1800
    for _, deal in ipairs(h.deals) do
        check(deal.base_damage == base_damage, "damage multiplier changed: " .. kind)
        check(deal.attacker == h.attacker and (deal.victim == h.enemies[1] or deal.victim == h.enemies[2]),
            "damage ownership or targets changed")
        check(deal.can_crit == false, "finite cleanup must not introduce critical damage")
    end
    if axe_stopped then
        local expected = invalid and "invalid_particle_handle"
            or failing_control and "injected_control_error" or "injected_release_error"
        local found
        for _, log in ipairs(h.logs) do
            if log:find("[EventBus] handler error", 1, true) and log:find(expected, 1, true) then found = true end
        end
        check(found and #h.proc_events == 0, "exclusive native error must still stop the proc and reach EventBus")
    elseif not direct then check(#h.proc_events == 1, "successful public proc emission changed") end
    if h.last_id ~= nil then
        local particle = h.particles[h.last_id]
        check(particle.releases == 1 and not particle.owned, "created finite particle must be released exactly once")
        check(particle.destroys == (failing_control and 1 or 0), "normal tails must not be destroyed")
        check(particle.owner == (kind == "wall" and h.wall or h.attacker), "particle owner changed")
        if kind == "gold_efficiency" or kind == "poison" then
            check(particle.writes[0] == 1, "first control must still be attempted once")
            if h.fault.control == 1 then check(particle.controls[0] ~= nil, "CP1 failure must follow a successful CP0") end
        end
    else
        for _, call in ipairs(h.native_calls) do
            check(call.method ~= "destroy" and call.method ~= "release",
                "failed Create or invalid ID must not destroy/release another resource")
        end
    end
    check(h.particles[700000].owned and h.particles[700000].destroys == 0
        and h.particles[700000].releases == 0, "unrelated particle must remain untouched")
    if h.cloud then check(h.cloud.owned and h.cloud.destroys == 0 and h.cloud.releases == 0,
        "death burst failure must not clean the persistent poison cloud") end
    if h.visibility then
        local after = h.visibility.debug_snapshot()
        check(after.owned_records == h.baseline.owned_records
            and after.owned_native_handles == h.baseline.owned_native_handles,
            "real visual proxy must return to its prior ownership baseline")
    end
    check(h.other_calls == 0, "cleanup must use the exact creating manager")
    if next(h.fault) == nil then
        local old_id = h.last_id
        local old = h.particles[old_id]
        if kind == "poison" then
            h.invoke()
            check(h.creates == 1 and #h.deals == 2, "duplicate native death must not duplicate the burst or damage")
            h.target = h.unit(22, 3, 0)
            h.target.alive = false
        end
        h.invoke()
        check(h.last_id ~= old_id and old.destroys == 0 and old.releases == 1,
            "later effects must never reuse or destroy an engine-owned finite tail")
        check(h.particles[h.last_id].destroys == 0 and h.particles[h.last_id].releases == 1,
            "later normal effect must retain its native tail")
    end
    cases = cases + 1
end
for _, kind in ipairs({"triggered", "wall", "gold_efficiency", "gold_crit", "axe", "flame", "poison"}) do
    for _, real_proxy in ipairs({false, true}) do
        verify(kind, {}, real_proxy)
        verify(kind, {kind = "create"}, real_proxy)
        verify(kind, {control = 0}, real_proxy)
        verify(kind, {control = 0, destroy = true}, real_proxy)
        verify(kind, {control = 0, release = true}, real_proxy)
        verify(kind, {control = 0, destroy = true, release = true}, real_proxy)
        verify(kind, {release = true}, real_proxy)
        if kind == "gold_efficiency" or kind == "poison" then
            verify(kind, {control = 1}, real_proxy)
            verify(kind, {control = 1, destroy = true, release = true}, real_proxy)
        end
        for _, invalid in ipairs(invalid_values) do
            -- The real visibility proxy already rejects nil/negative/non-number.
            -- Its native numeric check is type(number)/<0; NaN/fraction/inf are tested
            -- directly at these services, without broadening the proxy in this fix.
            if not real_proxy or invalid.name ~= "nan"
                and invalid.name ~= "fraction" and invalid.name ~= "infinite" then
                verify(kind, {kind = "invalid", value = invalid.value}, real_proxy)
            end
        end
    end
end
verify("wall", {control = 0, replace_manager = true}, false)
verify("gold_efficiency", {control = 1, replace_manager = true}, false)
print = output
output(string.format("FINITE_PARTICLE_CLEANUP_PASS cases=%d assertions=%d: full production services/public events, exact ownership, native tails, CP0/CP1 faults, Create/Destroy/Release faults, invalid IDs and real visibility proxy", cases, assertions))
