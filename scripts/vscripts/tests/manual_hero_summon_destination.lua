-- Tools server: script require("tests/manual_hero_summon_destination").run()
-- Read authored markers and call the production resolver. Teleport only owned
-- temporary creeps; never summon/replace a player's hero or modify map markers.
local M = {}
local function valid(unit) return unit and not unit:IsNull() end
local function copy(point) return Vector(point.x, point.y, point.z) end
local function log(tag, fields)
    local line = { "[MATCH_TEST]", "ALTAR_" .. tag }
    for _, value in ipairs(fields or {}) do line[#line + 1] = tostring(value) end
    print(table.concat(line, " "))
end
local function code(value)
    return tostring(value or "none"):gsub("[^a-zA-Z0-9_]", "_")
end

function M.run()
    if not IsServer() or not IsInToolsMode() then
        log("REFUSED", { "tools_server_required" })
        print("MATCH_TEST_ALTAR_RUNTIME_DONE")
        return { ok = false, error = "tools_server_required" }
    end
    local owned, passed, failed, cleanup_failed = {}, 0, 0, 0
    local function cleanup()
        for _, unit in ipairs(owned) do
            if valid(unit) then
                pcall(UTIL_Remove, unit)
                if valid(unit) then cleanup_failed = cleanup_failed + 1 end
            end
        end
    end
    local function check(slot, name, accepted, fields)
        if accepted then passed = passed + 1 else failed = failed + 1 end
        local values = { accepted and "PASS" or "FAIL", "slot=" .. slot, name }
        for _, field in ipairs(fields or {}) do values[#values + 1] = field end
        log("CHECK", values)
        return accepted
    end
    local ok = pcall(function()
        local resolver = require("systems/hero_summon_destination")
        local destination = require("systems/destination_validation_service")
        for slot = 0, 3 do
            local marker = Entities:FindByName(nil, "player_" .. slot .. "_hero_spawn")
            local builder = Entities:FindByName(nil, "player_" .. slot .. "_builder_spawn")
            if check(slot, "markers_present", valid(marker) and valid(builder)) then
                local authored, builder_position = copy(marker:GetAbsOrigin()), copy(builder:GetAbsOrigin())
                local forward = builder.GetForwardVector and builder:GetForwardVector() or Vector(1, 0, 0)
                local anchor = {
                    IsNull = function() return false end,
                    GetAbsOrigin = function() return copy(builder_position) end,
                    GetForwardVector = function() return copy(forward) end,
                    GetTeamNumber = function() return DOTA_TEAM_GOODGUYS end,
                }
                local original_ok, original_reason = destination.validate_hero_position(authored)
                local point, _, metadata = resolver.resolve(anchor, { spawn_offset = 260 }, slot)
                metadata = metadata or {}
                log("RESOLVE", { "slot=" .. slot,
                    "authored_valid=" .. tostring(original_ok == true),
                    "authored_reason=" .. code(original_reason),
                    "source=" .. code(metadata.source),
                    "attempts=" .. tostring(tonumber(metadata.attempts) or 0),
                    "search_distance=" .. string.format("%.2f", tonumber(metadata.distance) or 0),
                    "last_rejection=" .. code(metadata.last_reason) })
                if check(slot, "resolved", point ~= nil) then
                    check(slot, "candidate_navigation", destination.validate_hero_position(point) == true)
                    local unit = CreateUnitByName("npc_dota_creep_goodguys_melee",
                        point, false, nil, nil, DOTA_TEAM_GOODGUYS)
                    if check(slot, "probe_created", valid(unit)) then
                        owned[#owned + 1] = unit
                        unit:SetEntityName("manual_altar_destination_" .. math.floor(Time() * 1000) .. "_" .. slot)
                        unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
                        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
                        unit:SetIdleAcquire(false)
                        unit:SetAcquisitionRange(0)
                        unit:SetHullRadius(32)
                        unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
                        unit.survival_hero_id = "manual_altar_destination_probe"
                        local moved, move_reason = destination.teleport(unit, point, false)
                        local landed = copy(unit:GetAbsOrigin())
                        local dx, dy = landed.x - point.x, landed.y - point.y
                        check(slot, "actual_teleport", moved == true and dx * dx + dy * dy <= 1,
                            { "reason=" .. code(move_reason) })
                        check(slot, "actual_navigation", destination.validate_hero_position(landed) == true)
                        local floor = GetGroundHeight(landed, nil)
                        check(slot, "on_ground", math.abs(landed.z - floor) <= 2,
                            { "height_error=" .. string.format("%.2f", math.abs(landed.z - floor)) })
                        local clear = true
                        for direction = 0, 7 do
                            local angle = direction * math.pi / 4
                            local edge = landed + Vector(math.cos(angle) * 32, math.sin(angle) * 32, 0)
                            edge.z = GetGroundHeight(edge, nil)
                            if destination.validate_hero_position(edge) ~= true
                                or math.abs(edge.z - landed.z) > 64 then clear = false end
                        end
                        check(slot, "clearance_32", clear)
                        local reachable = 0
                        for direction = 0, 7 do
                            local angle = direction * math.pi / 4
                            local near = landed + Vector(math.cos(angle) * 128, math.sin(angle) * 128, 0)
                            near.z = GetGroundHeight(near, nil)
                            if destination.validate_hero_position(near) == true
                                and math.abs(near.z - landed.z) <= 64
                                and GridNav:CanFindPath(landed, near) then
                                reachable = reachable + 1
                            end
                        end
                        check(slot, "nearby_path_128", reachable > 0,
                            { "reachable_directions=" .. reachable,
                                "full_room_navigation_verified=false" })
                        -- The source marker is never corrected or moved by this test.
                        local after = marker:GetAbsOrigin()
                        check(slot, "marker_unchanged", after.x == authored.x
                            and after.y == authored.y and after.z == authored.z)
                        UTIL_Remove(unit)
                    end
                end
            end
        end
    end)
    if not ok then failed = failed + 1; log("EXCEPTION", { "fixture_aborted" }) end
    cleanup()
    local accepted = ok and failed == 0 and cleanup_failed == 0
    log("SUMMARY", { accepted and "PASS" or "FAIL", "passed=" .. passed,
        "failed=" .. failed, "remaining_handles=" .. cleanup_failed })
    print("MATCH_TEST_ALTAR_RUNTIME_DONE")
    return { ok = accepted, passed = passed, failed = failed, remaining = cleanup_failed }
end

return M
