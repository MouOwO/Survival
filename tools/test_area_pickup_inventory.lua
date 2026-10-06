-- Real inventory, shell adoption, reward claims, recipes and upgrade materials.
-- Engine mocks model item detachment, native stacking and deferred synthesis.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/item_definitions")
local weapons = require("config/generated/weapon_definitions")
local claim = require("items/challenge_ground_reward_claim")
local pickup = require("systems/ground_item_pickup_service")
package.loaded["systems/player_profile_service"] = {
    get_profile = function() return {save = {content_inventory = {}}} end,
}
function IsServer() return true end
DOTA_TEAM_GOODGUYS = 2
PlayerResource = {IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
    GetTeam = function() return 2 end}
CustomNetTables = {SetTableValue = function() end}
local vector = {}; vector.__index = vector
function Vector(x, y, z) return setmetatable({x = x, y = y or 0, z = z or 0}, vector) end
function vector.__sub(a, b) return Vector(a.x-b.x, a.y-b.y, a.z-b.z) end
function vector:Length2D() return math.sqrt(self.x*self.x + self.y*self.y) end
local serial = 0
local function entity(x)
    serial = serial + 1
    local e = {id = serial, position = Vector(x or 0)}
    function e:IsNull() return self.removed == true end
    function e:entindex() return self.id end
    function e:GetAbsOrigin() return self.position end
    function e:AddNewModifier() end
    return e
end
function UTIL_Remove(e) e.removed = true end
function CreateItem(name)
    local item = entity()
    item.name, item.charges = name, 1
    function item:GetAbilityName() assert(not self.removed); return self.name end
    function item:GetCurrentCharges() assert(not self.removed); return self.charges end
    function item:SetCurrentCharges(n) assert(not self.removed); self.charges = n end
    function item:IsStackable() return self.stackable == true end
    function item:GetContainer() return self.container end
    function item:SetAbilityTextureName() end
    return item
