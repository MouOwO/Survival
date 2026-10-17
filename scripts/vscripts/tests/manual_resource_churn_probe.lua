-- Explicit, bounded Tools diagnostic. require() installs no hooks or timers.
-- Counts only calls reaching these Lua API slots, not engine/internal/cached
-- calls. Released particle IDs are never retained as reusable native objects.
local M = {}
local active
local function world()
    return GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
end
local function pack(...) return {n=select('#', ...), ...} end
local function current(s)
    return active == s and s.world == world()
end
local function increment(s, name, key)
    s.calls[name] = (s.calls[name] or 0) + 1
    if key then
        local bucket = s.paths[name]
        if not bucket then bucket={}; s.paths[name]=bucket end
        if bucket[key] ~= nil or s.path_count < 256 then
            if bucket[key] == nil then s.path_count=s.path_count+1 end
            bucket[key]=(bucket[key] or 0)+1
        else s.paths_dropped=s.paths_dropped+1 end
    end
end
local function install(s, target, name, key_argument, handle_action)
    local original = target and target[name]
    if type(original) ~= 'function' then
        s.unavailable[#s.unavailable+1]=name
        return
    end
    local wrapper = function(...)
        local args=pack(...)
        if not current(s) then return original(unpack(args,1,args.n)) end
        local key=key_argument and args[key_argument]
        increment(s,name,type(key)=='string' and key or nil)
        local result=pack(pcall(original,unpack(args,1,args.n)))
        if not result[1] then
            s.errors[name]=(s.errors[name] or 0)+1
            error(result[2],0)
        end
        if handle_action=='create' then
            local id=result[2]
            if type(id)=='number' and id>=0 then
                if not s.handles[id] then
                    if s.owned<8192 then s.handles[id]=true; s.owned=s.owned+1
                    else s.handles_dropped=s.handles_dropped+1 end
                end
                s.peak=math.max(s.peak,s.owned)
            else s.invalid_particle_results=s.invalid_particle_results+1 end
        elseif handle_action=='release' then
            local id=args[2]
            if s.handles[id] then s.handles[id]=nil; s.owned=s.owned-1 end
        end
        return unpack(result,2,result.n)
    end
    local ok=pcall(function() target[name]=wrapper end)
    if ok and target[name]==wrapper then
        s.hooks[#s.hooks+1]={target=target,name=name,original=original,wrapper=wrapper}
    else s.unavailable[#s.unavailable+1]=name end
end
function M.snapshot()
    local s=active
    if not s then return {active=false,scope='No resource hooks installed'} end
    local time=GameRules:GetGameTime()
    local report={active=current(s),elapsed_seconds=math.max(0,time-s.started),
        calls={},paths={},errors={},unavailable={},restore_conflicts={},
        outstanding_observed_particle_handles=s.owned,peak_observed_particle_handles=s.peak,
        invalid_particle_results=s.invalid_particle_results,handles_dropped=s.handles_dropped,
        paths_dropped=s.paths_dropped,
        scope='Lua API-slot observations only; cached/internal engine calls are not covered. Outstanding handles do not measure naturally finishing released particles or a leak.'}
    for k,v in pairs(s.calls) do report.calls[k]=v end
    for k,b in pairs(s.paths) do report.paths[k]={}; for p,v in pairs(b) do report.paths[k][p]=v end end
    for k,v in pairs(s.errors) do report.errors[k]=v end
    for _,v in ipairs(s.unavailable) do report.unavailable[#report.unavailable+1]=v end
    for _,v in ipairs(s.restore_conflicts) do report.restore_conflicts[#report.restore_conflicts+1]=v end
    return report
end
function M.stop(reason)
    local s=active
    if not s then return M.snapshot() end
    for _,hook in ipairs(s.hooks) do
        if hook.target[hook.name]==hook.wrapper then
            local ok=pcall(function() hook.target[hook.name]=hook.original end)
            if not ok then s.restore_conflicts[#s.restore_conflicts+1]=hook.name end
        else s.restore_conflicts[#s.restore_conflicts+1]=hook.name end
    end
    require('core/scheduler').cancel('manual_resource_churn_probe')
    local report=M.snapshot(); report.active=false; report.reason=reason or 'manual'
    active=nil
    return report
end
function M.start(options)
    options=options or {}
    assert(options.enabled==true and IsInToolsMode() and IsServer(), 'Explicit Tools server opt-in required')
    assert(GetMapName()=='template_map','template_map required')
    local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    assert(guard and guard.mode==world(),'Current isolated test world required')
    assert(not active,'Resource diagnostic already active')
    local duration=tonumber(options.duration_seconds) or 10
    assert(duration>=1 and duration<=30,'Diagnostic must be bounded to 1..30 game seconds')
    local s={world=world(),started=GameRules:GetGameTime(),calls={},paths={},path_count=0,
        paths_dropped=0,handles={},owned=0,peak=0,handles_dropped=0,
        invalid_particle_results=0,errors={},hooks={},unavailable={},restore_conflicts={}}
    active=s
    for _,name in ipairs({'CreateParticle','CreateParticleForPlayer','CreateParticleForTeam'}) do
        install(s,ParticleManager,name,2,'create')
    end
    install(s,ParticleManager,'DestroyParticle')
    install(s,ParticleManager,'ReleaseParticleIndex',nil,'release')
    install(s,ParticleManager,'SetParticleControl')
    install(s,ParticleManager,'SetParticleControlEnt')
    install(s,_G,'CreateUnitByName',1)
    install(s,_G,'SpawnEntityFromTableSynchronous',1)
    install(s,_G,'UTIL_Remove')
    require('core/scheduler').after(duration,function()
        if active==s then
            local report=M.stop('bounded_duration')
            _G.SURVIVAL_RESOURCE_CHURN_LAST_REPORT=report
            print('[RESOURCE_CHURN_COMPLETE] elapsed='..report.elapsed_seconds)
        end
    end,'manual_resource_churn_probe')
    return M.snapshot()
end
return M
