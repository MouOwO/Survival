-- The real offline/provider/payment modules must keep cash traffic disabled,
-- including an owner session that already has a nonempty payment token.
package.path = "scripts/vscripts/?.lua;" .. package.path
local release_profile = {channel = "production"}
package.loaded["config/release_profile"] = release_profile
package.loaded["config/player_web_auth"] = {enabled = false}
IsServer, IsInToolsMode = function() return true end, function() return true end
local cash_policy = require("core/commerce_release_policy")
assert(not cash_policy.real_money_allowed())
assert(package.loaded["debug/offline_logic_test"] == nil,
    "production cash denial must not load the developer offline module")

local values = {
    survival_offline_logic_test = "0",
    survival_fishing_api_token = "nonempty_fake_offline_payment_token",
}
Convars = {
    RegisterConvar = function(_, key, default) if values[key] == nil then values[key] = default end end,
    GetStr = function(_, key) return values[key] or "" end,
}
Time = function() return 100 end
local http_calls, responses, chat, pass_provider = 0, {}, nil, "unset"
CreateHTTPRequestScriptVM = function()
    http_calls = http_calls + 1
    error("offline cash flow must never construct an HTTP request")
end
local player = {}
DisconnectClient = function() error("approved offline player must not be disconnected") end
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    IsFakeClient = function() return false end,
    GetSteamAccountID = function() return 885195478 end,
    GetPlayer = function(_, id) return id == 0 and player or nil end,
}
ListenToGameEvent = function(name, callback)
    if name == "player_chat" then chat = callback end
end
CustomGameEventManager = {
    RegisterListener = function() end,
    Send_ServerToPlayer = function(_, actor, name, payload)
        assert(actor == player and name == "survival_payment_result")
        responses[#responses + 1] = payload
    end,
}
package.loaded["core/logger"] = {info = function() end, warn = function() end}
package.loaded["systems/match_setup_service"] = {
    get_session_id = function() return "offline_payment_session" end,
    get_mode = function() return "standard" end,
    get_profile_mode = function() return "standard" end,
    is_mode_selected = function() return true end,
}
package.loaded["systems/commerce_service"] = {init = function() end}
package.loaded["systems/archive_service"] = {
    set_purchase_provider = function(value) pass_provider = value end,
}
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen = function() return false end}

release_profile.channel = "development"
assert(cash_policy.real_money_allowed(), "ordinary developer payment tests remain enabled")
local offline = require("debug/offline_logic_test")
assert(not offline.configure())
assert(cash_policy.real_money_allowed(), "an ordinary development launch retains its cash gate")
values.survival_offline_logic_test = "1"
assert(offline.configure() and offline.is_enabled())
-- The console value cannot change this match-local offline decision.
values.survival_offline_logic_test = "0"
assert(offline.is_enabled())

local profiles = require("systems/player_profile_service")
profiles.init(offline.profile_options())
assert(profiles.get_provider().resolve_account_id(0) == "885195478")
assert(profiles.authenticate_player(0, "offline_payment_test").authenticated)
assert(profiles.load_player(0).ok and profiles.get_profile(0),
    "payment isolation is tested after a real offline profile has loaded")
assert(Convars:GetStr("survival_fishing_api_token") ~= "",
    "absence of a token must not be the reason cash HTTP is blocked")
local payment = require("systems/payment_service")
payment.init()
for _, action in ipairs({"catalog", "create", "status", "cancel"}) do
    payment.handle({PlayerID = 0, action = action, sku = "u_coin_recharge", quantity = 1,
        provider = "wechat", real_money_enabled = true, channel = "development"})
    local result = assert(responses[#responses])
    if action == "catalog" then
        assert(result.ok and result.real_money_enabled == false and #result.products == 0)
        assert(result.wechat == false and result.alipay == false)
    else
        assert(result.ok == false and result.error == "real_money_disabled")
    end
end
for _, kind in ipairs({"refreshdata", "refreshmoney"}) do
    local ok, reason = payment.reset_player({player_id = 0, args = {}}, kind)
    assert(not ok and reason == "real_money_disabled", "offline must not reset a remote account")
    assert(type(chat) == "function", "the normal developer chat handler remains registered")
    chat({playerid = 0, text = kind})
end
local checkout
assert(not payment.open_pass_checkout(0, {sku = "archive_pass_monthly"}, function(result) checkout = result end))
assert(checkout and checkout.ok == false)
assert(http_calls == 0, "all offline cash routes must stop before creating HTTP")
assert(pass_provider == nil, "offline must not install the cash monthly-pass provider")

assert(not offline.configure(), "a later ordinary launch clears the offline match latch")
assert(not offline.is_enabled() and cash_policy.real_money_allowed(),
    "ending the offline match restores existing developer payment semantics")
print("OFFLINE_PAYMENT_ISOLATION_PASS: real offline/profile/payment, nonempty fake token, zero HTTP, catalog/orders/resets/pass blocked, developer cash gate restored")
