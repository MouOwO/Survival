-- Rebuild exact same-response references before normal profile validation.
-- No persistent baseline/cache, scene scan, polling, or native/network calls.
-- Init/idle O(1); one low-frequency decode O(B+R), R<=256/current40 daily rows.
local null = require('core/json_decoder').null
local M = {}
local fields = {'schema_version','account_id','revision','entitlements','achievements','save','public'}
local function object(value) return type(value)=='table'and value~=null end
local function clone(value, depth)
    if value==null or type(value)~='table'then return value end
    if depth>64 then error('profile_wire_depth',0)end
    local result={}
    for key,child in pairs(value)do result[key]=clone(child,depth+1)end
    return result
end
local function bit(mask, value) return math.floor(mask/value)%2==1 end
local function decode_v1(value)
    if not object(value)then return nil,'http_profile_wire_invalid'end
    local marker=value._http_profile_refs
    if marker==nil then return value end -- Old servers/full fallback stay compatible.
    if not object(marker)or marker.v~=1 or type(marker.m)~='number'
        or marker.m~=math.floor(marker.m)or marker.m<1 or marker.m>511 then
        return nil,'http_profile_wire_invalid'
    end
    for key in pairs(marker)do if key~='v'and key~='m'then return nil,'http_profile_wire_invalid'end end
    local profile=value.profile
    if not object(profile)then return nil,'http_profile_wire_invalid'end
    local account=profile.account_profile
    local assignments={}
    for index,key in ipairs(fields)do
        if bit(marker.m,2^(index-1))then
            if not object(account)or account[key]~=nil or profile[key]==nil then
                return nil,'http_profile_wire_invalid'
            end
            assignments[#assignments+1]={target=account,key=key,source=profile[key]}
        end
    end
    if bit(marker.m,128)or bit(marker.m,256)then
        if not object(profile.daily_limits)then return nil,'http_profile_wire_invalid'end
    end
    if bit(marker.m,128)then
        if value.daily_limits~=nil then return nil,'http_profile_wire_invalid'end
        assignments[#assignments+1]={target=value,key='daily_limits',source=profile.daily_limits}
    end
    if bit(marker.m,256)then
        if not object(profile.progression)or profile.progression.daily_limits~=nil then return nil,'http_profile_wire_invalid'end
        assignments[#assignments+1]={target=profile.progression,key='daily_limits',source=profile.daily_limits}
    end
    -- Validate and copy everything before modifying any part of the response.
    local ok=pcall(function()
        for _,entry in ipairs(assignments)do entry.copy=clone(entry.source,0)end
    end)
    if not ok then return nil,'http_profile_wire_invalid'end
    for _,entry in ipairs(assignments)do entry.target[entry.key]=entry.copy end
    value._http_profile_refs=nil
    return value
end
local function shallow(value)
    if not object(value)then return value end
    local copy={}
    for key,child in pairs(value)do copy[key]=child end
    return copy
end
function M.decode(value)
    if not object(value)then return nil,'http_profile_wire_invalid'end
    local marker=value._http_profile_refs
    if not object(marker)or marker.v~=2 then return decode_v1(value)end
    if type(marker.m)~='number'or marker.m~=math.floor(marker.m)
        or marker.m<512 or marker.m>1023 then return nil,'http_profile_wire_invalid'end
    for key in pairs(marker)do if key~='v'and key~='m'then return nil,'http_profile_wire_invalid'end end
    local profile=value.profile
    local daily=object(profile)and profile.daily_limits
    if not object(daily)or daily.by_key~=nil or not object(daily.rows)then return nil,'http_profile_wire_invalid'end
    local count=0
    for key in pairs(daily.rows)do
        if type(key)~='number'or key~=math.floor(key)or key<1 or key>256 then return nil,'http_profile_wire_invalid'end
        count=count+1
    end
    if count<1 or count>256 then return nil,'http_profile_wire_invalid'end
    local seen={}
    for index=1,count do
        local row=daily.rows[index]
        local key=object(row)and row.key
        if type(key)~='string'or #key<1 or #key>96 or not key:match('^[a-z][a-z0-9_]*$')or seen[key]then
            return nil,'http_profile_wire_invalid'
        end
        seen[key]=true
    end
    -- Copy only mutation targets; unrelated unknown fields retain v1 semantics.
    -- All reconstruction, including a later v1 failure, is atomic to the input.
    local ok,result=pcall(function()
        local copy=shallow(value)
        copy.profile=shallow(profile)
        copy.profile.account_profile=shallow(profile.account_profile)
        copy.profile.progression=shallow(profile.progression)
        copy.profile.daily_limits=shallow(daily)
        local reconstructed={}
        for index=1,count do
            local row=daily.rows[index]
            reconstructed[row.key]=clone(row,0)
        end
        copy.profile.daily_limits.by_key=reconstructed
        if marker.m==512 then copy._http_profile_refs=nil
        else copy._http_profile_refs={v=1,m=marker.m-512}end
        return decode_v1(copy)
    end)
    if not ok or result==nil then return nil,'http_profile_wire_invalid'end
    return result
end
return M
