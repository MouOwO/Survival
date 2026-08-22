package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local content_root = "../../../content/dota_addons/survival/panorama/"

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    assert(not text:find("\239\191\189", 1, true),
        "replacement character found in " .. path)
    return text
end

local xml = read(content_root .. "layout/custom_game/survival_hud.xml")
local js = read(content_root .. "scripts/custom_game/survival_ui.js")
local css = read(content_root .. "styles/custom_game/survival_hud.css")
local router = read("scripts/vscripts/ui/ui_request_router.lua")

for _, panel_id in ipairs({
    "DifficultySelectionOverlay",
    "DifficultySelectionDialog",
    "DifficultySelectionButtons",
    "DifficultySelectionError",
}) do
    assert(xml:find('id="' .. panel_id .. '"', 1, true),
        "difficulty UI panel is missing: " .. panel_id)
end

assert(css:find("#DifficultySelectionOverlay", 1, true),
    "difficulty overlay CSS is missing")
assert(css:find(".DifficultyOptionButton", 1, true),
    "difficulty button CSS is missing")
assert(js:find('wave.status === "selecting_difficulty"', 1, true),
    "difficulty UI is not gated by server wave state")
assert(js:find('SendCustomGameEventToServer("ui_difficulty_select_request"', 1, true),
    "difficulty UI request event is missing")
assert(js:find('GameEvents.Subscribe("ui_difficulty_select_result"', 1, true),
    "difficulty UI result event is missing")
assert(js:find("optionArray(wave.difficulty_options)", 1, true),
    "difficulty buttons are not data driven")
assert(router:find('"ui_difficulty_select_request"', 1, true),
    "server difficulty request listener is missing")
assert(router:find('"ui_difficulty_select_result"', 1, true),
    "server difficulty result event is missing")
assert(router:find("source_player_id(payload)", 1, true),
    "difficulty request does not use the trusted engine PlayerID")

print("DIFFICULTY_UI_CONTRACT_PASS")