-- Tools-only, synchronous and read-only: no units, orders, schedules, profiles,
-- rewards or files. Fresh region modules avoid changing a live builder guard.
local M = {}
local last_report

function M.run(nonce)
    assert(type(IsInToolsMode) == "function" and IsInToolsMode(), "mode_spawn_probe_tools_only")
    assert(type(GetMapName) == "function" and GetMapName() == "template_map", "mode_spawn_probe_wrong_map")
    nonce = tostring(nonce or "manual"):gsub("[^%w_-]", "_")
    local prefix = "[MODE_SPAWN_PROBE][" .. nonce .. "] "
    local watched = {"systems/match_setup_service", "systems/rich_region_service",
        "systems/mode_spawn_service", "systems/player_context_service", "systems/wave_spawn_routing",
        "config/mode_spawn_config"}
    local saved = {}
    for _, name in ipairs(watched) do saved[name] = package.loaded[name] end
    local report = {nonce=nonce, markers={}, routes={}, modes={}, errors={}, restored=false,
        read_only=true, spawned_units=0, account_writes=0, scheduled_jobs=0}
    local function issue(reason)
        report.errors[#report.errors + 1] = tostring(reason)
        print(prefix .. "FAIL " .. tostring(reason))
    end
    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
    local ok, failure = xpcall(function()
        package.loaded["config/mode_spawn_config"] = nil
        local config = require("config/mode_spawn_config")
        local context = require("systems/player_context_service")
        local routing = require("systems/wave_spawn_routing")
        local seen = {}
        for _, mode in ipairs({"rich", "cold", "scourge"}) do
            package.loaded["systems/match_setup_service"] = {get_mode=function() return mode end}
            package.loaded["systems/rich_region_service"] = nil
            -- Do not call init(): its scheduler.cancel would touch a real guard.
            local regions = require("systems/rich_region_service")
            local service = require("systems/mode_spawn_service")
            local row = assert(config.modes[mode], "missing_mode_config:" .. mode)
            local names = {row.center_marker}
            for id=0,3 do names[#names+1]=row.player_markers[id];names[#names+1]=row.monster_markers[id] end
            for _, name in ipairs(names) do
                if seen[name] then issue("duplicate_marker_name:" .. name) end
                seen[name]=true
                local entity, point, missing = service.marker(name)
                local landing, invalid
                if point then landing, invalid=service.landing(point,row.bounds) end
                local entry={name=name,mode=mode,ok=entity~=nil and landing~=nil}
                if point then entry.authored={x=point.x,y=point.y,z=point.z} end
                if landing then
                    entry.ground={x=landing.x,y=landing.y,z=landing.z}
                    entry.classname=entity.GetClassname and entity:GetClassname() or "unknown"
                    if entry.classname~="info_target" then entry.ok=false;issue("marker_class:"..name..":"..entry.classname) end
                    print(string.format(prefix.."MARKER name=%s class=%s ok=%s x=%.1f y=%.1f authored_z=%.1f ground_z=%.1f",
                        name,entry.classname,tostring(entry.ok),point.x,point.y,point.z,landing.z))
                else issue("marker_landing:"..name..":"..tostring(missing or invalid)) end
                report.markers[#report.markers+1]=entry
            end
            local channels, homes = {}, {}
            for id=0,3 do
                local home, reason=context.resolve_builder_spawn(id)
                if not home then issue("builder_spawn:"..mode..":"..id..":"..tostring(reason))
                else
                    homes[id]=home
                    local valid=home.mode==mode and home.marker==row.player_markers[id]
                        and regions.validate_position(id,home.position)
                    if not valid then issue("builder_mode_identity:"..mode..":"..id) end
                end
                local channel, error=service.wave_marker(id)
                if not channel then issue("wave_spawn:"..mode..":"..id..":"..tostring(error))
                else channels[id]=channel end
            end
            routing.refresh(channels,{},1)
            local mode_report={mode=mode,players=0,routes=0}
            for id=0,3 do
                local source=routing.position(channels[id])
                local home=homes[id]
                if home then mode_report.players=mode_report.players+1 end
                if source and home then
                    local path_ok, reachable=pcall(GridNav.CanFindPath,GridNav,source,home.position)
                    local measured,length=pcall(GridNav.FindPathLength,GridNav,source,home.position)
                    local route={mode=mode,player_id=id,monster_marker=channels[id].marker_name,
                        player_marker=home.marker,can_find_path=path_ok and reachable==true,
                        length=measured and finite(length) and length or nil,
                        source={x=source.x,y=source.y,z=source.z},
                        destination={x=home.position.x,y=home.position.y,z=home.position.z}}
                    route.ok=route.can_find_path and route.length~=nil and route.length>0
                        and channels[id].mode==mode and channels[id].marker_name==row.monster_markers[id]
                    if not route.ok then issue("path:"..mode..":"..id..":reachable="..tostring(reachable)..":length="..tostring(length)) end
                    print(string.format(prefix.."ROUTE mode=%s player=%d ok=%s can_find_path=%s length=%s monster=%s home=%s",
                        mode,id,tostring(route.ok),tostring(route.can_find_path),tostring(route.length),route.monster_marker,route.player_marker))
                    report.routes[#report.routes+1]=route
                    mode_report.routes=mode_report.routes+1
                else issue("route_missing:"..mode..":"..id) end
            end
            report.modes[#report.modes+1]=mode_report
        end
    end, debug.traceback)
    -- Always restore the exact module objects, including a nil prior cache.
    for _, name in ipairs(watched) do package.loaded[name]=saved[name] end
    report.restored=true
    for _, name in ipairs(watched) do
        if package.loaded[name]~=saved[name] then report.restored=false;issue("module_restore:"..name) end
    end
    if not ok then issue(failure) end
    report.ok=ok and report.restored and #report.errors==0 and #report.markers==27 and #report.routes==12
    last_report=report
    print(string.format(prefix.."SUMMARY ok=%s markers=%d routes=%d modes=%d errors=%d restored=%s spawned_units=0 account_writes=0 scheduled_jobs=0",
        tostring(report.ok),#report.markers,#report.routes,#report.modes,#report.errors,tostring(report.restored)))
    return report
end

function M.last() return last_report end
return M
