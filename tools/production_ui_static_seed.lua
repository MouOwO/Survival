-- Public display seed only. The catalogue runner supplies immutable Git blobs
-- through virtual IO; this program never reads player state or allocates IDs.
package.path = "scripts/vscripts/?.lua;" .. package.path
local config = require("config/research_technology_config")
local description = require("research/research_technology_description")
local mappings = require("config/generated/research_lab_abilities")
local training_definitions = require("config/generated/training_definitions")
local training_progress = require("systems/worker_training_progress")
local queue_service = require("systems/worker_training_queue_service")
local cost_service = require("research/research_cost_service")
local json = require("core/json_encoder")
local source_paths = {
    "scripts/vscripts/ui/ability_runtime_builder.lua",
    "scripts/vscripts/ui/production_ui_service.lua",
    "scripts/vscripts/systems/worker_system.lua",
    "scripts/vscripts/systems/shop_system.lua",
    "scripts/vscripts/systems/worker_training_queue_service.lua",
    "scripts/vscripts/systems/worker_training_progress.lua",
    "scripts/vscripts/research/research_technology_service.lua",
    "panorama/src/scripts/custom_game/production_progress.js",
}
local raw = {}
for _, path in ipairs(source_paths) do
    local f = assert(io.open(path, "rb"), "immutable_production_source_missing:" .. path)
    raw[path] = f:read("*a"); f:close()
end
local builder = raw[source_paths[1]]
local check = assert(builder:match("(local function with_cast_resource_check.-)local function value_delta"), "production_resource_check_boundary_changed")
local upgrade = assert(builder:match("(local function research_effect_value.-)local function with_upgrade_quote"), "production_research_boundary_changed")
local public_env = {
    tonumber=tonumber, tostring=tostring, type=type, math=math,
    research_config=config, research_description=description,
    research_lab_abilities=mappings, research_cost_service=cost_service,
    event_bus={request=function() return nil end}, events={},
}
local build_status = assert(loadstring(check .. upgrade .. "\nreturn research_upgrade", "@immutable/production_status_projection"))
setfenv(build_status, public_env)
local research_upgrade = build_status()

local training = training_progress.create(training_definitions, "train_lumberjack_", "lumberjack"):get_all(0)
for _, row in ipairs(training) do
    row.count, row.completed = nil, nil
    row.base_max_count, row.max_count = row.max_count, nil
    row.cost_wood, row.cost_gold, row.population = row.wood_cost, row.gold_cost, row.population_cost
end
local training_capacity = assert(tonumber(raw[source_paths[3]]:match("training_queue%s*=%s*worker_training_queue%.create%s*%(%s*{%s*capacity%s*=%s*(%d+)%s*,")), "production_training_capacity_missing")
local research_capacity = assert(tonumber(raw[source_paths[4]]:match("local RESEARCH_QUEUE_CAPACITY%s*=%s*(%d+)")), "production_research_capacity_missing")
assert(training_capacity == research_capacity, "production_queue_capacity_mismatch")
local queue = queue_service.create({capacity=training_capacity}):snapshot(0,0)
local research, status_labels, status_seen = {}, {}, {}
local function status(mapping, levels, transaction, rebirth)
    local value = assert(research_upgrade(mapping.ability_name, {
        building_id=mapping.building_id, research_levels=levels,
        research_transaction=transaction, reincarnation_level=rebirth,
    }, {}), "production_status_projection_missing")
    if value.research_status_code then
        local code=value.research_status_code
        assert(not status_labels[code] or status_labels[code]==value.status_text,"production_status_label_ambiguous")
        status_seen[code],status_labels[code]=true,value.status_text
    end
