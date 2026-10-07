-- Cosmetic preview never changes rewards or account ownership.
local bus = require("core/event_bus")
local events = require("core/events")
local profiles = require("systems/player_profile_service")
local titles = require("systems/archive_titles")
local models = require("systems/title_model_service")
local M = {}
local preview, published, selections = {}, {}, {}
local function account(id)
    return profiles.get_account_profile and profiles.get_account_profile(id) or profiles.get_profile(id)
end
function M.preview_mode()
    return type(IsInToolsMode)=="function" and IsInToolsMode()
        and require("systems/archive_http_adapter").enabled()
end
function M.rows(id, archive)
    return titles.rows(archive, M.preview_mode() and preview[id] or nil)
end
function M.preview(id, title_id)
    if not M.preview_mode() then return {ok=false,error="称号试穿仅在工具模式开放"} end
    local profile = account(id)
    if not profile then return {ok=false,error="玩家档案尚未加载"} end
    local archive = profile.save.archive or {}
    if type(title_id)~="string" or title_id~="" and not titles.unlocked(archive,title_id) then
        return {ok=false,error="称号未解锁或不存在"}
    end
    preview[id] = title_id
    M.publish(id)
    return {ok=true,preview=true}
end
function M.refresh(id)
    local profile = account(id)
    selections[id] = profile and titles.selected(profile.save.archive) or ""
end
function M.publish(id)
    if not CustomNetTables then return end
    if selections[id]==nil then M.refresh(id) end
    local title_id = selections[id]
    if M.preview_mode() and preview[id]~=nil then title_id=preview[id] end
    -- The summon service identifies the real combat hero, excluding builder anchors and clones.
    local summoned = bus.request(events.HERO_SUMMON_GET_REQUEST, {player_id=id})
    local unit = summoned and summoned.unit
    local valid = unit and (not unit.IsNull or not unit:IsNull())
        and not unit.survival_hide_custom_health_bar
        and not (unit.IsIllusion and unit:IsIllusion())
    local entindex = valid and unit.entindex and unit:entindex() or -1
    local name = valid and unit.GetUnitName and unit:GetUnitName() or ""
    models.clear(id) -- retire any previously equipped 3D prototype
    local signature = title_id..":"..entindex..":"..name..":layered_v1"
    if published[id]==signature then return end
    published[id]=signature
    CustomNetTables:SetTableValue("survival_hero_health_bar", "title_"..id,
        {player_id=id,entindex=entindex,title_id=title_id,unit_name=name,
            render_mode="layered",model_entindex=-1,model_height=0})
end
function M.init()
    local scheduler = require("core/scheduler")
    if scheduler.cancel then scheduler.cancel("title_mesh_update") end
    for id=0,(DOTA_MAX_TEAM_PLAYERS or 24)-1 do models.clear(id) end
    preview, published, selections = {}, {}, {}
    bus.subscribe(events.PLAYER_PROFILE_CHANGED,function(p) if p.player_id~=nil then M.refresh(p.player_id); M.publish(p.player_id) end end)
    bus.subscribe(events.HERO_SUMMONED,function(p) if p.player_id~=nil then M.publish(p.player_id) end end)
    require("core/scheduler").every(0.25,function()
        for id=0,(DOTA_MAX_TEAM_PLAYERS or 24)-1 do
            if PlayerResource and PlayerResource:IsValidPlayerID(id) then M.publish(id) end
        end
    end,"title_presentation")
end
return M
