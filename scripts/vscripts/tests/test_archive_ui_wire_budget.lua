-- Real archive projectors and quota module; synthetic account, no engine/I/O.
package.path = "scripts/vscripts/?.lua;" .. package.path
local raw_print, logs = print, {}
print = function(value) logs[#logs + 1] = tostring(value) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end; return result
end
local encoder = require("core/json_encoder")
local encode, encodes = encoder.encode, 0
encoder.encode = function(value) encodes = encodes + 1; return encode(value) end
package.loaded["core/test_access_policy"] = { enabled=function() return false end,
    allowed=function() return true end, enforce=function() return true end }
local timers, listeners, packets, profile, archive, fail_send = {}, {}, {}, nil, nil, false
local writes, http, sends = 0, 0, 0
local provider = { archive_enabled=function() return false end }
package.loaded["core/scheduler"] = { every=function(_, fn, key) timers[key]=fn end,
    after=function(_, fn, key) timers[key]=fn end, cancel=function(key) timers[key]=nil end }
package.loaded["systems/player_profile_service"] = {
    get_account_profile=function() return copy(profile) end, get_profile=function() return copy(profile) end,
    get_provider=function() return provider end,
    update_save_sections=function() writes=writes+1; error("unexpected persistence") end }
package.loaded["systems/archive_http_adapter"] = { enabled=function() return false end }
package.loaded["debug/mode_unlock_test"] = { is_enabled=function() return true end }
package.loaded["debug/offline_logic_test"] = { is_enabled=function() return true end,
    is_provider=function(value) return value==provider end }
package.loaded["systems/match_setup_service"] = { get_mode=function() return "standard" end,
    get_profile_mode=function() return "standard" end, get_session_id=function() return "synthetic_wire_budget" end,
    is_mode_selected=function() return true end }
GameRules = { GetGameTime=function() return 0 end, IsCheatMode=function() return false end }
IsInToolsMode=function() return true end
IsServer=function() return true end
IsClient=function() return false end
GetMapName=function() return "template_map" end
RandomInt=function(low) return low end
CreateHTTPRequestScriptVM=function() http=http+1; error("unexpected HTTP") end
local player = {}
PlayerResource = { GetPlayer=function(_, id) return id==0 and player or nil end,
    IsValidPlayerID=function(_, id) return id==0 end }
CustomNetTables = { SetTableValue=function() end }
CustomGameEventManager = { RegisterListener=function(_, name, fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_, recipient, name, data)
        assert(recipient==player and name=="survival_archive_snapshot")
        sends=sends+1
        if fail_send and data.category_id=="clear" and data.chunk==2 then error("synthetic_native_send_failure") end
        packets[#packets+1] = copy(data)
    end }
local bus, events = require("core/event_bus"), require("core/events")
local definitions = require("config/generated/archive_categories")
local function reset()
    bus.reset(); packets, timers, listeners, logs, fail_send = {}, {}, {}, {}, false
    profile={revision=1,save={gameplay_stats={},content_inventory={},archive={}},entitlements={}}
    for _, row in ipairs(require("config/generated/player_gameplay_stats").rows) do
        if row.enabled~=false then profile.save.gameplay_stats[row.field_id]=tonumber(row.default_value) or 0 end
    end
    package.loaded["systems/archive_service"]=nil
    archive=require("systems/archive_service");archive.init();archive.set_clock(function() return 1700000000 end)
    encodes, sends = 0, 0
end
local function publish() bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="synthetic_wire_budget"}) end
local function expected_pages()
    local result, count = {}, 0
    for _, category in ipairs(definitions.rows) do if category.enabled then
        local page=archive.snapshot(0,category.category_id)
        assert(page.ok and page.daily_limits and page.daily_limits.rows and page.daily_limits.by_key)
        count=count+#page.rows;page.daily_limits=nil;result[category.category_id]=page
    end end
    return result,count
