-- Exercise real preview creation, authored challenge profiles and scale recovery.
package.path = "scripts/vscripts/?.lua;" .. package.path
local function noop() end
local created, removed, jobs, listeners = {}, {}, {}, {}
local state = {ok=true,difficulty_id="N1",game_mode="standard"}
DOTA_TEAM_NEUTRALS=4
function Vector(x,y,z) return {x=x,y=y,z=z} end
function GetGroundPosition(point) return point end
function UTIL_Remove(body) removed[body]=true;body.removed=true end
Entities={FindByName=function(_,_,name)
    return {IsNull=function() return false end,GetAbsOrigin=function() return Vector(1,2,3) end,
        GetForwardVector=function() return Vector(1,0,0) end}
end}
function CreateUnitByName(name,_,_,_,_,team)
    local body={name=name,team=team,mods={}}
    function body:IsNull() return self.removed==true end
    function body:AddNewModifier(_,_,name) self.mods[name]=true end
    function body:HasModifier(name) return self.mods[name] end
    for _,entry in ipairs({{"SetBaseMaxHealth","base_health"},{"SetMaxHealth","max_health"},
        {"SetHealth","health"},{"SetBaseDamageMin","attack_min"},{"SetBaseDamageMax","attack_max"},
        {"SetPhysicalArmorBaseValue","native_armor"},{"SetBaseAttackTime","bat"},
        {"SetHullRadius","hull"},{"SetMinimumGoldBounty","gold_min"},
        {"SetMaximumGoldBounty","gold_max"},{"SetDeathXP","xp"},
        {"SetDayTimeVisionRange","day_vision"},{"SetNightTimeVisionRange","night_vision"},
        {"SetAcquisitionRange","acquisition"}}) do
        local method,key=entry[1],entry[2];body[method]=function(self,value) self[key]=value end
    end
    for _,name in ipairs({"SetIdleAcquire","SetModel","SetOriginalModel","SetAbsOrigin","SetForwardVector","Stop"}) do body[name]=noop end
    created[#created+1]=body;return body
end
package.loaded['systems/monster_hero_visual_service']={apply=function() return true end,clear=noop}
package.loaded['systems/startup_asset_preload_service']={snapshot=function() return {complete=true} end}
package.loaded['systems/unit_health_bar_service']={exclude=function(body) body.no_health_bar=true end}
package.loaded['visual/model_scale']={apply=noop}
package.loaded['core/logger']={warn=function(_,message) error(message) end,info=noop}
package.loaded['core/scheduler']={cancel=function(key) jobs[key]=nil end,after=function(_,fn,key) jobs[key]=fn end}
package.loaded['systems/match_setup_service']={public_snapshot=function() return {selected_game_mode=state.game_mode} end}
package.loaded['core/event_bus']={request=function() return state end,
    subscribe=function(name,fn) listeners[name]=fn;return name end,
    unsubscribe=function(name) listeners[name]=nil end,after_dispatch=function(_,fn) fn() end,
    emit=function() error('Preview must not publish combat/reward events') end}
local events=require('core/events')
local profiles=require('config/challenge_combat_profile_config')
local projection=require('combat/endless_stat_projection')
local encounters=require('config/generated/monster_encounters')
local service=require('systems/rebirth_scene_display_service')
local started=service.start();assert(started.ok and started.displayed==10)
local function check()
    for _,body in ipairs(created) do if not body.removed then
        local encounter=encounters.by_id[body.survival_encounter_id]
        local expected,reason=profiles.resolve(encounter.encounter_id,state.difficulty_id,state.game_mode)
        assert(expected and not reason)
        local function same(a,b) assert(math.abs(tonumber(a)-tonumber(b))<=math.max(1,math.abs(b))*1e-12) end
        same(projection.for_ui(body,body.health,'health'),expected.health)
        same(projection.for_ui(body,body.attack_max,'attack'),expected.attack)
        same(body.survival_war3_armor,expected.war3_armor or expected.armor)
        same(1/body.bat,expected.attack_speed)
        assert(body.survival_display_name==encounter.display_name)
        assert(body.health<=100000000 and body.attack_max<=100000000)
        assert(body.mods.modifier_rebirth_scene_display and body.no_health_bar)
        assert(body.gold_min==0 and body.gold_max==0 and body.xp==0 and body.hull==0)
    end end
end
check()
state.game_mode='rich'
for number=1,30 do
    state.difficulty_id='N'..number
    listeners[events.GAME_STARTED]();check()
end
for _,mode in ipairs({'standard','pure','rich','cold'}) do
    state.game_mode=mode;state.difficulty_id=mode=='rich' and 'N30' or mode=='cold' and 'N50' or 'N10'
    listeners[events.GAME_STARTED]();check()
end
assert(#created==10,'Stat refresh must retain the ten existing models')
service.hide('encounter_rebirth_01');assert(removed[created[1]])
service.restore('encounter_rebirth_01');assert(#created==11);check()
service.hide('encounter_rebirth_02');service.restore('encounter_rebirth_02',{after_corpse=true})
local restore;for _,fn in pairs(jobs) do restore=fn end
service.reset();if restore then restore() end
assert(#created==11 and next(listeners)==nil,'Reset cancels pending restoration and event subscriptions')
function class() return {} end
for index,name in ipairs({'INVULNERABLE','UNSELECTABLE','NO_HEALTH_BAR','NO_UNIT_COLLISION','NOT_ON_MINIMAP',
    'COMMAND_RESTRICTED','DISARMED','SILENCED','MUTED','PASSIVES_DISABLED','ROOTED'}) do _G['MODIFIER_STATE_'..name]=index end
local modifier=assert(loadfile('scripts/vscripts/modifiers/modifier_rebirth_scene_display.lua'))()
local flags=modifier:CheckState()
assert(flags[MODIFIER_STATE_UNSELECTABLE]~=true,'Idle rebirth bosses must be selectable')
for _,name in ipairs({'INVULNERABLE','NO_HEALTH_BAR','NO_UNIT_COLLISION','COMMAND_RESTRICTED','DISARMED','ROOTED'}) do assert(flags[_G['MODIFIER_STATE_'..name]]) end
print('REBIRTH_SCENE_SELECTION_PASS: ten selectable stat previews; standard/pure/rich/cold; exact large health/attack; armor/speed; no rewards; restore/reset isolation')
