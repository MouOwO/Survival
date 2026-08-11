local M = {}

function M.limit_reached(maximum, current)
    maximum = tonumber(maximum) or 0
    return maximum > 0 and (tonumber(current) or 0) >= maximum
end

function M.new(maximum_provider)
    local service = {
        counts = {},
        reservations = {},
        maximum_provider = maximum_provider,
    }

    function service:reset()
        self.counts = {}
        self.reservations = {}
    end

    function service:count(player_id, building_id)
        local by_player = self.counts[player_id]
        return by_player and (by_player[building_id] or 0) or 0
    end

    function service:change(player_id, building_id, delta)
        self.counts[player_id] = self.counts[player_id] or {}
        local value = (self.counts[player_id][building_id] or 0) + delta
        self.counts[player_id][building_id] = math.max(0, value)
    end

    function service:reservation_count(player_id, class_id)
        local by_player = self.reservations[player_id]
        local by_class = by_player and by_player[class_id] or nil
        local total = 0
        for _, reserved in pairs(by_class or {}) do
            if reserved then total = total + 1 end
        end
        return total
    end

    function service:snapshot(player_id, class_id)
        return {
            count = self:count(player_id, class_id),
            pending = self:reservation_count(player_id, class_id),
            maximum = tonumber(self.maximum_provider()) or 5,
        }
    end

    function service:release(player_id, class_id, entindex)
        local by_player = self.reservations[player_id]
        local by_class = by_player and by_player[class_id] or nil
        if not by_class or not by_class[entindex] then return false end
        by_class[entindex] = nil
        return true
    end

    function service:reserve(player_id, class_id, entindex)
        self.reservations[player_id] = self.reservations[player_id] or {}
        local by_player = self.reservations[player_id]
        by_player[class_id] = by_player[class_id] or {}
        local by_class = by_player[class_id]
        local snapshot = self:snapshot(player_id, class_id)
        if by_class[entindex] then
            snapshot.ok = true
            snapshot.reserved = true
            snapshot.idempotent = true
            return snapshot
        end
        if snapshot.maximum > 0
            and snapshot.count + snapshot.pending >= snapshot.maximum then
            snapshot.ok = false
            snapshot.error = "tower_class_limit_reached"
            return snapshot
        end
        by_class[entindex] = true
        snapshot = self:snapshot(player_id, class_id)
        snapshot.ok = true
        snapshot.reserved = true
        return snapshot
    end

    return service
end

return M