local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/recipe_definitions")
local content = require("config/generated/content_catalog")
local M = {}
local recipes, ordered_recipes, locks, done, auto_serial = {}, {}, {}, {}, {}
local pending_check = {}
local function index()
 recipes,ordered_recipes={},{}; for _,r in ipairs(config.rows or {}) do if r.enabled~=false then recipes[r.recipe_id]=r; ordered_recipes[#ordered_recipes+1]=r end end
end
local function maps(r)
 local c={}; for _,x in ipairs(r.ingredients or {}) do local id=tostring(x.content_id or ""); local n=math.floor(tonumber(x.quantity) or 0); if id=="" or n<1 then return nil end; if x.consume~=false then c[id]=(c[id] or 0)+n end end
 return c,{[r.result_content_id]=math.max(1,math.floor(tonumber(r.result_count) or 1))}
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
    local completed_count = 0
    for _ = 1, 100 do
      local inv = event_bus.request(events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id })
      local counts = inv and inv.snapshot and inv.snapshot.counts or {}
      local matched = nil
      for _, recipe in ipairs(ordered_recipes) do
        local consume = maps(recipe)
        local eligible = consume ~= nil
        for content_id, quantity in pairs(consume or {}) do
          if (tonumber(counts[content_id]) or 0) < quantity then
            eligible = false
            break
          end
        end
        if eligible then matched = recipe; break end
      end
      if not matched then break end
      auto_serial[player_id] = (auto_serial[player_id] or 0) + 1
      local result = synth({
        player_id = player_id,
        request_id = "auto:" .. tostring(auto_serial[player_id]),
        recipe_id = matched.recipe_id,
      })
      if not result or not result.ok then
        print("[WEAPON_SYNTH_AUTO_STOP] player=" .. tostring(player_id)
          .. " recipe=" .. tostring(matched.recipe_id)
          .. " error=" .. tostring(result and result.error or "unknown"))
        break
      end
      completed_count = completed_count + 1
      local catalog = (content.by_id or {})[matched.result_content_id] or {}
      event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = "合成完成：" .. tostring(catalog.name or matched.result_content_id),
        level = "info",
      })
      print("[WEAPON_SYNTH_AUTO_COMMIT] player=" .. tostring(player_id)
        .. " recipe=" .. tostring(matched.recipe_id))
    end
    pending_check[player_id] = nil
    print(string.format("[WEAPON_SYNTH_CHECK] player=%s reason=%s completed=%s",
      tostring(player_id), tostring(reason or "unknown"), tostring(completed_count)))
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
function M.init() locks,done,auto_serial,pending_check={}, {}, {}, {}; index(); event_bus.handle_request(events.WEAPON_SYNTHESIS_REQUEST,synth); event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED,try_auto_growth_mask); event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED,on_equipped_changed); event_bus.subscribe(events.WEAPON_GROWTH_CHANGED,on_growth_changed); print("[WEAPON_SYNTH_INIT] config=generated_csv atomic=true auto_all_recipes=true") end
return M
