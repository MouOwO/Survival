package.path = "scripts/vscripts/?.lua;" .. package.path
local prediction = require("systems/tower_laser_health_prediction")
local clock = 0
GameRules = {GetGameTime=function() return clock end}
local unit = {health=880,alive=true,IsNull=function() return false end,
    GetHealth=function(self) return self.health end,IsAlive=function(self) return self.alive end}
local owner = {laser_target=unit,last_interval_time=0,laser_elapsed=0}
prediction.record(owner,unit,1000,1.2,1.25,1)
local rows = prediction.snapshot(unit,1000,0.1)
assert(#rows == 1 and rows[1].due == 1 and math.abs(rows[1].fraction-0.125) < 0.00001)
assert(unit.health == 880, "forecast must never change real health")
local second = {laser_target=unit,last_interval_time=0.2,laser_elapsed=0}
clock=0.2; unit.health=780
prediction.record(second,unit,880,1,1.05,1)
assert(#prediction.snapshot(unit,1000,clock) == 2, "independent beams must not overwrite each other")
prediction.clear(owner)
assert(#prediction.snapshot(unit,1000,clock) == 1, "stopping one beam preserves the other")
assert(#prediction.snapshot(unit,1000,1.36) == 0, "expired forecasts must stop predicting")
clock=2; unit.health=500
owner.last_interval_time=2; owner.laser_elapsed=0.25
prediction.record(owner,unit,600,1,1.1,1)
rows=prediction.snapshot(unit,1000,2)
assert(rows[1].due == 2.75, "forecast must use the actual remaining damage clock")
prediction.record(owner,unit,500,1,1.1,1)
assert(#prediction.snapshot(unit,1000,2) == 0, "zero/blocked damage clears the old estimate")
unit.alive=false
prediction.record(owner,unit,600,1,1.1,1)
assert(#prediction.snapshot(unit,1000,2) == 0)
print("LASER_HEALTH_PREDICTION_PASS: actual health deltas, ramp, concurrent towers, stop, expiry, zero damage and lethal cleanup")
