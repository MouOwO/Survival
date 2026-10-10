-- Exercise the real attack modifier with the configured visible hero bodies.
-- Native animation and native projectile simulation remain engine-owned;
-- this regression detects additional scripted cycles and premature arrows.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(base) base.__index = base; return base end
LinkLuaModifier = function() end
IsServer = function() return true end
LUA_MODIFIER_MOTION_NONE = 0
ACT_DOTA_ATTACK = 17
PATTACH_WORLDORIGIN = 2
PATTACH_ABSORIGIN_FOLLOW = 0
DAMAGE_TYPE_PHYSICAL = 1
DOTA_DAMAGE_CATEGORY_ATTACK = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 1
DOTA_UNIT_TARGET_HERO = 2
DOTA_UNIT_TARGET_BASIC = 4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 8
FIND_CLOSEST = 1
FIND_ANY_ORDER = 0
RollPercentage = function() return false end -- Isolate ordinary frost hits from random blizzards.

local clock, candidates = 0, {}
local emitted, gestures, projectiles, tasks, hits, particles, buffs = {}, {}, {}, {}, {}, {}, {}
GameRules = {GetGameTime = function() return clock end}
local function vector(x, y, z)
    local v = {x = x or 0, y = y or 0, z = z or 0}
    return setmetatable(v, {
        __sub = function(a, b) return vector(a.x-b.x, a.y-b.y, a.z-b.z) end,
        __index = {Length2D = function(a) return math.sqrt(a.x*a.x+a.y*a.y) end},
    })
