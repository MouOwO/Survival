package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local now, net, attempts = 0, {}, {}
GameRules = {GetGameTime=function() return now end}
PlayerResource = {IsValidPlayerID=function(_, id) return id==0 or id==1 end}
CustomNetTables = {SetTableValue=function(_, table_name, key, value) net[key]=value end}
local service = require("systems/book_auto_purchase_service")
local function purchase(p)
 assert(p.silent_notification and not p.request_id)
 attempts[#attempts+1] = p
 return {ok=false, error="insufficient_resources"}
end
bus.reset(); scheduler.clear(); service.init(purchase)
local function toggle(id, player)
 return bus.request(events.SHOP_AUTO_PURCHASE_TOGGLE_REQUEST,{player_id=player or 0,entry_id=id})
end
local book, super = "shop_item_knowledge_book", "shop_item_super_knowledge_book"
assert(not toggle("shop_weapon_growth_sword_01").ok)
assert(toggle(book).enabled)
now=.99;scheduler.think();assert(#attempts==0)
now=1;scheduler.think();assert(#attempts==1 and attempts[1].entry_id==book)
now=2;scheduler.think();assert(#attempts==2, "failed purchases retry normally")
assert(toggle(super).enabled);assert(toggle(book,1).enabled)
now=3;scheduler.think();assert(#attempts==5)
assert(not toggle(book).enabled)
assert(net.auto_purchase_0[book]==nil and net.auto_purchase_0[super]==1)
now=4;scheduler.think();assert(#attempts==7)
bus.emit(events.PLAYER_DEFEATED,{player_id=0})
now=5;scheduler.think();assert(#attempts==8 and attempts[8].player_id==1)
assert(not toggle(super).ok, "defeated players cannot re-enable")
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
now=6;scheduler.think();assert(#attempts==8 and scheduler.task_count()==0)
bus.reset();service.init(purchase);assert(toggle(book).enabled)
bus.reset();service.init(purchase);assert(scheduler.task_count()==0 and next(net.auto_purchase_0)==nil)
print("BOOK_AUTO_PURCHASE_PASS: 1s pacing, both books, retries, toggles, isolation, defeat/disconnect/reset")
