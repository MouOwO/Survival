package.path = "scripts/vscripts/?.lua;" .. package.path
GetMapName = function() return "template_map" end
Vector = function(x, y, z) return {x=x, y=y, z=z} end
DOTA_TEAM_BADGUYS, DOTA_UNIT_CAP_NO_ATTACK = 3, 0
class = function(t) return t end
IsServer = function() return true end
RandomFloat = function() return 99 end
GameRules = {GetGameTime = function() return 0 end}
PlayerResource = {GetPlayer = function(_, id) return {id=id} end}
local events = require("core/events")
local handlers, requests, grids, awards, created = {}, {}, {}, {}, {}
local occupied, releases, occupancy_reads = {}, {}, 0
local fail_next_create = false
local function update_occupancy(payload, release)
    for x=payload.grid_x,payload.grid_x+payload.footprint.x-1 do
        for y=payload.grid_y,payload.grid_y+payload.footprint.y-1 do
            local key=x..":"..y
            if not release or occupied[key]==payload.entindex then
                occupied[key]=not release and payload.entindex or nil
            end
        end
    end
end
local bus = {
    subscribe = function(name, fn)
        handlers[name] = handlers[name] or {}
        table.insert(handlers[name], fn)
    end,
    handle_request = function(name, fn) requests[name] = fn end,
    emit = function(name, payload)
        for _, fn in ipairs(handlers[name] or {}) do fn(payload) end
    end,
    request = function(name, payload)
        if requests[name] then return requests[name](payload) end
        if name == events.GRID_OCCUPY_REQUEST then
            grids[#grids+1] = payload
            update_occupancy(payload)
            return true
        elseif name == events.GRID_RELEASE_REQUEST then
            assert(type(payload.entindex)=="number", "tree release must preserve other owners' occupancy")
            releases[#releases+1] = payload
            update_occupancy(payload,true)
            return true
        elseif name == events.RESOURCE_ADD_REQUEST then
            awards[#awards+1] = payload
            return {ok=true}
        elseif name == events.BUILDING_LIST_REQUEST then return {} end
    end,
}
package.loaded["core/event_bus"] = bus
package.loaded["core/particle_manager"] = {show_green_number = function() end}
package.loaded["core/sound_service"] = {play = function() end}
package.loaded["core/modifier_registry"] = {ensure = function() end}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
package.loaded["systems/technology_stat_manager"] = {get = function() return {final={lumberjack={}}} end}
package.loaded["systems/player_profile_service"] = {get_profile = function() return nil end}
package.loaded["systems/grid_placement_system"] = {occupant_at_position=function(point)
    occupancy_reads=occupancy_reads+1
    return occupied[math.floor(point.x/64)..":"..math.floor(point.y/64)]
end}
local function unit(name, id)
    local u = {name=name, id=id}
    function u:IsNull() return self.removed == true end
    function u:entindex() return self.id end
    function u:IsAlive() return true end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return 2 end
    function u:HasModifier() return false end
    function u:SetAbsOrigin(p) self.position=p end
    function u:GetAbsOrigin() return self.position end
    function u:SetBaseMaxHealth(h) self.max=h end
    function u:SetMaxHealth(h) self.max=h end
    function u:SetHealth(h) self.health=h end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.max end
    for _, name in ipairs({"SetPhysicalArmorBaseValue", "SetModel", "SetOriginalModel",
        "SetModelScale", "SetAttackCapability"}) do u[name] = function() end end
    return u
end
CreateUnitByName = function(name, position)
    if fail_next_create then fail_next_create=false; return nil end
    local u = unit(name, #created+100)
    u.position=position
    created[#created+1]=u
    return u
end
UTIL_Remove = function(u) u.removed=true end
local trees = require("systems/tree_system")
local workers = require("systems/worker_system")
local ai = require("modifiers/modifier_lumberjack_ai")
local config = require("config/tree_config")
local bonus = config.lumber_efficiency_buff_per_level
local function reset()
    handlers, requests, grids, awards, created = {}, {}, {}, {}, {}
    occupied, releases, occupancy_reads = {}, {}, 0
    fail_next_create=false
    trees.init()
    workers.init()
end
local function build(player_id, x, y)
    local city = unit("main_city", player_id+10)
    city.position = Vector(x,y,400)
    bus.emit(events.BUILDING_CREATED, {building_id="main_city", unit=city, player_id=player_id})
end
local function worker_state(player_id, tree, fusion)
    local u = unit("npc_survival_lumberjack", player_id+200)
    local modifier = setmetatable({GetParent=function() return u end}, {__index=ai})
    modifier:OnRefresh({player_id=player_id, tree_entindex=tree:entindex(),
        base_lumber_efficiency=10+player_id, fusion_count=fusion or 1})
    u.FindModifierByName = function() return modifier end
    local state = {unit=u, player_id=player_id, worker_type="lumberjack",
        base_lumber_efficiency=10+player_id, technology_efficiency=0,
        technology_multiplier=fusion or 1}
    for index=1,100 do
        local name, value = debug.getupvalue(requests[events.WORKER_LIST_REQUEST], index)
        if not name then break end
        if name == "workers" then value[u:entindex()] = state; return state, modifier end
    end
    error("worker state fixture unavailable")
end

reset()
assert(#grids == 4, "only the primary tree socket in each court is reserved before building")
local reserved_cells = {}
for _, grid in ipairs(grids) do
    for x=grid.grid_x,grid.grid_x+grid.footprint.x-1 do
        for y=grid.grid_y,grid.grid_y+grid.footprint.y-1 do
            local key=x..":"..y
            assert(not reserved_cells[key], "reserved tree footprints must not overlap")
            reserved_cells[key]=true
        end
    end
end
local cases = {
    {0,-2500,5500,"northwest"}, {1,600,5500,"northeast"},
    {2,-2500,2700,"southwest"}, {3,600,2700,"southeast"},
}
for _, case in ipairs(cases) do
    build(case[1],case[2],case[3])
    local tree, point = created[#created], config.spawn_regions[case[4]][1]
    assert(tree.position.x == point.x and tree.position.y == point.y)
    assert(tree.survival_tree_owner_id == case[1])
end
assert(#created == 4)
build(0,600,2700)
assert(#created == 4, "repeated city events cannot create a second personal tree")
local s0, m0 = worker_state(0,created[1])
local s1, m1 = worker_state(1,created[2],3)
local function hit(modifier, target)
    modifier:OnAttackLanded({attacker=modifier:GetParent(),target=target})
    return awards[#awards]
end
assert(hit(m0,created[2]).wood == 10, "foreign tree pays the attacker's own base yield")
assert(awards[#awards].player_id == 0)
created[2].survival_tree_depleted_callback(created[2])
assert(created[1].survival_tree_level == 1 and created[2].survival_tree_level == 2)
assert(m0:GetLumberEfficiency() == 10, "foreign tree upgrades cannot alter attacker UI efficiency")
assert(s1.tree_lumber_efficiency_buff == 3*bonus and m1:GetLumberEfficiency() == 11+3*bonus)
assert(m0.tree_entindex == created[1]:entindex() and m1.tree_entindex == created[2]:entindex())
assert(hit(m0,created[2]).wood == 10, "foreign tree upgrades cannot alter attacker settlements")
assert(m0.manual_control == true, "manual foreign-tree harvesting must not be redirected")
assert(hit(m1,created[1]).wood == 11+3*bonus, "own upgraded tree bonus applies even on foreign trees")
created[1].survival_tree_depleted_callback(created[1])
assert(hit(m0,created[2]).wood == 10+bonus)
assert(hit(m0,created[1]).wood == 10+bonus and not m0.manual_control)
local hero = unit("npc_dota_hero_sven", 300)
hero.IsRealHero = function() return true end
bus.emit(events.TREE_HIT, {attacker=hero, target=created[2], player_id=0,
    team=2, source="hero"})
assert(awards[#awards].player_id == 0
    and awards[#awards].wood == config.hero_base_lumber_efficiency+bonus,
    "heroes also harvest foreign trees using their own tree bonus")
local before = #awards
m0:OnAttackLanded({attacker=s0.unit,target=unit("ordinary_enemy",301)})
assert(#awards == before, "ordinary combat cannot generate tree income")

-- The occasional percentage damage must affect the actual target, not the
-- attacker's personal tree, while paying the same personal harvest amount.
RandomFloat = function() return 0 end
m0.tree_damage_chance_pct = 10
created[2].health = 2
local own_level = created[1].survival_tree_level
hit(m0,created[2])
assert(created[2].survival_tree_level == 3 and created[1].survival_tree_level == own_level)
assert(m0:GetLumberEfficiency() == 10+bonus)
RandomFloat = function() return 99 end

reset()
for player_id=0,3 do build(player_id,600,5500) end
assert(#created == 4)
for i=1,4 do
    for j=i+1,4 do
        local a,b=created[i].position,created[j].position
        assert((a.x-b.x)^2+(a.y-b.y)^2 >= 192^2, "same-region trees cannot overlap")
    end
end
-- Cleanup gives the next city the original reserved socket and a fresh level.
local removed = created[3]
bus.emit(events.PLAYER_DISCONNECTED, {player_id=2})
assert(removed.removed)
assert(#releases==1 and releases[1].entindex==removed:entindex(),
    "a backup tree releases its own footprint instead of reserving unused ground")
local released_grid=trees._tree_grid_for_test(removed.position)
for x=released_grid.grid_x,released_grid.grid_x+1 do
    for y=released_grid.grid_y,released_grid.grid_y+1 do
        assert(occupied[x..":"..y]==nil,"backup tree ground is buildable after disconnect")
    end
end
local previous_grids,previous_releases=#grids,#releases
bus.emit(events.PLAYER_DISCONNECTED, {player_id=2})
assert(#grids==previous_grids and #releases==previous_releases,
    "a duplicate disconnect must not touch another asset's cells")
build(2,600,5500)
assert(#created == 5)
assert(created[5].position.x == removed.position.x and created[5].position.y == removed.position.y)
assert(created[5].survival_tree_level == 1)
bus.emit(events.PLAYER_DISCONNECTED, {player_id=0})
local primary=trees._tree_grid_for_test(config.spawn_regions.northeast[1])
for x=primary.grid_x,primary.grid_x+1 do
    for y=primary.grid_y,primary.grid_y+1 do
        assert(occupied[x..":"..y]=="survival_tree_reserved",
            "the one primary patch remains reserved after its owner leaves")
    end
end

-- Backup points are normal building ground. A later city must skip any
-- footprint occupied by a real building, including partial cell overlaps.
reset()
build(0,600,5500)
local points=config.spawn_regions.northeast
local function building_at(slot,index,partial)
    local cells=trees._tree_grid_for_test(points[slot])
    bus.request(events.GRID_OCCUPY_REQUEST,{grid_x=cells.grid_x,grid_y=cells.grid_y,
        footprint=partial and {x=1,y=1} or cells.footprint,entindex=index})
end
building_at(2,900,true)
local before_reads=occupancy_reads
build(1,600,5500)
assert(#created==2 and created[2].position.x==points[3].x
    and created[2].position.y==points[3].y,"a blocked backup is skipped for the next clear one")
assert(occupancy_reads-before_reads<=16,"socket validation performs at most four fixed four-cell lookups")
local blocked=trees._tree_grid_for_test(points[2])
assert(occupied[blocked.grid_x..":"..blocked.grid_y]==900,"tree admission must not overwrite a building")
building_at(4,901)
previous_grids=#grids
build(2,600,5500)
assert(#created==2 and #grids==previous_grids,"full or built-over sockets never create an overlapping tree")
assert(occupied[blocked.grid_x..":"..blocked.grid_y]==900)

-- Precise owner release cannot erase an unrelated later reservation.
local backup=trees._tree_grid_for_test(points[3])
building_at(3,902)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
assert(occupied[backup.grid_x..":"..backup.grid_y]==902,
    "disconnect only releases cells still owned by the removed tree")
previous_releases=#releases
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
assert(#releases==previous_releases and occupied[backup.grid_x..":"..backup.grid_y]==902)

-- Failed native creation cannot leak a socket claim or block a retry.
bus.request(events.GRID_RELEASE_REQUEST,{grid_x=blocked.grid_x,grid_y=blocked.grid_y,
    footprint=blocked.footprint,entindex=900})
fail_next_create=true
previous_grids=#grids
build(2,600,5500)
assert(#created==2 and #grids==previous_grids,"failed creation must not occupy or claim the candidate")
build(2,600,5500)
assert(#created==3 and created[3].position.x==points[2].x and created[3].position.y==points[2].y)
building_at(1,903)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
local primary_grid=trees._tree_grid_for_test(points[1])
assert(occupied[primary_grid.grid_x..":"..primary_grid.grid_y]==903,
    "restoring a primary marker must not overwrite a newer foreign occupant")
print("MULTIPLAYER_TREES_PASS: four primary patches, independent shared-region trees, per-player harvest, built-over backup rejection and precise cleanup")

-- Rich Lv2 snapshots must reach the real worker/AI consumers, including fusion.
package.loaded["systems/match_setup_service"]={get_mode=function() return "rich" end}
reset()
local rich_tree=unit("enemy_tree",500)
trees._reset_for_test(1,rich_tree,0)
local rich_worker,rich_ai=worker_state(0,rich_tree,3)
local foreign_worker,foreign_ai=worker_state(1,rich_tree)
trees._upgrade_tree_for_test(rich_tree)
local expected=3*(bonus+config.rich_level2_reward.lumber_efficiency)
assert(rich_worker.tree_lumber_efficiency_buff==expected
    and rich_ai:GetLumberEfficiency()==10+expected,"owner worker panel and AI receive the extra rich reward")
assert(foreign_ai:GetLumberEfficiency()==11,"teammate worker panel cannot inherit the reward")
assert(hit(rich_ai,rich_tree).wood==rich_ai:GetLumberEfficiency(),"display and real yield must match")
print("RICH_TREE_WORKER_REWARD_PASS: real worker state, fused AI efficiency and harvest agree; teammate unchanged")
