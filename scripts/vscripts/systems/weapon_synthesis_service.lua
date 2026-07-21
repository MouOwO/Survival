local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/recipe_definitions")
local M = {}
local recipes, locks, done, auto_serial = {}, {}, {}, {}
local pending_check, last_fingerprint = {}, {}
local function index()
 recipes={}; for _,r in ipairs(config.rows or {}) do if r.enabled~=false then recipes[r.recipe_id]=r end end
end
local function maps(r)
 local c={}; for _,x in ipairs(r.ingredients or {}) do local id=tostring(x.content_id or ""); local n=math.floor(tonumber(x.quantity) or 0); if id=="" or n<1 then return nil end; c[id]=(c[id] or 0)+n end
 return c,{[r.result_content_id]=1}
end
local function synth(x)
 local p=tonumber(x.player_id); local q=tostring(x.request_id or ""); local id=tostring(x.recipe_id or "")
 if not p or p<0 or q=="" then return {ok=false,error="synthesis_invalid_identity"} end
 done[p]=done[p] or {}; if done[p][q] then print("[WEAPON_SYNTH_IDEMPOTENT] request="..q); return done[p][q] end
 if locks[p] then return {ok=false,error="synthesis_player_locked"} end
 local r=recipes[id]; if not r then return {ok=false,error="synthesis_recipe_closed"} end
 local c,g=maps(r); if not c then return {ok=false,error="synthesis_recipe_invalid"} end
 locks[p]=true
 local tx=event_bus.request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,{player_id=p,request_id="synth-tx:"..q,consume=c,grant=g,reason="weapon_synthesis:"..id}) or {ok=false,error="synthesis_transaction_unavailable"}
 locks[p]=nil; local out=tx.ok and {ok=true,request_id=q,recipe_id=id,result_content_id=r.result_content_id} or tx; done[p][q]=out
 print("[WEAPON_SYNTH_"..(out.ok and "COMMIT" or "ROLLBACK_SAFE").."] recipe="..id); if out.ok then event_bus.emit(events.WEAPON_SYNTHESIZED,out) end; return out
end
local function schedule_auto_check(player_id, reason)
  player_id = tonumber(player_id)
  if player_id == nil or pending_check[player_id] then return end
  pending_check[player_id] = true
  local function run()
    pending_check[player_id] = nil
    local inv = event_bus.request(events.CONTENT_INVENTORY_GET_REQUEST,
      { player_id = player_id })
    local counts = inv and inv.snapshot and inv.snapshot.counts or {}
    local sword = tonumber(counts.weapon_growth_sword_max) or 0
    local mask = tonumber(counts.item_death_mask) or 0
    local fingerprint = tostring(sword) .. ":" .. tostring(mask)
    print(string.format(
      "[WEAPON_SYNTH_CHECK] player=%s reason=%s sword_max=%s death_mask=%s",
      tostring(player_id), tostring(reason or "unknown"), tostring(sword), tostring(mask)
    ))
    if sword < 1 or mask < 1 or last_fingerprint[player_id] == fingerprint then return end
    local recipe = recipes["recipe_growth_max_mask_to_frost_01"]
    if not recipe then return end
    last_fingerprint[player_id] = fingerprint
    auto_serial[player_id] = (auto_serial[player_id] or 0) + 1
    local result = synth({
      player_id = player_id,
      request_id = "auto:growth-mask:" .. tostring(auto_serial[player_id]),
      recipe_id = recipe.recipe_id,
    })
    if result and result.ok then
      event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id, message = "合成完成：霜之剑刃 Lv1", level = "info",
      })
      print("[WEAPON_SYNTH_AUTO_COMMIT] player=" .. tostring(player_id))
    else
      last_fingerprint[player_id] = nil
      print("[WEAPON_SYNTH_AUTO_RETRY] player=" .. tostring(player_id)
        .. " error=" .. tostring(result and result.error or "unknown"))
    end
  end
  if GameRules and GameRules.GetGameModeEntity then
    local entity = GameRules:GetGameModeEntity()
    if entity and entity.SetContextThink then
      entity:SetContextThink("survival_auto_synth_" .. tostring(player_id), run, 0.10)
      return
    end
  end
  run()
end

local function try_auto_growth_mask(payload)
  schedule_auto_check(payload and payload.player_id, payload and payload.reason)
end
local function on_equipped_changed(payload)
  schedule_auto_check(payload and payload.player_id, "weapon_equipped_changed")
end
local function on_growth_changed(payload)
  schedule_auto_check(payload and payload.player_id, "weapon_growth_changed")
end
function M.init() locks,done,auto_serial,pending_check,last_fingerprint={}, {}, {}, {}, {}; index(); event_bus.handle_request(events.WEAPON_SYNTHESIS_REQUEST,synth); event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED,try_auto_growth_mask); event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED,on_equipped_changed); event_bus.subscribe(events.WEAPON_GROWTH_CHANGED,on_growth_changed); print("[WEAPON_SYNTH_INIT] config=recipe_definitions atomic=true auto_growth_mask=multi_entry_delayed") end
return M
