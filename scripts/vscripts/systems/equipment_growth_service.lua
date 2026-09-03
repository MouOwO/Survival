local event_bus = require("core/event_bus")
local events = require("core/events")
local levels = require("config/equipment_level_definitions")
local weapons = require("config/generated/weapon_definitions")
local player_profile_service = require("systems/player_profile_service")

local M = {}
local progress, attack_seen = {}, {}
local MAX_RECORDS = 256
local function trim(t, n) local c=0; for k in pairs(t) do c=c+1; if c>n then t[k]=nil end end end
local function bucket(p) progress[p]=progress[p] or {}; return progress[p] end
local function equipped(p)
 local r=event_bus.request(events.WEAPON_EQUIPMENT_GET_REQUEST,{player_id=p})
 return r and r.snapshot and r.snapshot.main_hand_content_id or ""
end
local function instance_count(p,id)
 local r=event_bus.request(events.EQUIPMENT_INSTANCE_GET_REQUEST,{player_id=p})
 local x=r and r.instances and r.instances[id]; return x and tonumber(x.quantity) or 0
end
local function next_id(id)
 local d=levels.by_id[id]; if not d then return nil end
 local n=(tonumber(d.level) or 0)+1
 local prefix=tostring(id):match("^(.*)_%d%d$")
 if not prefix then prefix=tostring(id):gsub("_max$", "") end
 if prefix==tostring(id) then return nil end
 for _,x in ipairs(levels.rows) do
  local candidate=tostring(x.content_id or "")
  if x.level==n and candidate:sub(1,#prefix)==prefix then return candidate end
 end
end
local function required_for(player_id,id,d)
 local configured=tonumber(weapons.by_id[id] and weapons.by_id[id].progression_value)
 local base=configured and configured>0 and configured or 200
 local projected=event_bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=player_id})
 local totals=projected and projected.totals or {}
 local reduction=tonumber(totals.weapon_upgrade_requirement_reduction)
 if reduction==nil then
  local profile=player_profile_service.get_profile(player_id); local stats=profile and profile.save and profile.save.gameplay_stats or {}
  reduction=tonumber(stats.weapon_upgrade_requirement_reduction)
 end
 return math.max(1,base-math.max(0,math.floor(reduction or 0)))
end
local function advance(p, kind, amount, why)
 local id=equipped(p); local d=levels.by_id[id]; if not d or not d.progression or d.progression.type~=kind then return end
 local b=bucket(p); b[id]=(b[id] or 0)+amount
 local required=required_for(p,id,d)
 while required and b[id]>=required do
  local to=next_id(id); if not to then break end
  local tx=event_bus.request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,{player_id=p,request_id="growth:"..id..":"..tostring(b[id]),consume={[id]=1},grant={[to]=1},reason="equipment_growth:"..why})
  if not tx or not tx.ok then break end
  b[to]=(b[to] or 0)+b[id]-required; b[id]=nil; id=to; d=levels.by_id[id]; required=d and d.progression and required_for(p,id,d)
 end
 local value=b[id] or 0
 event_bus.emit(events.EQUIPMENT_GROWTH_CHANGED,{player_id=p,content_id=id,value=value,reason=why,snapshot={stage_attack_target=required or 0,stage_attack_remaining=required and math.max(0,required-value) or 0}})
end
local function on_attack(x)
 local p,r=tonumber(x.player_id),tonumber(x.record); if not p or not r then return end
 attack_seen[p]=attack_seen[p] or {}; if attack_seen[p][r] then print("[WEAPON_ATTACK_DEDUP] record="..r); return end
 attack_seen[p][r]=true; trim(attack_seen[p],MAX_RECORDS)
 local id=equipped(p); local d=levels.by_id[id]
 if d and d.progression and d.progression.type=="normal_attack_count" then advance(p,"normal_attack_count",1+instance_count(p,"item_forging_hammer"),"normal_attack") end
end
local function valid_entity(entity)
 return entity and (not entity.IsNull or not entity:IsNull())
end
local function entity_player_id(entity)
 if not valid_entity(entity) then return nil end
 local explicit=tonumber(entity.survival_player_id)
 if explicit and explicit>=0 then return explicit end
 if entity.GetPlayerOwnerID then
  local player_id=tonumber(entity:GetPlayerOwnerID())
  if player_id and player_id>=0 then return player_id end
 end
 return nil
end
local function owner_player_id(attacker)
 local current=attacker; local seen={}
 for _=1,8 do
  if not valid_entity(current) or seen[current] then return nil end
  seen[current]=true
  local player_id=entity_player_id(current)
  if player_id then return player_id,current end
  if not current.GetOwnerEntity then return nil end
  current=current:GetOwnerEntity()
 end
 return nil
end
local function attributed_team(player_id, owner, attacker)
 if PlayerResource and PlayerResource.GetTeam then
  local team=tonumber(PlayerResource:GetTeam(player_id))
  if team then return team end
 end
 if valid_entity(owner) and owner.GetTeamNumber then
  return tonumber(owner:GetTeamNumber())
 end
 return attacker.GetTeamNumber and tonumber(attacker:GetTeamNumber()) or nil
end
local function on_equipped(x)
 if x.slot~="main_hand" then return end
 local p,id=tonumber(x.player_id),tostring(x.content_id or "")
 local d=levels.by_id[id]
 if not p or not d or not d.progression
  or d.progression.type~="valid_enemy_kill_count" then return end
 local required,value=required_for(p,id,d),bucket(p)[id] or 0
 event_bus.emit(events.EQUIPMENT_GROWTH_CHANGED,{player_id=p,content_id=id,value=value,reason="weapon_equipped",snapshot={stage_attack_target=required,stage_attack_remaining=math.max(0,required-value)}})
end
local function on_entity_killed(x)
 local victim,attacker=x.victim,x.attacker
 if not valid_entity(victim) or not valid_entity(attacker) then return end
 if victim.IsRealHero and victim:IsRealHero() then return end
 if victim.IsBuilding and victim:IsBuilding() then return end
 local player_id,owner=owner_player_id(attacker)
 if not player_id then return end
 if victim.GetTeamNumber
   and tonumber(victim:GetTeamNumber())==attributed_team(player_id,owner,attacker) then return end
 advance(player_id,"valid_enemy_kill_count",1,"legal_enemy_kill")
end
function M.init()
 progress,attack_seen={},{}; event_bus.handle_request(events.EQUIPMENT_GROWTH_GET_REQUEST,function(x) return {ok=true,progress=bucket(tonumber(x.player_id))} end)
 event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED,on_equipped); event_bus.subscribe(events.ENGINE_ENTITY_KILLED,on_entity_killed); print("[EQUIPMENT_GROWTH_INIT] config=equipment_level_definitions kill_source=ENGINE_ENTITY_KILLED csv_progress=true")
end
return M
