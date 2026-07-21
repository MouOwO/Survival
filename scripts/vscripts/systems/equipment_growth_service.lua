local event_bus = require("core/event_bus")
local events = require("core/events")
local levels = require("config/equipment_level_definitions")

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
local function advance(p, kind, amount, why)
 local id=equipped(p); local d=levels.by_id[id]; if not d or not d.progression or d.progression.type~=kind then return end
 local b=bucket(p); b[id]=(b[id] or 0)+amount
 local required=d.progression.required
 while required and b[id]>=required do
  local to=next_id(id); if not to then break end
  local tx=event_bus.request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,{player_id=p,request_id="growth:"..id..":"..tostring(b[id]),consume={[id]=1},grant={[to]=1},reason="equipment_growth:"..why})
  if not tx or not tx.ok then break end
  b[to]=(b[to] or 0)+b[id]; b[id]=nil; id=to; d=levels.by_id[id]; required=d and d.progression and d.progression.required
 end
 event_bus.emit(events.EQUIPMENT_GROWTH_CHANGED,{player_id=p,content_id=id,value=b[id] or 0,reason=why})
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
function M.init()
 progress,attack_seen,kill_seen={},{},{}; event_bus.handle_request(events.EQUIPMENT_GROWTH_GET_REQUEST,function(x) return {ok=true,progress=bucket(tonumber(x.player_id))} end)
 event_bus.subscribe(events.MONSTER_KILLED,on_kill); print("[EQUIPMENT_GROWTH_INIT] config=equipment_level_definitions kill_source=MONSTER_KILLED attack_owner=legacy_weapon_growth")
end
return M
