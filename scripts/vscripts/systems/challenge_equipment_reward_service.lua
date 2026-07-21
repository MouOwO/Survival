local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/challenge_definitions")
local M = {}
local ice_counts, granted = {}, {}
local function valid_owner(x)
 local p=tonumber(x.player_id); return p and p>=0 and p or nil
end
local function grant(p,id,key)
 granted[p]=granted[p] or {}; if granted[p][key] then return {ok=true,idempotent=true} end
 local r=event_bus.request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,{player_id=p,request_id="challenge:"..key,consume={},grant={[id]=1},reason="challenge_equipment_reward"})
 if r and r.ok then granted[p][key]=true; print("[CHALLENGE_EQUIP_REWARD] player="..p.." content="..id) end
 return r or {ok=false,error="challenge_inventory_unavailable"}
end
local function on_kill(x)
 local p=valid_owner(x); if not p then return end
 local name=tostring(x.archetype_id or (x.encounter and x.encounter.archetype_id) or "")
 local encounter=tostring(x.encounter_id or "")
 if name=="" and encounter=="" then return end
 if name~="ice_soul" and name~="ice_spirit" and not encounter:find("ice",1,true) then return end
 ice_counts[p]=(ice_counts[p] or 0)+1
 if ice_counts[p]>=200 then grant(p,"item_large_polar_crystal","ice_soul_200") end
end
local function claim(x)
 local p=valid_owner(x); local id=tostring(x.challenge_id or ""); if not p then return {ok=false,error="challenge_player_invalid"} end
 local d=config.by_id[id]; if not d or d.review_status=="暂不支持" then return {ok=false,error="challenge_unknown_fail_closed"} end
 if not d.reward_content_id then return {ok=false,error="challenge_no_equipment_reward"} end
 if x.authoritative~=true then return {ok=false,error="challenge_authority_required"} end
 return grant(p,d.reward_content_id,id..":"..tostring(x.completion_id or "default"))
end
function M.init() ice_counts,granted={},{}; event_bus.subscribe(events.MONSTER_KILLED,on_kill); event_bus.handle_request(events.CHALLENGE_EQUIPMENT_REWARD_REQUEST,claim); print("[CHALLENGE_EQUIP_INIT] ice_soul_target=200 unknown=fail_closed") end
return M
