-- Offline oracle contract only; actual solid movement is validated in Dota.
package.path='scripts/vscripts/?.lua;'..package.path
for _,name in ipairs({'systems/wall_navigation_service','systems/wall_navigation_geometry',
    'systems/wall_melee_contact','modifiers/modifier_enemy_wall_ai','core/json_encoder'}) do
    package.loaded[name]={}
end
package.loaded['systems/wall_melee_contact'].arrived=function(_,unit,goal)
    return unit.arrived and unit.ai.contact_move==goal
end
local clock=10
GameRules={GetGameTime=function() return clock end}
local function forbidden() error('oracle cannot move, phase, shrink, kill or fabricate attacks') end
UTIL_Remove=forbidden;ExecuteOrderFromTable=forbidden;ApplyDamage=forbidden
local probe=assert(loadfile('scripts/vscripts/tests/wall_native_redesign_probe.lua'))()
local pick=assert(probe._pick_vacancy_victim_for_test)
local hit=assert(probe._record_partial_vacancy_hit_for_test)
local function actor(id,x,y,locked)
    local p={x=x,y=y,z=0}
    local unit={id=id,p=p,alive=true,arrived=true,ai={contact_locked=locked~=false,contact_move=p}}
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.id end
    function unit:GetAbsOrigin() return self.p end
    function unit:FindModifierByName() return self.ai end
    function unit:GetHullRadius() return 32 end
    function unit:IsPhased() return false end
    unit.SetAbsOrigin=forbidden;unit.SetHullRadius=forbidden;unit.ForceKill=forbidden
    return unit
end
local function scene()
    local a,b,c,d=actor(1,-184,-88),actor(2,-184,0),actor(3,-184,88),actor(4,184,0)
    local s={monsters={c,a,b,d},hits={[1]=5,[2]=5,[3]=5,[4]=5},hit_face={[1]=1,[2]=1,[3]=1,[4]=2},
        wall={GetAbsOrigin=function() return {x=0,y=0,z=0} end},errors={}}
    return s,a,b,c,d
end
local cases=0
local function test(name,callback)
    cases=cases+1;local ok,message=pcall(callback);assert(ok,name..': '..tostring(message))
end
test('default keeps original four-lock face rule',function()
    local s,_,_,c=scene()
    assert(pick(s,{locked={3,1,0,0}})==nil,'partial faces cannot silently change default acceptance')
    assert(pick(s,{locked={4,1,0,0}})==c,'full face retains historical first eligible actor')
    s.vacancy_face=2
    assert(pick(s,{locked={4,1,0,0}})==nil,'explicit face cannot kill a different full face')
end)
test('partial face selects median of actual arrived locked hit occupants',function()
    local s,a,b,c,d=scene();s.allow_partial_vacancy=true;s.vacancy_face=1
    local victim,front=pick(s,{locked={3,1,0,0}})
    assert(victim==b and #front==3 and front[1].unit==a and front[3].unit==c)
    d.ai.contact_move={x=-184,y=176,z=0};d.p=d.ai.contact_move;d.arrived=false
    assert(pick(s,{locked={3,1,0,0}})==b,'a non-arrived body cannot displace the real median')
    a.ai.contact_locked=false;c.arrived=false
    assert(pick(s,{locked={3,1,0,0}})==nil,'lock totals alone cannot fabricate two real front blockers')
end)
local function opened_scene()
    local s,a,b,c=scene();s.allow_partial_vacancy=true;s.vacancy_face=1
    s.victim=2;s.victim_face=1;s.vacancy_goal={x=-184,y=0,z=0};s.killed_at=9
    s.vacancy_front_ids={[1]=true,[2]=true,[3]=true};s.vacancy_fill_ids={};s.vacancy_fills={}
    s.vacancy_blockers={a,c};s.replacement=0;b.alive=false
    return s,a,b,c
end
test('previously hitting other face actor can fill exact vacancy once',function()
    local s=opened_scene();local incoming=actor(9,-184,0);s.hits[9]=12;s.hit_face[9]=2
    assert(hit(s,incoming.ai,incoming,incoming.ai.contact_move),'global first-hit restriction must not hide a real fill')
    assert(s.replacement==1 and #s.vacancy_fills==1 and s.vacancy_fills[1].id==9)
    clock=11
    assert(not hit(s,incoming.ai,incoming,incoming.ai.contact_move) and s.replacement==1,'repeated attacks cannot count twice')
end)
test('wrong face existing blockers nonclaim and another goal cannot count',function()
    local s,a=opened_scene()
    local wrong=actor(10,184,0)
    assert(not hit(s,wrong.ai,wrong,wrong.ai.contact_move),'another face cannot count')
    a.ai.contact_move={x=-184,y=0,z=0}
    assert(not hit(s,a.ai,a,a.ai.contact_move),'an original survivor cannot count as replacement')
    local no_claim=actor(11,-184,0,false)
    assert(not hit(s,no_claim.ai,no_claim,no_claim.ai.contact_move),'unlocked actor cannot count')
    local another_slot=actor(12,-184,88)
    assert(not hit(s,another_slot.ai,another_slot,another_slot.ai.contact_move),'another same-face slot is not the vacancy')
    assert(s.replacement==0 and #s.vacancy_fills==0)
end)
test('loss of an original live blocker fails rather than relaxing collision',function()
    local s,a=opened_scene();a.alive=false
    local incoming=actor(13,-184,0)
    assert(not hit(s,incoming.ai,incoming,incoming.ai.contact_move))
    assert(s.vacancy_blocker_lost and s.errors[1]=='vacancy_live_blocker_lost' and s.replacement==0)
end)
test('partial observer cannot alter default replacement accounting',function()
    local s=opened_scene();s.allow_partial_vacancy=false
    local incoming=actor(14,-184,0)
    assert(not hit(s,incoming.ai,incoming,incoming.ai.contact_move) and s.replacement==0)
end)
print('WALL_NATIVE_PARTIAL_VACANCY_ORACLE_PASS cases='..cases
    ..' default=full4 partial=explicit_face_median arrived_lock=required slot=exact native_hit=required'
    ..' cross_face_history=allowed fill_ids=unique survivors=alive phase_or_motion=forbidden native_acceptance=false')
