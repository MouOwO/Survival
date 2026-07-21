local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/shop_upgrade_definitions")
local M = {}
local by_id, done, locked = {}, {}, {}
local function init_index() by_id={}; for _,x in ipairs(config.entries or {}) do if x.enabled~=false and x.upgrade=="repeat_purchase" then by_id[x.content_id]=x end end end
local function purchase(x)
 local p=tonumber(x.player_id); local q=tostring(x.request_id or ""); local id=tostring(x.content_id or "")
 if not p or p<0 or q=="" or not by_id[id] then return {ok=false,error="shop_equipment_invalid"} end
 done[p]=done[p] or {}; if done[p][q] then return done[p][q] end
 if locked[p] then return {ok=false,error="shop_equipment_player_locked"} end
 locked[p]=true
 local r=event_bus.request(events.SHOP_PURCHASE_REQUEST,{player_id=p,request_id="equipment:"..q,entry_id="weapon:"..id}) or {ok=false,error="shop_purchase_unavailable"}
 locked[p]=nil; done[p][q]=r
 print("[SHOP_EQUIP_PAID_CHAIN] content="..id.." ok="..tostring(r.ok)); return r
end
function M.init() done,locked={},{}; init_index(); event_bus.handle_request(events.SHOP_EQUIPMENT_UPGRADE_REQUEST,purchase); print("[SHOP_EQUIP_INIT] config=shop_upgrade_definitions paid_chain=true limit=5") end
return M
