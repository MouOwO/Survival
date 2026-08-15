local config = require("config/research_technology_config")
local Repository = require("research/research_technology_repository")
local EffectService = require("research/research_effect_service")
local Service = require("research/research_technology_service")
local Description = require("research/research_technology_description")

local M = {}

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

local function build_fixture(options)
    options = options or {}
    local account = {
        gold = options.gold or 1000000000,
        wood = options.wood or 1000000000,
    }
    local repository = Repository.new({ resolve_team = function() return 2 end })
    local effects = EffectService.new(repository)
    local bus = { emitted = {} }
    bus.emit = function(name, payload)
        table.insert(bus.emitted, { name = name, payload = payload })
    end
    local service = Service.new({
        repository = repository,
        effects = effects,
        event_bus = bus,
        valid_player = function(player_id) return player_id == 0 end,
        get_resources = function() return account end,
        spend_resources = options.spend_resources or function(_, cost)
            if account.gold < cost.gold then
                return { ok = false, error = "gold_not_enough" }
            end
            if account.wood < cost.wood then
                return { ok = false, error = "wood_not_enough" }
            end
            account.gold = account.gold - cost.gold
            account.wood = account.wood - cost.wood
            return { ok = true }
        end,
        refund_resources = function(_, cost)
            account.gold = account.gold + cost.gold
            account.wood = account.wood + cost.wood
            return { ok = true }
        end,
        get_reincarnation_level = function()
            return options.reincarnation_level or 3
        end,
        get_access_state = function()
            return options.access_state or {
                research_lab = true,
                advanced_research_lab = true,
            }
        end,
    })
    return service, repository, effects, account
end

local function run_failure_boundary_tests()
    local blocked, blocked_repository, _, blocked_account = build_fixture({
        access_state = {
            research_lab = false,
            advanced_research_lab = false,
        },
    })
    local blocked_wood = blocked_account.wood
    local denied = blocked:RequestUpgrade({ player_id = 0, tech_id = "RS-01" })
    assert_equal(denied.error_code, "research_access_not_met", "access denied")
    assert_equal(blocked_repository:GetLevel(0, "RS-01"), 0,
        "access denied does not level")
    assert_equal(blocked_account.wood, blocked_wood,
        "access denied does not spend")

    local gold_race, gold_repository = build_fixture({
        spend_resources = function()
            return { ok = false, error = "gold_not_enough" }
        end,
    })
    local gold_result = gold_race:RequestUpgrade({
        player_id = 0,
        tech_id = "RS-01",
    })
    assert_equal(gold_result.error_code, "insufficient_gold",
        "gold commit race")
    assert_equal(gold_repository:GetLevel(0, "RS-01"), 0,
        "gold commit race does not level")

    local wood_race, wood_repository = build_fixture({
        spend_resources = function()
            return { ok = false, error = "wood_not_enough" }
        end,
    })
    local wood_result = wood_race:RequestUpgrade({
        player_id = 0,
        tech_id = "RS-01",
    })
    assert_equal(wood_result.error_code, "insufficient_wood",
        "wood commit race")
    assert_equal(wood_repository:GetLevel(0, "RS-01"), 0,
        "wood commit race does not level")

    local rollback, rollback_repository, _, rollback_account = build_fixture()
    rollback_repository.SetLevel = function() return false end
    local rollback_wood = rollback_account.wood
    local failed = rollback:RequestUpgrade({ player_id = 0, tech_id = "RS-01" })
    assert_equal(failed.error_code, "resource_commit_failed",
        "repository failure")
    assert_equal(rollback_account.wood, rollback_wood,
        "repository failure refunds resources")
end

