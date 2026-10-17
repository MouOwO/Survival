-- Production archive dispatcher, with synthetic accounts and engine transports.
-- The helper and category metadata are real. No database or network is used.
package.path = "scripts/vscripts/?.lua;" .. package.path
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
local accounts, packets, listeners, writes, tasks = {}, {}, {}, 0, {}
local stats = require("config/generated/player_gameplay_stats")
local catalog = require("config/generated/archive_commerce_goods")
local product
for _, item in ipairs(catalog.rows) do if item.kind == "product" then product = item; break end end
assert(product)
local function new_profile()
    local p = {revision=1,entitlements={},save={content_inventory={},archive={},gameplay_stats={}}}
    for _, row in ipairs(stats.rows) do p.save.gameplay_stats[row.field_id] = row.default_value end
    return p
end
accounts[0], accounts[1] = new_profile(), new_profile()
package.loaded["systems/player_profile_service"] = {
    get_account_profile=function(id) return copy(accounts[id]) end,
    get_profile=function(id)
        -- Pure mode intentionally strips account commerce effects for combat.
        local p = new_profile(); p.save.content_inventory = {}; return p
    end,
    get_provider=function() return {} end,
    update_save_sections=function() writes=writes+1; error("collection must not write") end,
}
package.loaded["core/scheduler"] = {
    every=function(_, fn, key) tasks[key]=fn end,
    after=function(_, fn, key) tasks[key]=fn end,
    cancel=function(key) tasks[key]=nil end,
}
package.loaded["systems/archive_online_clock"] = {init=function() end,observe=function() end}
package.loaded["systems/archive_http_adapter"] = {enabled=function() return false end}
package.loaded["systems/title_presentation_service"] = {
    init=function() end, rows=function() return {} end, preview_active=function() return false end,
}
local time = 10
GameRules = {GetGameTime=function() return time end}
PlayerResource = {
    GetPlayer=function(_, id) if accounts[id] then return id end end,
    IsValidPlayerID=function(_, id) return accounts[id] ~= nil end,
}
CustomGameEventManager = {
    RegisterListener=function(_, name, fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_, id, name, data) packets[#packets+1]={id=id,name=name,data=copy(data)} end,
}
local bus = require("core/event_bus")
local events = require("core/events")
bus.reset()
local service = require("systems/archive_service")
service.init()
local checks = 0
local function check(name, run) run(); checks=checks+1; print("ARCHIVE_GOODS_SERVICE_PASS " .. name) end
local function row(snapshot)
    assert(snapshot.ok == true)
    for _, r in ipairs(snapshot.rows) do if r.id == product.id then return r end end
    error("collection_row_missing")
end
check("new_category_registered_without_enabling_legacy_shop", function()
    local categories = require("config/generated/archive_categories")
    assert(categories.by_id.commerce_goods.enabled)
    assert(categories.by_id.shop.enabled == false)
    assert(row(service.snapshot(0,"commerce_goods")).owned == 0)
end)
check("account_snapshot_remains_owned_when_pure_match_profile_is_filtered", function()
    accounts[0].save.content_inventory[product.ownership_id] = 1
    assert(row(service.snapshot(0,"commerce_goods")).owned == 1)
    assert(row(service.snapshot(1,"commerce_goods")).owned == 0)
end)
check("injected_PlayerID_keeps_prefetch_private_and_chunks_bounded", function()
    packets = {}
    listeners.survival_archive_request(nil,{PlayerID=0,player_id=1,category_id="commerce_goods",prefetch=1})
    local count, chunks = 0, 0
    for _, packet in ipairs(packets) do
        assert(packet.id == 0)
        if packet.data.category_id == "commerce_goods" then
            assert(packet.name == "survival_archive_snapshot" and #packet.data.rows <= 12)
            assert(packet.data.delta == nil)
            count, chunks = count + #packet.data.rows, chunks + 1
        end
    end
    assert(count == #catalog.rows and chunks == math.ceil(#catalog.rows/12))
end)
check("purchase_profile_refresh_pushes_existing_snapshot_delta", function()
    packets = {}
    accounts[0].save.content_inventory[product.ownership_id] = 2
    accounts[0].revision = accounts[0].revision + 1
    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="commerce_purchase"})
    local sent, changed_quantity = false, false
    for _, packet in ipairs(packets) do
        assert(packet.id == 0)
        if packet.data.category_id == "commerce_goods" then
            assert(packet.data.delta == 1 and packet.data.base_sequence)
            sent = true
            for _, change in ipairs(packet.data.rows) do
                if change.path[#change.path] == "count" and change.value == 2 then changed_quantity = true end
            end
        end
    end
    assert(sent and changed_quantity)
end)
check("identical_refresh_sends_no_redundant_UI_packets", function()
    packets = {}
    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="same_profile"})
    assert(#packets == 0)
end)
check("collection_reads_do_not_grant_rewards_or_mutate_accounts", function()
    local before = copy(accounts)
    for _ = 1, 20 do service.snapshot(0,"commerce_goods"); service.snapshot(1,"commerce_goods") end
    assert(writes == 0 and equal(before,accounts))
end)
check("new_page_adds_no_periodic_refresh_task", function()
    for key in pairs(tasks) do assert(not key:find("commerce_goods",1,true)) end
end)
print("ARCHIVE_GOODS_SERVICE_SUMMARY " .. checks .. " groups passed")
