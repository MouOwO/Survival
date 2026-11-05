-- Presentation dispatch only. Native 10938:11200340 paused-map evidence shows
-- delay/return 0 keeps thinking while positive delays stop. Install on demand,
-- return 0 only while a continuation exists, and return nil at idle. The
-- transport owns the shared real-time/work budget; gameplay timers stay paused.
local M = {}
local next_instance = 0

function M.new(options)
    local entity = assert(options.entity)
    assert(type(options.is_current) == "function", "dispatch_world_guard_required")
    next_instance = next_instance + 1
    local prefix = "SurvivalCompactDispatch_" .. next_instance .. "_"
    local pending, installed, running, disposed = nil, nil, false, false
    local serial = 0
    local api = {}

    function api.is_current()
        if disposed then return false end
        local ok, current = pcall(options.is_current)
        return ok and current == true
    end

    local function uninstall(ticket)
        if ticket and installed == ticket then installed = nil end
        if ticket then pcall(entity.SetContextThink, entity, ticket.key, nil, 0) end
    end

    function api.after(delay, callback, key)
        assert(delay == 0 and key == "compact_ui_dispatch", "compact_continuation_only")
        assert(type(callback) == "function", "dispatch_callback_required")
        assert(api.is_current(), "compact_dispatch_world_expired")
        pending = callback
        -- The installed callback consumes one continuation per engine frame.
        -- A nested after/cancel must not install a slot that its caller's nil
        -- return could remove; the current callback decides whether to repeat.
        if installed then return key end
        serial = serial + 1
        local ticket = {key = prefix .. serial}
        installed = ticket
        local ok = pcall(entity.SetContextThink, entity, ticket.key, function()
            if installed ~= ticket then return nil end
            if not api.is_current() then pending, installed = nil, nil;return nil end
            local callback = pending
            pending = nil
            running = true
            local succeeded = not callback or pcall(callback)
            running = false
            if not succeeded then
                -- A later explicit publication can start a fresh installation.
                -- Never retain a permanently running or installed failed job.
                pending = nil
            end
            if installed ~= ticket then return nil end
            if not api.is_current() then pending, installed = nil, nil;return nil end
            if pending then return 0 end
            installed = nil
            return nil
        end, 0)
        if not ok then
            pending = nil
            uninstall(ticket)
            error("compact_dispatch_native_install_failed", 0)
        end
        return key
    end

    function api.cancel(key)
        assert(key == "compact_ui_dispatch", "compact_continuation_only")
        pending = nil
        if not running then uninstall(installed) end
    end

    function api.dispose()
        disposed = true
        pending = nil
        uninstall(installed)
    end

    return api
end

return M
