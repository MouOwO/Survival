--[[
  Timers Library for Dota 2 Custom Games (Simplified BMD-style)
--]]

if not Timers then
  _G.Timers = class({})
  Timers.__index = Timers
end

Timers.timers = {}
Timers._nextID = 0

function Timers:CreateTimer(name, delay, callback)
  if type(name) == "number" then
    callback = delay
    delay = name
    name = nil
  elseif type(name) == "function" then
    callback = name
    delay = 0
    name = nil
  end

  if type(callback) ~= "function" then
    print("[Timers] ERROR: callback must be a function")
    return
  end

  Timers._nextID = Timers._nextID + 1
  local id = name or ("timer_" .. Timers._nextID)
  local endTime = GameRules:GetGameTime() + (delay or 0)

  Timers.timers[id] = {
    endTime = endTime,
    callback = callback,
  }

  return id
end

function Timers:RemoveTimer(id)
  Timers.timers[id] = nil
end

function Timers:RemoveAllTimers()
  Timers.timers = {}
end

function Timers:Think()
  local now = GameRules:GetGameTime()
  local toRemove = {}

  for id, timer in pairs(Timers.timers) do
    if timer.endTime <= now then
      local ok, result = pcall(timer.callback)
      if not ok then
        print("[Timers] ERROR in timer '" .. tostring(id) .. "': " .. tostring(result))
        table.insert(toRemove, id)
      elseif type(result) == "number" and result > 0 then
        timer.endTime = now + result
      else
        table.insert(toRemove, id)
      end
    end
  end

  for _, id in ipairs(toRemove) do
    Timers.timers[id] = nil
  end
end
