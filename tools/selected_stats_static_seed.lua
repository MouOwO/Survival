-- Read-only public catalogue seed. No player, process, network or ID allocation.
package.path="scripts/vscripts/?.lua;"..package.path
local schema=require("ui/selected_stats_schema")
local texts,seen={},{}
local function add(value)if type(value)=="string"and value~=""and not seen[value]then seen[value]=true;texts[#texts+1]=value end end
for _,text in ipairs({"七宗罪","科技与存档","英雄技能","装备","欢呼光环","未装备武器","终极之塔","main_city","wall","arrow_tower","gold_mine","hero_altar","building_research_lab","building_advanced_research_lab"})do add(text)end
for index=1,7 do add("class_"..index)end
local modules={"asset_catalog","asset_components","asset_native_wearables","unit_display_names","hero_definitions","weapon_definitions","building_definitions","builder_definitions","arrow_tower_base",
 "tower_class_death","tower_class_mystery","tower_class_lightning","tower_class_machine_gun","tower_class_multi","tower_class_frost","tower_class_anti_air"}
local allowed={id=true,unit_name=true,name=true,display_name=true,hero_id=true,content_id=true,item_id=true,weapon_id=true,
 asset_id=true,primary_model=true,portrait_unit_name=true,portrait_item_def=true,model_name=true,model=true,
 building_id=true,class_id=true,tower_class=true,record_id=true}
local function walk(value,visited)
 if type(value)~="table"or visited[value]then return end;visited[value]=true
 for key,child in pairs(value)do if type(child)=="table"then walk(child,visited)elseif allowed[key]then add(child)end end
end
local sources={}
for _,name in ipairs(modules)do local module="config/generated/"..name;walk(require(module),{});sources[#sources+1]="scripts/vscripts/"..module..".lua"end
walk(require("config/asset_catalog"),{})
sources[#sources+1]="scripts/vscripts/config/asset_catalog.lua"
-- Runtime display functions include rank suffixes, so enumerate the exact
-- configured stage calls rather than guessing suffixes from a small fixture.
local routes=require("config/tower_route_config")
local arrow=require("config/generated/arrow_tower_base")
for index=1,#arrow.rows do add(routes.display_name_for_unit({survival_building_id="arrow_tower",survival_level=index}))end
for class=1,7 do local key="class_"..class;local rows=routes.get_route(key)or{}
 for index=1,#rows do add(routes.display_name_for_unit({survival_building_id="arrow_tower",survival_level=index+5,survival_tower_class=key}))end
end
-- Follow the public NPC corpus from its real roots, not a fixture's observed
-- units. The generator supplies immutable, tracked blobs through virtual IO.
-- Normalization is independent of the host filesystem and never escapes NPC.
local visited={}
local function npc_path(parent,reference)
 assert(type(reference)=="string"and not reference:find("%z"),"npc_reference_invalid")
 reference=reference:gsub("\\","/")
 assert(not reference:match("^/")and not reference:match("^[A-Za-z]:"),"npc_absolute_reference_refused")
 local value=parent.."/"..reference;local stack={}
 for part in value:gmatch("[^/]+")do
  if part==".."then assert(#stack>2,"npc_reference_escape_refused");table.remove(stack)
  elseif part~="."then stack[#stack+1]=part end
 end
 local normalized=table.concat(stack,"/")
 assert(normalized:match("^scripts/npc/.*%.txt$")and not normalized:find(":",1,true),"npc_subtree_required")
 return normalized
end
local function read_npc(relative)
 if visited[relative]then return end;visited[relative]=true
 local file=assert(io.open(relative,"rb"),"tracked_npc_source_missing:"..relative);local raw=file:read("*a");file:close()
 for text in raw:gmatch('"([^"\r\n]+)"')do add(text)end;sources[#sources+1]=relative
 local parent=assert(relative:match("^(.*)/[^/]+$"))
 for line in raw:gmatch("[^\r\n]+")do
  local reference=line:match('^%s*#base%s+"([^"]+)"')or line:match("^%s*#base%s+(%S+)")
  if reference then read_npc(npc_path(parent,reference))end
 end
end
read_npc("scripts/npc/npc_units_custom.txt");read_npc("scripts/npc/npc_heroes_custom.txt")
table.sort(texts)
table.sort(sources)
print(require("core/json_encoder").encode({format=1,numeric_paths=schema.numeric_paths,text_paths=schema.text_paths,text_values=texts,units=schema.units,sources=sources}))
