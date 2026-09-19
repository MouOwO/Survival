package.path="scripts/vscripts/?.lua;"..package.path
class=function()return {} end
LUA_MODIFIER_MOTION_NONE=0
IsServer=function()return true end
local time, links, adds = 0, 0, 0
GameRules={GetGameTime=function()return time end}
LinkLuaModifier=function(name,path)
    links=links+1
    assert(path=="modifiers/"..name,"must link the actual definition")
    local scope=setmetatable({}, {__index=_G})
    local chunk=assert(loadfile("scripts/vscripts/"..path..".lua"))
    setfenv(chunk,scope); chunk()
    assert(rawget(scope,name)==_G[name],"engine scope requires an explicit class")
end
local service=require("systems/hero_base_health_service")
local modifier
local unit={FindModifierByName=function()return modifier end}
unit.AddNewModifier=function(_,_,_,name,kv)
    adds=adds+1
    modifier=setmetatable({stack=0,SetStackCount=function(self,n)self.stack=n end,
        GetStackCount=function(self)return self.stack end},{__index=_G[name]})
    modifier:OnCreated(kv)
    return modifier
end
assert(service.apply(unit,500):GetStackCount()==500 and links==1)
for i=1,100 do service.apply(unit,500+i) end
assert(adds==1 and modifier:GetStackCount()==600,"clone sync must update, not re-add")
local failed=0
local broken={FindModifierByName=function()return nil end,AddNewModifier=function()failed=failed+1 end}
for i=1,100 do service.apply(broken,200) end
assert(failed==1,"binding failure must not spam every sync tick")
time=5;service.apply(broken,200)
assert(failed==2 and links==2,"retry refreshes engine binding; new units reuse registration")
print("HERO_BASE_HEALTH_BINDING_PASS")
