return function(source)
    local clock,orders,stops,force_writes=0,{},0,0
    local env=setmetatable({},{__index=_G});env._G=env
    env.LinkLuaModifier=function() end;env.class=function(t) return t end
    env.IsServer=function() return true end
    env.GameRules={GetGameTime=function() return clock end}
    env.DOTA_UNIT_CAP_MELEE_ATTACK=1
    env.DOTA_UNIT_ORDER_ATTACK_TARGET=2;env.DOTA_UNIT_ORDER_MOVE_TO_POSITION=3
    env.MODIFIER_STATE_ROOTED=4;env.MODIFIER_STATE_DISARMED=5
    env.DOTA_TEAM_BADGUYS=3
    local plan=nil
    local contact={release=function() end,resolve=function() return plan end,attack_range=function() return 210 end}
    env.require=function(name)
        if name=='systems/wall_melee_contact' then return contact end
        return {are_enemies=function() return true end,enforce=function() error('unnecessary team update') end}
    end
    env.ExecuteOrderFromTable=function(order) orders[#orders+1]=order end
    local function wall(id)
        return {entindex=function() return id end,IsNull=function() return false end,
            IsAlive=function(self) return not self.dead end,GetAbsOrigin=function() return {x=0,y=0} end}
    end
    local walls={[1]=wall(1),[2]=wall(2)}
    env.EntIndexToHScript=function(id) return walls[id] end
    local chunk=assert(loadstring(source));setfenv(chunk,env);local M=chunk()
    local parent={idle=false,p={x=-400,y=40},rate=1}
    function parent:entindex() return 3 end
    function parent:IsNull() return false end
    function parent:IsAlive() return true end
    function parent:GetAbsOrigin() return self.p end
    function parent:GetTeamNumber() return 3 end
    function parent:GetForceAttackTarget() return self.force end
    function parent:SetForceAttackTarget(t) self.force=t;force_writes=force_writes+1 end
    function parent:IsIdle() return self.idle end
    function parent:Stop() stops=stops+1 end
    function parent:GetAttackCapability() return 1 end
    function parent:Script_GetAttackRange() return (self.base_range or 128)+(self.ai.contact_range_delta or 0) end
    function parent:GetAttacksPerSecond() return self.rate end
    function parent:IsStunned() return self.stunned end
    function parent:IsDisarmed() return self.disarmed end
    local intervals={}
    local ai=setmetatable({GetParent=function() return parent end,StartIntervalThink=function(_,dt) intervals[#intervals+1]=dt end},{__index=M})
    parent.ai=ai;ai:OnCreated({wall_entindex=1})
    assert(intervals[1]==0 and #orders==0,'first observation must run next frame, after spawn placement')
    local function tick(dt) clock=clock+(dt or .5);ai:OnIntervalThink() end
    tick(1/30)
    assert(#orders==1 and intervals[2]==0.5,'first frame must issue a goal and restore the normal observation cadence')
    for i=1,30 do parent.p={x=parent.p.x-10,y=40};tick() end
    assert(#orders==1 and force_writes==1 and stops==0,'ongoing chase must not restart')
    plan={point={x=-192,y=40},claimed=true};tick()
    assert(ai.ai_state=='approach' and #orders==2)
    parent.p={x=-195,y=40};tick()
    assert(ai.ai_state=='attack' and #orders==3 and stops==1,'one arrival transition')
    -- Deliberately no GetAttackTarget: cooldown/backswing nil must be irrelevant.
    parent.idle=true
    for i=1,60 do
        ai:OnAttackStart({attacker=parent,target=walls[1]});tick()
    end
    assert(#orders==3 and stops==1,'60 attack ticks must not reset native attacks')
    parent.base_range=64;tick()
    assert(parent:Script_GetAttackRange()==210 and #orders==3,'range debuff must not break rooted contact or restart attacks')
    parent.base_range=128;tick()
    parent.stunned=true
    for i=1,20 do tick() end
    assert(#orders==3 and ai.contact_locked,'stun must not clear or reissue goal')
    parent.stunned=false;tick();tick()
    assert(#orders==3,'control release has a recovery grace period')
    ai:OnAttackStart({attacker=parent,target=walls[1]})
    parent.rate=.2 -- Five-second cooldown is not a stuck attack.
    for i=1,9 do tick() end
    assert(#orders==3,'slow attacks must not trigger recovery during cooldown')
    parent.rate=1
    tick(4)
    assert(#orders==4 and stops==1,'actual prolonged interruption retries without Stop')
    for i=1,8 do tick() end
    assert(#orders==4,'failed recovery backs off')
    plan={point={x=-192,y=40},claimed=false};tick()
    local before=#orders
    for i=1,60 do plan.point={x=-192,y=(i%2==0 and 120 or -40)};tick() end
    assert(ai.ai_state=='waiting' and #orders==before,'blocked overflow must not repeat/redirect move orders')
    plan={point={x=-192,y=-40},claimed=true};tick()
    assert(ai.ai_state=='approach' and #orders==before+1,'free contact wakes waiting unit once')
    parent.p={x=-192,y=-40};tick()
    assert(ai.ai_state=='attack' and #orders==before+2)
    ai:SetWallEntIndex(-1)
    local stopped,writes=stops,force_writes
    for i=1,30 do ai:SetWallEntIndex(-1);tick() end
    assert(stops==stopped and force_writes==writes,'no-target notifications must be idempotent')
    assert(parent.force==nil and not ai.contact_locked and parent:Script_GetAttackRange()==128)
    ai:SetWallEntIndex(2);plan=nil;tick()
    assert(orders[#orders].TargetIndex==2,'retarget needs new native attack order')
    ai:OnDeath({unit=walls[2]})
    assert(ai.wall_entindex==-1 and not ai.contact_waiting,'death event releases immediately')
    -- Transition while externally controlled issues exactly one pending order on recovery.
    ai:SetWallEntIndex(1);parent.stunned=true;local pending=#orders;tick();tick()
    assert(#orders==pending and ai.order_pending)
    parent.stunned=false;tick();tick()
    assert(#orders==pending+1 and not ai.order_pending)
    print('[C6_AI_CHECK] PASS per-unit FSM, 60 stable attack ticks, cooldown/stun, bounded recovery, overflow, retarget/death')
end
