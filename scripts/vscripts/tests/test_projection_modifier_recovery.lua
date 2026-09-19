package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(t) return t end
LUA_MODIFIER_MOTION_NONE = 0
LUA_MODIFIER_MOTION_HORIZONTAL = 1
package.loaded['core/logger'] = {info=function() end}
package.loaded['core/event_bus'] = {}
package.loaded['core/events'] = {}
package.loaded['core/scheduler'] = {}
package.loaded['config/armor_balance'] = {}
local now, links, adds = 0, 0, 0
GameRules = {GetGameTime=function() return now end}
local bound = {}
LinkLuaModifier = function(name, path)
    assert(path == 'modifier_bindings/' .. name, 'must bind exported engine scope')
    links = links + 1
    local scope=setmetatable({}, {__index=_G})
    local entry=assert(loadfile('scripts/vscripts/'..path..'.lua'))
    setfenv(entry, scope);entry()
    assert(type(rawget(scope,name))=='table', 'definition missing from engine scope')
    bound[name]=scope[name]
end
local function unit()
    return {mods={}, IsNull=function() return false end,
        FindModifierByName=function(self,name) return self.mods[name] end,
        AddNewModifier=function(self,caster,ability,name,params)
            adds=adds+1
            assert(bound[name], 'unknown modifier')
            if self.fail then return nil end
            local m={definition=bound[name],params=params}
            self.mods[name]=m;return m
        end}
end
local registry=require('core/modifier_registry')
local a,b=unit(),unit()
for _,name in ipairs({'modifier_weapon_stat_projection','modifier_research_technology'}) do
    local m=assert(registry.ensure(a,name,{player_id=2}))
    assert(m.params.player_id==2)
    local before=adds
    for i=1,100 do assert(registry.ensure(a,name)==m) end
    assert(adds==before, 'existing projection recreated')
    bound={} -- Engine lost bindings, while require retains the actual definitions.
    assert(registry.ensure(b,name))
    b.mods[name]=nil;bound={}
    assert(registry.ensure(b,name), 'removed projection must recover')
end
local bad=unit();bad.fail=true
assert(not registry.ensure(bad,'modifier_research_technology'))
local before=adds
for i=1,100 do now=4.9;assert(not registry.ensure(bad,'modifier_research_technology')) end
assert(adds==before,'failed modifier creation flooded the engine')
now=5;bad.fail=false
assert(registry.ensure(bad,'modifier_research_technology'))
assert(adds==before+1)
assert(not registry.ensure({IsNull=function()return true end},'modifier_research_technology'))
print('PROJECTION_MODIFIER_RECOVERY_PASS: real definition exports, cached reload, reuse, removal recovery, player params, bounded failed retries')
