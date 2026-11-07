-- Presentation only. No settlement, authority, queue or periodic work lives here.
-- An explicit one-time client capability keeps old clients on their old event.
-- Do not infer this capability from a pre-existing compact schema handshake.
local events=require("core/events")
local M={}
local scope
local function current(value)
    return value and scope==value and value.manager==CustomGameEventManager
        and value.bus==package.loaded["core/event_bus"]
        and value.generation==value.bus.get_generation()
end
function M.init()
    if current(scope)then return end
    local old=scope
    scope=nil
    if old then
        old.bus.unsubscribe(old.disconnect)
        if old.listener and old.manager.UnregisterListener then
            old.manager:UnregisterListener(old.listener)
        end
    end
    local manager=CustomGameEventManager
    if not manager or type(manager.RegisterListener)~="function"then return end
    local event_bus=require("core/event_bus")
    local value={bus=event_bus,generation=event_bus.get_generation(),players={},manager=manager}
    scope=value
    -- Tests/older hosts without a listener retain the previous presentation.
    if manager and type(manager.RegisterListener)=="function"then
        value.listener=manager:RegisterListener("survival_gold_number_ready",function(source,payload)
            if not current(value)or type(payload)~="table"or payload.v~=1 then return end
            local id=tonumber(payload.PlayerID)
            if not id or id<0 or id~=math.floor(id)or id==math.huge then return end
            local player=PlayerResource and PlayerResource:GetPlayer(id)
            if not player then return end
            local ok,actor=pcall(EntIndexToHScript,tonumber(source)or-1)
            if not ok or actor~=player then return end
            if type(player.GetPlayerID)~="function"or player:GetPlayerID()~=id then return end
            value.players[id]=player
        end)
    end
    value.disconnect=event_bus.subscribe(events.PLAYER_DISCONNECTED,function(payload)
        if current(value)then value.players[tonumber(payload and payload.player_id)or-1]=nil end
    end)
end
function M.send(player_id,player,entindex,amount,critical)
    -- Callers already fetch the current recipient after successful settlement.
    -- No extra native player lookup or scene scan is added per income event.
    M.init()
    if not player then return false end
    if scope and scope.players[player_id]==player then
        return CustomGameEventManager:Send_ServerToPlayer(player,"gn",{e=entindex,a=amount,c=critical})
    end
    return CustomGameEventManager:Send_ServerToPlayer(player,"survival_gold_mine_income_number",{
        target_entindex=entindex,amount=amount,critical=critical,
    })
end
return M
