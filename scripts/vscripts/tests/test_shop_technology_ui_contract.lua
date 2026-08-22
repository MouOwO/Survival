local function read(path)
    local file = assert(io.open(path, "rb"), "missing UI source: " .. path)
    local content = file:read("*a")
    file:close()
    return content
end

local content_root = "../../../content/dota_addons/survival/"
local script = read(content_root .. "panorama/scripts/custom_game/shop_ui.js")
local style = read(content_root .. "panorama/styles/custom_game/shop.css")

local function contains(source, text, message)
    assert(source:find(text, 1, true), message .. ": " .. text)
end

contains(script, "ShopTechnologyCooldownMask",
    "technology cards must create a research progress mask")
assert(not script:find("ShopTechnologyCooldownLabel", 1, true),
    "research progress must not create a numeric countdown label")
assert(not script:find("Math.ceil(remaining)", 1, true),
    "research progress must not render remaining seconds")
contains(script, "19组非金矿科技 · 研究耗时2秒",
    "research subtitle must describe research duration instead of purchase cooldown")
contains(script, "已有科技正在研究中，请稍候",
    "blocked technology clicks must describe active research")
contains(script, "已开始研究，请等待进度完成……",
    "purchase result must report research start instead of completion")
contains(script, "ShopTechnologyLockBadge",
    "technology cards must expose their prerequisite lock")
contains(script, "technologyCooldownRemaining() > 0",
    "technology purchases must be blocked during team cooldown")
contains(script, "Object.keys(pendingTechnologyPurchases).length > 0",
    "all technology purchases must be disabled while one request is pending")
contains(script, "entry.technology_group || \"\") === source",
    "radial cooldown must target only the purchased technology group")
contains(script, "PrerequisiteLocked",
    "technology cards must distinguish prerequisite locks")
contains(script, "PurchaseCooldownLocked",
    "technology cards must distinguish the shared purchase cooldown")
contains(script, "snapshot.technology_cooldown_source_group",
    "incremental snapshots must retain the cooldown source group")
contains(script, "updateAllCooldownOverlays();\n    }\n\n    function renderCategories",
    "card rebuilds must restart the radial cooldown animation")

contains(style, ".ShopTechnologyCooldownMask",
    "technology research progress mask style is missing")
assert(not style:find(".ShopTechnologyCooldownLabel", 1, true),
    "numeric research countdown style must be removed")
contains(style, "clip: radial(50% 50%, 0deg, 360deg);",
    "technology cooldown mask must use a clockwise radial clip")
contains(style, ".ShopShelfSlot.Technology.PrerequisiteLocked",
    "prerequisite-locked technology style is missing")
contains(style, ".ShopShelfSlot.Technology.CooldownSource",
    "purchased technology cooldown-source style is missing")

print("SHOP_TECHNOLOGY_UI_CONTRACT_PASS")
