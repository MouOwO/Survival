local event_bus = require("core/event_bus")
local events = require("core/events")
local levels = require("config/equipment_level_definitions")
local weapons = require("config/generated/weapon_definitions")

local M = {}
local progress, attack_seen, kill_seen = {}, {}, {}
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
local function required_for(id,d)
 local configured=tonumber(weapons.by_id[id] and weapons.by_id[id].progression_value)
 return configured and configured>0 and configured or 200
end
local function advance(p, kind, amount, why)
 local id=equipped(p); local d=levels.by_id[id]; if not d or not d.progression or d.progression.type~=kind then return end
 local b=bucket(p); b[id]=(b[id] or 0)+amount
 local required=required_for(id,d)
 while required and b[id]>=required do
  local to=next_id(id); if not to then break end
  local tx=event_bus.request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,{player_id=p,request_id="growth:"..id..":"..tostring(b[id]),consume={[id]=1},grant={[to]=1},reason="equipment_growth:"..why})
  if not tx or not tx.ok then break end
  b[to]=(b[to] or 0)+b[id]-required; b[id]=nil; id=to; d=levels.by_id[id]; required=d and d.progression and required_for(id,d)
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
local function on_kill(x)
 local p=tonumber(x.player_id); local v=x.victim; local k=tonumber(x.victim_entindex) or (v and v.entindex and v:entindex())
 if not p or not k or k<0 then return end
 kill_seen[p]=kill_seen[p] or {}; if kill_seen[p][k] then return end; kill_seen[p][k]=true; trim(kill_seen[p],MAX_RECORDS)
 advance(p,"valid_enemy_kill_count",1,"legal_enemy_kill")
end
local function on_equipped(x)
 if x.slot~="main_hand" then return end
 local p,id=tonumber(x.player_id),tostring(x.content_id or "")
 local d=levels.by_id[id]
 if not p or not d or not d.progression
  or d.progression.type~="valid_enemy_kill_count" then return end
 local required,value=required_for(id,d),bucket(p)[id] or 0
 event_bus.emit(events.EQUIPMENT_GROWTH_CHANGED,{player_id=p,content_id=id,value=value,reason="weapon_equipped",snapshot={stage_attack_target=required,stage_attack_remaining=math.max(0,required-value)}})
end
local function on_entity_killed(x)
 local victim,attacker=x.victim,x.attacker
 if not victim or not attacker then return end
 if victim.IsRealHero and victim:IsRealHero() then return end
 if victim.IsBuilding and victim:IsBuilding() then return end
 if victim.GetTeamNumber and attacker.GetTeamNumber
  and victim:GetTeamNumber()==attacker:GetTeamNumber() then return end
 local owner=attacker
 if attacker.GetOwnerEntity then
  local candidate=attacker:GetOwnerEntity()
  if candidate and (not candidate.IsNull or not candidate:IsNull()) then owner=candidate end
 end
 local p=owner.GetPlayerOwnerID and tonumber(owner:GetPlayerOwnerID()) or -1
 if p<0 and attacker.GetPlayerOwnerID then
  p=tonumber(attacker:GetPlayerOwnerID()) or -1
 end
 on_kill({player_id=p,victim=victim})
end
function M.init()
 progress,attack_seen,kill_seen={},{},{}; event_bus.handle_request(events.EQUIPMENT_GROWTH_GET_REQUEST,function(x) return {ok=true,progress=bucket(tonumber(x.player_id))} end)
 event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED,on_equipped); event_bus.subscribe(events.ENGINE_ENTITY_KILLED,on_entity_killed); event_bus.subscribe(events.MONSTER_KILLED,on_kill); print("[EQUIPMENT_GROWTH_INIT] config=equipment_level_definitions kill_source=ENGINE_ENTITY_KILLED csv_progress=true")
end
return M
