package.path="scripts/vscripts/?.lua;"..package.path
class=function()return {} end
IsServer=function()return true end
local values={}
CustomNetTables={SetTableValue=function(_,_,key,value)values[key]=value end}
package.loaded["combat/endless_stat_projection"]={for_ui=function(_,value)return value end}
local definition=require("modifiers/modifier_single_health_bar")
local invalid=false
local unit={IsNull=function()return invalid end,entindex=function()assert(not invalid);return 42 end,
    GetHealth=function()return 50 end,GetMaxHealth=function()return 100 end,
    IsAlive=function()return true end,GetTeamNumber=function()return 2 end}
local modifier=setmetatable({GetParent=function()return unit end,StartIntervalThink=function()end},{__index=definition})
modifier:OnCreated()
assert(values.unit_42.health==50)
unit.survival_hide_custom_health_bar=true
modifier:OnIntervalThink()
assert(values.unit_42.removed==1)
unit.survival_hide_custom_health_bar=nil
modifier:OnIntervalThink()
assert(values.unit_42.health==50)
invalid=true
modifier:OnDestroy()
assert(values.unit_42.removed==1,"removal must work after parent handle expires")
print("HEALTH_BAR_CLEANUP_PASS")
