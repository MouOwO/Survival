local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/recipe_definitions")
local content = require("config/generated/content_catalog")
local M = {}
local recipes, ordered_recipes, locks, done, auto_serial = {}, {}, {}, {}, {}
local pending_check, check_dirty, pending_reason = {}, {}, {}
local INFERNAL_RECIPE_ID = "recipe_equipment_set_to_infernal_01"
local function index()
  recipes, ordered_recipes = {}, {}
  local recipe_ids = {}
  for _, recipe in ipairs(config.rows or {}) do
    if recipe.enabled ~= false then
      recipes[recipe.recipe_id] = recipe
      ordered_recipes[#ordered_recipes + 1] = recipe
      recipe_ids[#recipe_ids + 1] = tostring(recipe.recipe_id)
    end
  end
  print(string.format("[WEAPON_SYNTH_RECIPE_INDEX] count=%s ids=%s",
    tostring(#ordered_recipes), table.concat(recipe_ids, ",")))
end
local function maps(r)
 local c={}; for _,x in ipairs(r.ingredients or {}) do local id=tostring(x.content_id or ""); local n=math.floor(tonumber(x.quantity) or 0); if id=="" or n<1 then return nil end; if x.consume~=false then c[id]=(c[id] or 0)+n end end
 return c,{[r.result_content_id]=math.max(1,math.floor(tonumber(r.result_count) or 1))}
end
local function infernal_inventory_state(counts)
  local recipe = recipes[INFERNAL_RECIPE_ID]
  local required = recipe and maps(recipe) or {}
  local values, missing = {}, {}
  for content_id, quantity in pairs(required or {}) do
    local owned = tonumber(counts and counts[content_id]) or 0
    values[#values + 1] = string.format("%s=%s/%s", content_id,
      tostring(owned), tostring(quantity))
    if owned < quantity then
      missing[#missing + 1] = content_id .. ":" .. tostring(quantity - owned)
    end
  end
  table.sort(values)
  table.sort(missing)
  return table.concat(values, ","),
    #missing > 0 and table.concat(missing, ",") or "none"
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
  -- 事件里的 player_id 可能是字符串，这里统一转换为数字。
  -- tonumber 转换失败会返回 nil；没有有效玩家就不能读取其逻辑背包。
  player_id = tonumber(player_id)
  if player_id == nil then
    print("[WEAPON_SYNTH_SCHEDULE_REJECTED] player=nil reason="
      .. tostring(reason or "unknown"))
    return
  end

  -- 保存本轮检查原因，方便最终日志判断检查是由拾取、升级还是显式请求触发。
  -- reason 有值时优先使用新原因；没有则保留之前排队的原因；两者都没有时记 unknown。
  pending_reason[player_id] = reason or pending_reason[player_id] or "unknown"

  -- pending_check=true 表示该玩家已经有一个检查任务正在等待或执行。
  -- 此时不能再创建同名 SetContextThink，否则可能覆盖前一个任务。
  if pending_check[player_id] then
    -- 但也不能直接丢掉新事件：正在执行的任务可能已经读取过旧库存。
    -- 将 check_dirty 标记为 true，当前任务结束后会再安排一次检查。
    check_dirty[player_id] = true
    print(string.format(
      "[WEAPON_SYNTH_SCHEDULE] player=%s reason=%s action=merged pending=true dirty=true",
      tostring(player_id), tostring(reason or "unknown")))
    return
  end

  -- 占用该玩家的自动检查槽，直到 run() 完成后才清除。
  pending_check[player_id] = true
  print(string.format(
    "[WEAPON_SYNTH_SCHEDULE] player=%s reason=%s action=created pending=true dirty=%s",
    tostring(player_id), tostring(reason or "unknown"),
    tostring(check_dirty[player_id] == true)))

  -- 真正执行配方扫描的闭包。它会延迟 0.10 秒执行，让拾取入库、
  -- 装备壳同步等同一帧操作先完成，再读取最终的权威逻辑库存。
  local function perform_check()
    -- 清除上一轮遗留的脏标记。run() 执行期间若又收到事件，
    -- schedule_auto_check() 会重新把它设为 true。
    check_dirty[player_id] = false

    -- 固化本次运行使用的触发原因，随后清空排队原因。
    -- 新事件若在运行期间到达，可以重新写入 pending_reason。
    local run_reason = pending_reason[player_id] or reason or "unknown"
    pending_reason[player_id] = nil

    -- 统计本轮成功合成次数，用于通知、诊断和判断是否输出缺料日志。
    local completed_count = 0

    -- 最多连续合成 100 次。一次合成的产物可能又满足下一张配方，
    -- 因此成功后会重新读取库存继续扫描；100 是防止错误配方形成死循环的保险上限。
    for scan_round = 1, 100 do
      print(string.format(
        "[WEAPON_SYNTH_SCAN_BEGIN] player=%s round=%s recipe_count=%s",
        tostring(player_id), tostring(scan_round),
        tostring(#ordered_recipes)))
      -- 从 content_inventory_service 获取该玩家当前的“权威逻辑背包”。
      -- 注意：英雄界面里看到的是物品壳，合成判断只认 snapshot.counts。
      local inv, inventory_error = event_bus.request(events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id })

      -- 请求处理器缺失、处理器报错或返回非法快照时，不应伪装成“空库存”。
      -- 单独记录错误后停止本轮检查，便于区分服务故障和玩家确实缺少材料。
      if not inv or not inv.ok or not inv.snapshot then
        print(string.format(
          "[WEAPON_SYNTH_INVENTORY_UNAVAILABLE] player=%s error=%s",
          tostring(player_id),
          tostring(inventory_error or (inv and inv.error) or "unknown")))
        break
      end

      -- 请求成功时 counts 结构类似：
      -- { equipment_attack_gloves_max = 1, material_synthesis_gem = 1 }
      -- 请求失败或结构缺失时退化为空表，避免后续 pairs(nil) 报错。
      local counts = inv and inv.snapshot and inv.snapshot.counts or {}

      -- matched 保存第一张材料齐全的配方；nil 表示当前没有可合成内容。
      local matched = nil

      -- ordered_recipes 是初始化时按照配置顺序建立的所有启用配方。
      -- 使用 ipairs 可以保证严格按照配置数组顺序进行优先匹配。
      for _, recipe in ipairs(ordered_recipes) do
        -- maps(recipe) 返回两个值：consume（扣除表）和 grant（产物表）。
        -- 这里只接第一个返回值，因为扫描阶段只需要检查消耗材料。
        -- 配方字段非法时 maps 会返回 nil。
        local consume = maps(recipe)

        -- 只有配方能正确生成 consume 表时，才有资格继续检查库存。
        local eligible = consume ~= nil

        -- 遍历该配方要求扣除的每一种 content_id 及数量。
        for content_id, quantity in pairs(consume or {}) do
          -- counts[content_id] 是实际持有量；缺失字段按 0 处理。
          -- 任意一种材料不足，整张配方都不可合成，并立刻停止检查此配方。
          local owned = tonumber(counts[content_id]) or 0
          print(string.format(
            "[WEAPON_SYNTH_MATERIAL_CHECK] player=%s recipe=%s content_id=%s owned=%s required=%s",
            tostring(player_id), tostring(recipe.recipe_id),
            tostring(content_id), tostring(owned), tostring(quantity)))
          if owned < quantity then
            print(string.format(
              "[WEAPON_SYNTH_MATERIAL_MISSING] player=%s recipe=%s content_id=%s missing=%s",
              tostring(player_id), tostring(recipe.recipe_id),
              tostring(content_id), tostring(quantity - owned)))
            eligible = false
            break
          end
        end

        -- 找到第一张完全满足的配方后记录并停止遍历，避免一次循环提交多张配方。
        if eligible then matched = recipe; break end
      end

      -- 所有启用配方都不满足时结束连续扫描，本轮不会调用 synth()。
      if not matched then break end

      -- 为每个玩家生成单调递增的自动请求序号。
      -- synth() 和库存事务会用 request_id 做幂等保护，避免同一请求重复扣材料。
      auto_serial[player_id] = (auto_serial[player_id] or 0) + 1

      -- 调用正式合成函数：它会重新解析配方，并通过原子库存事务同时扣材料、发产物。
      local result = synth({
        player_id = player_id,
        request_id = "auto:" .. tostring(auto_serial[player_id]),
        recipe_id = matched.recipe_id,
      })

      -- 匹配成功并不代表事务一定成功；运行期间库存可能被其他逻辑修改或被锁定。
      -- 一旦事务失败就停止本轮连续合成，防止反复提交同一个失败配方。
      if not result or not result.ok then
        print("[WEAPON_SYNTH_AUTO_STOP] player=" .. tostring(player_id)
          .. " recipe=" .. tostring(matched.recipe_id)
          .. " error=" .. tostring(result and result.error or "unknown"))
        break
      end

      -- 到这里说明材料已被原子扣除，结果物品也已写入逻辑背包。
      completed_count = completed_count + 1

      -- 根据产物 content_id 查询显示名称；配置缺失时直接显示 content_id。
      local catalog = (content.by_id or {})[matched.result_content_id] or {}

      -- 发送 UI 通知事件，让当前玩家看到“合成完成”。
      event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = "合成完成：" .. tostring(catalog.name or matched.result_content_id),
        level = "info",
      })

      -- 服务端成功日志。循环随后回到顶部，重新读取合成后的最新库存。
      print("[WEAPON_SYNTH_AUTO_COMMIT] player=" .. tostring(player_id)
        .. " recipe=" .. tostring(matched.recipe_id))
    end

    -- 一次也没合成时，额外诊断“狱火熔铠”这张核心配方的材料状态。
    if completed_count == 0 then
      -- 再读一次最新库存，避免诊断信息引用扫描开始时的旧快照。
      local inv = event_bus.request(events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id })
      local counts = inv and inv.snapshot and inv.snapshot.counts or {}

      -- infernal_inventory_state 返回：
      -- values：每种材料的“持有量/需求量”；missing：缺少的 content_id 和数量。
      local values, missing = infernal_inventory_state(counts)
      print("[WEAPON_SYNTH_INFERNAL_PENDING] player=" .. tostring(player_id)
        .. " reason=" .. tostring(run_reason)
        .. " inventory=" .. values
        .. " missing=" .. missing)
    end

    -- 输出本轮汇总：玩家、触发原因以及成功合成次数。
    print(string.format("[WEAPON_SYNTH_CHECK] player=%s reason=%s completed=%s",
      tostring(player_id), tostring(run_reason), tostring(completed_count)))
  end

  local function run()
    -- perform_check 内任何异常都必须经过这里释放 pending_check。
    -- 否则一次调试 print 或运行期 API 错误就会令该玩家永久停留在
    -- pending_check=true，后续所有合成事件只会提前 return。
    local ok, error_message = xpcall(perform_check, function(error_value)
      if debug and debug.traceback then
        return debug.traceback(tostring(error_value), 2)
      end
      return tostring(error_value)
    end)

    if not ok then
      print(string.format(
        "[WEAPON_SYNTH_CHECK_ERROR] player=%s error=%s",
        tostring(player_id), tostring(error_message)))
    end

    -- 如果检查执行期间又发生库存/装备事件，释放锁后再排一次检查。
    -- 即使本轮因异常中断，也不会丢掉已经标记为 dirty 的库存变化。
    local needs_follow_up = check_dirty[player_id] == true
    print(string.format(
      "[WEAPON_SYNTH_RUN_RELEASE] player=%s ok=%s pending=%s dirty=%s follow_up=%s next_reason=%s",
      tostring(player_id), tostring(ok), tostring(needs_follow_up),
      tostring(check_dirty[player_id] == true),
      tostring(needs_follow_up),
      tostring(pending_reason[player_id] or "none")))
    if needs_follow_up then
      check_dirty[player_id] = nil
      -- Do not register another ContextThink with the same name from inside
      -- the active callback. When this callback returns nil, Dota removes that
      -- name and also cancels the newly registered callback, leaving
      -- pending_check stuck forever. Returning a delay is the engine-supported
      -- way to run this same callback again.
      return 0.10
    end
    pending_check[player_id] = nil
    return nil
  end

  -- 正常游戏环境使用 Dota 的 ContextThink 延迟 0.10 秒执行 run()。
  if GameRules and GameRules.GetGameModeEntity then
    -- GetGameModeEntity() 返回可注册服务端定时回调的游戏模式实体。
    local entity = GameRules:GetGameModeEntity()
    if entity and entity.SetContextThink then
      -- 回调名称按玩家隔离；run 没有返回下一次间隔，所以只执行一次。
      entity:SetContextThink("survival_auto_synth_" .. tostring(player_id), run, 0.10)
      return
    end
  end

  -- 单元测试或 GameRules 尚不可用时没有 ContextThink，直接同步执行检查。
  -- Tests and early bootstrap may not have ContextThink. Execute all dirty
  -- follow-ups synchronously so fallback behavior matches the engine callback.
  local next_delay = run()
  local fallback_guard = 0
  while next_delay ~= nil and fallback_guard < 100 do
    fallback_guard = fallback_guard + 1
    next_delay = run()
  end
end

-- 权威逻辑库存发生变化时的事件入口，例如拾取材料、商店升级或合成事务。
local function try_auto_growth_mask(payload)
  -- 已提交的逻辑库存快照是合成唯一依据。即使挑战物品脚本没有触发后续显式事件，
  -- CONTENT_INVENTORY_CHANGED 也必须触发一次自动检查。
  schedule_auto_check(payload and payload.player_id, payload and payload.reason)
end

-- 英雄装备身份发生变化时重新检查，防止装备升级链完成后漏掉合成。
local function on_equipped_changed(payload)
  schedule_auto_check(payload and payload.player_id, "weapon_equipped_changed")
end

-- 武器成长阶段发生变化时重新检查，处理由成长系统产生的新合成材料/装备。
local function on_growth_changed(payload)
  schedule_auto_check(payload and payload.player_id, "weapon_growth_changed")
end

-- 其他服务显式要求检查合成时的统一入口，并保留调用方提供的 reason。
local function on_check_requested(payload)
  schedule_auto_check(payload and payload.player_id,
    payload and payload.reason or "explicit_check_requested")
end
function M.init() locks,done,auto_serial,pending_check,check_dirty,pending_reason={}, {}, {}, {}, {}, {}; index(); event_bus.handle_request(events.WEAPON_SYNTHESIS_REQUEST,synth); event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED,try_auto_growth_mask); event_bus.subscribe(events.WEAPON_SYNTHESIS_CHECK_REQUESTED,on_check_requested); event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED,on_equipped_changed); event_bus.subscribe(events.WEAPON_GROWTH_CHANGED,on_growth_changed); print("[WEAPON_SYNTH_INIT] config=generated_csv atomic=true auto_all_recipes=true") end
return M
