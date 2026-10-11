-- Exercise the real wave spawn function with isolated engine/service fixtures.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(t) return t end
LinkLuaModifier = function() end
IsServer = function() return true end
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 2
DOTA_UNIT_CAP_MOVE_GROUND, DOTA_TEAM_BADGUYS = 1, 3
MODIFIER_EVENT_ON_DEATH, MODIFIER_PROPERTY_ATTACK_RANGE_BONUS = 3, 4
local noop = function() end
package.loaded["systems/enemy_attack_observer"] = { is_ready = function() return true end }
package.loaded["core/team_alignment"] = { enforce = noop }
package.loaded["systems/wall_navigation_service"] = {}
local ai = require("modifiers/modifier_enemy_wall_ai")
local rows = require("config/generated/wave_definitions").rows
local definitions = require("config/generated/monster_archetypes")
local marker = { GetAbsOrigin = function() return { x = 0, y = 0, z = 0 } end }
local units, sequence = {}, 0
local suppress_capability_getter, capability_override
local function unit()
    local u = { index = #units + 1, modifiers = {}, attack_capability = 2 }
    function u:IsNull() return false end
    function u:entindex() return self.index end
    function u:GetAttackCapability() return capability_override or self.attack_capability end
    if suppress_capability_getter then u.GetAttackCapability = nil end
    function u:SetAttackCapability(value)
        assert(not self.modifiers.modifier_enemy_wall_ai,
            "classification must be complete before wall AI declares")
        sequence = sequence + 1
        self.attack_capability, self.capability_sequence = value, sequence
    end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:FindAbilityByName() return nil end
    function u:AddNewModifier(_, _, name, params)
        if name ~= "modifier_enemy_wall_ai" then self.modifiers[name] = {}; return end
        assert(self.capability_sequence and self.hero_visual_complete,
            "opt-out cannot be captured before final capability/appearance")
        assert(self.survival_wave_movement_type ~= nil)
        local m = setmetatable({ GetParent = function() return self end,
            StartIntervalThink = noop, SetHasCustomTransmitterData = noop }, { __index = ai })
        -- Match the earliest possible native declaration order.
        m.declarations = m:DeclareFunctions()
        m:OnCreated(params)
        self.modifiers[name] = m
        return m
    end
    for _, name in ipairs({ "SetBaseMaxHealth", "SetMaxHealth", "SetHealth",
        "SetBaseDamageMin", "SetBaseDamageMax", "SetPhysicalArmorBaseValue",
        "SetBaseMoveSpeed", "SetBaseAttackTime", "Script_SetAttackRange",
        "SetModelScale", "SetModel", "SetOriginalModel", "SetMoveCapability", "AddAbility" }) do
        u[name] = noop
    end
    units[#units + 1] = u
    return u
end
local dependencies = {
    ["core/event_bus"] = { emit = noop },
    ["core/events"] = { MONSTER_SPAWNED = "spawned" },
    ["core/team_alignment"] = { enforce = noop },
    ["config/generated/monster_archetypes"] = definitions,
    ["config/generated/wave_definitions"] = { rows = rows },
    ["config/generated/archive_challenge_rules"] = { by_id = { default = {} } },
    ["systems/monster_navigation_policy"] = require("systems/monster_navigation_policy"),
    ["systems/wave_monster_collision"] = require("systems/wave_monster_collision"),
    ["systems/wave_spawn_sequence"] = require("systems/wave_spawn_sequence"),
    ["config/monster_visual_config"] = { resolve = function() return { model_path = "cosmetic.vmdl" } end },
    ["systems/monster_visual_service"] = { apply = function(u)
        assert(u.survival_wave_skip_contact_range_bonus == nil)
        u.cosmetic_complete = true
    end },
    ["systems/monster_hero_visual_service"] = { apply = function(u)
        assert(u.survival_wave_skip_contact_range_bonus == nil)
        u.hero_visual_complete = true
    end },
    ["systems/monster_hull_scale"] = { apply = function() return true end },
    ["systems/monster_corpse_lifecycle_service"] = { track = noop },
    ["systems/wave_native_attack_cap"] = { can_omit = function() return false end },
}
local env = setmetatable({
    require = function(name) return dependencies[name] or {} end,
    GetGroundHeight = function() return 0 end,
    CreateUnitByName = function() return unit() end,
    FindClearSpaceForUnit = function(u)
        assert(u.modifiers.modifier_enemy_wall_ai, "AI policy captured before placement")
    end,
}, { __index = _G })
local chunk = assert(loadfile("scripts/vscripts/systems/wave_system.lua"))
setfenv(chunk, env)
local wave = chunk()
local function find_function(module, wanted)
    local visited = {}
    local function visit(fn)
        if type(fn) ~= "function" or visited[fn] then return end
        visited[fn] = true
        for index = 1, math.huge do
            local name, value = debug.getupvalue(fn, index)
            if not name then break end
            if name == wanted then return value end
            local found = visit(value)
            if found then return found end
        end
    end
    for _, fn in pairs(module) do local result = visit(fn); if result then return result end end
    error("missing fixture upvalue " .. wanted)
end
local function set_upvalue(fn, wanted, value)
    for index = 1, math.huge do
        local name = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, index, value); return end
    end
    error("missing fixture state " .. wanted)
end
local spawn = find_function(wave, "spawn_one")
set_upvalue(spawn, "monster_spawn_marker", marker)
set_upvalue(spawn, "state", { pending = 9999, spawned = 0, alive = 0 })
set_upvalue(spawn, "publish", noop)
local batches, wave15, retained, wave15_melee = 0, 0, 0, 0
for _, row in ipairs(rows) do
    if row.enabled ~= false then
        local definition = assert(definitions.by_id[row.archetype_id])
        spawn(row, 0, row.wave_number, 1)
        local u = units[#units]
        local expected = definition.attack_type == "ranged"
        local m = u.modifiers.modifier_enemy_wall_ai
        assert(u.survival_wave_skip_contact_range_bonus == expected, row.wave_id)
        assert(m.contact_range_property_enabled == not expected, row.wave_id)
        assert(#m.declarations == (expected and 1 or 2), row.wave_id)
        assert(u.cosmetic_complete and u.hero_visual_complete, row.wave_id)
        if not expected then retained = retained + 1 end
        if row.difficulty_id == "N1" and row.wave_number == 15 then
            if not expected then wave15_melee = wave15_melee + row.monster_count end
            wave15 = wave15 + row.monster_count
        end
        batches = batches + 1
    end
end
assert(batches > 100 and retained > 0 and wave15 == 61 and wave15_melee > 0,
    "wave15 flying melee must keep contact reach compensation")

-- Unknown/missing native capability must not be optimized merely because the
-- configuration says ranged. Movement labels never decide native reach.
for _, case in ipairs({
    { "unknown", false, nil, true },
    { "ground", true, nil, false },
    { "ground", false, 0, false },
    { "flying", false, DOTA_UNIT_CAP_MELEE_ATTACK, false },
    { "flying", false, DOTA_UNIT_CAP_RANGED_ATTACK, true },
}) do
    definitions.by_id.range_policy_fixture = { unit_name = "fixture", model_path = "fixture.vmdl",
        movement_type = case[1], attack_type = "ranged" }
    suppress_capability_getter, capability_override = case[2], case[3]
    spawn({ archetype_id = "range_policy_fixture", health = 100, attack = 1 }, 0, 1, 1)
    local u = units[#units]
    assert(u.survival_wave_skip_contact_range_bonus == case[4])
    assert(u.modifiers.modifier_enemy_wall_ai.contact_range_property_enabled == not case[4])
end
definitions.by_id.range_policy_fixture = nil
suppress_capability_getter, capability_override = false, nil

-- Building challenge bosses are a separate spawn path and keep compensation,
-- including ranged/flying variants. Their callback lifecycle is unchanged.
set_upvalue(wave.spawn_challenge_monster, "wave_channels", { [0] = { marker = marker } })
for _, movement in ipairs({ "ground", "flying" }) do
    for _, capability in ipairs({ "melee", "ranged" }) do
        local u = assert(wave.spawn_challenge_monster({ health = 100, attack = 1 }, {
            unit_name = "test_boss", model_path = "boss.vmdl", enabled = true,
            movement_type = movement, attack_type = capability,
        }, 0))
        assert(u.survival_wave_skip_contact_range_bonus == nil)
        assert(u.modifiers.modifier_enemy_wall_ai.contact_range_property_enabled)
    end
end
print("ENEMY_RANGE_SPAWN_POLICY_PASS batches=" .. batches .. " retained=" .. retained
    .. " wave15_units=" .. wave15 .. " wave15_melee=" .. wave15_melee
    .. " final stats/visuals precede declaration; challenge fallback")
