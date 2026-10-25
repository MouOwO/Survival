-- Latest user decision (2026-10-25): retain the current monthly-pass bonuses.
-- Exercise real quota reducers and the real archive UI snapshot projection.
-- Synthetic profiles only; no providers, game process, database or config edits.
package.path = "scripts/vscripts/?.lua;" .. package.path

local now = 1792886400
local calendar = require("systems/archive_calendar")
calendar.set_clock(function() return now end)
local day = tostring(calendar.day())
local profiles = {}
package.loaded["systems/player_profile_service"] = {
    get_account_profile = function(id) return profiles[id] end,
}
local limits = require("systems/archive_daily_limits")
local definitions = require("config/generated/archive_daily_limits")
local archive_ui = require("systems/archive_service")
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "quota contract") .. ": "
        .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function profile(entitlement, earned)
    return {revision=23, save={archive={daily={[day]=earned or {}}}},
        entitlements=entitlement or {}}
end
local expected = {cage={30,90}, social_beast={10,20}, social_ex={10,20},
    social_friend={10,20}, social_wife={10,20}, clear={20,20}, mode_rich={20,20},
    mode_cold={10,10}, mode_scourge={10,10}, faith={3000,3000}}
for index = 1, 12 do expected[string.format("fragment_%02d", index)] = {20,40} end
for key, pair in pairs(expected) do
    equal(limits.limit(key, false), pair[1], key .. " ordinary cap")
    equal(limits.limit(key, true), pair[2], key .. " monthly cap")
end

local function ui_profile(id, p, pass)
    profiles[id] = p
    local before = p.save.archive.daily[day]
    local page = archive_ui.snapshot(id, "clear")
    equal(page.ok, true, "real archive page exists")
    equal(page.has_pass, pass and 1 or 0, "real page entitlement flag")
    equal(page.revision, 23, "snapshot preserves profile revision")
    local snapshot = page.daily_limits
    equal(snapshot.day_key, day, "UI uses server day")
    equal(#snapshot.rows, #definitions.rows, "all configured UI quotas remain present")
    for _, row in ipairs(snapshot.rows) do
        equal(snapshot.by_key[row.key], row, "UI row/key lookup identity")
        equal(row.limit, limits.limit(row.key, pass), "UI limit equals authoritative reducer")
        equal(row.earned, limits.earned(p.save.archive,row.key,day), "UI earned equals persisted counter")
        equal(row.remaining, limits.remaining(p.save.archive,row.key,day,pass), "UI remaining equals reducer")
        equal(row.capped, row.remaining == 0 and 1 or 0, "UI cap flag is consistent")
        equal(row.notes, nil, "obsolete author notes are never sent to UI")
        equal(row.pass_daily_limit, nil, "raw configuration is not a player DTO")
    end
    equal(p.save.archive.daily[day], before, "reading UI does not replace counter state")
    return page
end

local ordinary = profile(nil, {fragment_01=19,cage_total=29})
ui_profile(0,ordinary,false)
local active = profile({archive_pass={active=true,expires_at=now+60}}, {fragment_01=39,cage_total=89})
ui_profile(1,active,true)
local expired = profile({archive_pass={active=true,expires_at=now}}, {fragment_01=35,cage_total=65})
local expired_page = ui_profile(2,expired,false)
equal(expired_page.daily_limits.by_key.fragment_01.remaining,0,"expiry cannot reset earned quota")
equal(expired_page.daily_limits.by_key.cage.earned,65,"UI retains over-base earned total after expiry")
local vip_only = profile({vip={active=true,expires_at=now+60}}, {fragment_01=19})
vip_only.save.gameplay_stats={vip_level=99}
ui_profile(3,vip_only,false)
local inactive = profile({archive_pass={active=false,expires_at=now+60}})
ui_profile(4,inactive,false)

for _, pass in ipairs({false,true}) do
    for _, key in ipairs({"fragment_01","cage","social_friend"}) do
        local definition = limits.definition(key)
        local cap = limits.limit(key,pass)
        local state = {daily={[day]={[definition.storage_key]=cap-1}}}
        equal(limits.grant(state,key,5,day,pass),1,"only final available slot is granted")
        equal(limits.grant(state,key,5,day,pass),0,"at-cap request grants nothing")
        equal(limits.earned(state,key,day),cap,"counter stops at the configured cap")
        local p = profile(pass and {archive_pass={active=true,expires_at=now+60}} or nil)
        p.save.archive = state
        local view = ui_profile(5,p,pass).daily_limits.by_key[key]
        equal(view.limit,cap,"post-grant page uses same cap")
        equal(view.earned,cap,"post-grant page shows committed count")
        equal(view.remaining,0,"post-grant page shows no available slots")
    end
end
expired.entitlements.archive_pass.expires_at = now+60
local renewed = ui_profile(2,expired,true).daily_limits
equal(renewed.by_key.fragment_01.limit,40,"renewal restores monthly cap")
equal(renewed.by_key.fragment_01.earned,35,"renewal preserves original counter")
equal(renewed.by_key.fragment_01.remaining,5,"renewal opens only the true remaining slots")
equal(renewed.by_key.cage.limit,90,"renewed cage cap remains current monthly value")
equal(renewed.by_key.cage.remaining,25,"cage renewal never resets earned total")

print("UI_QA_DAILY_LIMITS_PASS checks=" .. checks
    .. " real server reducers/archive UI snapshots, monthly20/40+cage30/90,"
    .. " entitlement expiry/renewal, cap boundary, VIP isolation, no author notes")
