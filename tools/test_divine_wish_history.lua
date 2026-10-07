-- Exercise the production wish registry/runtime and reward history together.
package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["systems/player_context_service"] = {is_defeated=function() return false end}
package.loaded["systems/rogue_builder_start_effect_service"] = {init=function() end}
PlayerResource = {GetPlayer=function() return {} end}
GameRules = {GetGameTime=function() return 0 end}
RandomFloat = function() return 0 end
RandomInt = function() return 1 end
local snapshots = {}
local function copy(t)
    if type(t) ~= "table" then return t end
    local r = {}; for k,v in pairs(t) do r[k]=copy(v) end; return r
end
CustomNetTables = {SetTableValue=function(_,_,key,value) snapshots[key]=copy(value) end}
local cards = require("config/generated/rogue_reward_cards")
-- Force precisely the three real rewards observed in the reported live match.
local ids = {"divine_wish", "tower_growth", "gunpowder_splash", "internship_certificate"}
cards.rows = {}; for _,id in ipairs(ids) do cards.rows[#cards.rows+1]=cards.by_id[id] end
local bus, events = require("core/event_bus"), require("core/events")
local service = require("systems/rogue_reward_service")
local runtime = require("systems/rogue_effect_runtime_service")
local effect_state = require("systems/rogue_effect_state_service")
local registry = require("systems/rogue_effect_registry")
local function reset()
    bus.reset(); snapshots={}; service.init()
end
local function offer(player)
    local r=service.debug_offer(player,{"divine_wish","tower_growth","gunpowder_splash"})
    assert(r.ok)
    return {player_id=player,token=r.token,card_id="divine_wish"}
end
local function choose(p) return bus.request(events.ROGUE_REWARD_SELECT_REQUEST,p) end
local function validate(player)
    local history=snapshots[tostring(player)].history
    assert(#history==4,"wish plus all three granted treasures must be visible")
    local seen={}
    for _,row in ipairs(history) do
        assert(not seen[row.card_id],"duplicate history entry")
        seen[row.card_id]=true
        assert(row.icon_name==cards.by_id[row.card_id].icon_name)
        assert(row.description==cards.by_id[row.card_id].description)
        if row.card_id~="divine_wish" then assert(row.parent_card_id=="divine_wish") end
    end
    for _,id in ipairs(ids) do assert(seen[id],"missing "..id) end
    assert(history[1].card_id=="divine_wish")
    assert(#runtime.snapshot(player)==4,"actual effects must be applied once")
    assert(effect_state.numeric(player,"repairer_training_capacity_flat:train_repairer_01")==2)
    assert(effect_state.has_effect(player,"ballista_damage_bonus_pct"))
end
reset()
local p=offer(0); assert(choose(p).ok); validate(0)
assert(not choose(p).ok); validate(0)
local grant="reward:"..p.token..":divine_wish"
assert(bus.request(events.ROGUE_REWARD_GRANT_RANDOM_REQUEST,{
    player_id=0,parent_grant_id=grant,parent_card_id="divine_wish",count=3,reward_type="boss"
}).ok)
validate(0)
local q=offer(1); assert(#snapshots["1"].history==0)
assert(choose(q).ok); validate(1); validate(0)
assert(not bus.request(events.ROGUE_REWARD_OPEN_REQUEST,{player_id=0}).ok,
    "randomly granted cards must be excluded from subsequent offers")
-- A later child failing must neither conceal successful children nor reapply them on retry.
reset()
local handler=registry.get("training_capacity_flat")
local original=handler.apply
handler.apply=function() return false,"injected_failure" end
p=offer(0); assert(not choose(p).ok)
assert(#snapshots["0"].history==2,"already applied children must remain visible after failure")
assert(#runtime.snapshot(0)==2)
handler.apply=original
assert(choose(p).ok); validate(0)
-- Pool exhaustion must not create phantom history or effects.
reset()
cards.rows={cards.by_id.divine_wish,cards.by_id.tower_growth,cards.by_id.gunpowder_splash}
p=offer(0); assert(not choose(p).ok)
assert(#snapshots["0"].history==0 and #runtime.snapshot(0)==0)
print("PASS divine wish: real effects, all child icons/descriptions, isolation, retries, deduplication and pool exhaustion")
