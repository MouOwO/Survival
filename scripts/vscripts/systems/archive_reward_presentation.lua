-- Presentation of a committed receipt only; this module never grants rewards.
local M = {}
local colors = {
    white="#d7dee4", gray="#aeb8c2", green="#8fc47b", blue="#74c8f2",
    purple="#b680ee", gold="#f5c65e", red="#ef5350",
    N="#8fc47b", R="#74c8f2", SR="#b680ee", SSR="#f5c65e", UR="#ef5350",
}
local function integer(value)
    return type(value)=="number" and value>0 and value<math.huge and value==math.floor(value)
end
local function escape(value)
    return value:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;")
        :gsub('"',"&quot;"):gsub("'","&#39;")
end
function M.message(response)
    if type(response)~="table" or response.skipped_reason or not integer(response.awarded)
        or type(response.rewards)~="table" then return nil end
    local parts,total={},0
    for _,reward in ipairs(response.rewards) do
        if type(reward)~="table" or type(reward.name)~="string" or reward.name==""
            or not integer(reward.count) then return nil end
        local color=colors[reward.quality] or colors.white
        parts[#parts+1]='<font color="'..color..'">'..escape(reward.name)..'</font> ×'..tostring(reward.count)
        total=total+reward.count
    end
    -- Missing/legacy detail must not turn an estimated configured drop into a
    -- success message. The acknowledged accepted count is the exact boundary.
    if #parts==0 or total~=response.awarded then return nil end
    return "获得 "..table.concat(parts,"、")
end
return M
