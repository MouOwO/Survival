local event_bus = require("core/event_bus")
local events = require("core/events")
local M = {}
local subscription, serial, notices = nil, 0, {}

-- UI notification only: the wave system has already spawned the actual boss.
local function on_spawn(payload)
    if not payload or payload.monster_source ~= "wave" or payload.is_boss ~= true
        or payload.boss_warning == false then return end
    local wave = tonumber(payload.wave_number)
    if not wave or wave < 1 or wave ~= math.floor(wave) then return end
    local id = tonumber(payload.player_id)
    local key = tostring(id or "all") .. ":" .. tostring(wave)
    if notices[key] or not CustomGameEventManager then return end
    local player = id and PlayerResource and PlayerResource:GetPlayer(id)
    if id and not player then return end
    notices[key] = true
    serial = serial + 1
    local notice = {notice_id=tostring(serial)..":"..key, wave_number=wave}
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player,"survival_boss_warning",notice)
    else
        CustomGameEventManager:Send_ServerToAllClients("survival_boss_warning",notice)
    end
end
function M.init()
    if subscription then event_bus.unsubscribe(subscription) end
    subscription = event_bus.subscribe(events.MONSTER_SPAWNED,on_spawn)
end
return M
