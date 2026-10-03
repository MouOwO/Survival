-- Real hero runner, native visual helper, scheduler and tower storm module.
-- Mocked renderer: resource children and in-game appearance need separate checks.
package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x, y, z) return {x=x, y=y, z=z} end
local now, particles, hits, marked, mark_calls, sounds = 0, {}, {}, {}, {}, {}
local failure, create_attempts, kill_first = "none", {}, false
GameRules = {GetGameTime=function() return now end}
PATTACH_WORLDORIGIN = 6; PATTACH_ABSORIGIN = 0; PATTACH_ABSORIGIN_FOLLOW = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 1; DOTA_UNIT_TARGET_HERO = 2; DOTA_UNIT_TARGET_BASIC = 4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 8; FIND_CLOSEST = 1; DAMAGE_TYPE_PURE = 4
GetGroundPosition = function(p) return Vector(p.x, p.y, 384) end
local function forbidden() error("visual must not cast native abilities, issue orders or apply damage") end
ApplyDamage, ExecuteOrderFromTable, CreateUnitByName = forbidden, forbidden, forbidden
local function unit(id, team)
    local u = {id=id, team=team, alive=true, origin=Vector(id, 80, 454)}
    function u:entindex() return self.id end
    function u:IsNull() return self.null == true end
    function u:IsAlive() return self.alive end
    function u:GetTeamNumber() return self.team end
    function u:GetAbsOrigin() return self.origin end
    function u:FindAbilityByName() return {} end
    u.CastAbilityNoTarget, u.CastAbilityOnTarget = forbidden, forbidden
    return u
