-- Explicit, self-cleaning Workshop comparison of old and new initial cadence.
if not IsInToolsMode() or GetMapName() ~= "valley_decor_review"
    or not _G.VALLEY_SPAWN_LATENCY_TEST then return end
_G.VALLEY_SPAWN_LATENCY_TEST = nil
require("modifiers/modifier_enemy_wall_ai")
local state = {units={}, samples={}}
local loading = require("systems/startup_loading_service")
local ready, player_ready = loading.is_ready, loading.is_player_ready
loading.is_ready, loading.is_player_ready = function() return true end, function() return true end
local mode = GameRules:GetGameModeEntity()
mode:SetContextThink("valley_spawn_latency_cleanup", function()
    local passed = 0
    for _, s in ipairs(state.samples) do
        local ok = s.order and s.move and (s.baseline and s.order >= .4
            or not s.baseline and s.order < .2 and s.move < .35)
        if ok then passed = passed + 1 end
        print("VALLEY_SPAWN_LATENCY", s.lane, s.baseline and "old_500ms" or "next_frame",
            "first_order", s.order or -1, "first_move", s.move or -1, "pass", ok or false)
    end
    for _, u in ipairs(state.units) do if not u:IsNull() then UTIL_Remove(u) end end
    loading.is_ready, loading.is_player_ready = ready, player_ready
    print("VALLEY_SPAWN_LATENCY_DONE", passed, #state.samples)
end, 3)
local ok, err = pcall(function()
    for lane=1,4 do
        local p = Entities:FindByName(nil,"monsterborn_player"..lane):GetAbsOrigin()
        p.z = GetGroundHeight(p,nil)
        local forward = (p-Vector(-1024,4096,p.z)):Normalized()
        local side = Vector(-forward.y,forward.x,0)
        local goal = p + forward * 1050
        goal.z = GetGroundHeight(goal,nil)
        local wall = CreateUnitByName("building_wall",goal,false,nil,nil,DOTA_TEAM_GOODGUYS)
        state.units[#state.units+1] = wall
        wall.survival_player_id = 0
        wall:SetAbsOrigin(goal)
        wall:RemoveModifierByName("modifier_invulnerable")
        wall:SetMaxHealth(1000000);wall:SetHealth(1000000)
        AddFOWViewer(DOTA_TEAM_BADGUYS,p,1800,4,false)
        for n=1,2 do
            local start = p + side * (n==1 and -64 or 64)
            local unit = CreateUnitByName("npc_survival_wave_monster",start,false,nil,nil,DOTA_TEAM_BADGUYS)
            state.units[#state.units+1] = unit
            unit.survival_player_id = 0
            unit.survival_is_wave_monster = true
            unit:SetForwardVector(forward)
            local stamp = GameRules:GetGameTime()
            local modifier = unit:AddNewModifier(unit,nil,"modifier_enemy_wall_ai",{wall_entindex=wall:entindex(),no_unit_collision=1})
            if n==1 then modifier:StartIntervalThink(.5) end
            FindClearSpaceForUnit(unit,start,true)
            state.samples[#state.samples+1] = {lane=lane,baseline=n==1,unit=unit,modifier=modifier,
                started=stamp,start=unit:GetAbsOrigin()}
        end
    end
    mode:SetContextThink("valley_spawn_latency_observe",function()
        for _,s in ipairs(state.samples) do
            if not s.unit:IsNull() then
                if not s.order and s.modifier.last_order_time then
                    s.order=s.modifier.last_order_time-s.started
                end
                if not s.move and (s.unit:GetAbsOrigin()-s.start):Length2D()>2 then
                    s.move=GameRules:GetGameTime()-s.started
                end
                if not s.diagnostic and GameRules:GetGameTime()-s.started>.8 then
                    s.diagnostic=true
                    local names={};for _,m in ipairs(s.unit:FindAllModifiers()) do names[#names+1]=m:GetName() end
                    print("VALLEY_LATENCY_FLAGS",s.lane,s.baseline,s.unit:GetIdealSpeed(),
                        s.unit:IsRooted(),s.unit:IsStunned(),s.unit:IsCommandRestricted(),
                        s.unit:IsIdle(),s.unit:GetAttackTarget(),table.concat(names,","),s.unit:GetAbsOrigin(),
                        s.unit:IsDisarmed(),s.unit:GetAttackCapability(),s.unit:GetForceAttackTarget())
                end
            end
        end
        return .01
    end,0)
    mode:SetContextThink("valley_spawn_latency_stop",function()
        mode:SetContextThink("valley_spawn_latency_observe",nil,0)
    end,2.9)
end)
if not ok then print("VALLEY_SPAWN_LATENCY_ERROR",err) end
