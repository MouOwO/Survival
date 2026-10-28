-- Real challenge startup, profiles and staged checkout with native entities mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
local noop = function() end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS, DOTA_TEAM_NEUTRALS = 2, 3, 4
DOTA_UNIT_CAP_MOVE_GROUND = 1
Vector = function(x,y,z) return {x=x,y=y,z=z or 0} end
GameRules = {GetGameTime=function() return 0 end}
IsServer = function() return true end
local bodies, markers, missing, unique = {}, {}, nil, 0
DoUniqueString = function(prefix) unique=unique+1; return prefix..unique end
GridNav = {IsBlocked=function() return false end, IsTraversable=function() return true end}
PlayerResource = {GetTeam=function() return 2 end, GetSelectedHeroEntity=function() end}
Entities = {FindByName=function(_,_,name)
    if name == missing then return nil end
    if not markers[name] then
        local index=0; for _ in pairs(markers) do index=index+1 end
        local p=Vector(index*1000,index*150,256)
        markers[name]={IsNull=function() return false end, GetAbsOrigin=function() return p end,
            GetName=function() return name end}
    end
    return markers[name]
end}
FindClearSpaceForUnit = function(u,p) u.position=p end
UTIL_Remove = function(u) u.removed=true end
local excluded = {}
package.loaded["systems/player_context_service"]={is_defeated=function(id) return excluded[id] end}
package.loaded["core/scheduler"]={after=noop, every=noop, cancel=noop}
package.loaded["systems/challenge_monster_visual_service"]={apply=noop,clear=noop}
package.loaded["systems/monster_hero_visual_service"]={apply=function(u,a)
    u.outfit=a.default_wearable_asset_id; return true
end, clear=noop}
CreateUnitByName = function(name,p,_,_,_,team)
    local u={name=name,position=p,team=team,index=#bodies+1,modifiers={}}
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return not self.removed end
    function u:entindex() return self.index end
    function u:GetUnitName() return self.name end
    function u:GetAbsOrigin() return self.position end
    function u:GetTeamNumber() return self.team end
    function u:SetBaseMaxHealth(v) self.base_health=v end
    function u:SetMaxHealth(v) self.maximum=v end
    function u:SetHealth(v) self.health=v end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetBaseDamageMin(v) self.attack=v end
    function u:SetBaseDamageMax(v) self.attack_max=v end
    function u:SetBaseAttackTime(v) self.bat=v end
    function u:SetModel(v) self.model=v end
    function u:SetOriginalModel(v) self.original_model=v end
    function u:SetModelScale(v) self.scale=v end
    function u:SetHullRadius(v) self.hull=v end
    function u:GetHullRadius() return self.hull or 32 end
    function u:AddNewModifier(_,_,name,params)
        self.modifiers[name]={IsNull=function() return false end, Resume=function() self.resumed=true end}
    end
    function u:RemoveModifierByName(name) self.modifiers[name]=nil end
    function u:FindModifierByName(name) return self.modifiers[name] end
    u.SetPhysicalArmorBaseValue,u.SetBaseMoveSpeed,u.SetMoveCapability,u.SetAcquisitionRange=noop,noop,noop,noop
    bodies[#bodies+1]=u
    return u
end
local bus, events = require("core/event_bus"), require("core/events")
local wave_state={ok=true,difficulty_id="",game_mode="standard"}
bus.handle_request(events.WAVE_STATE_GET_REQUEST,function() return wave_state end)
local spawned, rewards=0,0
bus.subscribe(events.MONSTER_SPAWNED,function() spawned=spawned+1 end)
bus.subscribe(events.CHALLENGE_EQUIPMENT_REWARD_REQUEST,function() rewards=rewards+1 end)
local service=arg[1] and dofile(arg[1]) or require("systems/challenge_session_service")
service.init()
local function upvalue(fn,wanted)
    for i=1,100 do local name,value=debug.getupvalue(fn,i); if not name then break end
        if name==wanted then return value end end
    error("missing production state: "..wanted)
end
local prepared=upvalue(service.init,"challenge_11_prepared_by_player")
local meta=upvalue(service.init,"monster_meta")
local members=require("config/generated/encounter_members").rows
local archetypes=require("config/generated/monster_archetypes").by_id
local profiles=require("config/challenge_combat_profile_config")
local list={}
for _,m in ipairs(members) do if m.encounter_id=="encounter_challenge_11" then list[#list+1]=m end end
assert(#list==10)
bus.emit(events.HERO_READY,{player_id=0,team=2})
assert(#bodies==10 and prepared[0],"entry must display all ten bosses before combat-hero summon")
for index,u in ipairs(bodies) do
    local member=assert(meta[u.index]).member
    local a=archetypes[member.archetype_id]
    local point=markers[member.spawn_target_name]:GetAbsOrigin()
    assert(u.position.x==point.x and u.position.y==point.y and u.model==a.model_path)
    assert(u.outfit==a.default_wearable_asset_id and u.modifiers.modifier_challenge_11_staging)
    assert(u.survival_challenge_11_staged and u.survival_challenge_11_staged_owner==0)
end
bus.emit(events.HERO_READY,{player_id=0,team=2})
bus.emit(events.HERO_SUMMONED,{player_id=0,team=2})
assert(#bodies==10,"ready/summon repeats must reuse the existing bodies")
wave_state={ok=true,difficulty_id="N10",game_mode="pure"}
bus.emit(events.WAVE_CHANGED,{})
assert(#bodies==10 and prepared[0].difficulty_id=="N10" and prepared[0].game_mode=="pure")
for _,u in ipairs(bodies) do
    local member=meta[u.index].member
    local expected=assert(profiles.resolve(member.member_id,"N10","pure"))
    local actual=u.maximum*(u.survival_endless_health_scale or 1)
    assert(math.abs(actual-expected.health)<=math.max(1,expected.health)*1e-6,"selected-mode preview health")
end
local first_marker=list[2].spawn_target_name
missing=first_marker
bus.emit(events.HERO_READY,{player_id=1,team=2})
assert(not prepared[1],"incomplete display creation must roll back")
missing=nil
bus.emit(events.HERO_READY,{player_id=1,team=2})
assert(prepared[1],"a later ready event can recover the missing-marker failure")
local before=#bodies
excluded[2]=true
bus.emit(events.HERO_READY,{player_id=2,team=2})
assert(not prepared[2] and #bodies==before,"a defeated player cannot create new staged bodies")
local fill=upvalue(service.start,"fill_initial")
local activate=upvalue(fill,"activate_prepared_challenge_11")
local target={player_id=0,team=2,difficulty_id="N1",game_mode="standard",members={list[1]},monsters={},monster_count=0}
local combat_hero={IsNull=function() return false end, IsAlive=function() return true end, entindex=function() return 777 end}
PlayerResource.GetSelectedHeroEntity=function(_,id) if id==0 then return combat_hero end end
assert(activate(target) and target.monster_count==1)
assert(not prepared[0] and prepared[1],"checkout must preserve the other player's previews")
local active
for _,u in pairs(target.monsters) do active=u end
assert(active and not active.survival_challenge_11_staged and active.resumed)
assert(active.modifiers.modifier_practice_monster_ai.hero_entindex==777,
    "activation must bind the current combat hero instead of the initial placeholder")
local fill_current=upvalue(fill,"fill_current")
local activate_next=upvalue(fill_current,"activate_prepared_member")
combat_hero.entindex=function() return 778 end
assert(activate_next(target,list[2]))
for _,u in pairs(target.monsters) do
    if meta[u.index].member.member_id==list[2].member_id then
        assert(u.modifiers.modifier_practice_monster_ai.hero_entindex==778,
            "later stages must also follow a replacement combat hero")
    end
end
assert(spawned==before and rewards==0,"preview creation/checkout must not grant challenge rewards")
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1,defeat_cleanup=true})
assert(not prepared[1])
print("TEN_SIN_STARTUP_PASS: ten entry markers/models/outfits; ready dedup, profile refresh, current/replacement hero checkout, owner isolation, rollback/retry, defeat cleanup, no rewards")