end
Vector = vector
FindUnitsInRadius = function() return candidates end
ProjectileManager = {CreateTrackingProjectile = function(_, shot)
    projectiles[#projectiles+1] = shot; return #projectiles
end}
ParticleManager = {
    CreateParticle = function(_, name, attachment, owner)
        particles[#particles+1] = {name=name, attachment=attachment, owner=owner}
        return #particles
    end,
    SetParticleControl = function() end,
    ReleaseParticleIndex = function() end,
}
package.loaded["systems/combat_effect_visibility"] = {manager=function() return ParticleManager end}
package.loaded["core/event_bus"] = {emit=function(name, payload)
    emitted[#emitted+1] = {name=name, payload=payload}
end}
package.loaded["core/scheduler"] = {
    after=function(delay, callback, id)
        tasks[#tasks+1]={delay=delay, callback=callback}; return id or #tasks
    end,
    cancel=function() end,
}
package.loaded["combat/damage_service"] = {Deal=function(_, payload)
    hits[#hits+1]=payload; return {success=true,final_damage=payload.base_damage}
end}
package.loaded["systems/buff_manager"] = {
    apply=function(caster, target, name, options)
        buffs[#buffs+1]={caster=caster,target=target,name=name,options=options}
    end,
    value=function() return 0 end,
}
package.loaded["core/sound_service"] = {play=function() end}
package.loaded["systems/tower_skill_runtime"] = {get=function(unit) return unit.skills or {} end}
package.loaded["systems/tower_laser_effect_selector"] = {get=function() return nil end}
package.loaded["systems/disruptor_storm_visual"] = {particle_name=function() return "unused" end}
package.loaded["systems/zeus_lightning_visual"] = {}
package.loaded["systems/wyvern_blizzard_visual"] = {}
package.loaded["systems/tower_machine_gun_feedback"] = {}
package.loaded["systems/tower_damage_observer"] = {is_ready=function() return false end}
package.loaded["systems/tower_targeting"] = {valid=function(_,target) return target and target:IsAlive() end}
package.loaded["systems/tower_laser_damage"] = {}
package.loaded["systems/tower_laser_health_prediction"] = {}
package.loaded["systems/tower_laser_visual"] = {sync_pose=function() end}
package.loaded["systems/tower_attack_critical"] = {roll=function() return 1 end}

local catalog = require("config/asset_catalog")
local skills = require("config/generated/tower_skill_definitions")
local events = require("core/events")
if arg and arg[1] then
    package.preload["modifiers/modifier_tower_attack_effects"]=function() return dofile(arg[1]) end
end
local effects = require("modifiers/modifier_tower_attack_effects")
local function unit(id, team, x)
    local u = {id=id,team=team,position=vector(x,0,0),alive=true,skills={}}
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetTeamNumber() return self.team end
    function u:GetUnitName() return self.team==2 and "building_arrow_tower" or "npc_survival_wave_monster" end
    function u:GetAbsOrigin() return self.position end
    function u:GetAttackRange() return 800 end
    function u:GetAverageTrueAttackDamage() return 100 end
    function u:FindModifierByName() return nil end
    function u:StartGesture(activity) gestures[#gestures+1]={unit=self,activity=activity} end
    function u:StartGestureWithPlaybackRate(activity,rate)
        gestures[#gestures+1]={unit=self,activity=activity,rate=rate}
    end
    function u:PerformAttack() error("ordinary tower release must not grant another native attack") end
    function u:SetRangedProjectileName(name) self.projectile_name=name end
    return u
end
local primary, secondary = unit(2,3,200),unit(3,3,300)
local function reset()
    emitted,gestures,projectiles,tasks,hits,particles,buffs={},{},{},{},{},{},{}
    candidates={primary,secondary}; primary.alive=true; clock=clock+1
end
local function fixture(row, route)
    reset()
    local tower=unit(1,2,0)
    tower.survival_model_asset_id=row.model_asset_id
    tower.survival_projectile_model=row.projectile_model
    tower.projectile_name=row.projectile_model
    tower.survival_tower_class=route
    tower.survival_projectile_speed=row.projectile_speed
    for _,id in ipairs(row.skill_ids) do tower.skills[id]=assert(skills.by_id[id],id) end
    assert(catalog.get(row.model_asset_id).native_wearable_stage,
        row.record_id.." must test the configured visible native hero body")
    local modifier=setmetatable({GetParent=function() return tower end,
        StartIntervalThink=function() end},{__index=effects})
    modifier:OnCreated()
    return tower,modifier
end
local checked=0
for _,route in ipairs({
    {"class_5","tower_class_multi"},{"class_1","tower_class_death"},{"class_6","tower_class_frost"},
}) do
    for _,row in ipairs(require("config/generated/"..route[2]).rows) do
        local tower,m=fixture(row,route[1])
        local event={attacker=tower,target=primary,record=checked+1}
        m:OnAttackStart(event)
        assert(#gestures==0,row.record_id..": native windup must not also start an unscaled manual attack gesture")
        assert(#projectiles==0 and #tasks==0 and #hits==0,
            row.record_id..": a windup must not release an arrow or damage before the attack point")
        -- A canceled windup is allowed to animate, but must not release a shot.
        m:OnAttackStart(event)
        assert(#gestures==0 and #projectiles==0 and #tasks==0,
            row.record_id..": restarting an unfinished windup must not add a scripted cycle")
        m:OnAttack(event)
        assert(#gestures==0,row.record_id..": actual release must retain only the engine animation")
        if route[1]=="class_5" and not tower.skills.burning_great_arrow_lv01 then
            assert(#projectiles==2 and #tasks==2,row.record_id..": one release must create one arrow per legitimate target")
            assert(#hits==0,row.record_id..": projectile damage must wait for arrival")
            for _,shot in ipairs(projectiles) do
                assert(shot.Source==tower and not shot.bIsAttack and shot.Ability==nil,
                    row.record_id..": split-arrow visuals must not start another native attack")
            end
            for _,task in ipairs(tasks) do task.callback() end
            assert(#hits==2,row.record_id..": each released split arrow must land once")
            clock=clock+0.02
            m:OnAttack(event)
            assert(#projectiles==4 and #tasks==4,row.record_id..": the next native release must not be swallowed by visual deduplication")
        elseif route[1]=="class_1" or route[1]=="class_6" then
            assert(#projectiles==0 and #tasks==0,row.record_id..": ordinary native projectile must not gain a second scripted projectile")
            assert(tower.projectile_name==row.projectile_model,row.record_id..": keep the configured native projectile")
            m:OnAttackLanded(event)
            assert(#gestures==0,row.record_id..": impact must not replay its launch animation")
            if route[1]=="class_6" then
                assert(#particles==1 and #buffs==2,row.record_id..": one native hit must still produce one frost impact and both slow buffs")
            end
        end
        checked=checked+1
    end
end

-- Lightning uses a separate scripted attack visual, and keeps its faster
-- gesture. Guarding ordinary native attacks must not remove this behavior.
local tower,m=fixture(require("config/generated/tower_class_lightning").rows[1],"class_3")
m:OnAttackStart({attacker=tower,target=primary})
assert(#gestures==1 and gestures[1].rate==2,"preserve the scripted Zeus lightning gesture")

-- Mixed skill sets still use the machine-gun sequence's own animation owner.
-- The ordinary multi/frost guard applies only to native attack callbacks.
for _,extra in ipairs({"multi_attack_lv01","frost_attack_lv01"}) do
    tower,m=fixture(require("config/generated/tower_class_machine_gun").rows[1],"class_4")
    tower.skills[extra]=assert(skills.by_id[extra])
    local event={attacker=tower,target=primary}
    m:OnAttackStart(event)
    assert(#gestures==0,"machine-gun windup must wait for its scripted sequence")
    effects._start_machine_gun_sequence_for_test(m,tower,primary,skills.by_id.machine_gun_lv01)
    assert(#gestures==1,"mixed "..extra.." must keep one machine-gun sequence gesture")
    local count=0
    while #tasks>0 do
        local task=table.remove(tasks,1)
        task.callback(); count=count+1
        assert(count<20,"machine-gun sequence must remain bounded")
    end
    assert(#gestures==1 and #hits==skills.by_id.machine_gun_lv01.max_targets,
        "machine-gun sub-hits must retain damage without restarting the animation")
end
print("TOWER_NATIVE_ATTACK_ANIMATION_PASS: "..checked.." configured multi/critical/frost levels, canceled windups, one release per target, projectile arrival, lightning and mixed machine-gun preservation")
