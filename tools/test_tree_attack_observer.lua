-- Offline regression: real tree evidence/progression, mocked native broadcast
-- and immutable engine declaration caches. Does not run the game or console.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) value.__index = value; return value end
local server, tools_mode, map_name = true, true, "template_map"
IsServer = function() return server end
IsInToolsMode = function() return tools_mode end
GetMapName = function() return map_name end
LUA_MODIFIER_MOTION_NONE, DOTA_TEAM_NEUTRALS = 0, 4
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_PROPERTY_MIN_HEALTH, MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE = 1, 2
MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK_FAIL = 3, 4
MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY, MODIFIER_EVENT_ON_TAKEDAMAGE = 5, 6
MODIFIER_STATE_INVULNERABLE, MODIFIER_STATE_UNSELECTABLE = 7, 8
MODIFIER_STATE_NO_HEALTH_BAR, MODIFIER_STATE_OUT_OF_GAME = 9, 10
DOTA_DAMAGE_CATEGORY_ATTACK = 1
Vector = function(x, y, z) return {x=x, y=y, z=z} end
package.loaded["core/scheduler"] = {
    after=function() error("tree routing must stay synchronous") end,
    every=function() error("tree observer must not poll") end,
}

local events = {
    OnAttackStart=MODIFIER_EVENT_ON_ATTACK_START,
    OnAttackFail=MODIFIER_EVENT_ON_ATTACK_FAIL,
    OnAttackRecordDestroy=MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY,
    OnTakeDamage=MODIFIER_EVENT_ON_TAKEDAMAGE,
}
local function contains(rows, value)
    for _, row in ipairs(rows) do if row == value then return true end end
    return false
end
local function copy(rows)
    local result = {}; for index, row in ipairs(rows) do result[index]=row end; return result
end
local world, guard, clock, native_instances, latest_holder
local created, removed, create_failure, link_failure = 0, 0, nil, false
local function reset_world()
    world = {IsNull=function(self) return self.removed==true end}
    guard = {mode=world, blocked_http=0, blocked_saves=0, bots={}}
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = guard
    clock, native_instances, latest_holder = 10, {}, nil
end
reset_world()
GameRules = {
    GetGameModeEntity=function() return world end,
    GetGameTime=function() return clock end,
}
local function unit(id, name, real_hero)
    local value = {index=id, name=name, health=100, alive=true}
    function value:IsNull() return self.removed==true end
    function value:IsAlive() return self.alive end
    function value:entindex() return self.index end
    function value:GetUnitName() return self.name end
    function value:GetClassname() return self.classname or "npc_dota_creature" end
    function value:IsRealHero() return real_hero==true end
    function value:IsIllusion() return self.illusion==true end
    function value:GetTeamNumber() return self.name=="enemy_tree" and 3 or 2 end
    function value:GetHealth() return self.health end
    function value:SetHealth(amount) self.health=amount end
    function value:HasModifier(name) return self.modifier_name==name and not self.empty and not self.removed end
    function value:FindModifierByName(name) if self:HasModifier(name) then return self.modifier end end
    return value
end
local function modifier(methods, parent, name)
    local value = setmetatable({parent=parent}, {__index=methods})
    function value:GetParent() return self.parent end
    function value:IsNull() return self.removed==true end
    function value:StartIntervalThink() error("tree observer must not add a timer") end
    parent.modifier, parent.modifier_name = value, name
    return value
end
LinkLuaModifier = function(name, path)
    if link_failure then error("mock link failure") end
    require(path)
    assert(type(_G[name])=="table", "linked observer class must exist")
