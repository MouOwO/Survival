local function apply()
    local inspect=require("ws4_local_launcher/status")
    local before=inspect()
    if before.status=="waiting_for_map" then return before end
    local value=LoadKeyValues("scripts/vscripts/ws4_local_launcher/session.kv")
    if type(value)~="table" or type(value.token)~="string" or #value.token~=64
        or not value.token:match("^[a-f0-9]+$") then return {status="local_credential_missing"} end
    local expected=tonumber(value.expected_players)
    if not expected or expected<1 or expected>4 or expected~=math.floor(expected) then
        return {status="local_party_configuration_invalid"}
    end
    if before.players<expected then before.status="waiting_for_players" return before end
    Convars:SetStr("survival_fishing_api_token",value.token)
    Convars:SetStr("survival_archive_http_enabled","1")
    local applied=Convars:GetStr("survival_fishing_api_token")==value.token
    value.token=nil
    if not applied then return {status="local_credential_apply_failed"} end
    local stage
__RECOVERY__
    local result=inspect()
    result.credential_applied=true
    return result
end
local ok,result=pcall(apply)
if not ok then result={status="local_credential_apply_failed"} end
print("WS4_LOCAL_STATUS:"..require("core/json_encoder").encode(result))
