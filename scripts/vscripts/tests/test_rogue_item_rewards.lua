package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) return value end
IsServer = function() return true end
UF_SUCCESS, UF_FAIL_CUSTOM = 0, 1
local bus,events = require("core/event_bus"),require("core/events")
package.loaded["systems/rogue_builder_start_effect_service"] = {}
local legacy_grants=0
package.loaded["systems/rogue_effect_state_service"]={add_numeric=function() legacy_grants=legacy_grants+1 return true end}
local registry=require("systems/rogue_effect_registry")
local item_class=require("items/item_survival_rogue_building_upgrade")
local builder, target, items, removed, notifications, upgrade_calls, quote_ok, upgrade_ok, owner, building_id
local inventory_full, create_ok, builder_available
local function reset()
    bus.reset()
    items, removed, notifications, upgrade_calls={},{},{},{}
    quote_ok,upgrade_ok,create_ok,builder_available=true,true,true,true
    inventory_full=false;owner=0;building_id="main_city"
    builder={survival_player_id=0}
    function builder:IsNull() return false end
    function builder:IsAlive() return true end
    function builder:AddItem(item) if inventory_full then return nil end;items[#items+1]=item;return item end
    function builder:RemoveItem(item) removed[#removed+1]=item end
    target={}
    function target:IsNull() return false end
    function target:IsAlive() return self.dead~=true end
    function target:entindex() return 77 end
    function target:HasModifier() return self.constructing==true end
    CreateItem=function(name, item_owner, purchaser)
        assert(item_owner==builder and purchaser==builder,"reward must reach the registered builder")
        if not create_ok then return nil end
        local item=setmetatable({name=name,charges=1},{__index=item_class})
        function item:GetCaster() return builder end
        function item:GetCursorTarget() return target end
        function item:GetCurrentCharges() return self.charges end
        function item:SetCurrentCharges(n) self.charges=n end
        function item:EndCooldown() self.cooldown_reset=true end
        return item
    end
    UTIL_Remove=function(item) removed[#removed+1]=item end
    bus.handle_request(events.BUILDER_GET_REQUEST,function(p)
        if not builder_available then return {ok=false} end
        assert(p.player_id==0 or p.builder==builder)
        return {ok=true,builder=builder,player_id=0}
    end)
    bus.handle_request(events.BUILDING_QUERY_REQUEST,function(p)
        assert(p.entindex==77)
        return {player_id=owner,building_id=building_id}
    end)
    for _,event in ipairs({events.BUILDING_UPGRADE_QUOTE_REQUEST,events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST}) do
        bus.handle_request(event,function(p)
            assert(p.player_id==0 and p.upgrade_mode=="one")
            return {ok=quote_ok,error=not quote_ok and "已达最高等级" or nil}
        end)
    end
    for _,event in ipairs({events.BUILDING_UPGRADE_FREE_REQUEST,events.GOLD_MINE_LEVEL_UPGRADE_REQUEST}) do
        bus.handle_request(event,function(p)
            assert(p.player_id==0 and p.upgrade_mode=="one" and p.system_free_upgrade)
            upgrade_calls[#upgrade_calls+1]={event=event,payload=p}
            return {ok=upgrade_ok,error=not upgrade_ok and "升级中" or nil}
        end)
    end
    bus.subscribe(events.UI_NOTIFICATION,function(p) notifications[#notifications+1]=p end)
end
local function grant(kind,count)
    return registry.get(kind or "grant_building_upgrade_action").apply({player_id=0,params={count=count or 1},effect={effect_type=kind}})
end
reset();assert(grant());assert(#items==1 and items[1].name=="item_survival_rogue_building_upgrade")
assert(legacy_grants==0,"card must issue an item, not silently grant an automatic upgrade credit")
local item=items[1]
assert(item:CastFilterResultTarget(target)==UF_SUCCESS)
item:OnSpellStart();assert(#upgrade_calls==1 and #removed==1)
item:OnSpellStart();assert(#upgrade_calls==1 and #removed==1,"item cannot be consumed twice")
reset();inventory_full=true;local ok,err=grant();assert(not ok and err=="builder_inventory_full" and #removed==1)
reset();create_ok=false;ok,err=grant();assert(not ok and err=="item_create_failed" and #removed==0)
reset();builder_available=false;ok,err=grant();assert(not ok and err=="builder_unavailable")
reset();assert(grant());owner=1;item=items[1];assert(item:CastFilterResultTarget(target)==UF_FAIL_CUSTOM)
item:OnSpellStart();assert(#upgrade_calls==0 and #removed==0)
reset();assert(grant());target.constructing=true;items[1]:OnSpellStart();assert(#upgrade_calls==0 and #removed==0)
reset();assert(grant());target.dead=true;items[1]:OnSpellStart();assert(#upgrade_calls==0 and #removed==0)
reset();assert(grant());quote_ok=false;items[1]:OnSpellStart();assert(#upgrade_calls==0 and #removed==0)
reset();assert(grant());upgrade_ok=false;items[1]:OnSpellStart();assert(#upgrade_calls==1 and #removed==0)
upgrade_ok=true;items[1]:OnSpellStart();assert(#upgrade_calls==2 and #removed==1)
reset();assert(grant(nil,2));items[1]:OnSpellStart();assert(items[1].charges==1 and #removed==0)
items[1]:OnSpellStart();assert(#removed==1)
reset();building_id="gold_mine";assert(grant());items[1]:OnSpellStart()
assert(upgrade_calls[1].event==events.GOLD_MINE_LEVEL_UPGRADE_REQUEST and #removed==1)
reset();assert(grant("grant_nuclear_bomb_action"));assert(items[1].name=="item_survival_rogue_nuclear_bomb")
print("PASS rogue item rewards: builder delivery, full inventory, target ownership, failed upgrade retention, one-use and gold mine")
-- Nuclear-bomb effect audit uses the production action and scheduler callback.
local scheduled, killed = nil, {}
package.loaded["core/scheduler"] = {after=function(_,callback) scheduled=callback end}
DOTA_TEAM_BADGUYS=3
local function monster(index,flags)
    local u=flags or {}
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetTeamNumber() return self.team or 3 end
    function u:HasModifier() return self.modifier_boss==true end
    function u:ForceKill() self.dead=true;killed[#killed+1]=index end
    return u
end
local wave=monster(1,{survival_is_wave_monster=true})
local challenge=monster(2,{survival_is_challenge_monster=true})
local boss=monster(3,{survival_is_wave_monster=true,survival_is_boss=true})
local friend=monster(4,{survival_is_wave_monster=true,team=2})
local unrelated=monster(5)
Entities={FindAllByClassname=function() return {wave,challenge,boss,friend,unrelated} end}
require("items/item_survival_rogue_actions")
reset();assert(grant("grant_nuclear_bomb_action"))
local bomb=items[1]
setmetatable(bomb,{__index=item_survival_rogue_nuclear_bomb})
function bomb:IsNull() return false end
bomb:OnSpellStart();assert(scheduled and #killed==0 and #removed==0)
assert(scheduled()==0.05 and #killed==1)
assert(scheduled()==false and #killed==2 and #removed==1)
assert(not boss.dead and not friend.dead and not unrelated.dead)
bomb:OnSpellStart();assert(#killed==2 and #removed==1)
print("PASS nuclear bomb effect: bounded batches, wave/challenge kills, Boss/friendly exclusion, single consumption")
