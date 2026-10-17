-- Four-owner offline integration stress. No production module is replaced.
-- Engine entities, item transport and visual engine API are the only mocks.
-- Oracle values come from authored data plus explicit ownership equations.
package.path = "scripts/vscripts/?.lua;" .. package.path
local output_dir, phase_name, source_root = "output/four_player_stress_20261012", "baseline", nil
local positionals, index = {}, 1
while index <= #arg do
    if arg[index] == "--phase" then index = index + 1; phase_name = assert(arg[index], "missing --phase")
    elseif arg[index] == "--output" then index = index + 1; output_dir = assert(arg[index], "missing --output")
    elseif arg[index] == "--source-root" then index = index + 1; source_root = assert(arg[index], "missing --source-root")
    else positionals[#positionals + 1] = arg[index] end
    index = index + 1
end
output_dir, phase_name = positionals[1] or output_dir, positionals[2] or phase_name
local json = require("core/json_encoder")
local bus, events = require("core/event_bus"), require("core/events")
local now, next_entity = 0, 10000
local entities, engine_log, engine_errors, net_tables, mine_publications = {}, {}, {}, {}, {}
local active_case
local original_print = print
print = function(...)
    local parts = {}; for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    local line = table.concat(parts, " ")
    engine_log[#engine_log + 1] = line
    if line:find("handler error", 1, true) or line:find("task failed", 1, true) then
        engine_errors[#engine_errors + 1] = { case_id = active_case, error = line }
    end
end
function class(parent)
    local c = {}; c.__index = c
    return setmetatable(c, { __index = parent, __call = function(t, ...) local x = setmetatable({}, t); if x.constructor then x:constructor(...) end; return x end })
end
function IsServer() return true end
function LinkLuaModifier() end
LUA_MODIFIER_MOTION_NONE = 0
DOTA_MAX_TEAM_PLAYERS, DOTA_TEAM_GOODGUYS = 4, 2
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 0, 1, 2
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_ALL, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER = 3, 55, 0, 0
local vector_mt = {}
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector_mt) end
vector_mt.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector_mt.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector_mt.__mul = function(a, b) if type(a) == "number" then a, b = b, a end; return Vector(a.x * b, a.y * b, a.z * b) end
vector_mt.__index = { Length2D = function(v) return math.sqrt(v.x * v.x + v.y * v.y) end,
    Normalized = function(v) local l = math.max(1, math.sqrt(v.x * v.x + v.y * v.y)); return Vector(v.x / l, v.y / l, 0) end }
GameRules = { GetGameTime = function() return now end, GetGameModeEntity = function() return { IsNull = function() return false end } end }
PlayerResource = { IsValidPlayerID = function(_, id) return id >= 0 and id <= 3 end,
    GetSteamAccountID = function(_, id) return 990000100 + id end, GetTeam = function() return 2 end,
    GetPlayer = function(_, id) return { id = id } end }
CustomNetTables = { SetTableValue = function(_, table_id, key, value) net_tables[table_id .. ":" .. key] = value end }
CustomGameEventManager = { Send_ServerToPlayer = function() end }
Convars = { RegisterConvar = function() end, RegisterCommand = function() end, GetStr = function() return "" end,
    GetBool = function() return false end, GetInt = function() return 0 end }
GridNav = { IsTraversable = function() return true end, IsBlocked = function() return false end }
function GetGroundHeight() return 128 end
function GetGroundPosition(v) return Vector(v.x, v.y, 128) end
function FindClearSpaceForUnit(u, v) u.position = v end
function FindUnitsInRadius() return {} end
function RandomFloat(a, b) return (a + b) / 2 end
function RandomInt(a) return a end
function RollPercentage() return false end
function PrecacheResource() end
function PrecacheUnitByNameAsync(_, callback) if callback then callback() end end
function PrecacheUnitByNameSync() end
function EmitSoundOn() end
function StopSoundOn() end
function UTIL_Remove(u) u.null = true end
function EntIndexToHScript(id) return entities[id] end
ParticleManager = { CreateParticle = function() return 1 end, DestroyParticle = function() end,
    ReleaseParticleIndex = function() end, SetParticleControl = function() end,
    SetParticleControlEnt = function() end }
Entities = { FindByName = function() return nil end, FindAllByClassname = function() return {} end }

local function modifier(unit, name, params)
    local real_paths = { modifier_research_technology = "modifiers/modifier_research_technology",
        modifier_weapon_stat_projection = "modifiers/modifier_weapon_stat_projection",
        modifier_equipment_effects = "modifiers/modifier_equipment_effects",
        modifier_lumberjack_ai = "modifiers/modifier_lumberjack_ai" }
    if real_paths[name] then require(real_paths[name]) end
    local actual_class = real_paths[name] and rawget(_G, name) or nil
    local m = { stack = 0, params = params or {}, values = {}, name = name }
    function m:IsNull() return self.null == true end
    function m:GetStackCount() return self.stack end
    function m:SetStackCount(v) self.stack = v end
    function m:SetHealthBonus(v) self.stack = v end
    function m:SetProjectileSpeedBonus(v) self.stack = v end
    function m:GetParent() return unit end
    function m:GetCaster() return unit end
    function m:StartIntervalThink() end
    function m:SendBuffRefreshToClients() end
    function m:ForceRefresh() if actual_class and actual_class.OnRefresh then actual_class.OnRefresh(self) end end
    function m:Destroy() self.null = true; unit.modifiers[name] = nil end
    function m:GetModifierFixedAttackRate() return nil end
    setmetatable(m, { __index = function(_, key)
        if actual_class and actual_class[key] then return actual_class[key] end
        if key:match("^Set") then return function(self, ...) self.values[key] = { ... } end end
    end })
    if params and params.health_bonus then m.stack = params.health_bonus end
    if params and params.projectile_speed_bonus then m.stack = params.projectile_speed_bonus end
    return m
end
local function entity(name, owner, position)
    next_entity = next_entity + 1
    local u = { id = next_entity, name = name, owner = owner or 0, position = position or Vector(0, 0, 128),
        health = 1000, maximum = 1000, native_maximum = 1000, min_damage = 0, max_damage = 0,
        interval = 1, modifiers = {}, abilities = {}, inventory = {}, writes = 0, level = 1 }
    function u:IsNull() return self.null == true end
    function u:IsAlive() return not self.null and not self.dead end
    function u:entindex() return self.id end
    function u:GetUnitName() return self.name end
    function u:GetPlayerOwnerID() return self.owner end
    function u:GetTeamNumber() return 2 end
    function u:GetAbsOrigin() return self.position end
    function u:GetHullRadius() return 24 end
    function u:GetLevel() return self.level end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(v) self.health = v; self.writes = self.writes + 1 end
    function u:SetBaseMaxHealth(v) self.native_maximum = v end
    function u:SetMaxHealth(v) self.maximum = v end
    function u:SetBaseDamageMin(v) self.min_damage = v; self.writes = self.writes + 1 end
    function u:SetBaseDamageMax(v) self.max_damage = v; self.writes = self.writes + 1 end
    function u:GetBaseDamageMin() return self.min_damage end
    function u:GetBaseDamageMax() return self.max_damage end
    function u:SetBaseAttackTime(v) self.interval = v; self.writes = self.writes + 1 end
    function u:GetBaseAttackTime() return self.interval end
    function u:SetPhysicalArmorBaseValue(v) self.armor = v end
    function u:GetPhysicalArmorValue() return self.armor or 0 end
    function u:GetPhysicalArmorBaseValue() return self.armor or 0 end
    function u:SetBaseHealthRegen(v) self.regen = v end
    function u:GetHealthRegen() return self.regen or 0 end
    function u:GetMoveCapability() return 1 end
    function u:SetAttackCapability(v) self.attack_capability = v end
    function u:GetAttackCapability() return self.attack_capability end
    function u:GetAttackSpeed() return 100 end
    function u:Script_SetAttackRange(v) self.range = v end
    function u:GetAttackRange() return self.range or 800 end
    function u:SetProjectileSpeed(v) self.projectile_speed = v end
    function u:GetProjectileSpeed() local m = self.modifiers.modifier_survival_hero_projectile_speed; return (self.projectile_speed or 300) + (m and m.stack or 0) end
    function u:SetControllableByPlayer(v) self.owner = v end
    function u:HasModifier(n) return self.modifiers[n] ~= nil end
    function u:FindModifierByName(n) return self.modifiers[n] end
    function u:RemoveModifierByName(n) self.modifiers[n] = nil end
    function u:AddNewModifier(_, _, n, p)
        local m = modifier(self, n, p); self.modifiers[n] = m
        if m.OnCreated then m:OnCreated(p or {}) end
        return m
    end
    function u:CalculateStatBonus()
        local m = self.modifiers.modifier_survival_hero_base_health
        self.maximum = self.native_maximum + (m and m.stack or 0)
        self.health = math.min(self.maximum, self.health)
    end
    function u:FindAbilityByName(n) return self.abilities[n] end
    function u:AddAbility(n)
        local a = { name = n, level = 0 }; function a:GetLevel() return self.level end
        function a:SetLevel(v) self.level = v end; function a:IsNull() return false end
        function a:GetAbilityName() return self.name end
        function a:SetHidden(v) self.hidden = v end; function a:IsHidden() return self.hidden == true end
        function a:SetActivated(v) self.active = v end; function a:IsActivated() return self.active ~= false end
        function a:SetAbilityTextureName(v) self.texture = v end
        self.abilities[n] = a; return a
    end
    function u:RemoveAbility(n) self.abilities[n] = nil end
    function u:GetAbilityCount() local c = 0; for _ in pairs(self.abilities) do c = c + 1 end; return c end
    function u:GetAbilityByIndex(index) local c = 0; for _, a in pairs(self.abilities) do if c == index then return a end; c = c + 1 end end
    function u:AddItem(item) self.inventory[#self.inventory + 1] = item; return item end
    function u:RemoveItem(item) for i, v in ipairs(self.inventory) do if v == item then table.remove(self.inventory, i); break end end end
    function u:GetItemInSlot(slot) return self.inventory[slot + 1] end
    function u:IsBuilding() return self.survival_building_id ~= nil end
    function u:IsRealHero() return self.hero == true end
    function u:IsHero() return self.hero == true end
    function u:IsIllusion() return false end
    function u:IsClone() return false end
    function u:GetOwnerEntity() return nil end
    setmetatable(u, { __index = function(_, key)
        if key:match("^Set") or key:match("^Emit") then return function() end end
    end })
    entities[u.id] = u
    return u
end
function CreateUnitByName(name, position, _, owner) return entity(name, owner and owner.owner or 0, position) end
function CreateItem(name, owner) local item = entity(name, owner and owner.owner or 0); function item:GetAbilityName() return self.name end; return item end

-- All services below are the real production implementations, including scheduler.
if source_root then
    package.loaded["systems/building_health_projection"] = dofile(source_root
        .. "/scripts/vscripts/systems/building_health_projection.lua")
end
local scheduler = require("core/scheduler")
local profiles = require("systems/player_profile_service")
local technology = require("systems/technology_stat_manager")
local permanent = require("systems/permanent_reward_effect_service")
local resources = require("systems/resource_system")
local inventory = require("systems/content_inventory_service")
local equipment = require("systems/weapon_equipment_service")
local weapon_growth = require("systems/weapon_growth_service")
local function service_source(name)
    if not source_root then return require(name) end
    local module = dofile(source_root .. "/scripts/vscripts/" .. name .. ".lua")
    package.loaded[name] = module
    return module
end
local heroes = service_source("systems/hero_combat_stat_service")
local upgrades = service_source("systems/building_upgrade_system")
local workers = require("systems/worker_system")
local gold_mines = require("systems/gold_mine_system")
local definitions = require("config/generated/technology_definitions")
local buildings_config = require("config/buildings_config")
local tower_base = require("config/generated/arrow_tower_base")
local hero_definitions = require("config/generated/hero_definitions")
local weapon_definitions = require("config/generated/weapon_definitions")
local training_definitions = require("config/generated/training_definitions")
local rules = require("config/global_rules")
local resource_config = require("config/resources_config")
local phase_guard = require("systems/gameplay_phase_guard")
local map_matrix = { { 1, 9, 17, 24 }, { 3, 12, 20, 30 }, { 7, 16, 28, 34 }, { 8, 18, 25, 32 }, { 10, 19, 26, 33 } }
local seeds = { 12011, 12037, 12071, 12109, 12143 }
local difficulty_matrix = { 1, 3, 6, 9, 10 }
local operation_order = { { 0, 1, 2, 3 }, { 3, 2, 1, 0 }, { 1, 3, 0, 2 }, { 2, 0, 3, 1 }, { 3, 0, 2, 1 } }
local current_profiles, building_states, summoned_handles = {}, {}, {}
local provider = { init = function() end, resolve_account_id = function(id) return tostring(990000100 + id) end,
    fetch_snapshot = function(account, success) for _, p in pairs(current_profiles) do if p.account_id == account then success(p); return end end end,
    persist_save = function() return true end }

local report = { suite = "four_player_technology_stress", date = "2026-10-12", phase = phase_name, source_root = source_root,
    engine_boundary = "offline handles, items, visuals; all production modules retained",
    oracle = { source = "CSV-generated configuration values and independent ownership equations",
        personal = { "map_level_wall_health", "wall_stats", "tower_stats", "lumberjack_stats", "hero_stats", "resources", "inventory" },
        shared = { "team_hero_wall_armor_bonus", "enemy_initial_armor_reduction" },
        matrix = { "mixed_profiles_duplicate_initialization", "high_frequency_interleaving", "fractional_income_growth", "equipment_and_replacement_inheritance", "stale_account_duplicate_updates" } },
    technology_scope_audit = {}, rounds = {}, bugs = {}, totals = { checks = 0, passed = 0, failed = 0 } }
report.oracle.shared_scope_basis = "data/csv/玩家档案系统/player_gameplay_stats.csv:95-96 explicitly targets all online player heroes/walls and all map enemies"
report.oracle.native_wall_health_math = "floor((base * 100 + base * integer_percentage + flat * 100) / 100), with exact known 3000/147/131 -> 7541 HP; no widened tolerance"
report.difficulty_scope = "Global match difficulty labels are coordinated by the overall suite; personal permanent map_level is independently applied by the real profile reducer/effect consumers."
local bug_by_key = {}
local current_round
local function check(key, actual, expected, evidence)
    local good = type(actual) == type(expected) and (type(actual) ~= "number" and actual == expected
        or type(actual) == "number" and math.abs(actual - expected) <= 0.00001)
    current_round.checks = current_round.checks + 1; report.totals.checks = report.totals.checks + 1
    if good then current_round.passed = current_round.passed + 1; report.totals.passed = report.totals.passed + 1
    else
        current_round.failed = current_round.failed + 1; report.totals.failed = report.totals.failed + 1
        local failure = { check = key, actual = actual == nil and "nil" or actual, expected = expected,
            evidence = evidence or "", case_id = active_case }
        current_round.failures[#current_round.failures + 1] = failure
        local grouping = key:gsub("p%d+", "p*"):gsub("tick%d+", "tick*"):gsub("^opening_", "units_"):gsub("^final_", "units_"):gsub("^tick%*_", "units_"):gsub("_%d+$", "_*")
        local bug = bug_by_key[grouping]
        if not bug then bug = { id = "TECH-" .. tostring(#report.bugs + 1), key = grouping, count = 0, first = failure }; bug_by_key[grouping] = bug; report.bugs[#report.bugs + 1] = bug end
        bug.count = bug.count + 1
    end
end
local function request(event, payload) return bus.request(event, payload) or {} end
local function wallet(id) return request(events.RESOURCE_GET_REQUEST, { player_id = id }) end
local function projection(id) return request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, { player_id = id }).totals or {} end
local function hero_snapshot(id) return request(events.HERO_COMBAT_STATS_GET_REQUEST, { player_id = id }).snapshot or {} end
local function shallow(t) local x = {}; for k, v in pairs(t or {}) do x[k] = v end; return x end
local by_group = {}
for _, row in ipairs(definitions.rows) do by_group[row.technology_group] = by_group[row.technology_group] or {}; by_group[row.technology_group][row.level] = row end
local groups_by_effect = {}
local field_by_effect = {
    wall_health_pct = { "wall", "health_bonus_pct" }, wall_health_pct_advanced = { "wall", "technology_health_bonus_pct" },
    super_wall_health_pct = { "wall", "technology_health_bonus_pct" }, super_wall_armor_flat = { "wall", "technology_armor_bonus" },
    tower_attack_flat = { "tower", "attack_flat" }, tower_attack_flat_advanced = { "tower", "attack_flat" }, super_tower_attack_flat = { "tower", "attack_flat" },
    super_tower_crit_pct = { "tower", "attack_bonus_pct" }, super_tower_attack_range = { "tower", "attack_range_bonus" },
    lumberjack_attack_growth = { "lumberjack", "attack_gain_per_attack" }, lumberjack_attack_speed_pct = { "lumberjack", "attack_speed_bonus_pct" },
    lumberjack_attack_interval_flat = { "lumberjack", "attack_interval_flat" }, lumberjack_wood_per_hit = { "lumberjack", "wood_per_hit_bonus" },
    lumberjack_wood_per_hit_advanced = { "lumberjack", "wood_per_hit_bonus" }, lumberjack_critical_chance_pct = { "lumberjack", "critical_chance_pct" },
    lumberjack_attack_armor_reduction = { "lumberjack", "armor_reduction_per_attack" },
    hero_attack_flat = { "hero", "attack_flat" }, hero_final_damage_pct = { "hero", "final_damage_bonus_pct" },
    hero_attack_armor_reduction = { "hero", "armor_reduction_per_attack" } }
for _, row in ipairs(definitions.rows) do if row.enabled ~= false and row.level == 1 then
    groups_by_effect[row.effect_type] = row.technology_group
    report.technology_scope_audit[#report.technology_scope_audit + 1] = { effect_type = row.effect_type, technology_group = row.technology_group,
        authored_description = row.notes or row.display_name, expected_scope = "all_matching_units_of_purchasing_player",
        scope_basis = "docs/ai/archive/2026-08-24-pre-task-registry-current-task.md:1235 (independent player technology); gold-mine sharing is same-owner multi-mine",
        consumer = row.effect_type:match("^mine_") and "systems/gold_mine_system" or "systems/technology_stat_manager",
        total_or_delta = row.technology_group == "advanced_lumberjack_speed" and "accumulate_each_level" or "total_at_level" }
end end
local function effect_value(levels, effect)
    local group = groups_by_effect[effect]; if not group then return 0 end
    local level = levels[group] or 0
    if group == "advanced_lumberjack_speed" then local n = 0; for l = 1, level do n = n + tonumber(by_group[group][l].effect_value) end; return n end
    return tonumber((by_group[group][level] or {}).effect_value) or 0
end
local function tech_levels(id, round, bump)
    local result = {}
    for _, effect in ipairs({ "wall_health_pct", "wall_health_pct_advanced", "super_wall_health_pct", "super_wall_armor_flat",
        "tower_attack_flat", "tower_attack_flat_advanced", "super_tower_attack_flat", "super_tower_crit_pct", "super_tower_attack_range",
        "lumberjack_attack_growth", "lumberjack_attack_speed_pct", "lumberjack_attack_interval_flat", "lumberjack_wood_per_hit",
        "lumberjack_wood_per_hit_advanced", "lumberjack_critical_chance_pct", "lumberjack_attack_armor_reduction",
        "hero_attack_flat", "hero_final_damage_pct", "hero_attack_armor_reduction", "mine_efficiency_percent", "mine_crit_percent" }) do
        local g = groups_by_effect[effect]
        if g then local l = 1 + ((id * 3 + round + (bump or 0)) % 4); if by_group[g][l] then result[g] = l else result[g] = 1 end end
    end
    return result
end
local function profile(id, round)
    local s = { initial_wood = 1000000 + id * 17000 + round * 100, initial_gold = 100000 + id * 1100,
        hero_initial_gold = 37 + id * 11, initial_population_cap = 1000 + id * 100,
        wood_per_second = (id + 1) * 0.25, gold_per_second = (4 - id) * 0.25,
        map_level = map_matrix[round][id + 1], wall_initial_health = 31 + id * 101,
        wall_health_regen_per_second = 2 + id, wall_health_bonus_pct = 3 + id * 5,
        wall_armor = 7 + id * 3, wall_health_per_second = 1 + id,
        wall_armor_per_second = 0.1 * (id + 1), tower_attack_flat = 13 + id * 17,
        tower_attack_bonus_pct = 9 + id * 5, tower_attack_speed_bonus_pct = 4 + id * 7,
        tower_attack_per_second = 1 + id * 0.5, lumberjack_attack_efficiency = 13 + id * 2,
        lumberjack_efficiency = 3 + id, lumberjack_attack_speed_bonus_pct = 2 + id * 3,
        hero_initial_attack = 100 + id * 37, hero_attack_flat = 3 + id * 13,
        hero_initial_attributes = 1 + id * 7, hero_attack_bonus_pct = 5 + id * 3,
        hero_initial_health = 71 + id * 53, hero_attributes_per_second = 1 + id,
        hero_attack_per_second = 2 + id, hero_basic_attack_growth = 3 + id,
        team_hero_wall_armor_bonus = 1 + id, enemy_initial_armor_reduction = 0.5 * (id + 1) }
    return { schema_version = 1, account_id = tostring(990000100 + id), revision = 100 + round,
        mode = "standard", match_session_id = "injected_fixture", progression = { loaded = true, clear_counts = { n1 = id + round } },
        entitlements = {}, achievements = {}, public = {},
        save = { gameplay_stats = s, archive = {}, content_inventory = {}, permanent_effects = {} } }
end
local function permutation(seed)
    local list = { 0, 1, 2, 3 }; local v = seed
    for i = #list, 2, -1 do v = (v * 48271) % 2147483647; local j = 1 + v % i; list[i], list[j] = list[j], list[i] end
    return list
end
local function register_building(id, kind, level, position)
    local d = buildings_config[kind]; local u = entity(d.unit_name or kind, id, position)
    local base = kind == "arrow_tower" and tower_base.rows[level] or d.levels[level]
    u.survival_building_id, u.survival_player_id, u.survival_level = kind, id, level
    u.native_maximum, u.maximum, u.health = base.health or 1000, base.health or 1000, base.health or 1000
    u.min_damage, u.max_damage = base.base_attack_damage or 0, base.base_attack_damage or 0
    local st = { unit = u, entindex = u.id, player_id = id, team = 2, building_id = kind, level = level, definition = d,
        base_attack_damage = u.min_damage }
    building_states[u.id] = st
    bus.emit(events.BUILDING_CREATED, st)
    return u
end
local function reset()
    now = 0; entities, building_states, summoned_handles, engine_errors, mine_publications = {}, {}, {}, {}, {}; scheduler.clear(); bus.reset(); phase_guard.reset()
    require("systems/player_context_service").init()
    profiles.init({ provider = provider }); technology.init(); permanent.init(); resources.init(); inventory.init()
    equipment.init(); weapon_growth.init(); heroes.init(); upgrades.init(); workers.init(); gold_mines.init()
    -- Spawn registry is an engine-handle boundary; effects and calculations are real.
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(p) return { unit = summoned_handles[p.player_id] } end)
    bus.subscribe(events.GOLD_MINE_CHANGED, function(p) mine_publications[p.player_id] = p end)
    bus.subscribe(events.BUILDING_CHANGED, function(p)
        local st = building_states[p.entindex]
        if st and (not p.unit or st.unit == p.unit) then st.level = p.level or st.level end
    end)
    bus.handle_request(events.BUILDING_QUERY_REQUEST, function(p) return building_states[p.entindex] end)
    bus.handle_request(events.BUILDING_LIST_REQUEST, function(p)
        local list = {}; for _, st in pairs(building_states) do if (p.player_id == nil or p.player_id == st.player_id)
            and (p.building_id == nil or p.building_id == st.building_id) then list[#list + 1] = st end end
        return { ok = true, buildings = list }
    end)
end
local function verify_units(players, levels, seconds, attacks, phase)
    local team_armor, enemy_reduction = 0, 0
    for id = 0, 3 do local s = current_profiles[id].save.gameplay_stats; team_armor = team_armor + s.team_hero_wall_armor_bonus; enemy_reduction = enemy_reduction + s.enemy_initial_armor_reduction end
    for id = 0, 3 do
        local p, s, lv = players[id], current_profiles[id].save.gameplay_stats, levels[id]
        local prefix = phase .. "_p" .. id
        local projected = projection(id)
        local ts, expected_sections = technology.get(id), {}
        for effect, field in pairs(field_by_effect) do
            local key = field[1] .. ":" .. field[2]
            expected_sections[key] = (expected_sections[key] or 0) + effect_value(lv, effect)
        end
        -- The same authored super-tower row explicitly targets hero attack and crit too.
        expected_sections["hero:attack_bonus_pct"] = effect_value(lv, "super_tower_crit_pct")
        expected_sections["hero:critical_chance_pct"] = effect_value(lv, "super_tower_crit_pct")
        expected_sections["tower:critical_chance_pct"] = effect_value(lv, "super_tower_crit_pct")
        for key, value in pairs(expected_sections) do local section, field = key:match("^([^:]+):(.+)$")
            check(prefix .. "_technology_" .. section .. "_" .. field, ts.final[section][field], value) end
        check(prefix .. "_map_wall_initial", projected.wall_initial_health, s.wall_initial_health + s.map_level * 100)
        check(prefix .. "_map_wall_regen", projected.wall_health_regen_per_second, s.wall_health_regen_per_second + s.map_level * 5)
        check(prefix .. "_shared_team_armor", projected.team_hero_wall_armor_bonus, team_armor)
        check(prefix .. "_shared_enemy_armor", projected.enemy_initial_armor_reduction, enemy_reduction)
        local wall_base = buildings_config.wall.levels[p.wall.survival_level]
        local wall_pct = effect_value(lv, "wall_health_pct") + effect_value(lv, "wall_health_pct_advanced")
            + effect_value(lv, "super_wall_health_pct") + s.wall_health_bonus_pct
        local wall_flat = s.wall_initial_health + s.map_level * 100 + seconds * s.wall_health_per_second
        -- Integer-authored fixture values use a percentage numerator, not the
        -- production arithmetic path. This catches a mathematically integral
        -- result rounded below its HP by an intermediate binary 1 + pct / 100.
        local wall_health = math.max(1, math.floor((wall_base.health * 100
            + wall_base.health * wall_pct + wall_flat * 100) / 100))
        local wall_armor = (wall_base.war3_armor or wall_base.armor) + s.wall_armor + team_armor
            + effect_value(lv, "super_wall_armor_flat") * 3 + seconds * s.wall_armor_per_second
        check(prefix .. "_wall_native_health", p.wall.maximum, wall_health)
        check(prefix .. "_wall_runtime_armor", p.wall.survival_war3_armor, wall_armor)
        check(prefix .. "_wall_native_regen", p.wall.regen, s.wall_health_regen_per_second + s.map_level * 5)
        local wall_hud = p.wall.survival_hud_stat_bonuses or {}
        local static_wall_bonus = math.floor(wall_base.health * wall_pct / 100 + s.wall_initial_health + s.map_level * 100)
        check(prefix .. "_wall_hud_static_bonus", wall_hud.health_bonus, static_wall_bonus,
            "actual native health is separately verified; HUD must include this owner's archive/map static bonuses")
        if p.tower then
            local row = tower_base.rows[p.tower.survival_level]
            local b = row.base_attack_damage
            local tf = effect_value(lv, "tower_attack_flat") + effect_value(lv, "tower_attack_flat_advanced") + effect_value(lv, "super_tower_attack_flat")
            local tp = effect_value(lv, "super_tower_crit_pct") + s.tower_attack_bonus_pct
            check(prefix .. "_tower_native_attack", p.tower.min_damage, (b + tf + s.tower_attack_flat + seconds * s.tower_attack_per_second) * (1 + tp / 100))
            check(prefix .. "_tower_native_interval", p.tower.interval, (1 / row.base_attack_speed) / (1 + s.tower_attack_speed_bonus_pct / 100))
            check(prefix .. "_tower_native_range", p.tower.range, rules.tower_attack_range + effect_value(lv, "super_tower_attack_range"))
            check(prefix .. "_tower_critical_chance", p.tower.survival_super_tower_crit_chance, effect_value(lv, "super_tower_crit_pct"))
            check(prefix .. "_tower_hud_static_bonus", (p.tower.survival_hud_stat_bonuses or {}).attack_bonus,
                (b + tf + s.tower_attack_flat) * (1 + tp / 100) - b)
        end
        local hd = hero_definitions.by_id[p.hero_id]
        local hs = hero_snapshot(id)
        local weapon = request(events.WEAPON_EQUIPMENT_GET_REQUEST, { player_id = id }).snapshot or {}
        local wd = weapon_definitions.by_id[weapon.main_hand_content_id] or {}
        local hg = request(events.WEAPON_GROWTH_GET_REQUEST, { player_id = id }).snapshot or {}
        local expected_attrs = hd.base_strength + (wd.base_strength or 0) + (hg.growth_strength or 0)
            + s.hero_initial_attributes + seconds * s.hero_attributes_per_second
        check(prefix .. "_hero_strength", hs.strength, expected_attrs)
        local hero_flat = effect_value(lv, "hero_attack_flat") + s.hero_initial_attack + s.hero_attack_flat
            + seconds * s.hero_attack_per_second + attacks[id] * s.hero_basic_attack_growth
        local hero_pct = effect_value(lv, "super_tower_crit_pct") + s.hero_attack_bonus_pct
        local weapon_min = (wd.base_attack_min or 0) + (hg.growth_attack or 0)
        local weapon_max = (wd.base_attack_max or 0) + (hg.growth_attack or 0)
        local equipment_stats = request(events.EQUIPMENT_STATS_GET_REQUEST, { player_id = id }).snapshot or {}
        local eq_flat = (equipment_stats.values or {}).attack_flat or 0
        local intellect = hd.base_intellect + (wd.base_intellect or 0) + (hg.growth_intellect or 0)
            + s.hero_initial_attributes + seconds * s.hero_attributes_per_second
        local attribute_attack = intellect * rules.hero_intellect_attack_per_point
        check(prefix .. "_hero_attack_min", hs.attack_min,
            (hd.base_damage_min + attribute_attack + weapon_min + hero_flat + eq_flat) * (1 + hero_pct / 100))
        -- Evaluate the real modifier property consumers; a successful stat
        -- snapshot alone does not prove the native unit receives that attack.
        local attack_modifier = p.hero:FindModifierByName("modifier_weapon_stat_projection")
        local equipment_modifier = p.hero:FindModifierByName("modifier_equipment_effects")
        local native_attack = p.hero:GetBaseDamageMin()
            + (attack_modifier and attack_modifier:GetModifierPreAttack_BonusDamage() or 0)
            + (equipment_modifier and equipment_modifier:GetModifierPreAttack_BonusDamage() or 0)
        check(prefix .. "_hero_native_damage_components", native_attack,
            math.floor(hd.base_damage_min + attribute_attack) + weapon_min + hero_flat + eq_flat
                + (hd.base_damage_min + attribute_attack + weapon_min + hero_flat + eq_flat) * hero_pct / 100,
            "native integer base setter + real weapon/research modifier getter + real equipment getter; authored percentage includes intellect-derived attack")
        check(prefix .. "_hero_final_damage_modifier", p.hero.survival_research_final_damage_pct, effect_value(lv, "hero_final_damage_pct"))
        check(prefix .. "_hero_owner", hs.player_id, id)
        check(prefix .. "_hero_native_health", p.hero.maximum,
            hd.base_health + expected_attrs * rules.hero_strength_health_per_point + s.hero_initial_health)
        if p.worker then
            local wl = request(events.WORKER_LIST_REQUEST, { player_id = id })
            local st; for _, row in ipairs(wl) do if row.unit == p.worker then st = row end end
            check(prefix .. "_worker_owned_state", st and st.player_id, id)
            local t = training_definitions.by_id[st.training_id]
            local own_growth = p.worker_attack_growth or 0
            check(prefix .. "_worker_native_attack", p.worker.min_damage, t.base_attack + own_growth)
            local extra = effect_value(lv, "lumberjack_wood_per_hit") + effect_value(lv, "lumberjack_wood_per_hit_advanced")
                + s.lumberjack_attack_efficiency - 13 + s.lumberjack_efficiency
            check(prefix .. "_worker_efficiency", st.technology_efficiency, extra)
            check(prefix .. "_worker_modifier_efficiency", p.worker.modifiers.modifier_lumberjack_ai.technology_lumber_efficiency, extra)
            check(prefix .. "_worker_actual_harvest_efficiency", p.worker.modifiers.modifier_lumberjack_ai:GetLumberEfficiency(), t.wood_per_hit + extra)
            local speed = effect_value(lv, "lumberjack_attack_speed_pct") + s.lumberjack_attack_speed_bonus_pct
            check(prefix .. "_worker_native_interval", p.worker.interval,
                math.max(0.05, (1 / t.attack_rate - effect_value(lv, "lumberjack_attack_interval_flat")) / (1 + speed / 100)))
            check(prefix .. "_worker_modifier_critical", p.worker.modifiers.modifier_lumberjack_ai.technology_crit_chance, effect_value(lv, "lumberjack_critical_chance_pct"))
            check(prefix .. "_worker_modifier_armor_reduction", p.worker.modifiers.modifier_lumberjack_ai.technology_armor_reduction, effect_value(lv, "lumberjack_attack_armor_reduction"))
        end
        if p.mine then
            local publication = mine_publications[id] or {}
            check(prefix .. "_mine_efficiency_scope", publication.efficiency_percent, effect_value(lv, "mine_efficiency_percent"))
            check(prefix .. "_mine_crit_scope", publication.crit_chance, effect_value(lv, "mine_crit_percent"))
            check(prefix .. "_mine_owner", publication.player_id, id)
        end
    end
end

local function run_round(scenario, round)
    active_case = scenario .. tostring(round)
    current_round = { case_id = active_case, scenario = scenario, round = round,
        seed = seeds[round] + (scenario == "B" and 1000 or 0), difficulty = "N" .. difficulty_matrix[round], checks = 0, passed = 0, failed = 0,
        failures = {}, player_matrix = {}, final = {}, interleaving = {} }
    report.rounds[#report.rounds + 1] = current_round
    current_profiles = {}; for id = 0, 3 do current_profiles[id] = profile(id, round) end
    reset()
    local order = operation_order[round]
    for _, id in ipairs(order) do check("profile_load_p" .. id, profiles.load_player(id).ok, true) end
    local players, levels, attacks, opening = {}, {}, {}, {}
    bus.subscribe(events.WORKER_CHANGED, function(payload)
        local p = players[payload.player_id]
        if p and payload.unit and payload.worker_type == "lumberjack" and not payload.removed then
            p.worker = payload.unit
            p.worker_attack_growth = 0
        end
    end)
    local tower_owner = (round - 1) % 4
    current_round.tower_owner = scenario == "B" and tower_owner or "all"
    for _, id in ipairs(order) do
        local position = scenario == "A" and Vector((id == 0 and -6000 or id == 1 and 6000 or 0), (id == 2 and -6000 or id == 3 and 6000 or 0), 128)
            or Vector(400 + id * 64, 400, 128)
        players[id] = { hero_id = ({ "hero_doom", "hero_axe", "hero_drow_ranger", "hero_shadow_fiend" })[id + 1] }
        local p = players[id]; p.city = register_building(id, "main_city", 5, position)
        p.wall = register_building(id, "wall", 1, position)
        if scenario == "A" or id == tower_owner then p.tower = register_building(id, "arrow_tower", 1, position) end
        if scenario == "A" or id == tower_owner then p.mine = register_building(id, "gold_mine", 1, position) end
        p.hero = entity(hero_definitions.by_id[p.hero_id].unit_name, id, position); p.hero.hero = true; p.hero.survival_player_id = id
        summoned_handles[id] = p.hero
        bus.emit(events.HERO_SUMMONED, { player_id = id, hero_id = p.hero_id, unit = p.hero })
        levels[id], attacks[id] = tech_levels(id, round), 0
        bus.emit(events.TECHNOLOGY_CHANGED, { player_id = id, levels = levels[id] })
        check("equip_grant_p" .. id, request(events.CONTENT_INVENTORY_GRANT_REQUEST,
            { player_id = id, content_id = "weapon_growth_sword_01", count = 1 }).ok, true)
        if scenario == "A" or id == tower_owner then
            local trained = workers._train_worker_for_test({ player_id = id, city = p.city, training_id = "train_lumberjack_01", skip_training_progress = true })
            check("worker_train_p" .. id, trained.ok, true); p.worker_expected = true
        end
        opening[id] = wallet(id)
        local before = wallet(id)
        bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = id, reason = "hero_ready_cached" })
        bus.emit(events.TECHNOLOGY_CHANGED, { player_id = id, levels = levels[id] })
        check("duplicate_opening_wood_p" .. id, wallet(id).wood, before.wood)
        check("duplicate_opening_gold_p" .. id, wallet(id).gold, before.gold)
        local s = current_profiles[id].save.gameplay_stats
        current_round.player_matrix[#current_round.player_matrix + 1] = { player_id = id, account_id = current_profiles[id].account_id,
            map_level = s.map_level, initial_wood = s.initial_wood, initial_gold = s.initial_gold,
            tech_levels = levels[id], x = position.x, y = position.y, tower_count = p.tower and 1 or 0 }
    end
    verify_units(players, levels, 0, attacks, "opening")
    -- Exercise the real asynchronous upgrade consumer and its resource charge.
    for _, id in ipairs(operation_order[round]) do
        local p, before = players[id], wallet(id)
        local wall_quote = request(events.BUILDING_UPGRADE_QUOTE_REQUEST, { player_id = id, building = p.wall })
        check("wall_upgrade_quote_p" .. id, wall_quote.ok, true)
        check("wall_upgrade_start_p" .. id, request(events.BUILDING_UPGRADE_REQUEST,
            { player_id = id, building = p.wall }).ok, true)
        check("wall_upgrade_owner_charge_p" .. id, wallet(id).wood, before.wood - wall_quote.wood)
        if p.tower then
            local quote = request(events.BUILDING_UPGRADE_QUOTE_REQUEST, { player_id = id, building = p.tower })
            local before_tower = wallet(id)
            check("tower_upgrade_start_p" .. id, request(events.BUILDING_UPGRADE_REQUEST,
                { player_id = id, building = p.tower }).ok, true)
            check("tower_upgrade_owner_charge_p" .. id, wallet(id).wood, before_tower.wood - quote.wood)
        end
        opening[id] = wallet(id)
    end
    local seconds = 65 + round * 5
    local building_level_rows = require("config/generated/building_levels").rows
    local mine_base; for _, row in ipairs(building_level_rows) do if row.building_id == "building_gold_mine" and row.level == 1 then mine_base = row.base_income end end
    local mine_ledger = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 }
    for tick = 1, seconds do
        order = permutation(current_round.seed + tick * 37)
        for _, id in ipairs(order) do
            local p = players[id]
            current_round.interleaving[#current_round.interleaving + 1] = { tick = tick, player_id = id, action = "hero_attack_then_technology" }
            bus.emit(events.HERO_MAIN_ATTACK_LANDED, { player_id = id, hero = p.hero, unit = p.hero, target = p.wall,
                attacker = p.hero, owner_hero = p.hero, attack_record = tick * 100 + id })
            attacks[id] = attacks[id] + 1
            if p.worker then
                local amount = effect_value(levels[id], "lumberjack_attack_growth")
                p.worker_attack_growth = (p.worker_attack_growth or 0) + amount
                bus.emit(events.TREE_HIT, { player_id = id, source = "lumberjack", attacker = p.worker })
                -- A teammate claiming this attack must not credit either worker.
                bus.emit(events.TREE_HIT, { player_id = (id + 1) % 4, source = "lumberjack", attacker = p.worker })
            end
            if tick % (3 + id) == 0 then
                levels[id] = tech_levels(id, round, tick)
                bus.emit(events.TECHNOLOGY_CHANGED, { player_id = id, levels = levels[id] })
                bus.emit(events.TECHNOLOGY_CHANGED, { player_id = id, levels = levels[id] })
            end
            if p.mine then
                -- Engine RNG is fixed at 50: all authored crit chances in this matrix stay below 50.
                local eff = effect_value(levels[id], "mine_efficiency_percent")
                local bonus = eff > 0 and math.max(1, math.floor(mine_base * eff / 100)) or 0
                mine_ledger[id] = mine_ledger[id] + mine_base + bonus
            end
        end
        now = tick; scheduler.think()
        if tick % 5 == 0 then verify_units(players, levels, tick, attacks, "tick" .. tick) end
    end
    for id = 0, 3 do
        if players[id].worker_expected then check("worker_actual_completion_p" .. id, players[id].worker ~= nil, true) end
        local s = current_profiles[id].save.gameplay_stats; local w = wallet(id)
        check("fractional_wood_p" .. id, w.wood, opening[id].wood + math.floor(seconds * s.wood_per_second))
        check("fractional_gold_p" .. id, w.gold, opening[id].gold + math.floor(seconds * s.gold_per_second) + mine_ledger[id])
        local copied = profiles.get_profile(id); copied.save.gameplay_stats.map_level = 9999
        check("profile_read_copy_p" .. id, profiles.get_profile(id).save.gameplay_stats.map_level, s.map_level)
        local stale = profile(id, round); stale.revision = 1
        check("stale_snapshot_p" .. id, profiles.apply_snapshot(id, stale).error, "snapshot_revision_stale")
        local wrong = profile((id + 1) % 4, round)
        check("wrong_account_snapshot_p" .. id, profiles.apply_snapshot(id, wrong).ok, false)
        local rev = profiles.get_profile(id).revision
        -- Save subsections are complete replacements, as specified by reducer API.
        local next_stats = shallow(profiles.get_profile(id).save.gameplay_stats)
        next_stats.hero_initial_attack = s.hero_initial_attack + 19; next_stats.initial_wood = s.initial_wood + 123
        local update = { schema_version = 1, account_id = current_profiles[id].account_id, update_id = active_case .. "_" .. id,
            base_revision = rev, revision = rev + 1, changes = { save = { gameplay_stats = next_stats } } }
        check("incremental_apply_p" .. id, profiles.apply_incremental(update).ok, true)
        s.hero_initial_attack = s.hero_initial_attack + 19; s.initial_wood = s.initial_wood + 123
        local once = wallet(id)
        check("incremental_opening_delta_p" .. id, once.wood, w.wood + 123)
        check("incremental_duplicate_p" .. id, profiles.apply_incremental(update).duplicate, true)
        check("incremental_duplicate_wallet_p" .. id, wallet(id).wood, once.wood)
        local old_attack = hero_snapshot(id).attack_min
        local old_growth = request(events.WEAPON_GROWTH_GET_REQUEST, { player_id = id }).snapshot.growth_attack
        check("replacement_weapon_grant_p" .. id, request(events.CONTENT_INVENTORY_GRANT_REQUEST,
            { player_id = id, content_id = "weapon_growth_sword_02", count = 1 }).ok, true)
        check("weapon_upgrade_preserves_growth_p" .. id,
            request(events.WEAPON_GROWTH_GET_REQUEST, { player_id = id }).snapshot.growth_attack, old_growth)
        check("weapon_upgrade_preserves_attack_p" .. id, hero_snapshot(id).attack_min, old_attack)
    end
    verify_units(players, levels, seconds, attacks, "final")
    local enemy = entity("npc_test_enemy", -1); enemy.survival_war3_armor = 20; enemy.armor = 20 / 3
    bus.emit(events.MONSTER_SPAWNED, { unit = enemy })
    check("shared_enemy_native_spawn", enemy.survival_war3_armor, 15)
    -- Independently mutate personal then explicitly team-shared fields.
    local mutation_owner = tower_owner
    local before_walls, before_hero_armor, before_hero_attack = {}, {}, {}
    for id = 0, 3 do before_walls[id] = players[id].wall.maximum; before_hero_armor[id] = hero_snapshot(id).armor; before_hero_attack[id] = hero_snapshot(id).attack_min end
    local function mutate_stats(patch, suffix)
        local id = mutation_owner; local p = profiles.get_profile(id)
        local next_stats = shallow(p.save.gameplay_stats)
        for key, delta in pairs(patch) do next_stats[key] = next_stats[key] + delta end
        local update = { schema_version = 1, account_id = p.account_id, update_id = active_case .. suffix,
            base_revision = p.revision, revision = p.revision + 1, changes = { save = { gameplay_stats = next_stats } } }
        check("scope_mutation_apply" .. suffix, profiles.apply_incremental(update).ok, true)
        for key, delta in pairs(patch) do current_profiles[id].save.gameplay_stats[key] = current_profiles[id].save.gameplay_stats[key] + delta end
    end
    mutate_stats({ wall_initial_health = 111, hero_initial_attack = 17 }, "_personal")
    for id = 0, 3 do
        check("private_wall_change_p" .. id, players[id].wall.maximum, before_walls[id] + (id == mutation_owner and 111 or 0))
        local pct = effect_value(levels[id], "super_tower_crit_pct") + current_profiles[id].save.gameplay_stats.hero_attack_bonus_pct
        check("private_hero_change_p" .. id, hero_snapshot(id).attack_min, before_hero_attack[id] + (id == mutation_owner and 17 * (1 + pct / 100) or 0))
    end
    local before_wall_armor = {}; for id = 0, 3 do before_wall_armor[id] = players[id].wall.survival_war3_armor end
    mutate_stats({ team_hero_wall_armor_bonus = 13, enemy_initial_armor_reduction = 2 }, "_shared")
    for id = 0, 3 do
        check("shared_wall_armor_change_p" .. id, players[id].wall.survival_war3_armor, before_wall_armor[id] + 13)
        check("shared_hero_armor_change_p" .. id, hero_snapshot(id).armor, before_hero_armor[id] + 13)
    end
    check("shared_enemy_existing_refresh", enemy.survival_war3_armor, 13)
    local new_enemy = entity("npc_test_enemy_replacement", -1); new_enemy.survival_war3_armor = 20
    bus.emit(events.MONSTER_SPAWNED, { unit = new_enemy })
    check("shared_enemy_new_inheritance", new_enemy.survival_war3_armor, 13)
    current_round.scope_mutations = { player_id = mutation_owner, personal_wall_initial_health_delta = 111,
        personal_hero_initial_attack_delta = 17, shared_team_armor_delta = 13, shared_enemy_armor_reduction_delta = 2 }
    current_round.shared_enemy = { expected_reduction = 7, native_armor = enemy.armor,
        runtime_armor = enemy.survival_war3_armor }
    for id = 0, 3 do
        local p = players[id]
        check("wall_upgrade_native_completion_p" .. id, p.wall.survival_level, 2)
        if p.tower then check("tower_upgrade_native_completion_p" .. id, p.tower.survival_level, 2) end
        current_round.final[#current_round.final + 1] = { player_id = id, resources = wallet(id), permanent = projection(id),
            technology = technology.get(id), hero = hero_snapshot(id), wall = { maximum = p.wall.maximum,
                war3_armor = p.wall.survival_war3_armor, health_regen = p.wall.regen, hud = p.wall.survival_hud_stat_bonuses },
            hero_native_attack = p.hero:GetBaseDamageMin()
                + p.hero.modifiers.modifier_weapon_stat_projection:GetModifierPreAttack_BonusDamage()
                + p.hero.modifiers.modifier_equipment_effects:GetModifierPreAttack_BonusDamage(),
            worker = p.worker and { attack = p.worker.min_damage, interval = p.worker.interval,
                efficiency = p.worker.modifiers.modifier_lumberjack_ai:GetLumberEfficiency(), personal_attack_growth = p.worker_attack_growth,
                training_id = "train_lumberjack_01" } or nil,
            tower = p.tower and { attack = p.tower.min_damage, interval = p.tower.interval, hud = p.tower.survival_hud_stat_bonuses } or nil }
    end
    current_round.engine_errors = engine_errors
    check("production_dispatch_errors", #engine_errors, 0, table.concat((function() local x = {}; for _, e in ipairs(engine_errors) do x[#x + 1] = e.error end; return x end)(), "\n"))
    original_print(active_case .. " checks=" .. current_round.checks .. " passed=" .. current_round.passed .. " failed=" .. current_round.failed .. " seed=" .. current_round.seed)
end
for _, scenario in ipairs({ "A", "B" }) do
    for round = 1, 5 do
        local ok, err = xpcall(function() run_round(scenario, round) end, debug.traceback)
        if not ok then
            if current_round then current_round.fatal_error = err; check("harness_or_engine_boundary_fatal", err, "none") end
            original_print(active_case .. " fatal: " .. err)
        end
    end
end
local locations = {
    units_p_wall_hud_static_bonus = { "scripts/vscripts/systems/building_upgrade_system.lua:123", "scripts/vscripts/systems/building_upgrade_system.lua:231" },
    units_p_tower_hud_static_bonus = { "scripts/vscripts/systems/building_upgrade_system.lua:123", "scripts/vscripts/systems/building_upgrade_system.lua:150" },
    units_p_wall_native_health = { "scripts/vscripts/systems/building_health_projection.lua:8" },
    units_p_hero_native_damage_components = { "scripts/vscripts/systems/hero_combat_stat_service.lua:367", "scripts/vscripts/systems/hero_combat_stat_service.lua:483", "scripts/vscripts/modifiers/modifier_weapon_stat_projection.lua:273" } }
for _, bug in ipairs(report.bugs) do
    bug.locations = locations[bug.key:gsub("%*", "")] or {}
    bug.reproduce_command = '"C:/Program Files/lua/bin/lua5.1.exe" tools/test_four_player_technology_stress.lua --phase negative_source --source-root output/four_player_stress_20261012/baseline_source'
    if bug.key:find("wall_native_health", 1, true) then
        bug.root_cause = "Computing base * (1 + percentage / 100) can round a mathematically integral HP below its integer before floor; the same helper drives actual max HP and static HUD health."
        bug.minimal_reproduction = "maximum_with_flat_bonus(3000, 147, 131) mathematically equals 7541 HP, but the old binary intermediate floors 7540; a fractional 7541.2 must still floor 7541."
    elseif bug.key:find("hud_static", 1, true) then
        bug.root_cause = "research_context returns permanent totals but omits display_totals; apply_research_technology uses undefined permanent_result when constructing static HUD bonuses, so archive/map flat and percentage sources become empty."
        bug.minimal_reproduction = "A1 player 0, initialized personal archive/map effects, wall/tower BUILDING_CREATED then TECHNOLOGY_CHANGED; inspect native stats and survival_hud_stat_bonuses. Native stats include the archive; HUD excludes it."
    else
        bug.root_cause = "Hero logical attack includes the intellect-derived attribute_attack_bonus before percentage multiplication; engine_research_attack_bonus calculates the percentage from base/weapon/flat values and omits attribute_attack_bonus. Real modifier preattack getter inherits the smaller engine bonus."
        bug.minimal_reproduction = "A1 player 0, hero_doom, intellect 501, global intellect attack per point 0.1, archive 5 percent plus technology 1 percent attack. Respect native integer base setter: expected native components 757.906, actual 754.9; short by 50.1 * 0.06 = 3.006. Logical panel is 758.006."
    end
end
local file = assert(io.open(output_dir .. "/technology_" .. phase_name .. ".json", "wb")); file:write(json.encode(report)); file:close()
local log = assert(io.open(output_dir .. "/technology_" .. phase_name .. "_execution.log", "wb")); log:write(table.concat(engine_log, "\n")); log:close()
original_print("TECHNOLOGY_STRESS " .. phase_name .. " rounds=" .. #report.rounds .. " checks=" .. report.totals.checks .. " failed=" .. report.totals.failed .. " bugs=" .. #report.bugs)
-- Failure exit preserves real defects. Never change oracle merely to get PASS.
os.exit(report.totals.failed > 0 and 1 or 0)
