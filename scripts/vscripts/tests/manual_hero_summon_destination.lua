-- Tools server: script require("tests/manual_hero_summon_destination").run()
-- Build a main city first. Read real owned cities and call the production
-- resolver. Only teleport temporary creeps; never replace a player's hero.
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
        local listed = require("core/event_bus").request(require("core/events").BUILDING_LIST_REQUEST, {})
        local city_count = 0
        for _, building in ipairs(listed and listed.ok and listed.buildings or {}) do
            local city, slot = building.unit, tonumber(building.player_id)
            if building.building_id == "main_city" and slot and valid(city) and city:IsAlive() then
                city_count = city_count + 1
                local authored = copy(city:GetAbsOrigin())
                local point, _, metadata = resolver.resolve(city, {}, slot)
                metadata = metadata or {}
                log("RESOLVE", { "slot=" .. slot,
                    "source=" .. code(metadata.source),
                    "attempts=" .. tostring(tonumber(metadata.attempts) or 0),
                    "search_distance=" .. string.format("%.2f", tonumber(metadata.distance) or 0),
                    "last_rejection=" .. code(metadata.last_reason) })
                if check(slot, "resolved", point ~= nil) then
                    local city_dx, city_dy = point.x - authored.x, point.y - authored.y
                    check(slot, "near_own_city", metadata.source == "main_city"
                        and city_dx * city_dx + city_dy * city_dy <= 640 * 640 + 1)
                    check(slot, "candidate_navigation", destination.validate_hero_position(point) == true)
                    local unit = CreateUnitByName("npc_dota_creep_goodguys_melee",
                        point, false, nil, nil, city:GetTeamNumber())
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
                        local after = city:GetAbsOrigin()
                        check(slot, "city_unchanged", after.x == authored.x
                            and after.y == authored.y and after.z == authored.z)
                        UTIL_Remove(unit)
                    end
                end
            end
        end
        check(-1, "built_main_city_required", city_count > 0,
            { "eligible_cities=" .. city_count })
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