local function run_transaction_tests()
    local service, repository, effects, account = build_fixture()
    local before = account.wood
    local first = service:RequestUpgrade({ player_id = 0, tech_id = "RS-01" })
    assert_equal(first.success, true, "RS-01 level 1 success")
    assert_equal(before - account.wood, 200, "RS-01 level 1 wood")
    before = account.wood
    local second = service:RequestUpgrade({ player_id = 0, tech_id = "RS-01" })
    assert_equal(before - account.wood, 600, "RS-01 level 2 wood")

    local locked = service:RequestUpgrade({ player_id = 0, tech_id = "RS-02" })
    assert_equal(locked.error_code, "prerequisite_not_met", "RS-02 prerequisite")
    repository:SetLevel(0, "RS-01", 10)
    local unlocked = service:RequestUpgrade({ player_id = 0, tech_id = "RS-02" })
    assert_equal(unlocked.success, true, "RS-02 unlocked")

    repository:SetLevel(0, "RS-01", 10)
    local maxed = service:RequestUpgrade({ player_id = 0, tech_id = "RS-01" })
    assert_equal(maxed.error_code, "max_level_reached", "maximum level")

    repository:SetLevel(0, "ARS-03", 0)
    repository:SetLevel(0, "RS-09", 10)
    local old_gold, old_wood = account.gold, account.wood
    local dual = service:RequestUpgrade({ player_id = 0, tech_id = "ARS-03" })
    assert_equal(dual.success, true, "dual resource upgrade")
    assert_equal(old_gold - account.gold, 30000, "dual gold")
    assert_equal(old_wood - account.wood, 100000, "dual wood")

    account.gold, account.wood = 0, 0
    local old_level = repository:GetLevel(0, "ARS-03")
    local poor = service:RequestUpgrade({ player_id = 0, tech_id = "ARS-03" })
    assert_equal(poor.success, false, "insufficient resources")
    assert_equal(repository:GetLevel(0, "ARS-03"), old_level,
        "insufficient does not level")
    assert_equal(account.gold, 0, "insufficient does not spend gold")
    assert_equal(account.wood, 0, "insufficient does not spend wood")

    local invalid = service:RequestUpgrade({ player_id = 0, tech_id = "BAD" })
    assert_equal(invalid.error_code, "unknown_technology", "invalid tech id")

    repository:SetLevel(0, "RS-06", 3)
    repository:SetLevel(0, "RS-08", 2)
    repository:SetLevel(0, "ARS-08", 4)
    repository:SetLevel(0, "ARS-10", 5)
    local one = effects:Recalculate(0)
    local two = effects:Recalculate(0)
    assert_equal(one.legacy.tower.attack_flat, two.legacy.tower.attack_flat,
        "reinitialize tower idempotent")
    assert_equal(one.legacy.wall.health_bonus_pct,
        two.legacy.wall.health_bonus_pct, "reinitialize wall idempotent")
    assert_equal(one.legacy.hero.final_damage_bonus_pct, 4,
        "hero final damage once")
    assert_equal(one.legacy.hero.attack_flat, 10,
        "hero attack once")
end

local function run_config_tests()
    assert_equal(#config.technologies, 19, "technology count")
    local total_levels = 0
    for _, definition in ipairs(config.technologies) do
        total_levels = total_levels + definition.max_level
        local first = config.cost_for_level(definition, 1)
        local last = config.cost_for_level(definition, definition.max_level)
        assert_equal(first.gold, definition.generated_rows[1].gold_cost,
            definition.tech_id .. " first gold")
        assert_equal(first.wood, definition.generated_rows[1].wood_cost,
            definition.tech_id .. " first wood")
        assert_equal(last.gold,
            definition.generated_rows[definition.max_level].gold_cost,
            definition.tech_id .. " last gold")
        assert_equal(last.wood,
            definition.generated_rows[definition.max_level].wood_cost,
            definition.tech_id .. " last wood")
        assert_equal(config.cost_for_level(definition,
            definition.max_level + 1), nil,
            definition.tech_id .. " rejects overflow")
    end
    assert_equal(total_levels, 420, "all level count")
end

local function run_description_tests()
    for _, definition in ipairs(config.technologies) do
        local text = Description.build(definition, 0, 1)
        assert_equal(type(text), "string", definition.tech_id .. " description type")
        assert_equal(#text > 20, true, definition.tech_id .. " description present")
        assert_equal(string.find(text, "当前Lv.0", 1, true) ~= nil, true,
            definition.tech_id .. " current level text")
        assert_equal(string.find(text, "升级至Lv.1", 1, true) ~= nil, true,
            definition.tech_id .. " target level text")
    end
    local rs03 = Description.build(config.by_id["RS-03"], 2, 3)
    assert_equal(string.find(rs03, "采集暴击时获得2倍木材", 1, true) ~= nil,
        true, "lumberjack critical description")
    local ars07 = Description.build(config.by_id["ARS-07"], 1, 2)
    assert_equal(string.find(ars07, "防御塔暴击率", 1, true) ~= nil, true,
        "tower critical description")
    assert_equal(string.find(ars07, "英雄攻击力", 1, true) ~= nil, true,
        "hero attack description")
    assert_equal(Description.condition_text(config.by_id["RS-02"]),
        "伐木工速度 Lv.10", "prerequisite display name")
    assert_equal(Description.condition_text(config.by_id["ARS-08"]),
        "完成3转", "reincarnation description")
end

function M.run()
    local ok, error_message = pcall(function()
        run_config_tests()
        run_description_tests()
        run_transaction_tests()
        run_failure_boundary_tests()
    end)
    return ok, ok and "research_test passed: 19 technologies / 420 levels"
        or tostring(error_message)
end

return M