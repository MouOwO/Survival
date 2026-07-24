local event_bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/technology_definitions")

local M = {}

local function valid_player_id(player_id)
    return player_id ~= nil
        and player_id >= 0
        and PlayerResource:IsValidPlayerID(player_id)
end

function M.register(state, push_snapshot)
    event_bus.handle_request(
        events.TECHNOLOGY_CHEAT_SET_REQUEST,
        function(payload)
            local player_id = tonumber(payload and payload.player_id)
            local technology_id = tostring(
                payload and payload.technology_id or ""
            )
            if not valid_player_id(player_id) or technology_id == "" then
                return {
                    ok = false,
                    error = "technology_cheat_request_invalid",
                }
            end

            local definition = definitions.by_id[technology_id]
            if not definition then
                return {
                    ok = false,
                    error = "科技ID不存在：" .. technology_id,
                }
            end

            local group = tostring(definition.technology_group or "")
            local target_level = tonumber(definition.level) or 0
            if group == "" or target_level <= 0 then
                return {
                    ok = false,
                    error = "technology_definition_invalid",
                }
            end

            state.technology_by_player[player_id] =
                state.technology_by_player[player_id] or {}
            local levels = state.technology_by_player[player_id]
            local current_level = tonumber(levels[group]) or 0
            if target_level < current_level then
                return {
                    ok = false,
                    error = "不能用较低等级科技降级：当前Lv."
                        .. tostring(current_level),
                }
            end
            if target_level == current_level then
                return {
                    ok = false,
                    error = "科技已经是Lv." .. tostring(current_level),
                }
            end

            levels[group] = target_level
            event_bus.emit(events.TECHNOLOGY_CHANGED, {
                player_id = player_id,
                technology_group = group,
                level = target_level,
                levels = levels,
                reason = "cheat_addtechnology",
            })
            push_snapshot(player_id, "technology_cheat_changed")
            return {
                ok = true,
                technology_id = technology_id,
                technology_group = group,
                level = target_level,
                display_name = definition.display_name or technology_id,
            }
        end
    )
end

return M