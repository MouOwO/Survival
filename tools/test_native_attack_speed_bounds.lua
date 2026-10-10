local path=assert(arg[1],'helper path required')
local checks=0
local function check(v,message) checks=checks+1;assert(v,message) end
_G.class=function(t) return t end
_G.IsInToolsMode=function() return true end
_G.IsServer=function() return true end
_G.LinkLuaModifier=function() end
_G.LUA_MODIFIER_MOTION_NONE=0
_G.MODIFIER_ATTRIBUTE_MULTIPLE=2
_G.MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE=10
_G.MODIFIER_PROPERTY_IGNORE_ATTACKSPEED_LIMIT=11
_G.MODIFIER_PROPERTY_ATTACKSPEED_ABSOLUTE_MAX=12
package.preload['modifiers/modifier_debug_attack_cap']=function() return {} end
local m={IsNull=function()return false end,GetMinimumAttackSpeed=function()return 0 end,
 GetMaximumAttackSpeed=function()return 7 end}
local entities={}
GameRules={GetGameModeEntity=function()return m end}
EntIndexToHScript=function(i)return entities[i]end
local units={}
local function unit(i)
 local u={index=i,mods={},health=500,target={},survival_worker_native_cap_omitted=true,
  survival_wave_native_attack_cap=true,reads=0}
 entities[i]=u;units[#units+1]=u
 function u:IsNull()return self.null==true end
 function u:IsAlive()return not self.dead end
 function u:entindex()return self.index end
 function u:GetClassname()return 'npc_dota_creature'end
 function u:IsRealHero()return false end
 function u:GetUnitName()return 'npc_survival_lumberjack'end
 function u:GetHealth()return self.health end
 function u:GetTeamNumber()return 2 end
 function u:GetAttackTarget()return self.target end
 function u:FindAllModifiersByName(name)
  local out={};for _,v in ipairs(self.mods)do if v.name==name and not v.null then out[#out+1]=v end end;return out
 end
 function u:GetAttackSpeed(flag)
  check(flag==false,'native getter boolean required')
  self.reads=self.reads+1
  if self.fail_read==self.reads then error('metric_read_failed')end
  local raw,cap=2,false
  for _,v in ipairs(self.mods)do
   if not v.null then if v.name=='modifier_debug_attack_cap' then cap=true else raw=raw+v.value/100 end end
  end
  return math.max(cap and .01 or .2,raw)
 end
 function u:GetAttacksPerSecond(flag)check(flag==false);return self:GetAttackSpeed(false)/.7 end
 function u:GetBaseAttackTime(flag)check(flag==false);return .7 end
 function u:AddNewModifier(caster,ability,name,params)
  check(caster==self and ability==nil)
  local mod={name=name,value=params.value or 0,parent=self}
  function mod:IsNull()return self.null==true end
  function mod:Destroy()self.pending=true;self.destroy_calls=(self.destroy_calls or 0)+1 end
  self.mods[#self.mods+1]=mod
  return mod
 end
 return u
end
local function frame()
 for _,u in ipairs(units)do for _,v in ipairs(u.mods)do if v.pending then v.null=true end end end
end
local function reset()rawset(_G,'SURVIVAL_TOOLS_NATIVE_LOWER_FLOOR',nil)end
local ab=assert(loadfile(path))()
local u=unit(1401)
local ok,reason,p=ab.begin(u,'extreme')
check(ok and reason=='cleanup_pending' and p.restore_pending)
check(p.metrics_differ and p.without_cap.attack_speed==.2 and p.with_cap.attack_speed==.01)
check(u.target~=nil and u.health==500 and u.survival_worker_native_cap_omitted==true)
check(not ab.finalize(),'native Destroy must be finalized externally')
local _,again=ab.begin(u);check(again=='previous_restore_pending')
frame();ok,reason,p=ab.finalize();check(ok and reason=='restored' and not p.restore_pending)
check(p.restored.attack_speed==2 and #u:FindAllModifiersByName('modifier_debug_attack_cap')==0)
check(ab.finalize() and ab.stop(),'idempotent finalize and stop')
for _,v in ipairs(u.mods)do check(v.destroy_calls==1,'own handle destroyed exactly once')end
ok,reason,p=ab.begin(u,'combination');check(ok and #u.mods==7,'all four exact percent properties present')
check(not p.metrics_differ and math.abs(p.with_cap.attack_speed-1.05)<1e-6)
-- Model baseline2 means combination remains abovefloor, unlike baseline1.
frame();check(ab.finalize())
reset();local prior=unit(20);prior:AddNewModifier(prior,nil,'modifier_debug_attack_cap',{})
ok,reason,p=ab.begin(prior);check(not ok and string.find(reason,'original_cap_must_be_absent',1,true))
check(#prior.mods==1 and not prior.mods[1].pending,'original cap untouched')
reset();prior=unit(21);prior:AddNewModifier(prior,nil,'modifier_tools_native_lower_floor',{value=0})
check(not ab.begin(prior) and not prior.mods[1].pending,'original probe untouched')
reset();local dead=unit(22);dead.dead=true;check(not ab.begin(dead) and #dead.mods==0)
reset();local foreign=unit(23);entities[23]=unit(23);check(not ab.begin(foreign) and #foreign.mods==0)
reset();local failed=unit(24);failed.fail_read=3
ok,reason,p=ab.begin(failed);check(not ok and p.restore_pending and #failed.mods==1)
frame();failed.fail_read=nil;check(ab.finalize(),'failed measurement still restores')
reset();u=unit(25);check(ab.begin(u));frame();entities[25]=unit(25)
check(not ab.finalize(),'entity-index reuse cannot certify different handle')
check(#entities[25].mods==0,'replacement entity untouched')
reset();u=unit(26);check(ab.begin(u));frame();u.dead=true;check(not ab.finalize(),'death invalidates proof')
reset();u=unit(27);check(ab.begin(u));frame();local target=u.target;u.target={}
check(not ab.finalize(),'changed tree target invalidates proof');u.target=target;check(ab.finalize())
reset();u=unit(28);check(ab.begin(u));frame();m={}
check(not ab.finalize(),'GameMode replacement invalidates proof')
local modifier=modifier_tools_native_lower_floor
check(modifier:IsHidden() and not modifier:IsPurgable() and modifier:RemoveOnDeath())
check(modifier:GetAttributes()==MODIFIER_ATTRIBUTE_MULTIPLE)
local instance=setmetatable({},{__index=modifier});instance:OnCreated({value=-1000})
check(instance:GetModifierAttackSpeedPercentage()==-1000)
check(#instance:DeclareFunctions()==1,'one inert percentage property only')
print('PASS native attack speed bounds: '..checks..' checks')
