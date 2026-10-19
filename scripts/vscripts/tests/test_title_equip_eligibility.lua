-- Exercise the actual archive equip entry point, not only title selection.
package.path = "scripts/vscripts/?.lua;" .. package.path
local json = require("core/json_encoder")
local bus = require("core/event_bus")
local titles = require("systems/archive_titles")
local settlement = require("systems/archive_settlement")
local profiles, writes, remote, tools = {}, 0, false, true

IsInToolsMode = function() return tools end
GameRules = {GetGameTime = function() return 100 end}
PlayerResource = nil -- Snapshot assertions below call the real projector directly.
CustomNetTables = nil
CustomGameEventManager = {RegisterListener = function() end}
package.loaded["core/scheduler"] = {after = function() end, every = function() end, cancel = function() end}
package.loaded["systems/title_model_service"] = {clear = function() end}
package.loaded["systems/archive_online_clock"] = {init = function() end}
-- Limit this fixture's archive navigation to the page under test.
local category = {category_id = "titles", display_name = "称号", renderer = "titles", enabled = true}
package.loaded["config/generated/archive_categories"] = {rows = {category}, by_id = {titles = category}}
local function save_sections(id, sections)
    for key, value in pairs(sections) do profiles[id].save[key] = value end
    profiles[id].revision = profiles[id].revision + 1
    writes = writes + 1
    return {ok = true}
end
package.loaded["systems/player_profile_service"] = {
    get_account_profile = function(id) return profiles[id] end,
    get_provider = function() return {persist_save = function() end} end,
    update_save_sections = save_sections,
}
package.loaded["systems/archive_http_adapter"] = {
    enabled = function() return remote end,
    submit = function(id, command, complete)
        local result = settlement.settle(profiles[id], command, false)
        if result.ok and not result.duplicate then
            save_sections(id, {archive = result.archive, gameplay_stats = result.gameplay_stats})
        end
        complete(result)
    end,
}
local service = require("systems/archive_service")
local presentation = require("systems/title_presentation_service")

local function eligibility(id)
    local snapshot = service.snapshot(id, "titles")
    assert(snapshot.ok)
    local result = {}
    for _, row in ipairs(snapshot.rows) do
        result[row.id] = {unlocked = row.unlocked, count = row.count, target = row.target}
    end
    return json.encode(result), snapshot
end
local function selected(id, wanted)
    local _, snapshot = eligibility(id)
    local count = 0
    for _, row in ipairs(snapshot.rows) do
        if row.equipped == 1 then
            count = count + 1
            assert(row.id == wanted, "only the requested eligible title may be equipped")
        end
    end
    assert(count == (wanted == "" and 0 or 1))
    assert(snapshot.title_preview == 0, "ordinary equip must never activate the preview overlay")
end
local function fresh(wave)
    return {revision = 1, entitlements = {}, save = {
        archive = {endless_best_wave = wave}, gameplay_stats = {initial_wood = 37}, content_inventory = {},
    }}
end
local function saved_profiles()
    return json.encode({player0 = profiles[0], player1 = profiles[1], player2 = profiles[2]})
end

for _, tools_enabled in ipairs({true, false}) do
    for _, remote_enabled in ipairs({false, true}) do
        tools, remote, writes = tools_enabled, remote_enabled, 0
        profiles = {[0] = fresh(1), [1] = fresh(161), [2] = fresh(0)}
        bus.reset()
        service.set_provider(nil)
        service.init()
        local initial, initial_page = eligibility(0)
        assert(initial_page.rows[1].unlocked == 1 and initial_page.rows[2].unlocked == 0)
        local other_before = eligibility(1)
        local stats_before = json.encode(profiles[0].save.gameplay_stats)

        assert(service.equip_title(0, "peak_perfection").ok)
        assert(writes == 1, "normal Tools equip must persist a real account choice too")
        assert(not presentation.preview_active(0), "clicking an owned title must not enter debug preview")
        assert(eligibility(0) == initial, "equipping 登峰造极 must preserve every title's eligibility")
        assert(eligibility(1) == other_before, "another player's eligibility must not change")
        selected(0, "peak_perfection")
        assert(profiles[0].save.archive.title_selection_manual == true)
        assert(json.encode(profiles[0].save.gameplay_stats) == stats_before)

        local saved_before = json.encode(profiles[0])
        local rejected = service.equip_title(0, "jinghong")
        assert(not rejected.ok and rejected.error == "称号未解锁或不存在")
        assert(json.encode(profiles[0]) == saved_before and writes == 1)
        assert(eligibility(0) == initial and not presentation.preview_active(0))
        assert(not service.equip_title(2, "peak_perfection").ok, "the first title still requires earned progress")
        assert(not presentation.preview_active(2))

        assert(service.equip_title(0, "").ok)
        selected(0, "peak_perfection")
        assert(profiles[0].save.archive.title_selection_manual == false)
        assert(eligibility(0) == initial, "restoring automatic selection preserves all gates")

        assert(service.equip_title(1, "peak_perfection").ok)
        selected(1, "peak_perfection")
        assert(eligibility(1) == other_before)
        assert(service.equip_title(1, "youlong").ok)
        selected(1, "youlong")
        assert(eligibility(1) == other_before, "switching among earned titles preserves lower and upper gates")
        assert(not service.equip_title(1, "jian_tianya").ok)
        assert(eligibility(1) == other_before)
        assert(titles.best_wave(profiles[0].save.archive) == 1)
        assert(titles.best_wave(profiles[1].save.archive) == 161)
    end
end

-- A separate, explicit developer preview remains available in Workshop Tools.
tools, remote = true, false
service.set_provider(nil)
service.init()
local saved_before, writes_before = saved_profiles(), writes
assert(presentation.preview(0, "jinghong").ok)
assert(presentation.preview_active(0))
assert(service.equip_title(0, "chushen").preview == true)
assert(saved_profiles() == saved_before and writes == writes_before,
    "an explicitly started developer preview remains cosmetic and never saves ownership")
assert(service.snapshot(0, "titles").title_preview == 1)
assert(not presentation.preview_active(1))
tools = false
assert(not presentation.preview_active(0))
assert(not service.equip_title(0, "chushen").ok, "Tools previews never bypass production gates")

print("PASS title equip eligibility: real archive entry, Tools/production and local/remote settlement, stable gates, account isolation, automatic restore and explicit preview")
