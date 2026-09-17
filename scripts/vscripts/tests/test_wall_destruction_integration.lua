package.path='scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;'..package.path
local events=require('core/events')
local subscribers,handlers={},{}
local releases,clears,destroyed,winners=0,0,0,0
local pending,started
DOTA_TEAM_BADGUYS=3
Vector=function(x,y,z)return {x=x,y=y,z=z}end
GameRules={SetGameWinner=function(_,team)assert(team==3);winners=winners+1 end}
package.loaded['core/event_bus']={
    subscribe=function(name,fn)subscribers[name]=fn end,
    handle_request=function(name,fn)handlers[name]=fn end,
    request=function(name)
        if name==events.GRID_RELEASE_REQUEST then releases=releases+1 end
        return true
    end,
    emit=function(name)if name==events.BUILDING_DESTROYED then destroyed=destroyed+1 end end,
}
package.loaded['core/modifier_registry']={register=function()end}
package.loaded['core/team_alignment']={enforce=function()end}
package.loaded['systems/tower_skill_runtime']={apply=function()end}
package.loaded['systems/building_relocation']={bind=function()end}
package.loaded['systems/building_construction_visual_service']={reset=function()end,cancel=function()end}
package.loaded['systems/building_visual_service']={clear=function()end}
package.loaded['systems/building_population_service']={grant_level=function()return 0 end}
package.loaded['systems/war3_armor_target']={apply=function()end}
package.loaded['systems/wall_collision_barrier_service']={create=function()end,clear=function()clears=clears+1 end}
package.loaded['systems/archive_endless_service']={on_wall_destroyed=function()return false end}
package.loaded['systems/multiplayer_player_service']={is_disconnected=function()return false end}
package.loaded['systems/online_time_service']={finish=function()end}
package.loaded['systems/wall_destruction_visual']={
    play=function(state)
        assert(state.cleaned and state.building_id=='wall')
        started=(started or 0)+1;return {death=true}
    end,
    after_burst=function(handle,fn)assert(handle.death);pending=fn end,
    reset=function()pending=nil end,
}
local wall={survival_is_building=true,survival_building_id='wall',survival_level=1,
    survival_player_id=0,survival_grid_x=4,survival_grid_y=4,survival_grid_footprint={x=4,y=4}}
function wall:IsNull()return false end
function wall:IsAlive()return not self.dead end
function wall:entindex()return 909 end
function wall:GetUnitName()return 'building_wall' end
function wall:GetTeamNumber()return 2 end
function wall:GetPlayerOwnerID()return 0 end
function wall:GetAbsOrigin()return Vector(384,384,128)end
function wall:GetModelScale()return 1 end
function wall:SetAbsOrigin()end
function wall:HasModifier()return true end
function wall:AddNewModifier()end
function wall:GetMaxHealth()return 1000 end
function wall:GetPhysicalArmorBaseValue()return 0 end
function wall:SetHullRadius(r)self.radius=r end
Entities={FindAllByClassname=function(_,kind)if kind=='npc_dota_creature' then return {wall}end;return {}end}
EntIndexToHScript=function()return wall end
local buildings=require('systems/building_system')
buildings.init()
assert(handlers[events.BUILDING_QUERY_REQUEST]({entindex=909}))
wall.dead=true
subscribers[events.ENGINE_ENTITY_KILLED]({victim=wall})
assert(releases==1 and clears==1 and destroyed==1,'death did not release gameplay state immediately')
assert(handlers[events.BUILDING_QUERY_REQUEST]({entindex=909})==nil,'dead wall remains queryable')
assert(started==1 and winners==0 and pending,'winner must wait until the burst')
subscribers[events.ENGINE_ENTITY_KILLED]({victim=wall})
assert(started==1 and destroyed==1,'duplicate event replayed destruction')
pending();assert(winners==1)
print('WALL_DESTRUCTION_INTEGRATION_PASS immediate_grid_barrier_release removed_state single_effect delayed_winner')