end
CreateModifierThinker = function(_, _, name)
    created = created + 1
    if create_failure=="throw" then error("mock thinker failure") end
    local parent = unit(100000+created, "observer_holder")
    local instance = modifier(assert(_G[name]), parent, name)
    -- Native declaration cache is captured before creation and never refreshed.
    instance.native_declarations = copy(instance:DeclareFunctions())
    native_instances[#native_instances+1] = instance
    if instance.OnCreated then instance:OnCreated({}) end
    if create_failure=="empty" then parent.empty=true end
    latest_holder=parent
    return parent
end
UTIL_Remove = function(parent) parent.removed=true; removed=removed+1 end

local rules = require("systems/tree_damage_rules")
local service = require("systems/tree_attack_observer")
local progression = require("modifiers/modifier_tree_progression")
local observer_methods
local function enable(options)
    local result = service.enable_probe(options or {mode=world, guard=guard})
    return result~=nil and result~=false and (type(result)~="table" or result.ok~=false)
end
local function declarations(instance, native)
    local rows = native and instance.native_declarations or instance:DeclareFunctions()
    assert(contains(rows, MODIFIER_PROPERTY_MIN_HEALTH))
    assert(contains(rows, MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE))
    local count=0; for _, event in pairs(events) do if contains(rows,event) then count=count+1 end end
    return count
end
local counter_fields={"survival_tree_declaration_calls","survival_tree_declaration_calls_before_created",
    "survival_tree_declaration_calls_after_created"}
local function no_declaration_counters(instance)
    for _,field in ipairs(counter_fields) do
        assert(instance[field]==nil,"default-off/class queries must not install declaration counters: "..field)
    end
end
local function assert_declaration_counters(instance,total,before,after)
    assert(instance.survival_tree_declaration_calls==total,"unexpected total Lua declaration count")
    assert(instance.survival_tree_declaration_calls_before_created==before,"unexpected before-OnCreated declaration count")
    assert(instance.survival_tree_declaration_calls_after_created==after,"unexpected after-OnCreated declaration count")
end
local function tree(id, options)
    options=options or {}
    local parent=options.parent or unit(id, options.name or "enemy_tree", options.real_hero)
    parent.classname=options.classname
    parent.survival_tree_owner_id=options.owner_id==nil and 0 or options.owner_id
    parent.survival_tree_depleted_callback=options.callback or function(p)
        p.growth=(p.growth or 0)+1; p.health=100+p.growth
    end
    if options.no_callback then parent.survival_tree_depleted_callback=nil end
    local instance=modifier(progression, parent, "modifier_tree_progression")
    local owner_id,callback=parent.survival_tree_owner_id,parent.survival_tree_depleted_callback
    local native_class=parent.GetClassname
    if options.late_identity then parent.survival_tree_owner_id=nil;parent.survival_tree_depleted_callback=nil end
    if options.throwing_identity then parent.GetClassname=function() error("unknown native tree role") end end
    -- The real engine samples native declarations before OnCreated. That first
    -- sample fixes routing for this instance, including an incomplete identity.
    local probe_counters=service.can_register_new()
    instance.native_declarations=copy(instance:DeclareFunctions())
    if probe_counters then assert_declaration_counters(instance,1,1,0)
    else no_declaration_counters(instance) end
    if options.late_identity then parent.survival_tree_owner_id=owner_id;parent.survival_tree_depleted_callback=callback end
    if options.throwing_identity then parent.GetClassname=native_class end
    if not options.old_instance and instance.OnCreated then instance:OnCreated({}) end
    local after_creation=instance:DeclareFunctions()
    if probe_counters then
        assert_declaration_counters(instance,2,options.old_instance and 2 or 1,options.old_instance and 0 or 1)
    else no_declaration_counters(instance) end
    assert(#after_creation==#instance.native_declarations,"OnCreated must preserve the native declaration count")
    for index,value in ipairs(after_creation) do
        assert(value==instance.native_declarations[index],"OnCreated must preserve the exact cached native declarations")
    end
    native_instances[#native_instances+1]=instance
    return instance,parent
end
local function send(name, params)
    -- Snapshot the native broadcast list, including instances removed reentrantly.
    local snapshot=copy(native_instances)
    for _, instance in ipairs(snapshot) do
        if not instance.removed and contains(instance.native_declarations, events[name]) then
            instance[name](instance, params)
        end
    end
end
local function destroy(instance, invalidate_parent)
    if invalidate_parent then instance.parent.removed=true end
    instance:OnDestroy(); instance.removed=true
end
local function assert_empty_evidence(attacker, victim, message)
    assert(not rules.consume_basic_attack(attacker, victim), message)
end
local function exercise(shared)
    reset_world(); rules.reset_pending_attacks()
    if shared then assert(enable()) else service.disable_probe() end
    local first,a=tree(50); local second,b=tree(40); local third,c=tree(60)
    assert(declarations(first)==(shared and 0 or 4))
    assert(declarations(first,true)==(shared and 0 or 4))
    local hero=unit(1,"npc_dota_hero_sven",true)
    local worker=unit(2,"npc_survival_lumberjack")
    local denied=unit(3,"building_arrow_tower",false)
    local result={}
    local function observe(value) result[#result+1]=tostring(value) end
    for _,attacker in ipairs({hero,worker}) do
        assert(first:GetModifierIncomingDamage_Percentage({attacker=attacker})==0)
        send("OnAttackStart",{attacker=attacker,target=a,record=100+attacker.index})
        local evidence=rules.consume_basic_attack(attacker,a)
        observe(evidence);observe(rules.allows_damage(attacker,a,nil,evidence))
        assert(evidence and rules.allows_damage(attacker,a,nil,evidence))
        assert_empty_evidence(attacker,a,"one native attack supplies evidence once")
    end
    assert(first:GetMinHealth()==1)
    assert(first:GetModifierIncomingDamage_Percentage({attacker=denied})==-100)
    send("OnAttackStart",{attacker=denied,target=a,record=200})
    assert_empty_evidence(denied,a,"tower attacks never acquire tree evidence")
    assert(not rules.allows_damage(hero,a,2,false),"spells need real attack evidence")
    assert(not rules.allows_damage(denied,a,DOTA_DAMAGE_CATEGORY_ATTACK,true))
    send("OnAttackStart",{attacker=worker,target=a,record=201})
    send("OnAttackFail",{attacker=worker,target=a,record=201})
    assert_empty_evidence(worker,a,"failed starts must not authorize later damage")
    -- Preserve other records and other targets during target-less destruction.
    send("OnAttackStart",{attacker=hero,target=a,record=301})
    send("OnAttackStart",{attacker=hero,target=a,record=302})
    send("OnAttackStart",{attacker=hero,target=b,record=303})
    send("OnAttackStart",{attacker=worker,target=a,record=301})
    send("OnAttackRecordDestroy",{attacker=hero,record=301})
    local surviving_hero=rules.consume_basic_attack(hero,a)
    local surviving_worker=rules.consume_basic_attack(worker,a)
    assert(surviving_hero and surviving_worker,"record cleanup preserves another record and another attacker")
    observe(surviving_hero);assert_empty_evidence(hero,a);observe(surviving_worker)
    send("OnAttackRecordDestroy",{attacker=hero,record=303})
    assert_empty_evidence(hero,b)
    -- Record destruction must use cached tokens after the attacker becomes null.
    send("OnAttackStart",{attacker=worker,target=b,record=401})
    local token=second.tree_attackers[worker]
    worker.removed=true;worker.entindex=function() error("invalid attacker getter") end
    send("OnAttackRecordDestroy",{attacker=worker,record=401})
    assert(#token.entries==0 and second.tree_attackers[worker]==nil)
    worker.removed=false;worker.entindex=function(self) return self.index end
    -- Destroyed tree cleanup owns tokens even if its parent getter is unusable.
    send("OnAttackStart",{attacker=hero,target=c,record=402})
    local old_token=third.tree_attackers[hero]
    c.removed=true;third.GetParent=function() error("destroyed parent getter") end
    destroy(third)
    assert(#old_token.entries==0 and third.tree_attackers==nil)
    -- Reused attacker/tree indices cannot receive or clear the old evidence.
    send("OnAttackStart",{attacker=hero,target=b,record=501})
    hero.removed,b.removed=true,true
    local new_hero=unit(hero.index,"npc_dota_hero_sven",true)
    local replacement,new_b=tree(b.index)
    assert_empty_evidence(new_hero,b);assert_empty_evidence(hero,new_b)
    send("OnAttackStart",{attacker=new_hero,target=new_b,record=501})
    send("OnAttackRecordDestroy",{attacker=hero,record=501})
    destroy(second,true)
    assert(rules.consume_basic_attack(new_hero,new_b),"old cleanup must not clear same-index replacement evidence")
    -- Depletion stays synchronous, ignores unrelated/zero damage, and guards reentry.
    local nested=0
    a.survival_tree_depleted_callback=function(p)
        nested=nested+1
        send("OnTakeDamage",{attacker=new_hero,unit=p,damage=1})
        p.growth=(p.growth or 0)+1;p.health=100+p.growth
    end
    a.health=1
    send("OnTakeDamage",{attacker=new_hero,unit=new_b,damage=1})
    send("OnTakeDamage",{attacker=new_hero,unit=a,damage=0})
    assert(nested==0)
    for _=1,4 do
        a.health=1;send("OnTakeDamage",{attacker=new_hero,unit=a,damage=10})
        assert(not first.upgrade_pending)
    end
    observe(a.growth);observe(nested);assert(a.growth==4 and nested==4)
    -- Nil-record fallback is preserved until expiry, not guessed from a later id.
    send("OnAttackStart",{attacker=new_hero,target=a})
    send("OnAttackStart",{attacker=new_hero,target=a,record=601})
    send("OnAttackRecordDestroy",{attacker=new_hero,record=601})
    assert(rules.consume_basic_attack(new_hero,a));assert_empty_evidence(new_hero,a)
    send("OnAttackStart",{attacker=worker,target=a})
    clock=clock+4
    send("OnAttackRecordDestroy",{attacker=worker,record=999})
    assert(first.tree_attackers[worker]==nil)
    destroy(first);destroy(replacement)
    if shared then
        local finished=service.snapshot()
        assert(finished.registered_trees==0 and finished.pending_attackers==0 and finished.pending_bindings==0)
        assert(finished.metrics.callback_errors==0,"shared dispatch must not hide callback failures")
    end
    return table.concat(result,",")
end

assert(not service.is_ready(),"observer must default off at module load")
assert(created==0,"require must not install a native holder")
local legacy_result=exercise(false)
local shared_result=exercise(true)
assert(legacy_result==shared_result,"identical native sequence must preserve legacy evidence and growth")
print("TREE_ATTACK_OBSERVER_BUSINESS_PASS legacy/shared evidence, whitelist, fail/destroy, invalid handles, entity reuse, growth and reentry")

-- Registration is immutable from the first native declaration, which precedes
-- OnCreated. Disabled or incomplete instances retain their native fallback.
reset_world();rules.reset_pending_attacks();service.disable_probe()
local before,before_parent=tree(70)
local old,old_parent=tree(71,{old_instance=true})
assert(declarations(before)==4 and declarations(old)==4)
assert(enable())
observer_methods=assert(_G.modifier_tree_attack_observer)
local early=tree(72)
local shared,shared_parent=tree(73)
local late=tree(75,{late_identity=true})
local throwing=tree(76,{throwing_identity=true})
assert(declarations(early)==0,"a formal tree may share at its first declaration before OnCreated")
assert(declarations(late)==4,"missing fields at the first declaration permanently choose legacy")
assert(declarations(throwing)==4,"a role exception at the first declaration permanently chooses legacy")
assert(declarations(before)==4 and declarations(old)==4,"enable must not migrate existing trees")
no_declaration_counters(before);no_declaration_counters(old)
assert(declarations(shared)==0,"only a freshly created validated tree may share")
local hero=unit(10,"npc_dota_hero_sven",true)
local duplicate_parent=unit(200001,"observer_holder")
local duplicate=modifier(observer_methods,duplicate_parent,"modifier_tree_attack_observer")
duplicate:OnCreated({})
duplicate:OnAttackStart({attacker=hero,target=shared_parent,record=700})
assert_empty_evidence(hero,shared_parent,"a duplicate installed holder must not dispatch")
send("OnAttackStart",{attacker=hero,target=shared_parent,record=701})
assert(rules.consume_basic_attack(hero,shared_parent));assert_empty_evidence(hero,shared_parent)
-- Even stale local native caches cannot run the business callback twice.
shared:OnAttackStart({attacker=hero,target=shared_parent,record=702})
latest_holder.modifier:OnAttackStart({attacker=hero,target=shared_parent,record=702})
shared:OnAttackStart({attacker=hero,target=shared_parent,record=702})
assert(rules.consume_basic_attack(hero,shared_parent));assert_empty_evidence(hero,shared_parent)
service.disable_probe()
assert(declarations(shared)==0,"disable must not change an existing native declaration")
local after=tree(74);assert(declarations(after)==4,"disable stops new registrations")
send("OnAttackStart",{attacker=hero,target=shared_parent,record=703})
assert(rules.consume_basic_attack(hero,shared_parent),"disable preserves existing shared routes")
send("OnAttackStart",{attacker=hero,target=before_parent,record=704})
assert(rules.consume_basic_attack(hero,before_parent),"existing legacy route remains operational")
send("OnAttackStart",{attacker=hero,target=old_parent,record=705})
assert(rules.consume_basic_attack(hero,old_parent))
local count_before=created
local quiet=assert(service.snapshot())
assert(type(quiet)=="table" and created==count_before,"snapshot must not create a holder or migrate instances")
assert(quiet.registered_trees==2,"snapshot counts only shared registered trees, including disabled routes")
assert(type(service.snapshot())=="table" and created==count_before)
print("TREE_ATTACK_OBSERVER_CREATION_PASS default off, existing/incomplete legacy, first-declaration sharing, immutable native cache, disable continuity, quiet snapshot")

-- A class-level engine query has no parent and must not write an inherited
-- decision that poisons future instances. Four formally identified trees each
-- register once during the first Declare -> OnCreated -> Declare sequence.
reset_world();rules.reset_pending_attacks();service.disable_probe()
local class_declarations=progression.DeclareFunctions(progression)
for _,event in pairs(events) do assert(contains(class_declarations,event)) end
assert(progression.survival_tree_event_decl_sampled==nil and progression.shared_tree_observer==nil,
    "class-level declaration query must not cache a per-instance decision on the class")
no_declaration_counters(progression)
assert(enable())
local active_class_declarations=progression.DeclareFunctions(progression)
for _,event in pairs(events) do assert(contains(active_class_declarations,event)) end
no_declaration_counters(progression)
local formal_trees={}
for index=1,4 do
    local formal=tree(100+index)
    formal_trees[#formal_trees+1]=formal
    assert(declarations(formal,true)==0 and declarations(formal)==0)
    local total,before,after=formal.survival_tree_declaration_calls,
        formal.survival_tree_declaration_calls_before_created,formal.survival_tree_declaration_calls_after_created
    if formal.OnCreated then formal:OnCreated({}) end
    assert_declaration_counters(formal,total,before,after)
    assert(declarations(formal)==0 and service.snapshot().registered_trees==index,
        "repeated declaration/creation must not register a formal tree twice")
end
assert(service.snapshot().registered_trees==4,"four native-first formal trees must all share")
-- A per-instance nil parent is different from querying the class: it samples
-- an unknown role permanently, even when OnCreated later receives a real tree.
local nil_parent=unit(110,"enemy_tree")
nil_parent.survival_tree_owner_id=0;nil_parent.survival_tree_depleted_callback=function() end
local initially_nil=modifier(progression,nil_parent,"modifier_tree_progression")
initially_nil.GetParent=function() return nil end
initially_nil.native_declarations=copy(initially_nil:DeclareFunctions())
initially_nil.GetParent=function(self) return self.parent end
if initially_nil.OnCreated then initially_nil:OnCreated({}) end
assert(declarations(initially_nil)==4 and declarations(initially_nil,true)==4,
    "a first declaration with nil parent remains legacy after parent recovery")
assert(service.snapshot().registered_trees==4)
for _,formal in ipairs(formal_trees) do destroy(formal) end
assert(service.snapshot().registered_trees==0)
print("TREE_ATTACK_OBSERVER_NATIVE_FIRST_PASS class query isolation, four single registrations, stable native cache, nil-parent fallback")

-- The Tools opt-in requires the exact current world and isolation guard.
reset_world();service.disable_probe()
local function reject(options)
    local okay,result=pcall(enable,options)
    assert(not okay or not result,"invalid probe authority must be rejected")
end
reject({mode={},guard=guard})
reject({mode=world,guard={mode=world}})
local saved=guard;_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=nil
reject({mode=world,guard=saved});_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=saved
server=false;reject({mode=world,guard=guard});server=true
tools_mode=false;reject({mode=world,guard=guard});tools_mode=true
map_name="unsupported_map";reject({mode=world,guard=guard});map_name="template_map"
assert(enable())
for _,options in ipairs({{name="npc_survival_enemy"},{classname="npc_dota_hero"},{real_hero=true},{owner_id=-1},{owner_id=0.5},{owner_id="not_an_integer"},{no_callback=true}}) do
    local fallback=tree(80,options)
    assert(declarations(fallback)==4,"invalid resource-tree identity must retain original native callbacks")
    destroy(fallback)
end
local null_parent=unit(81,"enemy_tree");null_parent.removed=true
assert(declarations(tree(81,{parent=null_parent}))==4)
local current_guard=guard
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
assert(declarations(tree(88))==4,"changed isolation guard forces new trees onto native fallback")
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=current_guard
-- Uninstalled/null holders must not authorize new shared registrations.
local live_holder=latest_holder
live_holder.survival_tree_attack_observer_native_version=nil
assert(not service.is_ready() and declarations(tree(89))==4,
    "installed holder without confirmed native declarations cannot register trees")
live_holder.survival_tree_attack_observer_native_version=1
live_holder.empty=true
assert(not service.is_ready())
assert(declarations(tree(82))==4)
live_holder.empty=false;live_holder.removed=true
assert(not service.is_ready() and declarations(tree(83))==4)
-- Creation failures retain native fallback without auto recovery/polling.
reset_world();create_failure="throw"
assert(not enable() and declarations(tree(84))==4)
create_failure="empty"
assert(not enable() and declarations(tree(85))==4)
create_failure=nil;link_failure=true
assert(not enable() and declarations(tree(86))==4)
link_failure=false
assert(enable() and declarations(tree(87))==0)
print("TREE_ATTACK_OBSERVER_AUTHORITY_PASS exact Tools/world/guard, identity checks, bad holder and creation fallback")

-- Destroy broadcasts visit pending trees in their registration order, even
-- when a callback unregisters a later tree while the dispatch is in flight.
reset_world();rules.reset_pending_attacks();assert(enable())
local first,second,third,a,b,c
local order,reentrant={},false
local original=assert(progression.HandleAttackRecordDestroy)
-- Install before registration: the observer may capture callback functions.
progression.HandleAttackRecordDestroy=function(self,params)
    if self.tree_attackers and self.tree_attackers[params.attacker] then order[#order+1]=self.parent.index end
    if reentrant and self==first then destroy(second) end
    return original(self,params)
end
first,a=tree(93);second,b=tree(91);third,c=tree(92)
hero=unit(11,"npc_dota_hero_sven",true)
local empty_snapshot=service.snapshot()
assert(empty_snapshot.registered_trees==3 and empty_snapshot.pending_attackers==0 and empty_snapshot.pending_bindings==0)
for _,parent in ipairs({a,b,c}) do send("OnAttackStart",{attacker=hero,target=parent,record=901}) end
local pending_snapshot=service.snapshot()
assert(pending_snapshot.pending_attackers==1 and pending_snapshot.pending_bindings==3,
    "one attacker is bound independently to three resource trees")
send("OnAttackRecordDestroy",{attacker=hero,record=901})
assert(table.concat(order,",")=="93,91,92","pending tree dispatch must preserve modifier registration order")
for _,parent in ipairs({a,b,c}) do assert_empty_evidence(hero,parent) end
local drained_snapshot=service.snapshot()
assert(drained_snapshot.pending_attackers==0 and drained_snapshot.pending_bindings==0)
-- The dispatch list is a snapshot, so unregistering another pending tree
-- during the first callback cannot skip a surviving later registration.
for _,parent in ipairs({a,b,c}) do send("OnAttackStart",{attacker=hero,target=parent,record=902}) end
order={};reentrant=true
send("OnAttackRecordDestroy",{attacker=hero,record=902})
progression.HandleAttackRecordDestroy=original
assert(table.concat(order,",")=="93,92","reentrant unregister preserves snapshot order of surviving trees")
for _,parent in ipairs({a,b,c}) do assert_empty_evidence(hero,parent) end
destroy(first);destroy(third)
local final_snapshot=assert(service.snapshot())
assert(final_snapshot.registered_trees==0 and final_snapshot.pending_attackers==0 and final_snapshot.pending_bindings==0,
    "destroy releases both registry and attacker bindings")
assert(final_snapshot.metrics.callback_errors==0,"callback failures must remain observable and absent in successful routes")
print("TREE_ATTACK_OBSERVER_ORDER_PASS deterministic pending-tree dispatch and cleanup")
print("TREE_ATTACK_OBSERVER_PASS")
