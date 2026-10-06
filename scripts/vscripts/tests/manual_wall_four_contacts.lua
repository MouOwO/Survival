-- Explicit Workshop probe only. Temporary actors are always removed after 12s.
if not IsInToolsMode() or not _G.SURVIVAL_FOUR_CONTACT_TEST then return end
_G.SURVIVAL_FOUR_CONTACT_TEST=nil
LinkLuaModifier("modifier_wall_contact_probe_v2","tests/wall_contact_probe_modifier",LUA_MODIFIER_MOTION_NONE)
require("modifiers/modifier_enemy_wall_ai")
local nav=require("systems/wall_navigation_service")
local state={units={},hits={}}
local loading=require("systems/startup_loading_service")
local was_ready,was_player_ready=loading.is_ready,loading.is_player_ready
-- The isolated test does not interact with the startup HUD. Restore both gates
-- in the already-scheduled cleanup; gameplay code never bypasses these gates.
loading.is_ready=function() return true end
loading.is_player_ready=function() return true end
local origin=Vector(512,5248,384)
GameRules:GetGameModeEntity():SetContextThink("wall_four_cleanup",function()
    local n=0;for _ in pairs(state.hits) do n=n+1 end
    print("WALL_FOUR_RESULT",n,state.wall and not state.wall:IsNull() and state.wall:GetHealth())
    if state.wall then nav.clear(state.wall) end
    for _,unit in ipairs(state.units) do if not unit:IsNull() then UTIL_Remove(unit) end end
    loading.is_ready,loading.is_player_ready=was_ready,was_player_ready
    print("WALL_FOUR_DONE")
end,12)
local ok,err=pcall(function()
    local wall=CreateUnitByName("building_wall",origin,false,nil,nil,DOTA_TEAM_GOODGUYS)
    state.wall=wall;state.units[#state.units+1]=wall
    wall:SetHullRadius(128);wall:SetMaxHealth(100000);wall:SetHealth(100000)
    wall.survival_fixed_position=origin
    wall:SetAbsOrigin(origin)
    wall:AddNewModifier(wall,nil,"modifier_building_stationary",{})
    nav.create(wall);wall:RemoveModifierByName("modifier_invulnerable")
    AddFOWViewer(DOTA_TEAM_BADGUYS,origin,1200,13,false)
    GameRules:GetGameModeEntity():SetContextThink("wall_probe_unprotect",function() nav.create(wall) end,.3)
    for i=1,8 do
        local p=origin+Vector(-384-math.floor((i-1)/4)*96,((i-1)%4-1.5)*96,0)
        local unit=CreateUnitByName("npc_survival_wave_monster",p,false,nil,nil,DOTA_TEAM_BADGUYS)
        state.units[#state.units+1]=unit;FindClearSpaceForUnit(unit,p,true)
        unit.survival_player_id=0;unit.survival_contact_probe=state
        unit:SetHullRadius(32);FindClearSpaceForUnit(unit,p,true);unit:SetBaseDamageMin(1);unit:SetBaseDamageMax(1)
        unit:AddNewModifier(unit,nil,"modifier_wall_contact_probe_v2",{})
        unit:AddNewModifier(unit,nil,"modifier_enemy_wall_ai",{wall_entindex=wall:entindex()})
    end
    local ticks=0
    GameRules:GetGameModeEntity():SetContextThink("wall_four_observe",function()
        ticks=ticks+1
        for i=2,math.min(5,#state.units) do
            local u=state.units[i]
            if not u:IsNull() then
                local m=u:FindModifierByName("modifier_enemy_wall_ai")
                if ticks==1 and i==2 then
                    local names={};for _,mod in ipairs(u:FindAllModifiers()) do names[#names+1]=mod:GetName() end
                    print("WALL_FOUR_FLAGS",u:GetBaseMoveSpeed(),u:GetIdealSpeed(),u:IsRooted(),u:IsStunned(),u:IsCommandRestricted(),table.concat(names,","),GridNav:IsTraversable(u:GetAbsOrigin()),GridNav:IsBlocked(u:GetAbsOrigin()))
                end
                local accepted=require("systems/tree_attack_order_filter")._filter_for_test(nil,
                    {units={tostring(u:entindex())},order_type=DOTA_UNIT_ORDER_ATTACK_TARGET,
                    entindex_target=wall:entindex(),issuer_player_id_const=-1})
                print("WALL_FOUR_UNIT",ticks,u:entindex(),u:GetAbsOrigin()-origin,
                    "range",u:Script_GetAttackRange(),"wait",m.contact_waiting,
                    "target",u:GetAttackTarget(),"idle",u:IsIdle(),"disarm",u:IsDisarmed(),"filter",accepted,
                    "plan",m.contact_move,"teams",u:GetTeamNumber(),wall:GetTeamNumber())
            end
        end
        if ticks<3 then return 3 end
    end,2)
end)
if not ok then print("WALL_FOUR_ERROR",err) end
