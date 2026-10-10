-- Real harvesting and real armor accumulator; only native entity operations mocked.
package.path="scripts/vscripts/?.lua;"..package.path
local candidate=arg[1] or "scripts/vscripts/modifiers/modifier_lumberjack_ai.lua"
local before=arg[2]
local events=require("core/events")
IsServer=function() return true end
class=function(value) return value end
MODIFIER_ATTRIBUTE_PERMANENT=1
DOTA_UNIT_CAP_MELEE_ATTACK=1
local function encode(value)
    if type(value)~="table" then return tostring(value) end
    if type(value.entindex)=="function" then return "unit:"..value:entindex() end
    local keys,out={},{}
    for key in pairs(value) do keys[#keys+1]=key end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,key in ipairs(keys) do out[#out+1]=tostring(key).."="..encode(value[key]) end
    return "{"..table.concat(out,",").."}"
end
local function harness(path)
    local h={events={},stacks={},calls={},pending={},native=0,saw=false,clock=0,owner=0}
    GameRules={GetGameTime=function() return h.clock end}
    local bus={emit=function(name,payload)
        h.events[#h.events+1]=name..":"..encode(payload)
        if name==events.TREE_DEPLETED and h.deplete then h.deplete() end
    end}
    package.loaded["core/event_bus"]=bus
    package.loaded["core/scheduler"]={after=function(_,fn,key) h.pending[#h.pending+1]=fn end}
    package.loaded["core/sound_service"]={play=function(name) h.events[#h.events+1]="sound:"..name end}
    package.loaded["systems/commerce_effects"]={owned=function() return h.saw end}
    package.loaded["systems/tree_damage_rules"]={is_tree=function(unit) return unit.is_tree==true end}
    package.loaded["systems/lumberjack_attack_observer"]={is_ready=function() return false end}
    _G.modifier_research_technology=nil;_G.modifier_research_armor_reduction=nil
    package.loaded["modifiers/modifier_research_technology"]=nil
    require("modifiers/modifier_research_technology")
    local armor=_G.modifier_research_armor_reduction
    local add=armor.AddArmorReduction
    function armor:AddArmorReduction(amount,diagnostic,phase)
        h.calls[#h.calls+1]={amount=amount,diagnostic=diagnostic,phase=phase}
        if h.fail_add then
            self.armor_reduction=(self.armor_reduction or 0)+amount
            error(h.fail_add,0)
        end
        return add(self,amount,diagnostic,phase)
    end
    local ai=assert(loadfile(path))()
    local function unit(id,team)
        return {entindex=function() return id end,IsNull=function(self) return self.removed==true end,
            GetTeamNumber=function() return team end,GetAttackCapability=function() return 1 end,
            SetRangedProjectileName=function() end}
    end
    h.parents={unit(10,2),unit(11,2)}
    local tree=unit(50,3);h.tree=tree;tree.is_tree=true
    tree.base=100;tree.extra=0;tree.survival_minimum_armor=33;tree.health=100
    function tree:GetHealth() return self.health end
    function tree:GetPhysicalArmorValue() return self.base+self.extra-(self.mod and self.mod.stack or 0)/100 end
    function tree:FindModifierByName(name)
        assert(name=="modifier_research_armor_reduction")
        if h.find_error then error("find_error") end
        if h.find_override then return h.find_override end
        return self.mod
    end
    function tree:AddNewModifier(caster,ability,name,params)
        assert(name=="modifier_research_armor_reduction" and ability==nil)
        assert(params.duration==nil and params.diagnostic_hit==nil)
        h.native=h.native+1
        if not self.mod or self.mod.removed then
            local mod=setmetatable({stack=0,parent=self,caster=caster,duration=-1},{__index=armor})
            function mod:IsNull() return self.removed==true end
            function mod:GetParent() return self.parent end
            function mod:GetDuration() return self.duration end
            function mod:GetStackCount() return self.stack end
            function mod:SetStackCount(value) self.stack=value;h.stacks[#h.stacks+1]=value end
            self.mod=mod;mod:OnCreated(params)
        else self.mod:OnRefresh(params) end
        return self.mod
    end
    h.ai=setmetatable({},{__index=ai})
    function h.ai:GetParent() return h.parents[h.owner+1] end
    function h.ai:StartIntervalThink() end
    h.ai:OnCreated({player_id=0,tree_entindex=50,technology_armor_reduction=.3,
        base_lumber_efficiency=13,technology_lumber_efficiency=2,technology_crit_chance=7})
    function h.level(base,floor)
        if tree.mod then tree.mod.removed=true end
        tree.mod=nil;tree.base=base;tree.survival_minimum_armor=floor;tree.health=100
    end
    function h.hit()
        h.clock=h.clock+.1
        h.ai:OnHarvestLanded({attacker=h.parents[h.owner+1],target=tree})
        local pending=h.pending;h.pending={};for _,fn in ipairs(pending) do fn() end
    end
    function h.snapshot()
        local mod=tree.mod
        return {armor=tree:GetPhysicalArmorValue(),stack=mod and mod.stack,
            fractional=mod and mod.armor_reduction,client_armor=mod and mod:GetModifierPhysicalArmorBonus(),
            pending=#h.pending,events=h.events,stacks=h.stacks,calls=h.calls}
    end
    return h
end
local function suite(path,optimized)
    local traces={}
    -- Stable saturated trees still run precise accumulator logic, with no native refresh.
    local h=harness(path);h.level(100,33)
    h.tree:AddNewModifier(h.parents[1],nil,"modifier_research_armor_reduction",{armor_reduction_per_attack=67})
    h.native=0
    for _=1,1040 do h.owner=_%2;h.hit() end
    assert(h.native==(optimized and 0 or 1040) and h.tree.mod.stack==6700 and h.tree.mod.armor_reduction==67)
    assert(#h.stacks==1,"At-floor calls never write an unchanged client stack")
    traces[#traces+1]=encode(h.snapshot())
    -- Fractional increments below 0.01 must continue accumulating; external
    -- armor changes can clamp that fraction, and later restore reduction room.
    h=harness(path);h.ai.technology_armor_reduction=.003
    for _=1,25 do h.hit() end
    assert(h.tree.mod.stack==7 and h.tree.mod.armor_reduction>.07)
    h.tree.extra=-100;h.hit();assert(h.tree.mod.armor_reduction==0 and h.tree.mod.stack==7)
    h.tree.extra=5;for _=1,20 do h.hit() end
    local existing=h.tree.mod;h.level(150,40);h.hit()
    assert(existing.removed and existing~=h.tree.mod and h.tree.mod.stack==0)
    assert(h.native==(optimized and 2 or 47),"Only initial/after-level modifiers are created")
    traces[#traces+1]=encode(h.snapshot())
    -- The saw reduction precedes depletion; technology follows it and must
    -- obtain the replacement modifier after a synchronous tree level change.
    h=harness(path);h.saw=true;h.tree.health=1
    h.deplete=function() h.level(200,60);h.events[#h.events+1]="level_changed" end
    h.hit();h.deplete=nil
    assert(#h.calls==2 and h.calls[1].phase=="created" and h.calls[2].phase=="created")
    local saw=require("config/armor_balance").from_war3_linear(1)
    assert(h.calls[1].amount==saw and h.calls[2].amount==.3 and h.tree.mod.armor_reduction==.3)
    for _=1,10 do h.hit() end
    assert(h.native==(optimized and 2 or 22))
    traces[#traces+1]=encode(h.snapshot())
    -- Missing lookup, throwing lookup, invalid/foreign modifier, missing
    -- method, non-permanent duration and API inspection exceptions all retain
    -- the original engine path without executing an untrusted direct method.
    for _,mode in ipairs({"lookup_missing","lookup_error","null","foreign","method_missing","duration_missing","duration_error","finite_duration"}) do
        h=harness(path);h.hit();local mod=h.tree.mod
        if mode=="lookup_missing" then h.tree.FindModifierByName=nil
        elseif mode=="lookup_error" then h.find_error=true
        elseif mode=="finite_duration" then mod.duration=3
        else
            local proxy={IsNull=function() return false end,GetParent=function() return h.tree end,
                GetDuration=function() return -1 end,AddArmorReduction=function() error("Untrusted direct call") end}
            if mode=="null" then proxy.IsNull=function() return true end
            elseif mode=="foreign" then proxy.GetParent=function() return {} end
            elseif mode=="method_missing" then proxy.AddArmorReduction=nil
            elseif mode=="duration_missing" then proxy.GetDuration=nil
            elseif mode=="duration_error" then proxy.GetDuration=function() error("duration_error") end end
            h.find_override=proxy
        end
        for _=1,3 do h.hit() end
        assert(h.native==4 and h.tree.mod.armor_reduction==1.2,"Fallback "..mode)
        traces[#traces+1]=encode(h.snapshot())
    end
    -- An addition may mutate before failing. Preserve its error without an
    -- unsafe native retry that would increment the same harvest twice.
    h=harness(path);h.hit();local failure={message="after_partial_add"};h.fail_add=failure
    local ok,err=pcall(h.hit)
    assert(not ok and err==failure and h.tree.mod.armor_reduction==.6)
    assert(h.native==(optimized and 1 or 2))
    traces[#traces+1]=encode(h.snapshot())
    h=harness(path);h.ai.technology_armor_reduction=0;h.hit();assert(h.native==0)
    h.saw=true;h.tree.is_tree=false;h.hit();assert(h.native==0)
    traces[#traces+1]=encode(h.snapshot())
    return table.concat(traces,"\n")
end
local after=suite(candidate,true)
if before then assert(after==suite(before,false),"Every event, fractional accumulator, stack update and client armor remains identical") end
print("TREE_ARMOR_REFRESH_PASS: 1040 saturated hits use 0 native refreshes; fractions/external armor/level reset/saw order/fallback/error semantics preserved"..(before and "; original and candidate traces identical" or ""))
