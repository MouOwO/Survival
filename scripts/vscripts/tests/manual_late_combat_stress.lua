-- Explicit Tools-only scene, not loaded by gameplay. No player ownership,
-- wave registration, gold, progression, account writes, or gameplay settings.
local M = {}
local KEY, THINK = "SURVIVAL_LATE_COMBAT_STRESS", "SurvivalLateCombatStress"
local function valid(unit) return unit and not unit:IsNull() end
local bus=require("core/event_bus")
local counted={"tower.attack.start","tower.attack.landed","tower.laser.hit","combat:damage_calculated","combat:damage_resolved","commerce.tower_damage"}
function M.begin_measurement()
    local scene=assert(_G[KEY],"No private stress scene")
    scene.measured_wall,scene.measured_game=Time(),GameRules:GetGameTime()
    for _,name in ipairs(counted) do scene.counts[name]=0 end
    print("[LATE_HEAP] start_kib="..collectgarbage("count"))
end
function M.report()
    local scene=assert(_G[KEY],"No private stress scene")
    local elapsed=GameRules:GetGameTime()-scene.measured_game
    for _,name in ipairs(counted) do
        print(string.format("[LATE_HITS] event=%s count=%d game_seconds=%.3f per_game_second=%.3f",name,scene.counts[name],elapsed,scene.counts[name]/math.max(elapsed,0.001)))
    end
    print("[LATE_HEAP] end_kib="..collectgarbage("count"))
    local damage=require("combat/damage_transaction_repository").debug_snapshot()
    print(string.format("[LATE_DAMAGE_RECORDS] active=%d pending=%d recent=%d limit=%d",damage.active_records,damage.pending_records,damage.recent_records,damage.history_limit))
end
function M.stop()
    local scene = _G[KEY]
    if not scene then return end
    _G[KEY] = nil
    if bus.emit==scene.counter then bus.emit=scene.original_emit end
    scene.world:SetContextThink(THINK, nil, 0)
    PlayerResource:SetCameraTarget(0, nil)
    for _, unit in ipairs(scene.units) do if valid(unit) then unit:Stop(); UTIL_Remove(unit) end end
    print("[LATE_COMBAT_STRESS] cleaned units=" .. #scene.units)
end
function M.start(tower_count, enemy_count, duration)
    assert(IsInToolsMode() and GetMapName()=="template_map", "Private Tools template_map only")
    assert(GameRules:State_Get()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS,
        "Benchmark requires a running match, not a loading/setup screen")
    assert(require("systems/startup_loading_service").is_player_ready(0),
        "Benchmark requires the local player's loaded gameplay UI")
    M.stop()
    tower_count = math.max(4, math.min(96, math.floor(tonumber(tower_count) or 32)))
    enemy_count = math.max(4, math.min(256, math.floor(tonumber(enemy_count) or 96)))
    duration = math.max(10, math.min(180, tonumber(duration) or 30))
    local world = GameRules:GetGameModeEntity()
    local scene = {world=world, units={}, towers={}, targets={}, started=Time(), samples=0,counts={}}
    _G[KEY] = scene
    for _,name in ipairs(counted) do scene.counts[name]=0 end
    scene.original_emit=bus.emit
    scene.counter=function(name,payload)
        if scene.counts[name] then scene.counts[name]=scene.counts[name]+1 end
        return scene.original_emit(name,payload)
    end
    bus.emit=scene.counter
    -- Verified flat, traversable battlefield. Origin (0,0) is outside navigation
    -- and adds per-unit water effects, so it is not a representative benchmark.
    local origin = GetGroundPosition(Vector(-2800, 2800, 0), nil)
    local function spawn(name, position, team)
        position = GetGroundPosition(position, nil)
        local unit=CreateUnitByName(name,position,false,nil,nil,team)
        assert(valid(unit), "Stress unit creation failed: "..name)
        scene.units[#scene.units+1]=unit
        unit.survival_late_combat_fixture=true
        unit:SetMaxHealth(1000000000);unit:SetHealth(1000000000)
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
        return unit
    end
    local ok, err = pcall(function()
        -- Use the class linked by the game's real modifier bootstrap. Reloading
        -- its Lua table does not replace engine-captured native callbacks.
        if not _G.modifier_tower_attack_effects then
            DoIncludeScript("modifiers/modifier_tower_attack_effects", getfenv(0))
        end
        local skills=require("systems/tower_skill_runtime")
        local families={"laser_lv05","machine_gun_lv05","multi_attack_lv05","lightning_strike_lv05"}
        for i=1,enemy_count do
            local angle=i*2*math.pi/enemy_count
            local radius=60+((i-1)%5)*45
            local unit=spawn("npc_dota_creep_badguys_melee",origin+Vector(math.cos(angle)*radius,math.sin(angle)*radius,0),DOTA_TEAM_BADGUYS)
            unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
            scene.targets[#scene.targets+1]=unit
        end
        for i=1,tower_count do
            local angle=i*2*math.pi/tower_count
            local unit=spawn("building_arrow_tower",origin+Vector(math.cos(angle)*520,math.sin(angle)*520,0),DOTA_TEAM_GOODGUYS)
            unit.survival_building_id="arrow_tower"
            unit.survival_level=25
            unit.survival_attack_interval=0.1
            unit.survival_research_base_attack_time=1
            unit:SetBaseAttackTime(0.1);unit:SetBaseDamageMin(20);unit:SetBaseDamageMax(20)
            unit:SetRangedProjectileName("particles/units/heroes/hero_sniper/sniper_base_attack.vpcf")
            if unit.SetProjectileSpeed then unit:SetProjectileSpeed(5000) end
            local skill=families[(i-1)%#families+1]
            skills.apply(unit,{skill})
            if skill:match("^laser_") then unit:SetAttackCapability(DOTA_UNIT_CAP_MELEE_ATTACK) end
            unit:AddNewModifier(unit,nil,"modifier_tower_attack_effects",{})
            scene.towers[#scene.towers+1]=unit
            unit:SetForceAttackTarget(scene.targets[(i-1)%#scene.targets+1])
            unit:MoveToTargetToAttack(scene.targets[(i-1)%#scene.targets+1])
        end
        scene.anchor=spawn("npc_dota_creep_goodguys_melee",origin,DOTA_TEAM_GOODGUYS)
        scene.anchor:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
        scene.anchor:AddNoDraw()
        PlayerResource:SetCameraTarget(0,scene.anchor)
    end)
    if not ok then M.stop();error(err,0) end
    local callback_total, callback_max = 0, 0
    world:SetContextThink(THINK, function()
        if _G[KEY]~=scene then return nil end
        if Time()-scene.started>=duration then
            print(string.format("[LATE_COMBAT_STRESS] complete towers=%d enemies=%d seconds=%.2f callbacks=%d maintenance_ms=%.3f max_ms=%.3f",
                tower_count,enemy_count,Time()-scene.started,scene.samples,callback_total*1000,callback_max*1000))
            M.stop();return nil
        end
        local began=Time()
        for _,unit in ipairs(scene.targets) do if valid(unit) then unit:SetHealth(unit:GetMaxHealth()) end end
        scene.samples=scene.samples+1
        local elapsed=Time()-began
        callback_total,callback_max=callback_total+elapsed,math.max(callback_max,elapsed)
        return 1
    end,1)
    print(string.format("[LATE_COMBAT_STRESS] started towers=%d enemies=%d duration=%d attack_interval=0.1",tower_count,enemy_count,duration))
    return scene
end
return M
