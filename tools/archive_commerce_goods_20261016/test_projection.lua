-- Native Lua 5.1 tests of the production, read-only collection projector.
package.path = "scripts/vscripts/?.lua;" .. package.path
local json = require("core/json_encoder")
local null = require("core/json_decoder").null
local catalog = require("config/generated/archive_commerce_goods")
local projection = require("systems/archive_commerce_goods")
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local checks = 0
local function check(name, run)
    run(); checks = checks + 1; print("ARCHIVE_GOODS_PASS " .. name)
end
local function profile()
    return {revision=1, entitlements={}, save={archive={}, gameplay_stats={starjoy_reward_level=0}, content_inventory={}}}
end
local function index(p)
    local result = {}; for _, r in ipairs(projection.project(p)) do result[r.id] = r end; return result
end
local function find(kind, ownership_id)
    for _, r in ipairs(catalog.rows) do
        if r.kind == kind and (ownership_id == nil or r.ownership_id == ownership_id) then return r end
    end
    error("fixture_missing:" .. kind .. ":" .. tostring(ownership_id))
end
local product, vip, starjoy = find("product"), find("vip"), find("starjoy")
local function find_sku(sku)
    for _, item in ipairs(catalog.rows) do if item.sku == sku then return item end end
    error("fixture_missing_sku:" .. sku)
