local config = require("config/workshop_connection")
local M = {}

function M.resolve(local_url, local_token)
    if IsInToolsMode and IsInToolsMode() then return local_url, local_token end
    if config.enabled ~= true then return local_url, local_token end
    if not IsDedicatedServer or not IsDedicatedServer() then
        return nil, nil, "workshop_dedicated_server_required"
    end
    if type(config.base_url) ~= "string" or not config.base_url:match("^https://[%w%.%-]+/ws4$")
        or type(config.key_seed) ~= "string" or #config.key_seed > 64 then
        return nil, nil, "workshop_connection_invalid"
    end
    if type(GetDedicatedServerKeyV3) ~= "function" then
        return nil, nil, "workshop_key_api_unavailable"
    end
    local ok, key = pcall(GetDedicatedServerKeyV3, config.key_seed)
    if not ok then return nil, nil, "workshop_key_call_failed" end
    -- Only Valve's bounded Invalid_* sentinel may be shown to the owner.
    -- Never publish any part of a valid credential or a thrown Lua error.
    if type(key) == "string" and #key <= 64 and key:match("^Invalid_[A-Za-z0-9_]+$") then
        return nil, nil, "workshop_key_state_" .. key
    end
    if key == "" then return nil, nil, "workshop_key_empty" end
    if type(key) ~= "string" or #key < 24 or #key > 256
        or key:lower():match("^invalid") or key:find("[^%w_%-+/=]") then
        return nil, nil, "workshop_server_key_unavailable"
    end
    return config.base_url, key
end

function M.failure(body, fallback)
    if type(body) == "table" and body.error == "workshop_server_pairing_required"
        and type(body.pairing_fingerprint) == "string" and #body.pairing_fingerprint == 16
        and body.pairing_fingerprint:match("^[0-9a-f]+$") then
        return "workshop_pairing_" .. body.pairing_fingerprint
    end
    if type(body) == "table" and type(body.error) == "string" then return body.error end
    if config.enabled == true and not (IsInToolsMode and IsInToolsMode()) then
        if fallback == "http_status_0" then return "workshop_backend_unreachable" end
        if fallback == "http_status_401" or fallback == "http_status_403" then
            return "workshop_backend_rejected"
        end
    end
    return fallback
end

return M
