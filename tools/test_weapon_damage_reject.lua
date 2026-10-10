-- Offline regression: source may be a TEMP candidate; default is the repository module.
package.path = "scripts/vscripts/?.lua;" .. package.path
local path = arg[1] or "scripts/vscripts/systems/weapon_growth_service.lua"
local baseline = arg[2]
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local function encode(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys, pieces = {}, {}
    for key in pairs(value) do keys[#keys+1] = key end
    table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
    for _,key in ipairs(keys) do pieces[#pieces+1]=tostring(key).."="..encode(value[key]) end
    return "{"..table.concat(pieces,",").."}"
end
local function suite(source, optimized)
    local listeners,handlers={},{}
    local h={snapshots=0, inventory=0, permanent=0, profile=0, owner_reads=0,
        multiplier=3, publications={}, heroes={}, frozen=false}
    local bus={}
    function bus.subscribe(name,fn) listeners[name]=listeners[name] or {};table.insert(listeners[name],fn) end
    function bus.handle_request(name,fn) handlers[name]=fn end
    function bus.emit(name,payload) for _,fn in ipairs(listeners[name] or {}) do fn(payload) end end
    function bus.request(name,payload)
        if name==events.CONTENT_INVENTORY_GET_REQUEST then
            h.inventory=h.inventory+1;return {ok=true,snapshot={counts={item_forging_hammer=2}}}
        elseif name==events.PERMANENT_REWARD_EFFECTS_GET_REQUEST then
            h.permanent=h.permanent+1;return {ok=true,totals={weapon_upgrade_requirement_reduction=17}}
        end
        return assert(handlers[name],name)(payload)
    end
    package.loaded["core/event_bus"]=bus
    package.loaded["systems/technology_stat_manager"]={training_room_multiplier=function() return h.multiplier end}
    package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function() return h.frozen end}
    package.loaded["systems/player_profile_service"]={get_profile=function() h.profile=h.profile+1;return {} end}
    package.loaded["systems/commerce_effects"]={owned=function() return false end}
    local service=assert(loadfile(source))();service.init()
    local getter=assert(handlers[events.WEAPON_GROWTH_GET_REQUEST])
    local snapshot,slot
    for i=1,30 do local name,fn=debug.getupvalue(getter,i);if not name then break end
        if name=="snapshot" then snapshot,slot=fn,i;break end end
    assert(snapshot and slot)
    debug.setupvalue(getter,slot,function(...) h.snapshots=h.snapshots+1;return snapshot(...) end)
    bus.subscribe(events.WEAPON_GROWTH_CHANGED,function(payload)
        h.publications[#h.publications+1]=encode(payload)
    end)
    local function entity(fields)
        fields=fields or {};fields.IsNull=fields.IsNull or function() return false end
        fields.AddNewModifier=function() end
        fields.GetOwnerEntity=fields.GetOwnerEntity or function(self) h.owner_reads=h.owner_reads+1;return self.owner end
        return fields
    end
    local function hero(player)
        local unit=entity();h.heroes[player]=unit
        bus.emit(events.HERO_SUMMONED,{player_id=player,unit=unit});return unit
    end
    local equipped={}
    local function equip(player,id)
        bus.emit(events.WEAPON_EQUIPPED_CHANGED,{player_id=player,slot="main_hand",content_id=id,
            previous_content_id=equipped[player]});equipped[player]=id
    end
    local function hit(player,attacker,owner,damage)
        bus.emit(events.COMBAT_DAMAGE_RESOLVED,{player_id=player,attacker=attacker,
            owner_hero=owner or h.heroes[player],final_damage=damage or 10,target={}})
    end
    for player=0,3 do hero(player) end
    local worker=entity()
    local cold_before={h.snapshots,h.inventory,h.permanent,h.owner_reads,#h.publications}
    for _=1,104 do for player=0,3 do for _=1,30 do hit(player,worker) end end end
    local cold_snapshots=h.snapshots-cold_before[1]
    assert(cold_snapshots==(optimized and 0 or 12480))
    assert(h.owner_reads==0 and #h.publications==0,"Non-growth rejects before owner traversal and publication")
    if optimized then assert(h.inventory==0 and h.permanent==0,"Cold rejected hits do not build input snapshots") end
    equip(0,"weapon_growth_sword_01")
    local before=h.snapshots
    for _=1,1000 do hit(0,worker) end
    assert(h.snapshots-before==(optimized and 0 or 1000) and h.owner_reads==0)
    local selected={}
    for id,definition in pairs(weapons.by_id) do
        local series=definition.series_id
        if (series=="ice_blade" or series=="epic_icefire" or series=="legend_abyss")
            and (not selected[series] or id<selected[series]) then selected[series]=id end
    end
    local traces={}
    for index,series in ipairs({"ice_blade","epic_icefire","legend_abyss"}) do
        local player=index-1;local id=assert(selected[series]);equip(player,id)
        local definition=weapons.by_id[id];local unit=h.heroes[player]
        local sources={unit,entity({owner=unit}),entity({survival_owner_hero=unit}),
            entity({survival_hero_owner=unit}),entity({survival_monkey_king_clone=true,survival_player_id=player})}
        local count=0;before=h.snapshots
        for _=1,200 do for _,attacker in ipairs(sources) do hit(player,attacker);count=count+1 end end
        assert(h.snapshots-before==(optimized and count or count*2),"Exactly one surviving publication snapshot per accepted hit")
        local result=snapshot(player)
        assert(result.growth_attack==(tonumber(definition.attack_gain_per_attack) or 0)*count*h.multiplier)
        assert(result.growth_strength==(tonumber(definition.strength_gain_per_attack) or 0)*count*h.multiplier)
        assert(result.growth_agility==(tonumber(definition.agility_gain_per_attack) or 0)*count*h.multiplier)
        assert(result.growth_intellect==(tonumber(definition.intellect_gain_per_attack) or 0)*count*h.multiplier)
        local cycle=entity();cycle.owner=cycle
        local rejected={worker,entity({IsBuilding=function() return true end,owner=unit}),cycle,
            entity({IsNull=function() return true end}),h.heroes[3],
            entity({survival_monkey_king_clone=true,survival_player_id=3})}
        local publications=#h.publications;before=h.snapshots
        for _,attacker in ipairs(rejected) do hit(player,attacker) end
        hit(player,unit,h.heroes[3]);hit(player,unit,nil,0);hit(player,unit,nil,-1)
        h.frozen=true;hit(player,unit);h.frozen=false
        bus.emit(events.HERO_REMOVED,{player_id=player,unit=unit});hit(player,unit,unit)
        local replacement=hero(player);hit(player,unit,unit)
        assert(#h.publications==publications,"Invalid ownership/frozen/dead or replaced hero never grants growth")
        if optimized then assert(h.snapshots==before,"All rejection paths omit snapshot") end
        hit(player,replacement)
        traces[#traces+1]=encode(snapshot(player))
    end
    assert(h.profile==0)
    return table.concat(h.publications,"\n").."\n"..table.concat(traces,"\n"),cold_snapshots
end
local after,cold=suite(path,true)
if baseline then local before=suite(baseline,false);assert(after==before,"Growth publication payloads and final snapshots must remain byte-identical") end
print("WEAPON_DAMAGE_REJECT_PASS: 12480 unrelated hits use 0 snapshots; 3000 owned hits retain every gain/publication; hero summons, clones, replacement and guards preserved"..(baseline and "; before/after identical" or ""))
