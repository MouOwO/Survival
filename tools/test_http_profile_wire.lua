package.path='scripts/vscripts/?.lua;'..package.path
local json=require('core/json_decoder')
local wire=require('systems/http_profile_wire')
local function same(a,b)
    if a==json.null or b==json.null then return a==b end
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for key,value in pairs(a)do if not same(value,b[key])then return false end end
    for key in pairs(b)do if a[key]==nil then return false end end
    return true
end
local rows=json.decode(io.read('*a'))
for index,row in ipairs(rows)do
    local original=require('core/json_encoder').encode(row.wire)
    local value,reason=wire.decode(row.wire)
    if row.invalid then
        assert(value==nil and reason=='http_profile_wire_invalid','invalid vector accepted: '..index)
        assert(require('core/json_encoder').encode(row.wire)==original,'partial mutation: '..index)
    else
        assert(value~=nil and same(value,row.expected),'round trip mismatch: '..index)
        if value.profile and value.profile.account_profile and value.profile.save
            and value.profile.account_profile.save then
            assert(value.profile.save~=value.profile.account_profile.save,'profile/account share mutable save')
        end
        local daily=value.profile and value.profile.daily_limits
        if daily and daily.rows and daily.by_key then
            for _,entry in ipairs(daily.rows)do
                if daily.by_key[entry.key]then assert(entry~=daily.by_key[entry.key],'rows/index share mutable row')end
            end
            if value.daily_limits then assert(value.daily_limits~=daily,'root/profile share mutable daily map')end
            if value.profile.progression and value.profile.progression.daily_limits then
                assert(value.profile.progression.daily_limits~=daily,'progression/profile share mutable daily map')
            end
        end
    end
end
print('HTTP_PROFILE_WIRE_VECTORS_PASS '..#rows)
