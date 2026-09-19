package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local profile = { save = { content_inventory = { lottery_ticket = 7 }, gameplay_stats = {} } }
local writes = 0
local function reject()
    writes = writes + 1
    return { ok = false, error = "remote_save_requires_server_transaction" }
end
package.loaded["systems/player_profile_service"] = {
    get_profile = function() return profile end,
    update_save_sections = reject, update_save_section = reject,
}
PlayerResource = { IsValidPlayerID = function(_, id) return id == 0 or id == 1 end }
local inventory = require("systems/content_inventory_service")
local shop = require("systems/shop_grant_service")
local weapons = require("config/generated/weapon_definitions")
local items = require("config/generated/item_definitions")
local function counts(id)
    return assert(bus.request(events.CONTENT_INVENTORY_GET_REQUEST, {player_id=id or 0})).snapshot.counts
end
local function purchase(id)
    return shop.grant(0, 2, { entryid=id, contentid=id, grant_type="virtual_item",
        definition=weapons.by_id[id] or items.by_id[id] }, {})
end
bus.reset(); inventory.init()
assert(purchase("weapon_growth_sword_01").ok)
assert(purchase("item_death_mask").ok)
local gloves
for _, row in ipairs(weapons.rows) do
    if row.series_id == "attack_gloves" and row.stage == 1 then gloves = row end
end
assert(gloves)
assert(purchase(gloves.content_id).ok)
assert(purchase(gloves.content_id).ok)
assert(counts()[gloves.content_id] == nil)
assert(counts()[gloves.next_content_id] == 1)
assert(writes == 0, "shop must not write HTTP saves")
local evolved = bus.request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST, {
    player_id=0, consume={weapon_growth_sword_01=1}, grant={weapon_growth_sword_02=1},
})
assert(evolved.ok and counts().weapon_growth_sword_02 == 1)
profile.save.content_inventory = { lottery_ticket=9, weapon_growth_sword_01=99 }
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id=0})
assert(counts().weapon_growth_sword_02 == 1 and counts().item_death_mask == 1)
assert(counts().lottery_ticket == 9 and counts().weapon_growth_sword_01 == nil)
assert(counts(1).weapon_growth_sword_02 == nil, "players must not share match inventory")
local denied = bus.request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST, {
    player_id=0, consume={lottery_ticket=1}, grant={special_lottery_ticket=1},
})
assert(not denied.ok and denied.error == "remote_save_requires_server_transaction")
assert(counts().lottery_ticket == 9 and counts().special_lottery_ticket == nil)
local mixed = bus.request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST, {
    player_id=0, consume={weapon_growth_sword_02=1}, grant={lottery_ticket=1},
})
assert(not mixed.ok and counts().weapon_growth_sword_02 == 1 and counts().lottery_ticket == 9)
local missing = bus.request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST, {
    player_id=0, consume={weapon_growth_sword_02=2}, grant={weapon_growth_sword_03=1},
})
assert(not missing.ok and counts().weapon_growth_sword_02 == 1)
local blocked = bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST, {
    player_id=0, content_id="lottery_ticket", count=1,
})
assert(not blocked.ok and counts().lottery_ticket == 9)
bus.reset(); inventory.init()
assert(counts().weapon_growth_sword_02 == nil and counts().item_death_mask == nil)
profile = nil
assert(purchase("weapon_growth_sword_01").ok, "match shop works without loaded HTTP profile")
print("MATCH_INVENTORY_PASS: shop grants/upgrades, evolution, refresh, player isolation, new match reset, permanent write protection and atomic failure")