end
for _, definition in ipairs(config.technologies) do
    local mapping
    for _, candidate in ipairs(mappings.rows) do
        if candidate.enabled ~= false and candidate.technology_group==definition.legacy_group then
            assert(not mapping,"duplicate_production_research_mapping"); mapping=candidate
        end
    end
    assert(mapping,"production_research_mapping_missing")
    local row={group=definition.legacy_group,ability_name=mapping.ability_name,mapping=mapping,definition=definition,
        condition_text=description.condition_text(definition),levels={}}
    for level=0,definition.max_level do
        local target=math.min(definition.max_level,level+1)
        local sections=description.sections(definition,level,target)
        row.levels[#row.levels+1]={level=level,effect_summary=description.effect_summary(definition,level),
            fields=description.fields(definition,level),sections=sections,
            current_effect_text=sections.current_effect_text,next_effect_text=sections.next_effect_text,
            upgrade_effect_text=description.sections(definition,0,level).next_effect_text,
            upgrade_description=description.build(definition,level,target),
            research_effect_value=config.effect_value((definition.effects or {})[1],level,true),
            base_cost=level>0 and config.cost_for_level(definition,level) or {gold=0,wood=0}}
    end
    research[#research+1]=row
    local satisfied={}
    for _, other in ipairs(config.technologies) do satisfied[other.legacy_group]=other.max_level end
    satisfied[definition.legacy_group]=0
    status(mapping,satisfied,{queue_count=0,capacity=research_capacity},100)
    status(mapping,satisfied,{queue_count=1,capacity=research_capacity},100)
    status(mapping,satisfied,{queue_count=research_capacity,capacity=research_capacity},100)
    status(mapping,satisfied,{reserved_levels={[definition.legacy_group]=definition.max_level}},100)
    satisfied[definition.legacy_group]=definition.max_level
    status(mapping,satisfied,{},100)
    status(mapping,{}, {},0)
end
table.sort(research,function(a,b)return a.group<b.group end)
local status_codes={""}
local sorted_status={};for code in pairs(status_seen)do sorted_status[#sorted_status+1]=code end;table.sort(sorted_status)
for _, code in ipairs(sorted_status)do status_codes[#status_codes+1]=code end
local error_table=assert(raw[source_paths[2]]:match("local operation_error_messages%s*=%s*(%b{})"),"production_error_dictionary_missing")
local error_fn=assert(loadstring("return "..error_table,"@immutable/production_errors"));setfenv(error_fn,{})
local error_messages,error_seen=error_fn(),{[""]=true,production_failed=true}
for code,text in pairs(error_messages)do error_seen[code],error_seen[text]=true,true end
-- Error identifiers originate from the real public business/queue code.
for _, text in pairs(raw) do
    for code in text:gmatch('"([a-z][a-z0-9_]+)"') do
        if code:find("_",1,true) and (code:find("failed",1,true) or code:find("missing",1,true)
            or code:find("invalid",1,true) or code:find("not_",1,true)
            or code:find("queue_",1,true) or code:find("owner_",1,true)
            or code:find("limit",1,true) or code:find("cancel",1,true)
            or code:find("insufficient",1,true)) then error_seen[code]=true end
    end
end
local errors={"","production_failed"};local sorted_errors={}
for code in pairs(error_seen)do if code~="" and code~="production_failed"then sorted_errors[#sorted_errors+1]=code end end
table.sort(sorted_errors);for _,code in ipairs(sorted_errors)do errors[#errors+1]=code end
local fallback=assert(raw[source_paths[8]]:match('"(暂时无法执行，请稍后重试)"'),"production_generic_label_missing")
error_messages.production_failed=fallback
local result={format=1,training=training,research=research,errors=errors,error_messages=error_messages,
    status_codes=status_codes,status_labels=status_labels,queue_capacity=training_capacity,
    cost_timing_text=queue.cost_timing_text,sources=source_paths}
-- Lua 5.1 tostring rounds doubles to ~14 digits. Static research effects must
-- retain the exact binary64 value calculated by the immutable configuration.
local function encode(value)
    local kind=type(value)
    if kind=="number"then
        assert(value==value and value~=math.huge and value~=-math.huge,"finite_production_number_required")
        local number=string.format("%.17g",value)
        return number=="-0" and "-0.0" or number
    end
    if kind~="table"then return json.encode(value)end
    local keys,n={},0
    for key in pairs(value)do keys[#keys+1]=key;if type(key)=="number"then n=n+1 end end
    local output={}
    if #keys>0 and n==#keys and n==#value then
        for index=1,n do output[index]=encode(value[index])end
        return "["..table.concat(output,",").."]"
    end
    table.sort(keys)
    for _,key in ipairs(keys)do assert(type(key)=="string");output[#output+1]=json.encode(key)..":"..encode(value[key])end
    return "{"..table.concat(output,",").."}"
end
print(encode(result))
