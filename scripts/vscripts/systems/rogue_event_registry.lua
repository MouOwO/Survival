local events = require("core/events")

local M = {}

local event_names = {
    building_created = events.BUILDING_CREATED,
    building_changed = events.BUILDING_CHANGED,
    building_destroyed = events.BUILDING_DESTROYED,
    monster_spawned = events.MONSTER_SPAWNED,
    worker_changed = events.WORKER_CHANGED,
    hero_summoned = events.HERO_SUMMONED,
    reward_offer_created = events.ROGUE_REWARD_CHANGED,
}

function M.core_event(event_type)
    return event_names[tostring(event_type or "")]
end

return M