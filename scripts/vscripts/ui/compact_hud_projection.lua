-- Display-only typed HUD projection. Initial/full O(F), real state changes
-- O(F) for F=43 fixed scalar fields, never scene/catalogue size. Stable state
-- produces zero operations; clocks transmit deadlines, not ticking snapshots.
local M={}
local UINT,MAX=4294967296,9007199254740991
M.phases={waiting=1,selecting_mode=2,selecting_difficulty=3,fishing=4,countdown=5,
    spawning=6,spawn_channel_missing=7,all_waves_spawned=8,cleared=9,
    archive_challenges=10,archive_challenges_pending=11,defeat=12,dev_mode=13,
    dev_spawn=14,dev_preloading=15,victory=16}
M.modes={standard=1,pure=2,rich=3,cold=4,scourge=5,ruins=6,celestial=7,fishing=8}
M.defeat_reasons={monster_limit_exceeded=1,main_city_destroyed=2,player_disconnected=3,
    disconnect=4,base_destroyed=5,native_defeat=6,wall_destroyed=7,
    wall_destroyed_while_disconnected=8,disconnect_timeout=9,unknown=10}
local function need(ok,why)if not ok then error(why,0)end end
local function integer(value,name)
    need(type(value)=="number" and value==value and value>=0 and value<=MAX
        and value==math.floor(value),"hud_unsigned_integer_required:"..name)
    return value
end
local function flag(value,name)
    need(value==true or value==false or value==0 or value==1,"hud_boolean_required:"..name)
    return value==true or value==1
end
local function enumeration(value,values,name)
    if value==nil or value=="" then return nil end
    need(values[value]~=nil,"hud_enum_unknown:"..name..":"..tostring(value))
    return values[value]
end
local numeric={current_wave="wave_index",total_waves="wave_total",planned="wave_planned",
    pending="wave_pending",spawned="wave_spawned",alive="wave_alive",killed="wave_killed",
    failed_spawn="wave_failed_spawn",alive_limit="alive_limit",overflow_grace_seconds="overflow_grace_seconds"}
local boolean={boss_alive="wave_boss_alive",difficulty_selected="wave_selected",
    early_final_used="wave_early_final_used",victory_settled="wave_victory_settled",
    defeat_settled="wave_defeat_settled",post_clear_frozen="wave_post_clear_frozen",
    overflow_active="overflow_active",player_defeated="player_defeated",challenge_saving="challenge_saving",
    challenge_player_finished="challenge_player_finished",challenge_ended="challenge_ended"}
local deadlines={countdown_deadline="countdown_deadline_ms",overflow_deadline="overflow_deadline_ms",
    challenge_deadline="challenge_deadline_ms"}
function M.new(lookup)
    local F=assert(lookup.field_by_name)
    local record=assert(lookup.by_key["hud:state"])
    local allowed={known=true,wood=true,wood_hi=true,gold=true,gold_hi=true,population=true,
        max_population=true,city_level=true,worker_count=true,shop_unlocked=true,research_unlocked=true,
        advanced_researcher_unlocked=true,wave_phase=true,wave_game_mode=true,wave_difficulty=true,defeat_reason=true}
    for _,name in pairs(numeric)do allowed[name]=true end
    for _,name in pairs(boolean)do allowed[name]=true end
    for _,name in pairs(deadlines)do allowed[name]=true end
    local ids={};for name in pairs(allowed)do need(F[name]~=nil,"hud_field_missing:"..name);ids[#ids+1]=F[name]end
    table.sort(ids)
    local function project(snapshot)
        need(type(snapshot)=="table" and type(snapshot.resources)=="table" and type(snapshot.wave)=="table","hud_snapshot_required")
        local values={[F.known]=true};local resource,wave=snapshot.resources,snapshot.wave
        local function put(name,value)if value~=nil then values[F[name]]=value end end
        for _,name in ipairs({"wood","gold"})do
            if resource[name]~=nil then
                local value=integer(resource[name],name)
                put(name,value%UINT);put(name.."_hi",math.floor(value/UINT))
            end
        end
        for _,name in ipairs({"population","max_population"})do
            if resource[name]~=nil then put(name,integer(resource[name],name))end
        end
        for _,name in ipairs({"city_level","worker_count"})do
            if snapshot[name]~=nil then put(name,integer(snapshot[name],name))end
        end
        for _,name in ipairs({"shop_unlocked","research_unlocked","advanced_researcher_unlocked"})do
            if snapshot[name]~=nil then put(name,flag(snapshot[name],name))end
        end
        for source,target in pairs(numeric)do if wave[source]~=nil then put(target,integer(wave[source],source))end end
        for source,target in pairs(boolean)do if wave[source]~=nil then put(target,flag(wave[source],source))end end
        for source,target in pairs(deadlines)do if wave[source]~=nil then
            local value=wave[source]
            need(type(value)=="number" and value==value and value>=0 and value<4294967,"hud_deadline_invalid:"..source)
            put(target,math.ceil(value*1000))
        end end
        put("wave_phase",enumeration(wave.status,M.phases,"phase"))
        put("wave_game_mode",enumeration(wave.game_mode,M.modes,"mode"))
        -- Optional explanatory text cannot discard authoritative defeat flags
        -- or the rest of the HUD. Unregistered reasons use the existing wire
        -- value for unknown; the server retains its original diagnostic text.
        local reason=wave.defeat_reason
        if reason~=nil and reason~="" and M.defeat_reasons[reason]==nil then reason="unknown"end
        put("defeat_reason",enumeration(reason,M.defeat_reasons,"defeat_reason"))
        if wave.difficulty_id~=nil then
            local id=wave.difficulty_id=="" and 0 or tonumber(tostring(wave.difficulty_id):match("^N(%d+)$"))
            need(id~=nil and id<=10,"hud_difficulty_invalid");put("wave_difficulty",id)
        end
        return values
    end
    local function convert(values,previous,full)
        local operations={}
        for _,id in ipairs(ids)do
            local value=values[id]
            if full and value~=nil or not full and value~=previous[id]then
                operations[#operations+1]={record=record,field=id,value=value,remove=value==nil or nil}
            end
        end
        return operations
    end
    local api={}
    function api.initialize(snapshot)
        local ok,values=pcall(project,snapshot);if not ok then return nil,values end
        local state={values=values}
        function state.update(next_snapshot)
            local valid,next_values=pcall(project,next_snapshot);if not valid then return nil,next_values end
            local operations=convert(next_values,state.values,false);state.values=next_values
            return operations,{fixed_fields=#ids,changed_fields=#operations,catalogue_rows=0}
        end
        return state,convert(values,{},true)
    end
    return api
end
return M
