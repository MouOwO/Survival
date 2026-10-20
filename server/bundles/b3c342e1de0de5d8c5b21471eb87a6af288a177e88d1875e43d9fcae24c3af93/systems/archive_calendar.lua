local M = {}
local clock
function M.set_clock(value) clock=value end
function M.now()
    if clock then return clock() end
    if os and os.time then return os.time() end
    if GetSystemDate and GetSystemTime then
        local m,d,y=GetSystemDate():match("(%d+)/(%d+)/(%d+)")
        local h,n,s=GetSystemTime():match("(%d+):(%d+):(%d+)")
        if m and h then
            m,d,y=tonumber(m),tonumber(d),tonumber(y); if y<100 then y=y+2000 end
            y=y-(m<=2 and 1 or 0)
            local era=math.floor(y/400); local yo=y-era*400
            local days=era*146097+yo*365+math.floor(yo/4)-math.floor(yo/100)
                +math.floor((153*(m+(m>2 and -3 or 9))+2)/5)+d-1-719468
            return days*86400+tonumber(h)*3600+tonumber(n)*60+tonumber(s)-8*3600
        end
    end
    error("archive_server_clock_unavailable")
end
function M.day() return math.floor((M.now()+8*3600)/86400) end
function M.has_pass(profile)
    local e=profile and profile.entitlements and profile.entitlements.archive_pass
    return e and e.active==true and (e.expires_at==nil or tonumber(e.expires_at) and tonumber(e.expires_at)>M.now()) or false
end
return M
