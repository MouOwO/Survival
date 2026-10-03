-- Opt-in native-engine regression. Never registered by gameplay.
-- Run only in an isolated, already-ready Tools session:
-- SURVIVAL_WALL_CROWD_TEST=true
-- require('tests/manual_wall_crowd_contacts').start({origin=Vector(512,5248,384)})
-- stop() also cleans a test while the game is paused.
local M = {}
local navigation = require('systems/wall_navigation_service')
local state
local TIMER = 'survival_manual_wall_crowd'
local function valid(u) return u and not u:IsNull() end
local function alive(u) return valid(u) and u:IsAlive() end
local function distance(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return math.sqrt(x*x+y*y)
end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function detail(u)
    local m=u:FindModifierByName('modifier_enemy_wall_ai')
    local p,w=u:GetAbsOrigin(),state.origin
    print('WALL_CROWD_UNIT',u:entindex(),p.x-w.x,p.y-w.y,
        'hits',state.hits[u:entindex()] or 0,'hull',u:GetHullRadius(),
        'padded',u:GetPaddedCollisionRadius(),'range',u:Script_GetAttackRange(),
        'distance',distance(p,w),'state',m and m.ai_state,
        'root',u:IsRooted(),'disarm',u:IsDisarmed(),'target',u:GetAttackTarget(),
        'force',u:GetForceAttackTarget(),'idle',u:IsIdle(),
        'last_attack',m and m.last_attack_activity,'last_order',m and m.last_order_time,
        'last_progress',m and m.last_progress_time,'pending',m and m.order_pending)
end

function M.stop(reason)
    local s=state
    if not s then return end
    state=nil
    GameRules:GetGameModeEntity():SetContextThink(TIMER,nil,0)
    if valid(s.wall) then pcall(navigation.clear,s.wall) end
    for _,u in ipairs(s.units) do
        if valid(u) then
            pcall(function() u:RemoveModifierByName('modifier_enemy_wall_ai') end)
            pcall(UTIL_Remove,u)
        end
    end
    for _,e in ipairs(s.obstacles) do
        if valid(e) then
            pcall(DoEntFireByInstanceHandle,e,'Disable','',0,nil,nil)
            pcall(UTIL_Remove,e)
        end
    end
    if s.viewer and RemoveFOWViewer then pcall(RemoveFOWViewer,DOTA_TEAM_BADGUYS,s.viewer) end
    M.last_result={ok=s.passed==true,reason=reason or 'stopped',unique=count(s.hits),
        hits=s.hits,invalid_hits=s.invalid_hits,elapsed=GameRules:GetGameTime()-s.started}
    print('WALL_CROWD_RESULT',M.last_result.ok and 'PASS' or (s.observe_seconds and 'OBSERVED' or 'FAIL'),M.last_result.reason,
        'unique',M.last_result.unique,'invalid_hits',s.invalid_hits,'elapsed',M.last_result.elapsed)
    print('WALL_CROWD_DONE')
end

local function prepare()
    local s=state
    local p=s.origin
    local wall=CreateUnitByName('building_wall',p,false,nil,nil,DOTA_TEAM_GOODGUYS)
    assert(valid(wall),'temporary wall creation failed')
    s.wall=wall;s.units[#s.units+1]=wall
    wall:SetHullRadius(128);wall:SetMaxHealth(100000);wall:SetHealth(100000)
    wall:SetBaseHealthRegen(0);wall:SetAbsOrigin(p)
    wall.survival_fixed_position=p
    wall:AddNewModifier(wall,nil,'modifier_building_stationary',{})
    navigation.create(wall)
    s.viewer=AddFOWViewer(DOTA_TEAM_BADGUYS,p,3000,90,false)
    for index=1,90 do
        local row,lane=math.floor((index-1)/4),(index-1)%4
        local q=Vector(p.x-320-row*70,p.y+(lane-1.5)*64,p.z)
        if s.center_first then
            if index<=2 then q=Vector(p.x-224,p.y+(index==1 and -42 or 42),p.z)
            else
                local column={-32,32,-96,96}
                q=Vector(p.x-320-math.floor((index-3)/4)*70,p.y+column[(index-3)%4+1],p.z)
            end
        end
        q.z=GetGroundHeight(q,nil)
        local u=CreateUnitByName('npc_survival_wave_monster',q,false,nil,nil,DOTA_TEAM_BADGUYS)
        assert(valid(u),'temporary crowd creation failed')
        s.units[#s.units+1]=u;s.monsters[#s.monsters+1]=u
        -- These actors are never added to wave/reward/archive registries.
        u:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
        u:SetHullRadius(32);u:SetMaxHealth(10000);u:SetHealth(10000)
        u:SetBaseDamageMin(1);u:SetBaseDamageMax(1);u:SetBaseAttackTime(1)
        u:SetAcquisitionRange(0)
        u:SetMinimumGoldBounty(0);u:SetMaximumGoldBounty(0);u:SetDeathXP(0)
        FindClearSpaceForUnit(u,q,true)
        u.survival_crowd_probe=s
        u:AddNewModifier(u,nil,'modifier_wall_crowd_probe',{})
        u:AddNewModifier(u,nil,'modifier_enemy_wall_ai',{wall_entindex=wall:entindex()})
    end
    s.phase=s.observe_seconds and 'observe' or 'front';s.phase_started=GameRules:GetGameTime()
    print('WALL_CROWD_STARTED','native_corridor_width',256,'population',#s.monsters,
        'origin',p,'wall_hull',wall:GetHullRadius(),'wall_padded',wall:GetPaddedCollisionRadius())
end

local function tick()
    local s=state
    if not s then return end
    local t=GameRules:GetGameTime()
    assert(s.observe_seconds or s.invalid_hits==0,'a waiting/non-contact monster landed a hit')
    for id,orders in pairs(s.first_hit_orders) do
        if not s.observe_seconds and id~=s.victim and s.phase~='release' then
            local u=EntIndexToHScript(id)
            local m=valid(u) and u:FindModifierByName('modifier_enemy_wall_ai')
            assert(m and m.last_order_time==orders,'an attacking front unit received another order')
        end
    end
    assert(t-s.started<75,'native crowd test timed out')
    if s.phase=='prepare' then prepare();return .5 end
    if not s.unprotected then navigation.create(s.wall);s.unprotected=true end
    if t>=(s.next_report or 0) then
        s.next_report=t+5
        local attacking,waiting,approaching=0,0,0
        for _,u in ipairs(s.monsters) do
            if alive(u) then
                local m=u:FindModifierByName('modifier_enemy_wall_ai')
                if m and m.ai_state=='attack' then attacking=attacking+1;detail(u)
                elseif m and m.ai_state=='waiting' then waiting=waiting+1
                else approaching=approaching+1 end
            end
        end
        print('WALL_CROWD_SAMPLE',s.phase,t-s.started,'attackers',attacking,
            'waiting',waiting,'approaching',approaching,'unique_hits',count(s.hits))
        assert(s.observe_seconds or attacking<=4,'more than four front attackers were admitted')
        if s.diagnose and attacking<4 and s.phase~='release' then
            DoIncludeScript('tests/probe_live_diagnostic',getfenv(0))
        end
    end
    if s.rescue and not _G.WALL_PROBE_RESCUED and t-s.phase_started>=2 and s.phase~='release' then
        DoIncludeScript('tests/probe_clear_force_once',getfenv(0))
    end
    if s.phase=='observe' then
        if t-s.phase_started>=s.observe_seconds then M.stop('baseline observation completed');return end
    elseif s.phase=='front' then
        assert(count(s.hits)<=4,'a fifth monster attacked before any vacancy')
        assert(not s.front_deadline or t-s.phase_started<=s.front_deadline or count(s.hits)==4,
            'front row did not produce four native hits within the admission deadline')
        local ready=count(s.hits)==4 and t-s.phase_started>=10
        for _,hits in pairs(s.hits) do if hits<4 then ready=false end end
        if ready then
            s.original={};local victim
            for _,u in ipairs(s.monsters) do
                local id=u:entindex()
                if s.hits[id] then
                    s.original[id]=s.hits[id]
                    local p=u:GetAbsOrigin()
                    if not victim or math.abs(p.y-s.origin.y)>math.abs(victim:GetAbsOrigin().y-s.origin.y) then victim=u end
                end
            end
            s.victim=victim:entindex();s.phase='replacement';s.phase_started=t
            print('WALL_CROWD_VACATE_OUTER',s.victim)
            victim:ForceKill(false)
        end
    elseif s.phase=='replacement' then
        assert(count(s.hits)<=5,'more than one replacement attacked for one vacancy')
        assert(not s.replacement_deadline or t-s.phase_started<=s.replacement_deadline or count(s.hits)==5,
            'outer-row vacancy was not replaced within the admission deadline')
        local ready=count(s.hits)==5 and t-s.phase_started>=10
        for id,hits in pairs(s.hits) do
            if id~=s.victim and hits-(s.original[id] or 0)<4 then ready=false end
        end
        if ready then
            print('WALL_CROWD_REPLACED','unique_hits',count(s.hits),'overflow_hits',s.invalid_hits)
            s.phase='release';s.phase_started=t
            s.wall:ForceKill(false)
        end
    elseif s.phase=='release' and t-s.phase_started>=1.5 then
        local released=0
        for _,u in ipairs(s.monsters) do
            if alive(u) then
                local m=u:FindModifierByName('modifier_enemy_wall_ai')
                assert(m and not m.contact_locked and not m.contact_waiting and m.wall_entindex==-1,
                    'wall death did not release an AI contact')
                assert(not u:IsRooted() and not u:IsDisarmed() and u:GetForceAttackTarget()==nil,
                    'wall death retained a native combat restriction')
                assert(math.abs(u:Script_GetAttackRange()-128)<.01,'wall death did not restore native range')
                released=released+1
            end
        end
        assert(released==89,'unexpected crowd population after a single casualty')
        s.passed=true
        M.stop('four sustained attackers, zero overflow hits, outer replacement, 89 released')
        return
    end
    return .5
end

function M.start(options)
    assert(IsInToolsMode() and _G.SURVIVAL_WALL_CROWD_TEST==true,'explicit Tools test flag required')
    _G.SURVIVAL_WALL_CROWD_TEST=nil
    assert(not state,'stop the previous crowd test first')
    M.last_result=nil
    local loading=package.loaded['systems/startup_loading_service']
    assert(not loading or loading.is_ready(),'run only in an isolated already-ready session; never bypass profile/startup gates')
    assert(not GameRules:IsGamePaused(),'start the isolated test unpaused; this fixture never changes pause')
    options=options or {}
    local p=assert(options.origin,'an explicitly inspected empty test origin is required')
    assert(p.x%64==0 and p.y%64==0,'test origin must align to the 64-unit navigation grid')
    p=Vector(p.x,p.y,GetGroundHeight(p,nil))
    -- Refuse to overwrite or corral gameplay actors in the test rectangle.
    for _,u in ipairs(Entities:FindAllByClassname('npc_dota_creature') or {}) do
        local q=u:GetAbsOrigin()
        assert(q.x<p.x-2176 or q.x>p.x+384 or math.abs(q.y-p.y)>512,
            'test rectangle contains an existing unit; use a separate empty test area')
    end
    for x=-2048,256,64 do for y=-96,96,64 do
        local q=Vector(p.x+x,p.y+y,p.z)
        assert(GridNav:IsTraversable(q) and not GridNav:IsBlocked(q)
            and math.abs(GetGroundHeight(q,nil)-p.z)<16,'test rectangle is not a flat traversable corridor')
    end end
    LinkLuaModifier('modifier_wall_crowd_probe','tests/wall_crowd_probe_modifier',LUA_MODIFIER_MOTION_NONE)
    state={origin=p,units={},monsters={},obstacles={},hits={},first_hit_orders={},invalid_hits=0,
        phase='prepare',started=GameRules:GetGameTime(),observe_seconds=tonumber(options.observe_seconds),
        center_first=options.center_first==true,diagnose=options.diagnose==true,rescue=options.rescue==true,
        front_deadline=tonumber(options.front_deadline),replacement_deadline=tonumber(options.replacement_deadline)}
    local ok,err=pcall(function()
        -- Real native obstructions form a 256-wide straight throat. No mocked
        -- GridNav, hand-placed front row, forced attacks, or readiness override.
        for x=-2112,192,128 do for _,y in ipairs({-192,192}) do
            local e=SpawnEntityFromTableSynchronous('point_simple_obstruction',{
                origin=Vector(p.x+x,p.y+y,p.z),StartDisabled=0,block_fow=0,
                targetname='survival_manual_wall_crowd_bank'})
            assert(valid(e),'temporary corridor bank creation failed')
            state.obstacles[#state.obstacles+1]=e
        end end
        GameRules:GetGameModeEntity():SetContextThink(TIMER,function()
            local success,result=pcall(tick)
            if not success then M.stop(tostring(result));return nil end
            return result
        end,.2)
    end)
    if not ok then M.stop(tostring(err));error(err) end
    return true
end
return M
