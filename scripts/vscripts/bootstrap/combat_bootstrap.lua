local event_bus = require("core/event_bus")
local combat_events = require("combat/combat_events")
local rules = require("combat/damage_rule_config")
local context = require("combat/damage_context")
local repository = require("combat/damage_transaction_repository")
local adapter = require("adapters/dota_damage_adapter")
local damage_service = require("combat/damage_service")
local filter_service = require("combat/damage_filter_service")
local debug_service = require("combat/combat_debug_service")
local debug_command = require("combat/combat_debug_command")

local M = {}

function M.init()
    repository.init(rules)
    debug_service.init(rules)
    damage_service.init({ event_bus = event_bus, events = combat_events,
        context = context, rules = rules, repository = repository,
        adapter = adapter, debug = debug_service })
    event_bus.handle_request(combat_events.DEAL_REQUEST, function(request)
        return damage_service:Deal(request)
    end)
    filter_service.init({ event_bus = event_bus, events = combat_events,
        repository = repository, config = rules })
    filter_service.register()
    debug_command.init(damage_service, rules)
end

return M
