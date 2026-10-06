-- Real growth, equipment shells, kill progression, UI projection and tooltip.
-- Only engine entities/output and external inventory/profile inputs are mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local weapons = require("config/generated/weapon_definitions")
local progression = require("systems/weapon_progression")
local counts, net, items, transactions = {}, {}, {}, {}
local reduction, time, next_entity, equipped_id = 0, 0, 100, nil
local native_print = print
print = function(...)
    local first = tostring(select(1, ...))
    assert(not first:find("[EventBus] handler error", 1, true), first)
    native_print(...)
end
GameRules = {GetGameTime = function() return time end}
PlayerResource = {IsValidPlayerID = function(_, id) return id == 0 end,
    GetPlayer = function() return {} end, GetTeam = function() return 2 end}
CustomNetTables = {SetTableValue = function(_, name, key, value)
    net[name] = net[name] or {}; net[name][key] = value
end}
CustomGameEventManager = {Send_ServerToPlayer = function() end}
package.loaded["systems/technology_stat_manager"] = {training_room_multiplier = function() return 1 end}
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen = function() return false end}
package.loaded["systems/player_profile_service"] = {get_profile = function() return {} end}
local hero = {IsNull = function() return false end, GetPlayerOwnerID = function() return 0 end,
    GetTeamNumber = function() return 2 end, AddNewModifier = function() end,
    AddItem = function(_, item) items[item.id] = item end,
    RemoveItem = function(_, item) items[item.id] = nil end}
CreateItem = function(name)
    next_entity = next_entity + 1
    return {id = next_entity, name = name, charges = -1,
        IsNull = function(self) return self.removed == true end,
        entindex = function(self) return self.id end,
        SetCurrentCharges = function(self, value) self.charges = value end}
end
UTIL_Remove = function(item) item.removed = true end
bus.reset(); scheduler.clear()
bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, function() return {ok = true, snapshot = {counts = counts}} end)
bus.handle_request(events.EQUIPMENT_INSTANCE_GET_REQUEST, function()
    local instances = {}; for id, quantity in pairs(counts) do instances[id] = {quantity = quantity} end
    return {ok = true, instances = instances}
end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function()
    return {ok = true, totals = {weapon_upgrade_requirement_reduction = reduction}}
end)
local function equip(id, reason)
    local changes = {[id] = 1}
    if equipped_id and equipped_id ~= id then changes[equipped_id] = -1; counts[equipped_id] = nil end
    counts[id], equipped_id = 1, id
    bus.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = 0, changes = changes,
        snapshot = {counts = counts}, reason = reason or "test_equip"})
end
local function transaction(payload)
    transactions[#transactions + 1] = payload
    equip(assert(next(payload.grant)), payload.reason)
    return {ok = true}
end
bus.handle_request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST, transaction)
bus.handle_request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST, transaction)
require("systems/weapon_growth_service").init()
require("systems/weapon_equipment_service").init()
require("systems/equipment_growth_service").init()
local ui = require("ui/weapon_synthesis_snapshot_service"); ui.init()
bus.emit(events.HERO_SUMMONED, {player_id = 0, unit = hero})
local function growth() return bus.request(events.WEAPON_GROWTH_GET_REQUEST, {player_id = 0}).snapshot end
local function shell()
    for _, item in pairs(items) do if item.survival_content_id == equipped_id then return item end end
    error("missing real equipment shell")
end
local function snapshot()
    ui.publish_player(0, "test_read")
    return net.survival_weapon_snapshot["0"]
end
local function field(view, label)
    for _, entry in ipairs(view.fields) do if entry.label == label then return entry.value end end
end
local function assert_max()
    local value, combined, item = growth(), snapshot(), shell()
    assert(value.is_max_level == 1 and value.stage_attack_target == 0 and value.stage_attack_remaining == 0)
    assert(item.charges == 0, "terminal shell must never show fake native charges")
    assert(net.survival_inventory_item_identity[tostring(item.id)].is_max_level == 1)
    assert(combined.growth.is_max_level == 1 and combined.growth.stage_attack_target == 0)
    local view = combined.tooltip_view_model.items[equipped_id]
    assert(field(view, "当前进度") == "MAX" and field(view, "剩余进度") == nil)
end
local victim = {IsNull = function() return false end, GetTeamNumber = function() return 3 end}
local function kills(count)
    for _ = 1, count do bus.emit(events.ENGINE_ENTITY_KILLED, {attacker = hero, victim = victim}) end
end
local function damages(count)
    for _ = 1, count do bus.emit(events.COMBAT_DAMAGE_RESOLVED,
        {player_id = 0, attacker = hero, owner_hero = hero, final_damage = 10, target = victim}) end
end

equip("weapon_growth_sword_01")
assert(growth().is_max_level == 0 and growth().stage_attack_target == 200 and shell().charges == 200)
equip("weapon_ice_blade_01")
assert(growth().stage_attack_target == 200 and shell().charges == 200)
reduction = 35
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, totals = {weapon_upgrade_requirement_reduction = reduction}})
equip("weapon_ice_blade_02")
assert(growth().stage_attack_target == 215 and shell().charges == 215)
kills(10); damages(3)
local lower = snapshot()
assert(lower.growth.stage_attack_count == 10 and lower.growth.stage_attack_target == 215
    and lower.growth.stage_attack_remaining == 205 and shell().charges == 205,
    "kill progress owns the counter and keeps the reduced authoritative target")
assert(field(lower.tooltip_view_model.items[equipped_id], "当前进度") == "10 / 215")

-- Complete the authored kill upgrade to MAX, then interleave damage and kills.
equip("weapon_ice_blade_04"); kills(315)
assert(equipped_id == "weapon_ice_blade_max" and #transactions == 1)
assert_max()
local attack_before = growth().growth_attack
damages(100); kills(100)
assert(growth().growth_attack == attack_before + 1600 and #transactions == 1)
assert_max()
-- Even an old/default counter event cannot revive charges on the max shell.
bus.emit(events.WEAPON_GROWTH_CHANGED, {player_id = 0, reason = "damage_dealt", snapshot = {
    content_id = equipped_id, stage_attack_target = 200, stage_attack_remaining = 200}})
assert(shell().charges == 0)

for _, id in ipairs({"weapon_growth_sword_max", "weapon_frost_blade_max", "weapon_legend_abyss_10"}) do
    equip(id); assert_max()
    local before = growth().growth_attack
    if id == "weapon_legend_abyss_10" then damages(10) else
        for _ = 1, 10 do bus.emit(events.HERO_MAIN_ATTACK_LANDED, {player_id = 0, target = victim}) end
    end
    assert(growth().growth_attack == before + weapons.by_id[id].attack_gain_per_attack * 10)
    assert_max()
end
assert(#transactions == 1, "MAX does not synthesize another series or stop permanent growth")
assert(not progression.is_max_level(weapons.by_id.weapon_epic_icefire_06))
assert(not progression.is_max_level(weapons.by_id.weapon_ice_blade_04))
assert(not progression.is_max_level({}))
-- Inventory/synthesis material tooltips also show MAX when not equipped.
counts.weapon_ice_blade_max = 1
local material = snapshot().tooltip_view_model.items.weapon_ice_blade_max
assert(field(material, "当前进度") == "MAX")
native_print("WEAPON_MAX_PROGRESS_PASS: real upgrade to MAX, native charge setter 0, identity/UI/tooltip MAX, reduced kill progress, 100 damage growth hits and terminal attack growth retained")
