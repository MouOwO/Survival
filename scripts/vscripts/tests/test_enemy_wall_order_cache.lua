return function(source)
    local orders,force_writes=0,0
    local env=setmetatable({},{__index=_G})
    env._G=env
    env.LinkLuaModifier=function() end
    env.class=function(t) return t end
    env.require=function() return {release=function() end} end
    env.ExecuteOrderFromTable=function() orders=orders+1 end
    local chunk=assert(loadstring(source)) setfenv(chunk,env)
    local M=chunk()
    local wall={entindex=function() return 1 end}
    local wall2={entindex=function() return 2 end}
    local parent={force=nil,target=nil,idle=false}
    function parent:entindex() return 3 end
    function parent:IsNull() return false end
    function parent:GetForceAttackTarget() return self.force end
    function parent:SetForceAttackTarget(t) self.force=t force_writes=force_writes+1 end
    function parent:GetAttackTarget() return self.target end
    function parent:IsIdle() return self.idle end
    function parent:Stop() self.idle=true end
    local ai=setmetatable({wall_entindex=1,GetParent=function() return parent end},{__index=M})
    for i=1,30 do ai:AttackWallOnce(parent,wall) end
    assert(orders==1 and force_writes==1,'ongoing chase repeated an order')
    parent.idle=true ai:AttackWallOnce(parent,wall)
    assert(orders==2,'idle unit did not recover')
    parent.idle=false parent.target=wall
    ai:AttackWallOnce(parent,wall)
    assert(orders==2,'attacking unit repeated an order')
    parent.target=nil parent.force=nil
    ai:AttackWallOnce(parent,wall)
    assert(force_writes==2,'engine force target was not restored')
    ai:MoveToOnce(parent,Vector(10,20,0),'slot:1')
    ai:AttackWallOnce(parent,wall)
    assert(orders==4,'new navigation failed to restore attack order')
    ai:SetWallEntIndex(2) ai:AttackWallOnce(parent,wall2)
    assert(orders==5 and parent.force==wall2,'retarget did not issue new attack')
    ai:SetWallEntIndex(-1)
    assert(parent.force==nil and parent.idle,'invalid wall was not released')
    print('[C6_AI_CHECK] PASS attack order cache, idle recovery, navigation, retarget and invalid target')
end
