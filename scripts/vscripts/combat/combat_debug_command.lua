local M = {}
local damage_service = nil
local rules = nil

local function hero(player_id)
    return PlayerResource:GetSelectedHeroEntity(player_id)
end

local function enemy_for(unit)
    local units = FindUnitsInRadius(unit:GetTeamNumber(), unit:GetAbsOrigin(), nil,
        2000, DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_NONE, FIND_CLOSEST, false)
    return units[1]
end

local function print_result(name, result)
    print("[damage_test] " .. name .. " " .. tostring(result.success)
        .. " tx=" .. tostring(result.transaction_id)
        .. " damage=" .. tostring(result.calculated_damage)
        .. " blocked=" .. tostring(result.blocked_reason))
end

local function run(_, player_id)
    if not IsInToolsMode() and not rules.debug_enabled then return end
    local attacker = hero(tonumber(player_id) or 0)
    local victim = attacker and enemy_for(attacker) or nil
    local tests = {
        { "physical", DAMAGE_TYPE_PHYSICAL, {} },
        { "magical", DAMAGE_TYPE_MAGICAL, {} },
        { "pure", DAMAGE_TYPE_PURE, {} },
        { "critical", DAMAGE_TYPE_MAGICAL, { can_crit=true, crit_chance=1, crit_multiplier=2 } },
        { "post_bonus", DAMAGE_TYPE_MAGICAL, { post_damage_bonus_pct=0.20 } },
        { "post_reduction", DAMAGE_TYPE_MAGICAL, { target_post_reduction_pct=0.20 } },
    }
    for _, test in ipairs(tests) do
        local extra = test[3]
        extra.attacker, extra.victim = attacker, victim
        extra.source_kind, extra.base_damage, extra.damage_type = "script", 100, test[2]
        print_result(test[1], damage_service:Deal(extra))
    end
    local parent = nil
    for depth = 0, 7 do
        local recursion = damage_service:Deal({ attacker=attacker, victim=victim,
            source_kind="reflection", base_damage=1,
            damage_type=DAMAGE_TYPE_PURE, parent_transaction_id=parent })
        parent = recursion.transaction_id
        print_result("recursion_" .. tostring(depth), recursion)
    end
    print_result("invalid_entity", damage_service:Deal({ attacker=nil, victim=nil,
        source_kind="script", base_damage=100, damage_type=DAMAGE_TYPE_PURE }))
end

function M.init(service, config)
    damage_service, rules = service, config
    Convars:RegisterCommand("damage_test", run,
        "Run Survival damage module tests", FCVAR_CHEAT)
end

return M
