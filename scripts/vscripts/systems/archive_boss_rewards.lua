local definitions=require("config/generated/archive_boss_achievements")
local calendar=require("systems/archive_calendar")
local M={}
function M.project(profile)
    local count=tonumber(profile and profile.save and profile.save.archive and profile.save.archive.boss_kills) or 0
    local pass=calendar.has_pass(profile)
    local rows, effects={},{}
    for _, item in ipairs(definitions.rows) do
        if item.enabled then
            local target=pass and item.pass_required_kills or item.required_kills
            local active=count>=target
            rows[#rows+1]={id=item.achievement_id,name=item.display_name.."（"..target.."次）",
                description=item.description, count=count,target=target, completed=active and 1 or 0,quality="SSR",icon_style="seal",rune="王"}
            if active then for i,field in ipairs(item.effect_ids) do effects[field]=(effects[field] or 0)+tonumber(item.effect_values[i]) end end
        end
    end
    return rows,effects
end
return M
