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
        return nil, nil, "workshop_server_key_unavailable"
    end
    local ok, key = pcall(GetDedicatedServerKeyV3, config.key_seed)
    if not ok or type(key) ~= "string" or #key < 24 or #key > 256
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
    return type(body) == "table" and type(body.error) == "string" and body.error or fallback
end

return M
