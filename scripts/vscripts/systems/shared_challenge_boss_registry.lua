-- Physical shared-arena bosses are world slots, not player-owned instances.
-- Personal sessions subscribe only after their normal entry checks succeed.
local M = {}
local slots, by_entindex, by_session, by_player = {}, {}, {}, {}
local hooks, epoch = nil, 0

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit:IsAlive()
end

function M.key(encounter_id, member)
    if not member or member.spawn_mode == "maintain_count"
        or (tonumber(member.max_alive) or 1) ~= 1 then return nil end
    -- Only authored single bosses share a physical arena. Private practice
    -- rooms and their configured multi-monster populations retain their rules.
    if encounter_id ~= "encounter_challenge_05"
        and encounter_id ~= "encounter_challenge_08"
        and encounter_id ~= "encounter_challenge_09"
        and encounter_id ~= "encounter_challenge_11" then return nil end
    return encounter_id .. ":" .. tostring(member.member_id)
        .. ":" .. tostring(member.spawn_target_name or member.location_id)
end

local function forget_session(slot, session)
    slot.participants[session] = nil
    local owned = by_session[session]
    if owned then
        owned[slot.key] = nil
        if next(owned) == nil then
            by_session[session] = nil
            local player = by_player[session.player_id]
            if player then
                player[session] = nil
                if next(player) == nil then by_player[session.player_id] = nil end
            end
        end
    end
    if slot.target_session == session then slot.target_session, slot.target = nil, nil end
end

function M.detach(session)
    local owned = by_session[session]
    if not owned then return end
    for _, slot in pairs(owned) do forget_session(slot, session) end
end

local function create(slot)
    if slots[slot.key] ~= slot or slot.epoch ~= epoch then return nil, "shared_boss_retired" end
    if slot.spawning then return nil, "shared_boss_spawning" end
    slot.spawning = true
    slot.pending_unit = nil
    local ok, unit, reason = pcall(hooks.create, slot)
    local pending = slot.pending_unit
    slot.pending_unit = nil
    slot.spawning = nil
    if not ok or not alive(unit) then
        if valid(pending) and hooks.destroy then hooks.destroy(pending) end
        return nil, ok and (reason or "shared_boss_spawn_failed") or "shared_boss_spawn_failed"
    end
    slot.unit, slot.life = unit, slot.life + 1
    slot.respawn_at = nil
    by_entindex[unit:entindex()] = slot
    return unit
end

function M.acquire(key, context, member)
    assert(hooks, "shared_boss_registry_not_configured")
    local slot = slots[key]
    if not slot then
        slot = {key=key, context=context, member=member, participants={}, life=0, epoch=epoch}
        slots[key] = slot -- Reserve before native creation/events can reenter.
    end
    if alive(slot.unit) then return slot.unit, slot end
    if slot.unit then return nil, nil, "shared_boss_death_pending" end
    if slot.respawn_at and hooks.now() < slot.respawn_at then
        return nil, nil, "shared_boss_respawning"
    end
    local unit, reason = create(slot)
    return unit, unit and slot or nil, reason
end

function M.attach(slot, session, hero)
    if slots[slot.key] ~= slot or not alive(slot.unit) then return false end
    local owned = by_session[session]
    if not owned then
        owned = {}; by_session[session] = owned
        by_player[session.player_id] = by_player[session.player_id] or {}
        by_player[session.player_id][session] = true
    end
    owned[slot.key], slot.participants[session] = slot, hero or false
    return true
end

function M.bind_player_hero(player_id, hero)
    for session in pairs(by_player[player_id] or {}) do
        for _, slot in pairs(by_session[session] or {}) do
            slot.participants[session] = hero or false
            if slot.target_session == session then slot.target = hero end
        end
    end
end

function M.get(key)
    return slots[key]
end

function M.slot_for(unit)
    if not valid(unit) then return nil end
    local slot = by_entindex[unit:entindex()]
    return slot and slot.unit == unit and slot or nil
end

function M.target_for(unit, position, radius)
    local slot = M.slot_for(unit)
    if not slot then return nil end
    local target = slot.target
    if slot.target_session and slot.participants[slot.target_session] == target
        and alive(target) and (target:GetAbsOrigin() - position):Length2D() <= radius then
        return target
    end
    slot.target_session, slot.target = nil, nil
    -- At most the four accepted players for this one boss, never world units.
    -- A live retained target takes the O(1) branch above.
    for session, hero in pairs(slot.participants) do
        if alive(hero) and (hero:GetAbsOrigin() - position):Length2D() <= radius then
            slot.target_session, slot.target = session, hero
            return hero
        end
    end
    return nil
end

function M.on_death(unit, delay)
    local slot = M.slot_for(unit)
    if not slot then return nil end
    local participants = {}
    for session in pairs(slot.participants) do participants[#participants + 1] = session end
    for _, session in ipairs(participants) do forget_session(slot, session) end
    by_entindex[unit:entindex()] = nil
    slot.unit = nil
    local life, world = slot.life, epoch
    delay = math.max(0, tonumber(delay) or 1)
    slot.respawn_at = hooks.now() + delay
    local function replenish()
        if epoch ~= world or slots[slot.key] ~= slot or slot.life ~= life or slot.unit then return end
        if hooks.now() < slot.respawn_at then return slot.respawn_at - hooks.now() end
        local fresh = create(slot)
        -- Failed native creation retries this same vacant slot, never creates a
        -- second slot/timer or lets an old callback remove a newer occupant.
        if not fresh then slot.respawn_at = hooks.now() + delay; return math.max(1, delay) end
    end
    hooks.after(delay, replenish, "shared_challenge_boss:" .. slot.key)
    return participants, slot
end

function M.reset()
    epoch = epoch + 1
    local old = slots
    slots, by_entindex, by_session, by_player = {}, {}, {}, {}
    for _, slot in pairs(old) do
        if hooks then hooks.cancel("shared_challenge_boss:" .. slot.key) end
        if valid(slot.unit) and hooks and hooks.destroy then hooks.destroy(slot.unit) end
    end
end

function M.configure(options)
    M.reset()
    hooks = assert(options)
end

return M
