-- Offline isolation/lifecycle regression for the opt-in native probe. This
-- fixture simulates native callbacks; it never starts Dota or a live test.
package.path = "scripts/vscripts/?.lua;" .. package.path
local tools_mode, server = true, true
IsInToolsMode = function() return tools_mode end
IsServer = function() return server end
class = function(base) return base or {} end
Vector = function(x, y, z) return { x = x, y = y, z = z } end
DOTA_TEAM_NEUTRALS, DOTA_TEAM_BADGUYS, DOTA_TEAM_GOODGUYS = 4, 3, 2
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 2
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_MOVE_NONE = 0, 0
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 0
DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_MAGICAL, DAMAGE_TYPE_PURE = 1, 2, 4
LUA_MODIFIER_MOTION_NONE = 0

local function forbidden(name)
    return function() error("probe must not invoke " .. name) end
end
local original_filter = function() return "original_filter" end
local mode = { IsNull = function() return false end, native_filter = original_filter,
    SetDamageFilter = forbidden("SetDamageFilter"),
    SetContextThink = forbidden("SetContextThink"),
    SetMaximumAttackSpeed = forbidden("SetMaximumAttackSpeed"),
    SetMinimumAttackSpeed = forbidden("SetMinimumAttackSpeed") }
GameRules = { GetGameTime = function() return 0 end,
    GetGameModeEntity = function() return mode end }