end
local caster, target, second, third, outside, friendly = unit(10,2), unit(20,3), unit(30,3), unit(40,3), unit(500,3), unit(50,2)
local enemy_pool = {target}
FindUnitsInRadius = function(team, position, _, radius)
    assert(radius == 400, "hero splash keeps its 400-unit gameplay radius")
    local result = {}
    for _, u in ipairs(enemy_pool) do
        local dx, dy = u.origin.x-position.x, u.origin.y-position.y
        if u.alive and u.team ~= team and dx*dx + dy*dy <= radius*radius then result[#result+1] = u end
    end
    return result
end
package.loaded["systems/buff_manager"] = {
    apply=function(source, victim, id, params)
        assert(source == caster and id == "debuff_hero_fury_thunder_mark" and params.duration == 3)
        marked[victim] = {expires=now+params.duration, value=params.value}
        mark_calls[#mark_calls+1] = {victim=victim, time=now, value=params.value, duration=params.duration}
    end,
    has=function(victim, id)
        assert(id == "debuff_hero_fury_thunder_mark")
        return marked[victim] and marked[victim].expires > now
    end,
    remove=function() end,
}
package.loaded["systems/hero_exclusive_passive_service"] = {runners={}, init=function() end}
package.loaded["core/sound_service"] = {
    play=function(id, payload)
        assert(id == "hero_fury_thunder_strike" and payload.source == caster)
        sounds[#sounds+1] = {time=now, position=payload.position}
    end,
    reset=function() end,
}
local config = require("config/generated/tower_lightning_effects").by_id
local hero_main, hero_cast = config.hero_strike.particle_name, config.hero_strike.cast_particle
assert(hero_main == "particles/econ/items/zeus/lightning_weapon_fx/zuus_lightning_bolt_immortal_lightning.vpcf")
assert(hero_cast == "particles/econ/items/zeus/lightning_weapon_fx/zuus_lb_cfx_il.vpcf")
assert(config.strike.particle_name:find("disruptor_2022_immortal_static_storm", 1, true), "tower retains the immortal Disruptor storm")
ParticleManager = {
    CreateParticle=function(_, name, attach, owner)
        create_attempts[name] = (create_attempts[name] or 0) + 1
        local role = name == hero_main and "main" or name == hero_cast and "cast" or "storm"
        if failure == role.."_create_throw" then error("injected creation failure") end
        if failure == role.."_create_nil" then return nil end
        local id = #particles+1
        particles[id] = {name=name, cp={}, bindings={}, cp_order={}, operation=0, attach=attach, owner=owner, time=now}
        return id
    end,
    SetParticleControlEnt=function(_, id, cp, victim, attach, attachment, position, lock)
        if failure == "main_binding" then error("injected model binding failure") end
        assert(cp == 1 and attach == PATTACH_ABSORIGIN and attachment == "" and lock == true)
        local p = particles[id]; p.operation=p.operation+1
        p.bindings[cp] = {unit=victim, attach=attach, position=position, order=p.operation}
    end,
    SetParticleControl=function(_, id, cp, value)
        local role = particles[id].name == hero_main and "main" or particles[id].name == hero_cast and "cast" or "storm"
        if failure == role.."_control" then error("injected optional visual control failure") end
        local p = particles[id]; p.operation=p.operation+1
        p.cp[cp]=value; p.cp_order[cp]=p.operation
    end,
    DestroyParticle=function(_, id, immediate)
        local p = assert(particles[id]); assert(not p.destroyed, "destroy exactly once")
        p.destroyed=true; p.immediate=immediate
    end,
    ReleaseParticleIndex=function(_, id)
        local p = assert(particles[id]); assert(not p.released, "release exactly once")
        p.released=1
    end,
}
local bus = require("core/event_bus"); bus.reset()
bus.handle_request(require("combat/combat_events").DEAL_REQUEST, function(p)
    assert(p.damage_type == DAMAGE_TYPE_PURE and p.can_crit == false and p.tags.source_skill_id == "proto_chain_lightning")
    hits[#hits+1] = {amount=p.base_damage, time=now, victim=p.victim,
        secondary=p.tags.is_secondary_effect, particle_count=#particles}
    if kill_first and #hits == 1 then p.victim.alive=false end
    return {ok=true}
end)
local service = require("systems/hero_passive_skill_service")
local scheduler = require("core/scheduler")
local storm = require("systems/disruptor_storm_visual")
local zeus = require("systems/zeus_lightning_visual")
local definition = require("config/hero_passive_skill_definitions").by_id.proto_chain_lightning
local function reset(mode, pool)
    storm.clear(); scheduler.clear()
    now, particles, hits, marked, mark_calls, sounds, create_attempts = 0, {}, {}, {}, {}, {}, {}
    failure, kill_first, enemy_pool = mode or "none", false, pool or {target}
    for _, u in ipairs({caster,target,second,third,outside,friendly}) do
        u.alive=true; u.null=false; u.origin=Vector(u.id,80,454)
    end
end
local function run(level)
    service._test.runners.proto_chain_lightning({attacker=caster,target=target,player_id=0,
        skill_id="proto_chain_lightning",attack_id="test",level=level,attributes={all_attributes=100}}, definition)
    assert(scheduler.task_count() == (level == 5 and 2 or 0), "only existing delayed damage strikes may create tasks")
    now=0.12; scheduler.think(); now=0.24; scheduler.think()
    assert(scheduler.task_count() == 0, "released native W visuals create no timers")
end
local function total(victim)
    local result = 0
    for _, hit in ipairs(hits) do if not victim or victim == hit.victim then result=result+hit.amount end end
    return result
end
local function vector_equal(value, expected)
    assert(value and value.x == expected.x and value.y == expected.y and value.z == expected.z)
end
local function assert_main(p, victim, position)
    assert(p.name == hero_main and p.owner == nil and p.attach == PATTACH_WORLDORIGIN)
    assert(p.released == 1 and not p.destroyed, "main root is released naturally, preserving its native ground children")
    assert(p.bindings[1].unit == victim and p.bindings[1].attach == PATTACH_ABSORIGIN,
        "model electricity samples the victim without a FOLLOW ground attachment")
    assert(p.cp_order[1] > p.bindings[1].order, "fixed impact CP1 must be written after one-time model sampling")
    vector_equal(p.cp[0], Vector(position.x,position.y,position.z+4000))
    vector_equal(p.cp[1], position); vector_equal(p.cp[3], position)
    assert(p.cp[2] == nil, "hero bolt must not receive the tower storm radius/duration controls")
end

local failure_modes = {"none", "main_create_throw", "main_create_nil", "main_binding", "main_control",
    "cast_create_throw", "cast_create_nil", "cast_control"}
local roots_per_strike = {none=2, main_create_throw=0, main_create_nil=0, main_binding=1,
    main_control=1, cast_create_throw=1, cast_create_nil=1, cast_control=2}
for level=1,5 do
    for _, mode in ipairs(failure_modes) do
        reset(mode); run(level)
        local strikes = level == 5 and 3 or 1
        assert(total() == (level == 5 and 900 or 300), "visual failure must preserve fury damage and repeated-hit/mark rules")
        assert(#hits == (level == 5 and 5 or 1))
        if level == 5 then
            for index, expected in ipairs({{300,0},{150,0.12},{150,0.12},{150,0.24},{150,0.24}}) do
                assert(hits[index].amount == expected[1] and hits[index].time == expected[2])
            end
            assert(hits[2].secondary == false and hits[3].secondary == true, "repeat half damage and mark bonus remain separate settlements")
        end
        assert(#particles == strikes * roots_per_strike[mode], "each actual hit has an independent W bundle")
        assert(create_attempts[hero_main] == strikes and #sounds == strikes)
        if mode:find("^main_") then assert(not create_attempts[hero_cast], "main failure must not launch cast art")
        else assert(create_attempts[hero_cast] == strikes) end
        for _, p in ipairs(particles) do
            assert(p.owner == nil and p.attach == PATTACH_WORLDORIGIN and p.released == 1)
            local failed = (mode == "main_binding" or mode == "main_control") and p.name == hero_main
                or mode == "cast_control" and p.name == hero_cast
            assert((p.destroyed == true) == failed, "only failed partial effects are destroyed")
            if failed then assert(p.immediate == true)
            elseif p.name == hero_main then assert_main(p, target, target.origin)
            else assert(p.name == hero_cast); vector_equal(p.cp[0], caster.origin) end
        end
        if level == 1 then assert(#mark_calls == 0)
        else
            assert(#mark_calls == strikes)
            for _, mark in ipairs(mark_calls) do assert(mark.value == (level >= 3 and -15 or 0)) end
            assert(marked[target].expires == (level == 5 and 3.24 or 3), "every hit refreshes the original three-second mark")
        end
        now=10; scheduler.think()
        assert(#particles == strikes * roots_per_strike[mode] and scheduler.task_count() == 0)
        for _, p in ipairs(particles) do assert(p.released == 1) end
    end
end

-- A partial Tools reload can leave the shared selector without its new helper.
-- Both a missing helper and an unexpected optional exception stay cosmetic.
local original_bolt = zeus.bolt
for _, level in ipairs({1,5}) do
    for _, unavailable in ipairs({"missing", "throwing"}) do
        reset()
        if unavailable == "missing" then zeus.bolt = nil
        else zeus.bolt = function() error("injected helper exception") end end
        run(level)
        assert(total() == (level == 5 and 900 or 300) and #particles == 0,
            "unavailable optional bolt helper must preserve all damage settlements")
    end
end
zeus.bolt = original_bolt

-- Existing mark bonus and 400-radius splash are independent of native W art.
reset(); marked[target] = {expires=1, value=0}; run(2)
assert(total() == 450 and #hits == 2 and marked[target].expires == 3)
reset(); marked[target] = {expires=0, value=-15}; run(3)
assert(total() == 300 and marked[target].value == -15, "expired marks do not grant bonus damage")
reset("none", {target,second,third,outside,friendly}); run(1)
assert(total(target) == 300 and total(second) == 150 and total(third) == 150 and total() == 600)
assert(total(outside) == 0 and total(friendly) == 0 and #mark_calls == 0 and #particles == 2)
reset("none", {target,second,third,outside,friendly}); run(5)
assert(total(target) == 900 and total(second) == 900 and total(third) == 900 and total() == 2700)
assert(#hits == 15 and #mark_calls == 9 and #particles == 6, "distinct targets retain full strike damage, mark refresh and splash")
for index, victim in ipairs({target,second,third}) do assert_main(particles[index*2-1], victim, victim.origin) end
assert(total(outside) == 0 and total(friendly) == 0)
reset("none", {target,second}); run(5)
assert(total(target) == 900 and total(second) == 825 and total() == 1725,
    "third strike returning to the primary keeps half base damage and half splash, with unchanged mark bonus")

-- Fatal first damage retains already released world roots; later dead-target
-- strikes keep the original skip behavior. Moving/recycling units cannot drag CPs.
reset(); kill_first=true
local target_snapshot, caster_snapshot = Vector(20,80,454), Vector(10,80,454)
run(5)
assert(#hits == 1 and hits[1].amount == 300 and hits[1].particle_count == 2 and #particles == 2,
    "both native roots exist before fatal settlement, without phantom later strikes")
target.origin.x, target.origin.y, target.origin.z = 9000,9000,-6000
caster.origin.x, caster.origin.y, caster.origin.z = -9000,-9000,-6000
target.null=true; caster.alive=false
assert_main(particles[1], target, target_snapshot)
vector_equal(particles[2].cp[0], caster_snapshot)
now=30; scheduler.think()
assert(#particles == 2 and not particles[1].destroyed and not particles[2].destroyed)

reset(); config.hero_strike.enabled=false; run(5); config.hero_strike.enabled=true
assert(total() == 900 and #particles == 0, "disabling optional hero art cannot disable damage")

-- Tower module retains its exact radius, duration, reuse and natural endcap.
reset(); now=2
local a = storm.play(caster,Vector(1,2,500),125,2)
local b = storm.play(caster,Vector(50,60,500),750,3)
assert(#particles == 2 and particles[1].name == config.strike.particle_name and particles[2].name == config.strike.particle_name)
assert(particles[1].owner == caster and particles[1].cp[0].z == 384)
assert(particles[1].cp[1].x == 125 and particles[2].cp[1].x == 750 and particles[1].cp[2].x == 2 and particles[2].cp[2].x == 3)
assert(storm.play(caster,Vector(90,100,500),125,2,a) == a and #particles == 2,
    "tower storms still reuse the same native system when requested")
service.init()
assert(not particles[1].destroyed and not particles[2].destroyed and scheduler.task_count() == 2,
    "hero reset no longer clears independently owned tower storms")
now=3.99; scheduler.think(); assert(not particles[1].destroyed)
now=4; scheduler.think(); assert(particles[1].destroyed and particles[1].released == 1 and particles[1].immediate == false)
assert(not particles[2].destroyed)
now=5; scheduler.think(); assert(particles[2].destroyed and particles[2].released == 1 and particles[2].immediate == false)
storm.clear(); storm.clear(); assert(scheduler.task_count() == 0)
reset("storm_control")
assert(storm.play(caster,Vector(1,2,500),125,2) == nil and #particles == 1)
assert(particles[1].destroyed and particles[1].released == 1 and scheduler.task_count() == 0)
storm.clear(); storm.clear()

-- The hero row never alters rank-based tower attacks, and every native root
-- (including the cast root) reaches the existing deduplicated precache loop.
caster.survival_building_id = "arrow_tower"
for level=6,25 do
    caster.survival_level=level
    local expected = level <= 10 and "original" or level <= 15 and config.SR.particle_name or config.SSR.particle_name
    assert(zeus.chain_particle(caster,"original") == expected)
end
caster.survival_building_id="ultimate_tower"; caster.survival_level=1
assert(zeus.chain_particle(caster,"original") == config.SSR.particle_name)
local precached, context = {}, {}
PrecacheResource = function(...)
    assert(select('#',...) == 3)
    local kind, name, actual = ...
    assert(kind == "particle" and actual == context and not precached[name]); precached[name]=true
end
zeus.precache(context)
for _, row in pairs(config) do
    for _, key in ipairs({"particle_name","impact_particle","cast_particle"}) do
        if row[key] and row[key] ~= "" then assert(precached[row[key]]) end
    end
end
assert(precached[hero_main] and precached[hero_cast] and precached[config.strike.particle_name])
local cue = require("config/generated/hero_skill_sound_definitions").by_id.hero_fury_thunder_strike
assert(cue.sound_event == "Hero_Zuus.LightningBolt.Righteous" and cue.cooldown_seconds == 0.08
    and cue.max_plays_per_window == 3 and cue.window_seconds == 0.5
    and cue.max_concurrent == 2 and cue.concurrency_seconds == 0.3)
print("HERO_ZEUS_BOLT_VISUAL_PASS: five fury tiers, 40 normal/engine-failure and four missing/throwing-helper cases, independent triple W roots, damage/timing/marks/splash, lethal world snapshots, natural release/no visual timers, tower storm isolation, native precache and sound limits; game visuals not validated")