end
local function check_packets(values)
    local bytes, max_bytes, rows = 0, 0, 0
    for _, packet in ipairs(values) do
        local size=#encode(packet);assert(size<=6144,"wire JSON budget exceeded")
        assert(#packet.rows<=12 and packet.daily_limits==nil,"wire-only projection/row cap")
        assert(packet.chunk>=1 and packet.chunk<=packet.chunks)
        if packet.delta==1 then for _, operation in ipairs(packet.rows) do
            assert(operation.path and operation.path[1]~="daily_limits","quota metadata must not leak into deltas")
        end end
        bytes=bytes+size;max_bytes=math.max(max_bytes,size);rows=rows+#packet.rows
    end
    return bytes,max_bytes,rows
end
local function rejects(reason)
    for _, line in ipairs(logs) do if line:find("REJECT",1,true) and line:find(reason,1,true) then return true end end
end
local function timer_count() local n=0;for _ in pairs(timers) do n=n+1 end;return n end

reset()
local before_timers=timer_count()
local initial_expected, initial_rows=expected_pages()
encodes=0;publish()
local initial_encodes=encodes
local initial_packets=copy(packets)
local initial_bytes,max_bytes,sent_rows=check_packets(initial_packets)
assert(initial_rows==945 and sent_rows==initial_rows,"all real catalogue rows must be retained")
assert(not rejects("budget") and timer_count()==before_timers,"catalogue fits without new scheduling")
packets,encodes={},0;publish()
assert(#packets==0 and encodes==0,"same-state refresh performs zero native sends/JSON encodes")
local unchanged_encodes=encodes
profile.save.content_inventory.commerce_p026=1;profile.revision=2
packets,encodes={},0;publish()
local delta_packets,change_encodes=copy(packets),encodes
assert(#delta_packets>0);check_packets(delta_packets)
for _,packet in ipairs(delta_packets) do assert(packet.delta==1 and packet.base_sequence) end
local changed_expected=expected_pages()
-- The server quota API remains complete and continues enforcing its real cap.
local quota=require("systems/archive_daily_limits");local day=require("systems/archive_calendar").day()
local limit=quota.limit("faith",false)
assert(quota.grant(profile.save.archive,"faith",limit+1,day,false)==limit)
assert(quota.remaining(profile.save.archive,"faith",day,false)==0)
assert(archive.snapshot(0,"clear").daily_limits.by_key.faith.earned==limit)

-- Reject the entire page before emitting its earlier small row or committing a
-- baseline. The real server snapshot keeps both rows, including the large one.
reset()
archive.register_category("clear",function(private)
    private.save.content_inventory.synthetic_mutation=1
    return {{id="small"},{id="large",description=string.rep("饰",2500)}}
end)
publish()
for _,packet in ipairs(packets) do assert(packet.category_id~="clear","no partial rejected page") end
assert(rejects("row_budget") and #archive.snapshot(0,"clear").rows==2)
assert(profile.save.content_inventory.synthetic_mutation==nil,"custom projector argument stays private")
archive.register_category("clear",function() return {{id="small"}} end)
packets={};publish()
local found=false;for _,packet in ipairs(packets) do if packet.category_id=="clear" then
    assert(packet.delta==nil,"rejected page cannot become a delta baseline");found=true
end end;assert(found)

-- Header rejection does not remove data from M.snapshot or create baselines.
reset();profile.save.archive.social_last_draw={description=string.rep("大",2500)}
publish();assert(#packets==0 and rejects("header_budget"))
assert(archive.snapshot(0,"clear").last_draw.description==profile.save.archive.social_last_draw.description)
profile.save.archive.social_last_draw=nil;packets={};publish()
assert(#packets>0);for _,packet in ipairs(packets) do assert(packet.delta==nil) end

-- A synchronous native failure after chunk1 must not advance sent_pages.
reset();fail_send=true;publish()
local partial=false;for _,packet in ipairs(packets) do if packet.category_id=="clear" then partial=true end end
assert(partial,"failure must occur after an actual first chunk")
fail_send=false;packets={};publish()
found=false;for _,packet in ipairs(packets) do if packet.category_id=="clear" then
    assert(packet.delta==nil,"partial send cannot become a baseline");found=true
end end;assert(found)
assert(writes==0 and http==0,"fixture must not invoke persistence or HTTP")
local result={kind="REAL_ARCHIVE_UI_WIRE_BUDGET_SYNTHETIC_NOT_NATIVE",rows=initial_rows,
    packets=#initial_packets,json_payload_bytes=initial_bytes,max_json_packet_bytes=max_bytes,
    initial_json_encode_calls=initial_encodes,unchanged_json_encode_calls=unchanged_encodes,
    change_json_encode_calls=change_encodes,change_packets=#delta_packets,per_packet_json_budget=6144,
    server_quota_preserved=true,rejected_header_and_row_preserved=true,partial_send_baseline_safe=true,
    timers_added=0,http_calls=http,persistence_calls=writes,native_calls=0}
if arg and arg[1]=="emit" then result.initial_packets=initial_packets;result.delta_packets=delta_packets
    result.initial_expected=initial_expected;result.changed_expected=changed_expected end
raw_print(encode(result))