end
check("loaded_empty_account_is_known_zero", function()
    local rows = projection.project(profile())
    assert(#rows == #catalog.rows and #rows > 0)
    for _, r in ipairs(rows) do assert(r.count == 0 and r.count_known == 1 and r.unlocked == 0) end
end)
check("missing_account_and_sections_remain_unknown", function()
    for _, source in ipairs({{}, {save={}}, {save={content_inventory=null,archive=null,gameplay_stats=null}}}) do
        for _, r in ipairs(projection.project(source)) do
            assert(r.count == nil and r.quantity_unknown == 1 and r.count_known == 0)
            assert(r.owned == nil and r.unlocked == nil and r.completed == nil)
        end
    end
end)
check("direct_purchase_exact_marker", function()
    local p = profile(); p.save.content_inventory[product.ownership_id] = 1
    local r = index(p)[product.id]
    assert(r.count == 1 and r.owned == 1 and r.unlocked == 1 and r.completed == 1)
end)
check("owned_quantity_is_never_clipped_to_cap", function()
    local p = profile(); p.save.content_inventory[product.ownership_id] = 321
    assert(index(p)[product.id].count == 321)
end)
check("bad_quantities_are_unknown_not_locked", function()
    for _, value in ipairs({-1, 0.5, math.huge, -math.huge, "garbage", false, null}) do
        local p = profile(); p.save.content_inventory[product.ownership_id] = value
        local r = index(p)[product.id]
        assert(r.count == nil and r.quantity_unknown == 1 and r.unlocked == nil)
    end
    local p = profile(); p.save.content_inventory[product.ownership_id] = 0/0
    assert(index(p)[product.id].quantity_unknown == 1)
end)
check("missing_inventory_is_not_an_empty_inventory", function()
    local p = profile(); p.save.content_inventory = nil
    assert(index(p)[product.id].count == nil)
end)
check("bundle_and_members_have_independent_real_ownership", function()
    local bundle = find_sku("video_bundle_b003")
    local p = profile()
    for _, marker in ipairs({"commerce_p028", "commerce_p020", "commerce_p018", "commerce_p032"}) do
        p.save.content_inventory[marker] = 1
        assert(index(p)[find("product", marker).id].owned == 1)
    end
    assert(index(p)[bundle.id].owned == 0, "owning all components does not forge a bundle purchase")
    p.save.content_inventory[bundle.ownership_id] = 1
    assert(index(p)[bundle.id].owned == 1)
end)
check("shared_lottery_marker_lights_same_collection_entry", function()
    local monkey = find("product", "lottery_monkey_king")
    local p = profile(); p.save.content_inventory.lottery_monkey_king = 1
    assert(index(p)[monkey.id].owned == 1)
end)
check("VIP_claim_map_and_inventory_are_both_authoritative", function()
    local p = profile(); p.save.archive.vip_claimed = {[vip.ownership_id]=true}
    assert(index(p)[vip.id].owned == 1)
    p = profile(); p.save.content_inventory[vip.ownership_id] = 1
    assert(index(p)[vip.id].owned == 1)
end)
check("VIP_recharge_and_eligibility_do_not_mean_claimed", function()
    local p = profile(); p.save.gameplay_stats.vip_recharge_total_fen = 100000000
    p.entitlements.vip = {active=true}
    assert(index(p)[vip.id].owned == 0)
end)
check("VIP_missing_archive_and_malformed_claims_are_unknown", function()
    local p = profile(); p.save.archive = nil
    assert(index(p)[vip.id].count == nil)
    p = profile(); p.save.archive.vip_claimed = {[vip.ownership_id]="true"}
    assert(index(p)[vip.id].count == nil)
    p = profile(); p.save.archive.vip_claimed = null
    assert(index(p)[vip.id].count == nil)
    p = profile(); p.save.archive.vip_claimed = {}; p.save.content_inventory = nil
    assert(index(p)[vip.id].count == nil)
    p.save.archive.vip_claimed[vip.ownership_id] = true
    assert(index(p)[vip.id].owned == 1, "a real claim independently proves ownership")
end)
check("starjoy_uses_settled_level_not_balance_or_lifetime_earnings", function()
    local p = profile()
    p.save.gameplay_stats.starjoy_points = 10000000
    p.save.gameplay_stats.starjoy_points_earned = 10000000
    assert(index(p)[starjoy.id].owned == 0)
    p.save.gameplay_stats.starjoy_points = 0
    p.save.gameplay_stats.starjoy_points_earned = 0
    p.save.gameplay_stats.starjoy_reward_level = starjoy.level
    assert(index(p)[starjoy.id].owned == 1)
end)
check("missing_settled_starjoy_level_is_unknown", function()
    local p = profile(); p.save.gameplay_stats.starjoy_reward_level = nil
    local r = index(p)[starjoy.id]
    assert(r.count == nil and r.quantity_unknown == 1 and r.owned == nil)
end)
check("formal_order_icons_description_and_limits_preserved", function()
    local rows = projection.project(profile())
    local ids, permanent_markers = {}, {}
    for i, r in ipairs(rows) do
        local item = catalog.rows[i]
        assert(r.id == item.id and r.name == item.name and r.icon == item.icon and r.description == item.description)
        assert(not ids[r.id]); ids[r.id] = true
        if item.kind == "product" then
            assert(not permanent_markers[item.ownership_id]); permanent_markers[item.ownership_id] = true
        end
        assert(r.target == (item.max_owned and item.max_owned > 0 and item.max_owned or nil))
    end
end)
check("read_only_repeated_opening_preserves_all_account_and_config_values", function()
    local p = profile(); p.save.content_inventory[product.ownership_id] = 1
    p.save.archive.vip_claimed = {[vip.ownership_id]=true}
    local before, config_before = copy(p), copy(catalog)
    for _ = 1, 50 do projection.project(p) end
    assert(equal(before, p) and equal(config_before, catalog))
end)
check("different_accounts_never_share_ownership", function()
    local a, b = profile(), profile()
    a.save.content_inventory[product.ownership_id] = 1
    assert(index(a)[product.id].owned == 1 and index(b)[product.id].owned == 0)
end)

if arg[1] then
    local fixture = profile()
    for _, marker in ipairs({"commerce_p028", "commerce_p020", "commerce_p018", "commerce_p032", find_sku("video_bundle_b003").ownership_id, "lottery_monkey_king"}) do
        fixture.save.content_inventory[marker] = 1
    end
    fixture.save.archive.vip_claimed = {vip_privilege_01=true, vip_package_01=true, vip_medal_01=true}
    fixture.save.gameplay_stats.starjoy_reward_level = 3
    fixture.save.content_inventory.lottery_ember_of_legacy = 23
    local file = assert(io.open(arg[1], "wb"))
    file:write(json.encode({synthetic=true, source="Production Lua projection with formal local catalog",
        empty={ok=true,category_id="commerce_goods",revision=1,rows=projection.project(profile())},
        owned={ok=true,category_id="commerce_goods",revision=2,rows=projection.project(fixture)},
        unknown={ok=true,category_id="commerce_goods",revision=1,rows=projection.project({save={}})}}))
    file:close()
end
print("ARCHIVE_GOODS_SUMMARY " .. checks .. " groups passed")
