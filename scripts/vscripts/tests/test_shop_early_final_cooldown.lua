package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local catalog = require("systems/shop_catalog")
local context = {
    ui_mode = "shop", resources = { gold = 100000, wood = 100000 },
    purchased_count = { [0] = {} }, hero_summoned = true,
    city_level = 99, rebirth_level = 10, building_counts = {}, owned_content = {},
    wave_state = { game_started = true, current_wave = 1, total_waves = 30,
        early_final_remaining = 30, early_final_cooldown_total = 60,
        early_final_cooldown_until = 160 },
}
local function entry()
    for _, row in ipairs(catalog.build_snapshot(0, context).entries) do
        if row.content_id == "service_early_final_boss" then return row end
    end
    error("missing early final service")
end
local row = entry()
assert(row.purchasable == 0)
assert(row.early_final_cooldown_remaining == 30)
assert(row.early_final_cooldown_until == 160)
assert(row.early_final_cooldown_total == 60)
context.debug_all_unlocked = true
assert(entry().purchasable == 0, "debug unlock must match the wave service cooldown")
assert(entry().early_final_cooldown_remaining == 30)
context.debug_all_unlocked = false
context.wave_state.early_final_remaining = 0
assert(entry().purchasable == 1)
context.wave_state.game_started = false
context.wave_state.early_final_remaining = 60
assert(entry().purchasable == 0)
assert(entry().early_final_cooldown_until == 0)
context.wave_state.game_started = true
context.wave_state.early_final_used = true
assert(entry().purchasable == 0)
assert(entry().early_final_cooldown_remaining == 0)
print("SHOP_EARLY_FINAL_COOLDOWN_PASS")
