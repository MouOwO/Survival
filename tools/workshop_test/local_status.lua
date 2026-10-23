-- Installed only into the separate frozen local test addon.
return function()
    local result = {status="waiting_for_map", players=0, authenticated=0, profiles=0}
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName() ~= "template_map" then return result end
    local ok, marker = pcall(require, "config/ws4_local_launcher")
    if not ok or type(marker) ~= "table" or marker.kind ~= "WS4-LOCAL-1"
        or marker.proxy_port ~= 18766 then return result end
    local profiles = package.loaded["systems/player_profile_service"]
    local loading = package.loaded["systems/startup_loading_service"]
    if not profiles or not loading or not PlayerResource or not Convars
        or type(loading.snapshot) ~= "function" then return result end
    result.status = "waiting_for_credentials"
    if #(Convars:GetStr("survival_fishing_api_token") or "") == 64 then result.status = "connected" end
    for id=0,(DOTA_MAX_TEAM_PLAYERS or 24)-1 do
        if PlayerResource:IsValidPlayerID(id) and not PlayerResource:IsFakeClient(id)
            and PlayerResource:GetTeam(id) ~= (DOTA_TEAM_SPECTATOR or 1)
            and PlayerResource:GetPlayer(id) ~= nil then
            result.players=result.players+1
            local account=string.format("%.0f",tonumber(PlayerResource:GetSteamAccountID(id) or 0))
            if profiles.is_authenticated_for_account(id,account) then result.authenticated=result.authenticated+1 end
            if profiles.is_loaded_for_account(id,account) then result.profiles=result.profiles+1 end
        end
    end
    local state=loading.snapshot()
    result.admission_complete=state.admission_complete==true
    result.profiles_ready=state.profiles_ready==true
    result.phase=type(state.phase)=="string" and state.phase:match("^[a-z_]+$") or "waiting"
    if type(state.error)=="string" and #state.error<=83 and state.error:match("^[A-Za-z0-9_]+$") then
        result.error=state.error
    end
    return result
end
