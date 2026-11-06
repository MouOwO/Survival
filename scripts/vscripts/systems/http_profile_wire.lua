-- Rebuild exact same-response references before normal profile validation.
-- No persistent baseline/cache, scene scan, polling, or native/network calls.
-- Init/idle O(1); one low-frequency decode O(B) time/space for copied fields.
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
function M.decode(value)
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
return M