end
CreateUnitByName = function(_, position) return entity(position.x) end
local function harness()
    bus.reset()
    local h = {inventory = {}, drops = {}, tasks = {}, notices = {}, scans = 0, time = 0, adds = 0}
    local hero = entity(0); h.hero = hero
    function hero:GetPlayerOwnerID() return 0 end
    function hero:IsAlive() return not self.dead end
    function hero:GetItemInSlot(slot) return h.inventory[slot] end
    function hero:AddItem(item)
        h.adds = h.adds + 1
        if item.stackable then
            for slot = 0, 8 do
                local held = h.inventory[slot]
                if held and held.stackable and held.name == item.name and not item.reject_merge then
                    held.charges = held.charges + item.charges
                    if item.container then item.container.item = nil end
                    item.removed = true
                    return held
                end
            end
        end
        for slot = 0, 8 do
            if not h.inventory[slot] then
                h.inventory[slot] = item
                if item.container then item.container.item = nil end
                return item
            end
        end
        return nil
    end
    function hero:RemoveItem(item)
        for slot = 0, 8 do
            if h.inventory[slot] == item then h.inventory[slot] = nil; return end
        end
        error("RemoveItem must not be called for a world item")
    end
    function h.ground(item, x, owner)
        local box = entity(x)
        box.item, item.container, item.survival_owner_player_id = item, box, owner or 0
        function box:GetContainedItem() return self.item end
        h.drops[#h.drops+1] = box
        return box
    end
    function hero:DropItemAtPositionImmediate(item, position)
        self:RemoveItem(item)
        return h.ground(item, position.x, item.survival_owner_player_id)
    end
    Entities = {FindAllByClassname = function() h.scans = h.scans+1; return h.drops end}
    local mode = {}
    function mode:SetContextThink(name, callback, delay)
        h.tasks[name] = {callback = callback, due = h.time + delay}
    end
    GameRules = {GetGameModeEntity = function() return mode end}
    function h.drain()
        local calls = 0
        while next(h.tasks) do
            local name, task
            for key, value in pairs(h.tasks) do
                if not task or value.due < task.due then name, task = key, value end
            end
            h.time = task.due
            h.tasks[name] = nil
            local delay = task.callback()
            if delay then h.tasks[name] = {callback = task.callback, due = h.time+delay} end
            calls = calls+1; assert(calls < 50, "pickup/synthesis must terminate")
        end
        return calls
    end
    bus.subscribe(events.UI_NOTIFICATION, function(p) h.notices[#h.notices+1] = p end)
    require("systems/content_inventory_service").init()
    require("systems/inventory_transaction_service").init()
    require("systems/weapon_equipment_service").init()
    require("systems/weapon_synthesis_service").init()
    h.upgrades = require("systems/challenge_upgrade_material_service"); h.upgrades.init()
    bus.emit(events.HERO_SUMMONED, {player_id = 0, unit = hero})
    function h.grant(id, count)
        assert(bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST,
            {player_id = 0, content_id = id, count = count}).ok)
    end
    function h.count(id)
        return bus.request(events.CONTENT_INVENTORY_GET_REQUEST,
            {player_id = 0}).snapshot.counts[id] or 0
    end
    function h.fill()
        for slot = 0, 8 do
            if not h.inventory[slot] then h.inventory[slot] = CreateItem("filler_" .. slot) end
        end
    end
    function h.reward(id, x, count)
        local item = CreateItem(assert(definitions.by_id[id]).engine_item_name)
        item.survival_content_id, item.survival_ground_reward = id, true
        item.charges, item.Claim = count or 1, claim.claim
        return item, h.ground(item, x)
    end
    return h
end

-- Full backpack: skip the nearest blocked item, merge both cores without an
-- extra slot, then use the slot freed by the REAL 3:1 recipe to finish pickup.
do
    local h = harness()
    h.grant("material_molten_core_01", 1)
    h.grant("material_molten_core_02", 1)
    h.drain(); h.fill()
    local loot = CreateItem("test_loot"); local box = h.ground(loot, 5)
    local a, ab = h.reward("material_molten_core_01", 10)
    local b, bb = h.reward("material_molten_core_01", 20)
    local adds = h.adds
    local result = pickup.pickup(h.hero, 0)
    assert(result.picked == 2 and h.adds == adds, "reward stacking must bypass temporary slots")
    assert(h.count("material_molten_core_01") == 3 and ab.removed and bb.removed)
    h.drain()
    assert(result.picked == 3 and not result.full and box.removed)
    assert(h.count("material_molten_core_01") == 0 and h.count("material_molten_core_02") == 2)
    assert(h.scans == 1, "retry must reuse the original cast, not scan the world")
    local again = pickup.pickup(h.hero, 0); h.drain()
    assert(again.found == 0 and h.count("material_molten_core_02") == 2, "no duplicate claims")
end

-- Engine-stackable consumables still merge when every slot is occupied; a
-- genuinely new item stays on the ground and gets a single final capacity hint.
do
    local h = harness()
    local stack = CreateItem("test_stack"); stack.stackable, stack.charges = true, 2
    h.hero:AddItem(stack); h.fill()
    local blocked = CreateItem("new_item"); local blocked_box = h.ground(blocked, 1)
    local incoming = CreateItem("test_stack"); incoming.stackable, incoming.charges = true, 5
    local box = h.ground(incoming, 10)
    local foreign = CreateItem("foreign"); local foreign_box = h.ground(foreign, 20, 1)
    local outside = CreateItem("outside"); local outside_box = h.ground(outside, 301)
    local result = pickup.pickup(h.hero, 0); h.drain()
    assert(result.picked == 1 and result.full and stack.charges == 7 and box.removed)
    assert(not blocked_box.removed and blocked_box.item == blocked)
    assert(not foreign_box.removed and not outside_box.removed)
    assert(#h.notices == 1 and h.notices[1].message:find("空间不足"))
    assert(h.scans == 1)
    local rejected = CreateItem("test_stack")
    rejected.stackable, rejected.reject_merge = true, true
    local rejected_box = h.ground(rejected, 30)
    result = pickup.pickup(h.hero, 0); h.drain()
    assert(result.picked == 0 and result.full and not rejected_box.removed)
    assert(stack.charges == 7 and not rejected.removed, "engine-rejected merges must preserve the drop")
end

-- A failed grant returns the item to its original target, without losing or
-- duplicating either the item or its authoritative quantity.
do
    local h = harness()
    local item, old_box = h.reward("material_molten_core_01", 250)
    local request = bus.request
    bus.request = function(event, payload)
        if event == events.CONTENT_INVENTORY_GRANT_REQUEST
            and payload.reason == "challenge_ground_reward_pickup" then
            return {ok = false, error = "injected_grant_failure"}
        end
        return request(event, payload)
    end
    local result = pickup.pickup(h.hero, 0); h.drain()
    bus.request = request
    assert(result.picked == 0 and not item.removed and old_box.removed)
    assert(#h.drops == 2 and h.drops[2].item == item and h.drops[2].position.x == 250)
    assert(h.count("material_molten_core_01") == 0)
end

-- Every available slot is used, including the ninth backpack slot and the
-- inclusive 300-unit boundary. A new material type cannot bypass a full bag.
do
    local h = harness()
    for i = 1, 8 do h.ground(CreateItem("loot_" .. i), i * 10) end
    local material, box = h.reward("material_molten_core_01", 300)
    local result = pickup.pickup(h.hero, 0); h.drain()
    assert(result.picked == 9 and not result.full and box.removed)
    assert(h.inventory[8] == material and h.count("material_molten_core_01") == 1)
    local other, other_box = h.reward("material_molten_core_02", 10)
    result = pickup.pickup(h.hero, 0); h.drain()
    assert(result.picked == 0 and result.full and not other_box.removed and not other.removed)
    assert(h.count("material_molten_core_02") == 0)
    -- Claimed, persistent shells may be dropped and picked up again. This is a
    -- physical move only; their logical inventory must not be granted twice.
    h.hero:DropItemAtPositionImmediate(material, Vector(100))
    UTIL_Remove(other_box); UTIL_Remove(other)
    result = pickup.pickup(h.hero, 0); h.drain()
    assert(result.picked == 1 and h.inventory[8] == material)
    assert(h.count("material_molten_core_01") == 1)
end

-- A dropped shell no longer provides capacity for merging. Deferred candidates
-- that move outside the original target area are also left alone.
do
    local h = harness()
    h.grant("material_molten_core_01", 1); h.drain()
    local shell = h.inventory[0]
    h.hero:DropItemAtPositionImmediate(shell, Vector(500))
    h.fill()
    local incoming, box = h.reward("material_molten_core_01", 10)
    local result = pickup.pickup(h.hero, 0); h.drain()
    assert(result.picked == 0 and result.full and not box.removed)
    assert(h.count("material_molten_core_01") == 1 and not incoming.removed)
    h.hero:RemoveItem(h.inventory[0])
    local request = bus.request
    bus.request = function(event, payload)
        if event == events.CONTENT_INVENTORY_GRANT_REQUEST
            and payload.reason == "challenge_ground_reward_pickup" then
            return {ok = false, error = "injected_grant_failure"}
        end
        return request(event, payload)
    end
    result = pickup.pickup(h.hero, 0); h.drain()
    bus.request = request
    assert(result.picked == 0 and not shell.removed and h.count("material_molten_core_01") == 1)
    -- The failed adoption restores the old shell mapping and leaves the new
    -- reward at its original position, ready for a later successful retry.
    assert(h.drops[#h.drops].item == incoming and h.drops[#h.drops].position.x == 10)
    result = pickup.pickup(h.hero, 0); h.drain()
    assert(result.picked == 1 and h.inventory[0] == incoming)
    assert(h.count("material_molten_core_01") == 2 and incoming.charges == 2)
    assert(shell.removed and shell.container.removed, "retire the replaced ground shell without duplicating quantities")

    h = harness()
    h.grant("material_molten_core_01", 1); h.grant("material_molten_core_02", 1)
    h.drain(); h.fill()
    local loot = CreateItem("moving_loot"); local moved = h.ground(loot, 5)
    h.reward("material_molten_core_01", 10, 2)
    result = pickup.pickup(h.hero, 0)
    moved.position = Vector(500)
    h.drain()
    assert(result.picked == 1 and not moved.removed and moved.item == loot)
end

-- A stale candidate or a changed owner must never be claimed by the callback.
do
    local h = harness()
    local item, box = h.reward("material_molten_core_01", 30)
    local candidate = pickup.nearby(h.hero, 0)[1]
    item.survival_owner_player_id = 1
    assert(not pickup.pickup_candidate(h.hero, candidate).ok and not box.removed)
    item.survival_owner_player_id = 0
    h.hero:AddItem(item)
    assert(not pickup.pickup_candidate(h.hero, candidate).ok)
    assert(h.count("material_molten_core_01") == 0)
end

-- Matching upgrade materials do not need a spare inventory slot. The nearer
-- stage-1 material must be retried after the farther stage-0 material succeeds.
do
    local h = harness()
    local current, final
    for _, definition in ipairs(weapons.rows) do
        if definition.series_id == "epic_icefire" and tonumber(definition.stage) == 0 then current = definition end
        if definition.series_id == "epic_icefire" and tonumber(definition.stage) == 2 then final = definition end
    end
    assert(current and final)
    h.grant(current.content_id, 1); h.drain(); h.fill()
    for _, info in ipairs({{1, 10}, {0, 20}}) do
        assert(bus.request(events.CHALLENGE_MATERIAL_DROP_REQUEST, {
            authoritative = true, challenge_id = "challenge_10", required_stage = info[1],
            player_id = 0, position = Vector(info[2]),
        }).ok)
    end
    local candidates = h.upgrades.nearby(h.hero, 0)
    table.sort(candidates, function(a,b) return a.distance < b.distance end)
    local result = pickup.pickup_batch(h.hero, 0, candidates, function(candidate)
        return h.upgrades.pickup_candidate(candidate, 0)
    end)
    h.drain()
    assert(result.picked == 2 and not result.full and h.count(final.content_id) == 1)
    assert(#h.upgrades.nearby(h.hero, 0) == 0)
end

local rules = require("config/molten_core_challenge_rules")
assert(rules.drop_chance_pct == 20)
assert(rules.roll(function() return 19.999 end))
assert(not rules.roll(function() return 20 end))
print("AREA_PICKUP_INVENTORY_PASS: full-slot merging, deferred recipe capacity, native stacks, rollback, ownership, stale candidates, upgrade ordering, 20% drop unchanged")
