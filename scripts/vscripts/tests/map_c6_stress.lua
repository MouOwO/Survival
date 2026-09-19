-- Explicit, temporary Workshop test only. Does not run during normal gameplay.
-- Invoke via MCP dota_run_lua: DoIncludeScript('tests/map_c6_stress_run',getfenv(0))
-- Restart only these test units with C6Stress.start({100,200,400}).
-- Uses the base NPC KV + actual wall AI; no tower skills or boss cosmetics.
if not IsInToolsMode() or GetMapName() ~= 'survival_c6' then return end
if C6Stress and C6Stress.cleanup then C6Stress.cleanup() end
C6Stress = { units = {}, walls = {}, generation = 0 }
local M = C6Stress
local function valid(u) return u and not u:IsNull() end
function M.cleanup()
    M.generation = M.generation + 1
    for _,u in ipairs(M.units) do
        if valid(u) then u:RemoveModifierByName('modifier_enemy_wall_ai') UTIL_Remove(u) end
    end
    for _,u in ipairs(M.walls) do if valid(u) then UTIL_Remove(u) end end
    M.units, M.walls = {}, {}
end
function M.start(counts, clustered, sample_seconds)
    M.cleanup()
    Convars:SetFloat('host_timescale', 1)
    GameRules:GetGameModeEntity():SetFogOfWarDisabled(true)
    GameRules:SetTimeOfDay(0.3)
    local phase = 0
    local function next_phase()
        M.cleanup()
        phase = phase + 1
        local count = counts[phase]
        if not count then
            Convars:SetFloat('host_timescale', 0.001)
            print('[C6_STRESS] COMPLETE cleanup=true')
            return
        end
        assert(count >= 1 and count <= 400, 'bounded test: 1..400 units')
        local generation = M.generation
        local centers = {Vector(350,6600,384),Vector(-2250,6600,384),Vector(-2250,4050,384),Vector(350,4050,384)}
        for i=1,(clustered and 1 or 4) do
            local wall = CreateUnitByName('building_wall', centers[i] + Vector(0,350,0), true, nil, nil, DOTA_TEAM_GOODGUYS)
            assert(valid(wall), 'test wall creation failed')
            wall:SetBaseMaxHealth(10000000) wall:SetMaxHealth(10000000) wall:SetHealth(10000000)
            wall:SetForwardVector(Vector(0,-1,0))
            M.walls[i]=wall
        end
        for i=1,count do
            local group = clustered and 1 or ((i-1)%4+1)
            local local_index = clustered and (i-1) or math.floor((i-1)/4)
            local columns = clustered and 20 or 10
            local p=centers[group]+Vector((local_index%columns-(columns-1)/2)*52,-math.floor(local_index/columns)*45,0)
            local u=CreateUnitByName('npc_survival_wave_monster',p,true,nil,nil,DOTA_TEAM_BADGUYS)
            assert(valid(u),'test monster creation failed')
            u.survival_wave_movement_type='ground'
            u:AddNewModifier(u,nil,'modifier_enemy_wall_ai',{wall_entindex=M.walls[group]:entindex(),no_unit_collision=0})
            M.units[#M.units+1]=u
        end
        print('[C6_STRESS] SPAWN count='..count..' clustered='..tostring(clustered==true))
        GameRules:GetGameModeEntity():SetContextThink('C6StressWarmup',function()
            if M.generation~=generation then return end
            M.positions={}
            for i,u in ipairs(M.units) do M.positions[i]=u:GetAbsOrigin() end
            print('[C6_STRESS] BEGIN count='..count..' state='..GameRules:State_Get())
            GameRules:GetGameModeEntity():SetContextThink('C6StressSample',function()
                if M.generation~=generation then return end
                local alive,ai,moving,attacking=0,0,0,0
                for i,u in ipairs(M.units) do if valid(u) and u:IsAlive() then
                    alive=alive+1
                    if u:HasModifier('modifier_enemy_wall_ai') then ai=ai+1 end
                    if (u:GetAbsOrigin()-M.positions[i]):Length2D()>16 then moving=moving+1 end
                    if valid(u:GetAttackTarget()) then attacking=attacking+1 end
                end end
                print('[C6_STRESS] END count='..count..' alive='..alive..' ai='..ai..' moved='..moving..' attack_target='..attacking..' state='..GameRules:State_Get())
                GameRules:GetGameModeEntity():SetContextThink('C6StressNext',next_phase,2)
            end,math.max(10,math.min(60,tonumber(sample_seconds) or 10)))
        end,5)
    end
    next_phase()
end
print('[C6_STRESS] loaded; call C6Stress.start({100,200,400}) or C6Stress.cleanup()')
