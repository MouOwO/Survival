-- Offline broadcast fanout experiment. This does not measure Dota's engine,
-- native/Lua transition cost, rendered FPS or a real server frame.
-- Uses the production enemy/worker callbacks unchanged. The guarded variant
-- and direct-owner dispatcher exist only here; no gameplay state is modified.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(t) t.__index = t; return t end
IsServer = function() return true end
GameRules = { GetGameTime = function() return 123 end }
package.loaded["core/team_alignment"] = {}
package.loaded["systems/wall_melee_contact"] = {}
package.loaded["systems/wall_navigation_service"] = {}
package.loaded["core/sound_service"] = {}
package.loaded["systems/tree_damage_rules"] = {is_tree=function() return false end}
local enemy_ai = require("modifiers/modifier_enemy_wall_ai")
local worker_ai = require("modifiers/modifier_lumberjack_ai")
local start_key = enemy_ai.HandleAttackStart and "HandleAttackStart" or "OnAttackStart"
local original_start = enemy_ai[start_key]
local counters
enemy_ai[start_key] = function(self, params)
    counters.nested_start = counters.nested_start + 1
    return original_start(self, params)
end

local function actor(id)
    return { entindex=function() return id end, IsNull=function() return false end }
end

local function fixture(enemy_count, worker_count)
    local enemies, workers = {}, {}
    local wall = actor(1000000)
    for i=1,enemy_count do
        local unit = actor(i)
        unit.survival_is_wave_monster = true
        unit.survival_is_boss = false
        local mod = setmetatable({wall_entindex=wall:entindex(),
            GetParent=function()
                counters.get_parent = counters.get_parent + 1
                return unit
            end}, enemy_ai)
        unit.enemy_owner = mod
        enemies[i] = {unit=unit,mod=mod}
    end
    for i=1,worker_count do
        local unit = actor(enemy_count+i)
        local mod = setmetatable({GetParent=function()
            counters.get_parent = counters.get_parent + 1
            return unit
        end}, worker_ai)
        unit.worker_owner = mod
        workers[i] = {unit=unit,mod=mod}
    end
    -- Reuse event tables to isolate listener work from allocation and harvesting.
    -- One third owned enemies, one third workers, one third unrelated attackers.
    local events = {
        {attacker=enemies[1].unit,target=wall},
        {attacker=workers[1].unit,target=wall},
        {attacker=actor(1000001),target=wall},
    }
    return enemies,workers,events
end

local count = tonumber(arg and arg[1]) or 12000
assert(count > 0 and count % 3 == 0, "event count must be a positive multiple of 3")
for _, scenario in ipairs({{61,26},{244,104}}) do
    local enemies,workers,events = fixture(scenario[1],scenario[2])
    for _, mode in ipairs({"broadcast", "early_owner_guard", "direct_owner_dispatch"}) do
        counters = {native_callbacks=0,nested_start=0,get_parent=0,forwarded=0}
        collectgarbage("collect")
        local started = os.clock()
        for i=1,count do
            local params = events[(i-1)%3+1]
            if mode == "direct_owner_dispatch" then
                counters.native_callbacks = counters.native_callbacks + 1
                local owner = params.attacker.enemy_owner
                if owner then
                    counters.forwarded = counters.forwarded + 1
                    enemy_ai.OnAttackLanded(owner,params)
                end
                owner = params.attacker.worker_owner
                if owner then
                    counters.forwarded = counters.forwarded + 1
                    worker_ai.OnAttackLanded(owner,params)
                end
            else
                for _, entry in ipairs(enemies) do
                    counters.native_callbacks = counters.native_callbacks + 1
                    if mode == "early_owner_guard" then
                        -- Optimistic guard: use the cached owner, not another
                        -- native GetParent call. It still receives every event.
                        if params.attacker == entry.unit then
                            enemy_ai.OnAttackLanded(entry.mod,params)
                        end
                    else
                        enemy_ai.OnAttackLanded(entry.mod,params)
                    end
                end
                for _, entry in ipairs(workers) do
                    counters.native_callbacks = counters.native_callbacks + 1
                    worker_ai.OnAttackLanded(entry.mod,params)
                end
            end
        end
        local cpu = (os.clock()-started)*1000
        assert(enemies[1].mod.last_attack_activity==123,
            "owned enemy contact must retain its native progress update")
        local expected_callbacks = mode == "direct_owner_dispatch" and count
            or count*(scenario[1]+scenario[2])
        assert(counters.native_callbacks==expected_callbacks)
        assert(counters.nested_start==(mode=="broadcast" and count*scenario[1] or count/3))
        print(string.format(
            "OFFLINE_FANOUT enemies=%d workers=%d events=%d mode=%s callbacks=%d nested_start=%d get_parent=%d forwarded=%d lua_cpu_ms=%.3f",
            scenario[1],scenario[2],count,mode,counters.native_callbacks,
            counters.nested_start,counters.get_parent,counters.forwarded,cpu))
    end
end
print("PASS: deterministic listener count assertions; timings are offline Lua CPU, not in-game frame cost")
