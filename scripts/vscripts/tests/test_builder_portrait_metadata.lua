package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local definitions = require("config/generated/builder_definitions")
local metadata = require("ui/portrait_metadata")
local callbacks, sent, published = {}, {}, {}
local unit = {survival_builder_id="default_builder",survival_player_id=0,health=1000}
function unit:IsNull() return false end
function unit:entindex() return 156 end
function unit:GetUnitName() return "npc_survival_builder_proxy" end
function unit:GetModelName() return "models/heroes/wisp/wisp.vmdl" end
function unit:GetHealth() return self.health end
function unit:GetMaxHealth() return 1000 end
function unit:GetPlayerOwnerID() return 0 end
function unit:GetTeamNumber() return 2 end
local player = {}
EntIndexToHScript = function(index) if index==156 then return unit end end
PlayerResource = {IsValidPlayerID=function(_,id) return id==0 end,
 GetPlayer=function() return player end,GetTeam=function() return 2 end}
CustomGameEventManager = {
 RegisterListener=function(_,name,callback) callbacks[name]=callback end,
 Send_ServerToPlayer=function(_,owner,name,payload)
  assert(owner==player and name=="ui_selected_unit_stats_snapshot");sent[#sent+1]=payload
 end}
CustomNetTables = {SetTableValue=function(_,name,key,payload)
 if name=="survival_combat_stats" then assert(key=="player_0");published[#published+1]=payload end
end}
local clock, clock_reads = 0, 0
GameRules = {GetGameTime=function() clock_reads=clock_reads+1;return clock end}
for _,name in ipairs({"systems/building_system","ui/weapon_synthesis_snapshot_service",
 "systems/hero_summon_projection","systems/building_batch_upgrade_service",
 "systems/gold_mine_batch_upgrade_service"}) do package.loaded[name]={} end
package.loaded["systems/startup_loading_service"]={is_player_ready=function() return true end}
bus.reset()
require("ui/ui_request_router").init()
require("ui/combat_stats_ui_service").init()
local function check(snapshot)
 assert(snapshot.entindex==156 and snapshot.model_asset_id=="builder_io_benevolent_companion")
 assert(snapshot.portrait_unit_name=="npc_dota_hero_wisp" and snapshot.portrait_item_def=="9235")
 assert(snapshot.portrait_model_name=="models/heroes/wisp/wisp.vmdl")
end
callbacks.ui_selected_unit_stats_request(nil,{PlayerID=0,entindex=156})
check(sent[#sent]);assert(sent[#sent].success==1 and sent[#sent].health==1000)
for version=1,30 do
 local raw={entindex=156,health=1000-version,max_health=1000,refresh_version=version,damage_total=4321}
 unit.health=raw.health
 local send_count=#sent
 bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=raw})
 clock=clock+0.11;require("core/scheduler").think()
 assert(#sent==send_count+1,"the existing coalesced selected channel must deliver its snapshot")
 check(published[#published]);check(sent[#sent])
 assert(published[#published].health==raw.health and published[#published].damage_total==4321)
 assert(raw.model_asset_id==nil and raw.portrait_unit_name==nil,"portrait must not mutate combat authority")
end
assert(#published==30)
assert(unit.survival_model_asset_id==nil,"portrait mapping must not take world model ownership")
local unsupported=metadata.apply({survival_model_asset_id="builder_io_benevolent_companion"},{})
assert(unsupported.portrait_unit_name=="","only the real configured builder opts in")
assert(metadata.apply({survival_builder_id="unknown"},{}).portrait_unit_name=="")
local def=definitions.by_id.default_builder
local enabled=def.enabled;def.enabled=false
assert(metadata.apply(unit,{}).portrait_unit_name=="")
def.enabled=enabled
local reads=clock_reads
check(metadata.apply(unit,{entindex=156}))
assert(clock_reads==reads,"portrait metadata must not introduce clock reads")
assert(require("core/scheduler").task_count()==0)
print("BUILDER_PORTRAIT_METADATA_PASS: real selected request and 30 regular publications, native proxy/Io identity, immutable damage and builder role, zero polling")
