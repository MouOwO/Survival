-- Opt-in Tools-only orchestration. Never initialized by the addon.
local M = {}
local bus, e = require('core/event_bus'), require('core/events')
local json = require('core/json_encoder')
local cards = require('config/generated/rogue_reward_cards')
local probe = require('tests/game_rogue_builder_probe')
local runtime = require('systems/rogue_effect_runtime_service')
M.reports = {}
local function compact(value, seen)
    if type(value) ~= 'table' then return type(value) == 'userdata' and tostring(value) or value end
    if value.entindex and type(value.entindex) == 'function' then return value:entindex() end
    seen = seen or {}; if seen[value] then return '<cycle>' end; seen[value] = true
    local out = {}; for k,v in pairs(value) do if type(v) ~= 'function' then out[k]=compact(v,seen) end end
    seen[value] = nil; return out
end
local function log_view(value, depth)
    if type(value) ~= 'table' then return value end
    depth=depth or 0
    local out={}
    for k,v in pairs(value) do
        if k=='history' or k=='ui_updates' or k=='resource_events' or k=='heal_events'
            or k=='ticks' or k=='income_samples' then
            out[k..'_count']=type(v)=='table' and #v or 0
        elseif k=='hero' and type(v)=='table' and v.snapshot then
            local s=v.snapshot
            out[k]={entindex=s.entindex,attack_min=s.attack_min,attack_speed=s.attack_speed,
                strength=s.strength,agility=s.agility,intellect=s.intellect}
        else out[k]=log_view(v,depth+1) end
    end
    return out
end
function M.emit(id, report)
    local out = compact(report); M.reports[id]=out
    print('[ROGUE_LIVE:'..id..'] '..json.encode(log_view(out))); return report
end
function M.context()
    local out={}; local r=bus.request(e.BUILDER_GET_REQUEST,{player_id=0}) or {}
    out.builder = r.builder or r.unit
    for _,b in ipairs((bus.request(e.BUILDING_LIST_REQUEST,{player_id=0}) or {}).buildings or {}) do
        if b.building_id == 'main_city' then out.city=b.unit elseif b.building_id=='wall' then out.wall=b.unit
        elseif b.building_id=='arrow_tower' then out.tower=b.unit elseif b.building_id=='gold_mine' then out.mine=b.unit
        elseif b.building_id=='hero_altar' then out.altar=b.unit elseif b.building_id=='challenge_building' then out.challenge=b.unit end
    end
    out.hero = (bus.request(e.HERO_SUMMON_GET_REQUEST,{player_id=0}) or {}).unit
    for _,w in ipairs(bus.request(e.WORKER_LIST_REQUEST,{player_id=0}) or {}) do
        if w.unit and w.unit.survival_worker_type=='lumberjack' then out.worker=w.unit end
    end
    return out
end
function M.grant(id)
    assert(IsInToolsMode(),'requires_tools_mode')
    for _,i in ipairs(runtime.snapshot(0)) do if i.card_id==id then return {ok=true,previously_granted=true} end end
    local target=assert(cards.by_id[id]); local ids={id}
    for _,c in ipairs(cards.rows) do if c.enabled and c.type==target.type and c.card_id~=id and #ids<3 then ids[#ids+1]=c.card_id end end
    local offer=require('systems/rogue_reward_service').debug_offer(0,ids)
    if not offer or not offer.ok then return M.emit(id..':grant',{ok=false,offer=offer}) end
    return M.emit(id..':grant',bus.request(e.ROGUE_REWARD_SELECT_REQUEST,{player_id=0,card_id=id,token=offer.token,reward_type=target.type}))
end
function M.build(id, positions)
    local c=M.context(); local report={id=id,attempts={}}
    for _,p in ipairs(positions) do
        local valid=bus.request(e.BUILD_CAN_PLACE_REQUEST,{player_id=0,caster=c.builder,building_id=id,position=p})
        report.attempts[#report.attempts+1]={position=tostring(p),placement=valid}
        if valid and valid.ok then
            FindClearSpaceForUnit(c.builder,p+Vector(350,0,0),true)
            report.result=bus.request(e.BUILD_REQUEST,{player_id=0,caster=c.builder,building_id=id,position=p}); break
        end
    end
    return M.emit('build:'..id,report)
end
function M.setup()
    local c=M.context(); assert(c.city and c.hero,'scene_not_ready')
    M.emit('context',c)
    M.build('arrow_tower',{Vector(1152,6656,385),Vector(1408,6400,385),Vector(1024,5888,385)})
    M.emit('train:lumberjack',bus.request(e.WORKER_TRAIN_REQUEST,{city=c.city,player_id=0,training_id='train_lumberjack_01'}))
end
function M.stat(id, unit)
    local before=probe.snapshot(unit,0); local grant=M.grant(id); local after=probe.snapshot(unit,0)
    return M.emit(id,{grant=grant,before=before,after=after})
end
return M
