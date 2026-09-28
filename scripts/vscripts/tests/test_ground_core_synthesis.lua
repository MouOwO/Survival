package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
package.loaded["systems/player_profile_service"] = {get_profile=function()return {save={content_inventory={},gameplay_stats={}}}end}
PlayerResource = {IsValidPlayerID=function(_,id)return id==0 or id==1 end}
CustomNetTables = {SetTableValue=function()end}
IsServer=function()return true end
local inventory = require("systems/content_inventory_service")
local claims = require("items/challenge_ground_reward_claim")
local pickup = require("systems/ground_item_pickup_service")
local callbacks = {}
GameRules = {GetGameModeEntity=function()return {SetContextThink=function(_,name,fn)callbacks[name]=fn end}end}
local slots = {}
local hero = {IsNull=function()return false end,GetPlayerOwnerID=function()return 0 end,
 GetItemInSlot=function(_,slot)return slots[slot]end,GetAbsOrigin=function()return {}end}
function hero:RemoveItem(item) for i=0,8 do if slots[i]==item then slots[i]=nil end end end
function UTIL_Remove(item) item.removed=true end
local native_event=false
function hero:AddItem(item) slots[0]=item;if native_event then item:Claim(self) end end
bus.reset();inventory.init();require("systems/inventory_transaction_service").init();require("systems/weapon_synthesis_service").init()
bus.handle_request(events.INVENTORY_ITEM_SHELL_ADOPT_REQUEST,function()return {ok=true,adopted=false}end)
local function counts(player)return bus.request(events.CONTENT_INVENTORY_GET_REQUEST,{player_id=player or 0}).snapshot.counts end
local serial=0
local function core(quantity)
 serial=serial+1;local id=serial
 return {survival_owner_player_id=0,survival_content_id="material_molten_core_01",survival_ground_reward=true,
 IsNull=function(self)return self.removed==true end,entindex=function()return id end,
 GetCurrentCharges=function()return quantity or 1 end,Claim=claims.claim}
end
local function flush()
 for i=1,10 do
  local any=false
  for name,fn in pairs(callbacks)do any=true;callbacks[name]=nil;if fn() then callbacks[name]=fn end end
  if not any then return end
 end
 error("synthesis never settled")
end
for i=1,9 do
 native_event=(i%2==0)
 local item=core()
 assert(pickup.pickup_candidate(hero,{item=item}).ok)
 flush()
 if i==3 then assert(counts().material_molten_core_02==1) end
end
assert(counts().material_molten_core_03==1)
assert((counts().material_molten_core_01 or 0)==0 and (counts().material_molten_core_02 or 0)==0)
assert(not counts(1).material_molten_core_03)
native_event=false;assert(pickup.pickup_candidate(hero,{item=core(9)}).ok);flush()
assert(counts().material_molten_core_03==2,"a charged stack grants its full quantity exactly once")
print("GROUND_CORE_SYNTHESIS_PASS: F pickup and native event, no duplicate grants, 3-to-1, 9-to-1, charged stack, player isolation")
