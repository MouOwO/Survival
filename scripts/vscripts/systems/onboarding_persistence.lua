-- Account metadata only. Never infer first login from combat stats or wins.
local profiles = require("systems/player_profile_service")
local setup = require("systems/match_setup_service")
local M = {}
local states = {}
local statuses = {required=true,completed=true,skipped=true,legacy=true}

local function snapshot(state)
    return {loaded=state and state.loaded == true or false, required=state and state.required == true or false,
        status=state and state.status or "pending", version=state and state.version or 1}
end

local function identity(player_id)
    if type(player_id) ~= "number" or player_id ~= player_id or player_id < 0
        or player_id == math.huge or player_id ~= math.floor(player_id) then
        return nil,nil,nil,"player_id_invalid"
    end
    local provider = profiles.get_provider()
    local account = provider and provider.resolve_account_id and provider.resolve_account_id(player_id)
    local session = setup.get_session_id()
    if type(account) ~= "string" or account == "" or type(session) ~= "string" or #session < 8 then
        return nil, nil, nil, "account_id_unresolved"
    end
    if not profiles.is_loaded_for_account(player_id, account) then return nil,nil,nil,"profile_not_loaded" end
    return account, session, provider
end

local function bound(player_id)
    local account, session, provider, error_code = identity(player_id)
    if not account then return nil,nil,error_code end
    local state = states[player_id]
    if not state or state.account ~= account or state.session ~= session then
        state = {account=account,session=session,loaded=false}
        states[player_id] = state
    end
    return state, provider
end

local function result(state, ok, error_code)
    local value = snapshot(state)
    value.ok, value.error = ok, error_code
    return value
end

local function current(player_id, state)
    local account, session = identity(player_id)
    return states[player_id] == state and account == state.account and session == state.session
end

local function notify(callbacks, state, ok, error_code)
    for _, callback in ipairs(callbacks or {}) do pcall(callback, result(state, ok, error_code)) end
end

local function accept(state, receipt)
    if type(receipt) ~= "table" or receipt.ok ~= true or receipt.account_id ~= state.account
        or receipt.match_session_id ~= state.session or receipt.version ~= 1
        or not statuses[receipt.status] or type(receipt.required) ~= "boolean"
        or receipt.required ~= (receipt.status == "required") then return false end
    state.loaded, state.status, state.required, state.version = true, receipt.status, receipt.required, 1
    return true
end

function M.get(player_id)
    local state = bound(tonumber(player_id))
    return snapshot(state)
end

function M.ensure(player_id, callback)
    player_id = tonumber(player_id)
    local state, provider, error_code = bound(player_id)
    if not state then
        if type(callback) == "function" then callback(result(nil,false,error_code)) end
        return {ok=false,pending=false,error=error_code}
    end
    if state.loaded then
        if type(callback) == "function" then callback(result(state,true)) end
        return result(state,true)
    end
    if state.read_callbacks then
        if type(callback) == "function" then state.read_callbacks[#state.read_callbacks+1] = callback end
        return {ok=true,pending=true}
    end
    if type(provider.onboarding_state) ~= "function" then
        if type(callback) == "function" then callback(result(state,false,"onboarding_provider_unavailable")) end
        return {ok=false,pending=false,error="onboarding_provider_unavailable"}
    end
    state.read_callbacks = type(callback) == "function" and {callback} or {}
    local done = false
    local function finish(receipt, failure)
        if done then return end
        done = true
        local callbacks = state.read_callbacks
        state.read_callbacks = nil
        if not current(player_id,state) then notify(callbacks,nil,false,"account_binding_changed");return end
        local ok = not failure and accept(state,receipt)
        notify(callbacks,state,ok,not ok and (failure or receipt and receipt.error or "onboarding_response_invalid") or nil)
    end
    local called = pcall(provider.onboarding_state, {account_id=state.account},
        function(receipt) finish(receipt) end, function(failure) finish(nil,tostring(failure)) end)
    if not called then finish(nil,"onboarding_provider_failed") end
    return {ok=true,pending=not done}
end

function M.finish(player_id, outcome, callback)
    player_id = tonumber(player_id)
    local dispatch = {ok=true,pending=true}
    local function complete(value)
        value.pending = false
        dispatch = value
        if type(callback) == "function" then callback(value) end
    end
    if outcome ~= "completed" and outcome ~= "skipped" then
        complete(result(nil,false,"onboarding_outcome_invalid"))
        return dispatch
    end
    M.ensure(player_id, function(loaded)
        if not loaded.ok then complete(loaded);return end
        local state, provider = bound(player_id)
        if not state then complete(result(nil,false,"account_binding_changed"));return end
        if not state.required then complete(result(state,true));return end
        if state.finish_callbacks then
            state.finish_callbacks[#state.finish_callbacks+1] = complete
            return
        end
        if type(provider.onboarding_finish) ~= "function" then
            complete(result(state,false,"onboarding_provider_unavailable"))
            return
        end
        state.finish_callbacks = {complete}
        local done = false
        local function finish(receipt, failure)
            if done then return end
            done = true
            local callbacks = state.finish_callbacks
            state.finish_callbacks = nil
            if not current(player_id,state) then notify(callbacks,nil,false,"account_binding_changed");return end
            -- A finish response must actually be a durable terminal state.
            local valid = type(receipt) == "table" and (receipt.status == "completed" or receipt.status == "skipped")
            local ok = not failure and valid and accept(state,receipt)
            notify(callbacks,state,ok,not ok and (failure or receipt and receipt.error or "onboarding_response_invalid") or nil)
        end
        local called = pcall(provider.onboarding_finish, {account_id=state.account,outcome=outcome},
            function(receipt) finish(receipt) end, function(failure) finish(nil,tostring(failure)) end)
        if not called then finish(nil,"onboarding_provider_failed") end
    end)
    return dispatch
end

function M.init() states = {} end
return M
