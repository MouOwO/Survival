package.path="scripts/vscripts/?.lua;"..package.path
local now, tasks, popups=0,{},{}
GameRules={GetGameTime=function() return now end}
package.loaded["core/scheduler"]={
    after=function(delay,callback) tasks[#tasks+1]={delay=delay,callback=callback};return #tasks end,
    cancel=function(id) tasks[id].cancelled=true end,
}
package.loaded["core/sound_service"]={play=function() end}
OVERHEAD_ALERT_GOLD=0
PlayerResource={GetPlayer=function(_,id) return "player_"..id end}
SendOverheadEventMessage=function(player,style,unit,amount)
    assert(player=="player_0" and style==OVERHEAD_ALERT_GOLD)
    popups[#popups+1]={unit=unit,amount=amount}
end
local tower={survival_player_id=0,IsNull=function() return false end}
local feedback=require("systems/tower_machine_gun_feedback")
local function state(sequence) return {machine_gun_sequence=sequence,next_gold_feedback_at=999} end
local burst=state(5)
for _,amount in ipairs({3,3,3,3,3,3}) do feedback.gold(burst,tower,amount) end
assert(#tasks==0 and #popups==0,"round must not display predicted income before actual hits finish")
feedback.flush_gold(burst,tower)
assert(#popups==1 and popups[1].amount==18 and popups[1].unit==tower)
feedback.flush_gold(burst,tower)
assert(#popups==1,"flush replay duplicated income")
feedback.gold(burst,tower,3);feedback.flush_gold(burst,tower)
assert(popups[2].amount==3,"interrupted round must show only its earned amount")
local fusion=state(0)
for hit=1,20 do feedback.gold(fusion,tower,2) end
assert(#tasks==1 and tasks[1].delay==0.8,"fusion numbers must coalesce without per-hit timers")
tasks[1].callback()
assert(#popups==3 and popups[3].amount==40)
local fractions=state(8)
feedback.gold(fractions,tower,0.6);feedback.flush_gold(fractions,tower)
feedback.gold(fractions,tower,0.6);feedback.flush_gold(fractions,tower)
assert(popups[4].amount==1 and math.abs(fractions.pending_gold_number-0.2)<0.00001)
print("TOWER_GOLD_NUMBERS_PASS: actual round totals, interrupted bursts, fusion aggregation, duplicate flush and fractional carry")
