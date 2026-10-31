package.path = "scripts/vscripts/?.lua;" .. package.path
-- Actual request router and metadata. Native entities, admission and unrelated
-- systems are isolated; every requester inspects another player's builder.
package.loaded["core/test_access_policy"] = {enforce=function() return true end,
    enabled=function() return false end,allowed=function() return true end}
local bus = require("core/event_bus")
local callbacks, players, builders, replies = {}, {}, {}, {}
for id=0,3 do
    players[id]={id=id}
    local unit={survival_builder_id="default_builder",survival_player_id=id,index=100+id}
    function unit:IsNull() return false end
    function unit:entindex() return self.index end
    function unit:GetUnitName() return "npc_survival_builder_proxy" end
    function unit:GetModelName() return "models/heroes/wisp/wisp.vmdl" end
    function unit:GetPlayerOwnerID() return -1 end -- registry owns proxy identity
    function unit:GetHealth() return 1000 end
    function unit:GetMaxHealth() return 1000 end
    function unit:GetTeamNumber() return 2 end
    builders[100+id]=unit
end
EntIndexToHScript=function(id) return builders[id] end
GameRules={GetGameTime=function() return 0 end}
PlayerResource={IsValidPlayerID=function(_,id) return players[id]~=nil end,
    GetPlayer=function(_,id) return players[id] end,GetTeam=function() return 2 end}
CustomGameEventManager={RegisterListener=function(_,name,fn) callbacks[name]=fn end,
    Send_ServerToPlayer=function(_,player,name,payload)
        assert(name=="ui_selected_unit_stats_snapshot")
        replies[#replies+1]={player=player.id,snapshot=payload}
    end}
for _,name in ipairs({"systems/building_system","ui/weapon_synthesis_snapshot_service",
    "systems/hero_summon_projection","systems/building_batch_upgrade_service",
    "systems/gold_mine_batch_upgrade_service"}) do package.loaded[name]={} end
package.loaded["systems/startup_loading_service"]={is_player_ready=function() return true end}
bus.reset();require("ui/ui_request_router").init()
for viewer=0,3 do
    for owner=0,3 do
        callbacks.ui_selected_unit_stats_request(nil,{PlayerID=viewer,player_id=owner,entindex=100+owner})
        local reply=replies[#replies];local snapshot=reply.snapshot
        assert(reply.player==viewer and snapshot.entindex==100+owner and snapshot.success==1)
        assert(snapshot.model_asset_id=="builder_io_benevolent_companion")
        assert(snapshot.portrait_unit_name=="npc_dota_hero_wisp" and snapshot.portrait_item_def=="9235")
    end
end
assert(#replies==16 and require("core/scheduler").task_count()==0)
print("TEAMMATE_BUILDER_METADATA_PASS: four viewers x four builders, correct entity/appearance/private recipient, zero polling")