Timers = { CreateTimer = forbidden("CreateTimer") }
Convars = { RegisterCommand = forbidden("RegisterCommand") }
ListenToGameEvent = forbidden("ListenToGameEvent")
package.loaded["core/event_bus"] = {
    subscribe = forbidden("event_bus.subscribe"), emit = forbidden("event_bus.emit"),
    handle_request = forbidden("event_bus.handle_request"),
}
local cached_projection = {
    marker = "existing production module",
    is_finite=function(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end,
    prepare_attack = forbidden("cached prepare_attack"),
    prepare_attack_components = forbidden("cached prepare_attack_components"),
}
package.loaded["combat/endless_stat_projection"] = cached_projection
local cached_filter = { _filter_for_test = original_filter }
package.loaded["combat/damage_filter_service"] = cached_filter
local cached_armor = require("config/armor_balance")
local rule_config = require("combat/damage_rule_config")
local repository = require("combat/damage_transaction_repository")
local damage_service = require("combat/damage_service")
damage_service.init({event_bus={emit=function() end},events=require("combat/combat_events"),
    context=require("combat/damage_context"),rules=rule_config,repository=repository,
    adapter=require("adapters/dota_damage_adapter"),debug={log=function() end}})

local failures, units, alive, created, create_attempts, removed, max_alive
local attacks, applications, links, clock, messages
local function reset(failure)
    failures, units = failure or {}, {}
    alive, created, create_attempts, removed, max_alive = 0, 0, 0, 0, 0
    attacks, applications, links, clock, messages = 0, 0, 0, 0, {}
    repository.init(rule_config)
end
reset()
local file_dofile = dofile
dofile = function(module_name)
    assert(module_name == "combat/endless_stat_projection", "Source2 dofile requires the extension-free native module name")
    if failures.dofile then error("injected native dofile failure") end
    if failures.shared_projection then return cached_projection end
    if failures.no_projection then return nil end
    return file_dofile("scripts/vscripts/" .. module_name .. ".lua")
end
GetSystemTimeMS = function() clock = clock + 0.1; return clock end
GetWorldMinX = function() return -8192 end
GetWorldMaxX = function() return 8192 end
GetWorldMinY = function() return -8192 end
GetWorldMaxY = function() return 8192 end
LinkLuaModifier = function(name, path)
    links = links + 1
    assert(name == "modifier_survival_large_attack_native_probe", "unexpected modifier linked")
    if failures.link then error("injected LinkLuaModifier failure") end
    require(path)
end
local output = print
print = function(message) messages[#messages + 1] = tostring(message) end

local function fail_setter(name)
    if failures.setter == name and not failures.setter_used then
        failures.setter_used = true
        error("injected setter failure: " .. name)
    end
end
local function notify(attacker, victim, amount, category)
    if failures.no_callback then return end
    local event = { attacker = attacker, unit = victim, damage = amount,
        damage_type = DAMAGE_TYPE_PHYSICAL, damage_category = category,
        original_damage = amount, record = attacks, damage_flags = 0 }
    if failures.wrong_callback then event.attacker = victim end
    for _, unit in ipairs(units) do
        if not unit.null then
            for _, modifier in pairs(unit.modifiers) do
                if modifier.OnTakeDamage then modifier:OnTakeDamage(event) end
            end
        end
    end
end
local function native_damage(attacker, victim, amount, category)
    local record = repository.consume_pending(attacker,victim)
    local filter_category = not failures.no_filter_category and category or nil
    local logical = amount
    if not record and (filter_category==nil or filter_category==DOTA_DAMAGE_CATEGORY_ATTACK) then
        logical = logical * (attacker.survival_endless_attack_scale or 1)
    end
    if victim.survival_war3_armor_target or victim.survival_monster_corpse then
        logical = logical / (1 + math.max(0, victim.survival_effective_war3_armor or 0) * 0.02)
    end
    local final = logical / (victim.survival_endless_health_scale or 1)
    if record then record.engine_damage,record.final_damage=logical,logical end
    local before = victim.health
    victim.health = math.max(0, before - final)
    local measured = final
    if failures.native_precision then
        -- Native float HP near 1e8 has an eight-point quantum; callbacks can
        -- report the actual HP delta rather than a sub-point logical result.
        victim.health = math.floor(victim.health / 8 + 0.5) * 8
        measured = before - victim.health
    end
    notify(attacker, victim, measured, category)
    return measured
end
CreateUnitByName = function(name, position, _, owner, unit_owner, team)
    create_attempts = create_attempts + 1
    if failures.create == create_attempts then error("injected create failure") end
    assert(name == "npc_dota_creature", "probe created a managed gameplay unit")
    assert(owner == nil and unit_owner == nil, "probe inherited a gameplay owner")
    assert(team == DOTA_TEAM_NEUTRALS or team == DOTA_TEAM_BADGUYS, "probe used a player team")
    assert((position.x == 15000 or position.x == 15064) and position.y == 15000 and position.z == -3000,
        "probe position must stay outside gameplay and inside native cell bounds")
    local unit = { index = 20000 + created, team = team, position = position, modifiers = {},
        health = 1000, maximum = 1000, damage_min = 0, damage_max = 0 }
    created, alive = created + 1, alive + 1
    max_alive = math.max(max_alive, alive)
    units[#units + 1] = unit
    function unit:IsNull() return self.null == true end
    function unit:IsAlive() return not self.null and self.health > 0 end
    function unit:IsRealHero() return false end
    function unit:IsBuilding() return false end
    function unit:entindex() return self.index end
    function unit:GetUnitName() return name end
    function unit:GetPlayerOwnerID() return failures.owner and 0 or -1 end
    function unit:GetOwnerEntity() return failures.owner_entity and mode or nil end
    function unit:GetPlayerOwner() return nil end
    function unit:GetTeamNumber() return self.team end
    function unit:GetAbsOrigin() return self.position end
    function unit:SetAbsOrigin(value)
        self.position = failures.position and Vector(0, 0, value.z) or value
    end
    function unit:GetHealth() return self.health end
    function unit:GetMaxHealth() return self.maximum end
    function unit:SetHealth(value) fail_setter("SetHealth"); self.health = value end
    function unit:SetBaseMaxHealth(value) fail_setter("SetBaseMaxHealth"); self.maximum = value end
    function unit:SetMaxHealth(value) fail_setter("SetMaxHealth"); self.maximum = value end
    function unit:SetBaseDamageMin(value) fail_setter("SetBaseDamageMin"); self.damage_min = math.floor(value) end
    function unit:SetBaseDamageMax(value) fail_setter("SetBaseDamageMax"); self.damage_max = math.floor(value) end
    function unit:GetBaseDamageMin() return self.damage_min end
    function unit:GetBaseDamageMax() return self.damage_max end
    function unit:GetAverageTrueAttackDamage() return (self.damage_min + self.damage_max) * 0.5 end
    function unit:SetPhysicalArmorBaseValue(value) self.armor = value end
    function unit:GetPhysicalArmorValue() return self.armor or 0 end
    function unit:SetBaseMagicalResistanceValue() end
    function unit:SetBaseAttackTime() end
    function unit:SetAttackCapability() end
    unit.Script_SetAttackRange = forbidden("Script_SetAttackRange (not available on npc_dota_creature)")
    function unit:SetMoveCapability() end
    function unit:SetAcquisitionRange() end
    function unit:SetDeathXP(value) assert(value == 0, "probe enabled native XP"); self.death_xp = value end
    function unit:SetMinimumGoldBounty(value) assert(value == 0, "probe enabled minimum bounty"); self.min_gold = value end
    function unit:SetMaximumGoldBounty(value) assert(value == 0, "probe enabled maximum bounty"); self.max_gold = value end
    function unit:SetIdleAcquire(value) assert(value == false, "probe enabled auto acquisition") end
    function unit:SetDayTimeVisionRange() end
    function unit:SetNightTimeVisionRange() end
    function unit:SetBaseHealthRegen() end
    function unit:Stop() end
    function unit:AddNoDraw() end
    function unit:CalculateStatBonus() end
    function unit:HasModifier(modifier_name) return self.modifiers[modifier_name] ~= nil end
    function unit:FindModifierByName(modifier_name) return self.modifiers[modifier_name] end
    function unit:AddNewModifier(caster, ability, modifier_name, parameters)
        assert(modifier_name == "modifier_survival_large_attack_native_probe", "probe attached a gameplay modifier")
        assert(ability == nil, "probe acquired a gameplay ability")
        local definition = assert(_G[modifier_name], "native probe modifier was not loaded")
        local modifier = setmetatable({}, { __index = definition })
        function modifier:GetParent() return unit end
        function modifier:GetCaster() return caster end
        function modifier:IsNull() return unit.null == true end
        function modifier:SetStackCount(value) self.stack = value end
        function modifier:GetStackCount() return self.stack or 0 end
        self.modifiers[modifier_name] = modifier
        if modifier.OnCreated then modifier:OnCreated(parameters or {}) end
        return modifier
    end
    function unit:PerformAttack(victim)
        attacks = attacks + 1
        if failures.attack then error("injected PerformAttack failure") end
        local amount = self:GetAverageTrueAttackDamage()
        for _, modifier in pairs(self.modifiers) do
            if modifier.OnAttackRecord then modifier:OnAttackRecord({attacker=self,target=victim,record=attacks}) end
            if modifier.GetModifierPreAttack_CriticalStrike then
                local critical = modifier:GetModifierPreAttack_CriticalStrike({target=victim})
                amount = amount * math.max(1, (tonumber(critical) or 100) / 100)
            end
            if modifier.GetModifierDamageOutgoing_Percentage then
                amount = amount * (1 + (tonumber(modifier:GetModifierDamageOutgoing_Percentage()) or 0) / 100)
            end
        end
        local result = native_damage(self, victim, amount, DOTA_DAMAGE_CATEGORY_ATTACK)
        for _, modifier in pairs(self.modifiers) do
            if modifier.OnAttackLanded then
                modifier:OnAttackLanded({attacker=self,target=victim,record=attacks,damage=result})
            end
        end
        return result
    end
    return unit
end
ApplyDamage = function(input)
    applications = applications + 1
    if failures.apply then error("injected ApplyDamage failure") end
    return native_damage(input.attacker, input.victim, input.damage, DOTA_DAMAGE_CATEGORY_SPELL)
end
UTIL_Remove = function(unit)
    assert(unit and not unit.null, "probe tried to remove a missing/already removed handle")
    unit.null = true
    removed, alive = removed + 1, alive - 1
end

local function isolation()
    assert(package.loaded["combat/endless_stat_projection"] == cached_projection,
        "manual probe replaced the production projection module")
    assert(mode.native_filter == original_filter, "manual probe replaced the engine filter")
    assert(package.loaded["combat/damage_filter_service"] == cached_filter
        and package.loaded["config/armor_balance"] == cached_armor,
        "manual probe changed an existing production module")
    assert(package.loaded["combat/damage_service"]==damage_service and repository.debug_snapshot().pending_records==0,
        "manual probe changed its live service or stranded a logical transaction")
    assert(alive == 0 and removed == created, "manual probe stranded native units")
    assert(max_alive <= 2, "manual probe accumulated units between cases")
    for _, unit in ipairs(units) do
        assert(unit.survival_hero_id == nil and unit.survival_is_wave_monster == nil
            and unit.survival_is_challenge_monster == nil and unit.survival_monster_corpse == nil,
            "manual probe registered a unit in a gameplay domain")
        assert(unit.survival_player_id == nil or unit.survival_player_id == -1,
            "manual probe assigned a player")
        assert(unit.survival_large_attack_native_capture == nil,
            "manual probe retained the temporary capture on a retired unit")
        for _, modifier in pairs(unit.modifiers) do
            if modifier.OnTakeDamage then
                -- A late native broadcast after finally cleanup must not
                -- resurrect a capture or dereference a missing callback list.
                modifier:OnTakeDamage({attacker=unit,unit=unit,damage=1,
                    damage_category=DOTA_DAMAGE_CATEGORY_ATTACK})
                assert(unit.survival_large_attack_native_capture == nil)
            end
        end
    end
end

local manual = require("tests/manual_large_attack_native")
assert(type(manual) == "table" and type(manual.run) == "function", "manual run API unavailable")
assert(created == 0 and create_attempts == 0 and links == 0 and attacks == 0 and applications == 0,
    "requiring the manual probe had native side effects")
assert(_G.modifier_survival_large_attack_native_probe == nil, "requiring the probe loaded its native modifier")

tools_mode = false
local disabled = manual.run()
assert(disabled.ok == false and disabled.status == "rejected" and created == 0 and links == 0,
    "non-Tools run acquired native state")
tools_mode, server = true, false
disabled = manual.run()
assert(disabled.ok == false and disabled.status == "rejected" and created == 0 and links == 0,
    "client run acquired native state")
server = true

for _, failure in ipairs({{dofile=true}, {link=true}, {shared_projection=true}, {no_projection=true}}) do
    reset(failure)
    local ok, failed = pcall(manual.run)
    assert(ok and failed.ok == false and #failed.rows == 0,
        "native preload errors must be reported without acquiring units or throwing")
    assert(failed.status == ((failure.shared_projection or failure.no_projection) and "unsupported" or "fail"),
        "native preload rejection did not preserve its status")
    assert(created == 0 and #messages == 1 and messages[1]:find("result=FAILED", 1, true),
        "preload rejection must print a bounded failed summary before any unit creation")
    isolation()
end

reset()
local result = manual.run()
assert(result.ok == true and result.status == "pass" and #result.rows == 12, result.reason)
assert(created == 24 and removed == 24 and max_alive == 2,
    "12 native cases must create/retire exactly one isolated pair each: created=" .. created)
assert(attacks == 8 and applications == 4, "native basic/20x/ApplyDamage case counts changed")
for _, row in ipairs(result.rows) do
    assert(row.status == "pass" and row.event_count == 1 and row.cleanup_failures == 0,
        "a native pair was not measured and retired exactly once")
    assert(row.event.damage_category == (row.kind == "logical_deal"
        and DOTA_DAMAGE_CATEGORY_SPELL or DOTA_DAMAGE_CATEGORY_ATTACK),
        "probe changed the actual operation's callback category")
    assert(row.event.inflictor_entindex == -1, "native fixture attached a gameplay ability")
end
for _, unit in ipairs(units) do
    assert(unit.death_xp == 0 and unit.min_gold == 0 and unit.max_gold == 0,
        "successful fixture enabled native rewards")
end
isolation()

reset({no_filter_category=true,native_precision=true})
local native_keys_missing = manual.run({external_isolated_filter=true})
assert(native_keys_missing.ok and #native_keys_missing.rows==12,
    "genuine logical Deal must remain unscaled when native filter omits category and inflictor")
assert(native_keys_missing.filter_replaced==true and messages[#messages]:find("filter_replaced=true",1,true),
    "externally isolated native callback must be accurately labelled")
for _, row in ipairs(native_keys_missing.rows) do
    if row.kind=="logical_deal" then
        assert(row.delivery=="damage_service.Deal" and row.transaction_id~=nil and applications==4,
            "logical cases must use the real initialized service/adapter/native ApplyDamage")
        assert(row.logical_result_damage>0 and row.event.damage_category==DOTA_DAMAGE_CATEGORY_SPELL,
            "logical transaction must retain its real native callback and result")
    end
end
isolation()

reset({native_precision=true})
local quantized = manual.run()
assert(quantized.ok and #quantized.rows == 12,
    "representable scaled damage must survive native integer/float HP quantization")
for _, row in ipairs(quantized.rows) do
    if row.target:find("scaled_", 1, true) == 1 then
        assert(row.logical_health == row.logical_attack * 1e4,
            "scaled probe health must track attack to retain observable native HP loss")
        assert(row.expected_filtered > 800 and row.event.damage > 0,
            "scaled native capacity test returned to sub-point damage")
        assert(math.abs(row.event.damage - row.expected_filtered) <= 16,
            "probe accepted damage outside the native HP precision tolerance")
        assert(not row.killed and row.final_health < row.native_health,
            "scaled precision fixture must actually lose HP without dying")
    else
        assert(row.killed and row.event.damage == row.native_health,
            "ordinary overkill must retain the native clamped callback and kill outcome")
    end
end
isolation()

for _, failure in ipairs({
    { create = 2 }, { setter = "SetBaseDamageMin" }, { setter = "SetHealth" },
    { attack = true }, { apply = true }, { no_callback = true }, { wrong_callback = true },
    { owner = true }, { owner_entity = true }, { position = true },
}) do
    reset(failure)
    local failed = manual.run()
    assert(failed.ok == false and #failed.rows >= 1, "injected failure was reported as success")
    local expected_status = (failure.no_callback or failure.wrong_callback) and "unsupported" or "fail"
    assert(failed.status == expected_status, "injected failure did not preserve the reason/category")
    assert(created < 24, "manual probe continued after an unsupported/failing case")
    isolation()
end
reset()
local recovered = manual.run({projection_path="combat/endless_stat_projection"})
assert(recovered.ok and #recovered.rows == 12, "a previous failure left the probe running")
isolation()
output("MANUAL_LARGE_ATTACK_NATIVE_FIXTURE_PASS inert require/Tools guards, 12 pairs, original package/filter, real modifier callbacks and fault cleanup")
