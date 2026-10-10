package.path = 'scripts/vscripts/?.lua;' .. package.path
local bus = require('core/event_bus')
local events = require('combat/combat_events')
local rules = require('combat/damage_rule_config')
local repository = require('combat/damage_transaction_repository')
local context = require('combat/damage_context')
local service = require('combat/damage_service')
local adapter = require('adapters/dota_damage_adapter')
DAMAGE_TYPE_PURE = 4
GameRules = { GetGameTime = function() return 0 end }
local unit = { IsNull = function() return false end, entindex = function() return 1 end }
local applies, blocked = 0, 0
ApplyDamage = function(input) applies = applies + 1; assert(input.damage == input.damage and input.damage < math.huge) end
RandomFloat = function() return 0 end
repository.init(rules)
service.init({ event_bus = bus, events = events, context = context, rules = rules,
    repository = repository, adapter = adapter, debug = { log = function() end } })
bus.subscribe(events.DAMAGE_BLOCKED, function() blocked = blocked + 1 end)
for _, value in ipairs({ 0/0, math.huge, -math.huge, -1 }) do
    local result = service:Deal({ attacker = unit, victim = unit, source_kind = 'ability',
        base_damage = value, damage_type = 4 })
    assert(not result.success and result.blocked_reason == 'invalid_base_damage')
    local applied = adapter:Apply({ attacker = unit, victim = unit, damage = value, damage_type = 4 })
    assert(not applied.ok and applied.error == 'invalid_damage')
end
assert(applies == 0 and blocked == 4, 'invalid damage must never enter native combat')
local overflow = service:Deal({ attacker = unit, victim = unit, source_kind = 'ability',
    base_damage = 1e308, pre_damage_bonus_pct = 10, damage_type = 4 })
assert(not overflow.success and overflow.blocked_reason == 'invalid_damage' and applies == 0)
for _, value in ipairs({ 0, 1, 1e12, 9e15 }) do
    local result = service:Deal({ attacker = unit, victim = unit, source_kind = 'ability',
        base_damage = value, damage_type = 4 })
    assert(result.success and result.calculated_damage == value)
end
assert(applies == 4)
print('DAMAGE_FINITE_BOUNDARY_PASS NaN/Inf/overflow rejected before ApplyDamage, logical large damage preserved')
