-- Real route data, queued ability sync and native utility sync; mock engine entities only.
package.path = "scripts/vscripts/?.lua;" .. package.path
local queued = {}
package.loaded["core/scheduler"] = { after = function(_, callback) queued[#queued + 1] = callback end }
package.loaded["core/logger"] = {error = function(_, message) error(message) end}
package.loaded["systems/tower_skill_runtime"] = {get = function() return {} end}
local routes = require("config/tower_route_config")
local sync = require("systems/tower_ability_sync")
local bus, events = require("core/event_bus"), require("core/events")
local fusion_by_player = {[0] = false, [1] = true}
local routes_ready_by_player, ultimates_by_player = {}, {}
bus.handle_request(events.TOWER_FUSION_ELIGIBILITY_REQUEST, function(payload)
    return {eligible = fusion_by_player[payload.player_id] == true,
        route_count = routes_ready_by_player[payload.player_id] or 0,
        ultimate_count = ultimates_by_player[payload.player_id] or 0, maximum = 1}
end)
bus.handle_request(events.TOWER_CLASS_SLOT_REQUEST, function() return {count = 0, maximum = 5} end)
local definition = {class_options = {}}
for index = 1, 7 do
    definition.class_options[index] = {id = "class_" .. index, ability = "ability_class_" .. index}
end
local function unit(index)
    local entity = {abilities = {}, index = index, added = 0, removed = 0}
    function entity:IsNull() return false end
    function entity:entindex() return self.index end
    function entity:FindAbilityByName(name) return self.abilities[name] end
    function entity:AddAbility(name)
        if self.abilities[name] then return self.abilities[name] end
        self.added = self.added + 1
        local ability = {name = name, activation_writes = 0}
        function ability:SetLevel(value) self.level = value end
        function ability:SetActivated(value)
            self.active = value
            self.activation_writes = self.activation_writes + 1
        end
        function ability:IsActivated() return self.active == true end
        function ability:SetHidden(value) self.hidden = value end
        function ability:IsHidden() return self.hidden == true end
        function ability:IsNull() return self.removed == true end
        function ability:GetAbilityName() return self.name end
        self.abilities[name] = ability
        return ability
    end
    function entity:RemoveAbility(name)
        local ability = self.abilities[name]
        if ability then
            self.removed = self.removed + 1
            ability.removed = true
            self.abilities[name] = nil
        end
    end
    function entity:GetAbilityCount() local count = 0 for _ in pairs(self.abilities) do count = count + 1 end return count end
    function entity:GetAbilityByIndex(index)
        local all = {} for _, ability in pairs(self.abilities) do all[#all + 1] = ability end
        return all[index + 1]
    end
    return entity
end
local function update(state, row)
    sync.sync(state, row)
    while #queued > 0 do table.remove(queued, 1)() end
    assert(not state.unit.survival_tower_ability_sync_pending)
end
local upgrade_names = {"ability_upgrade_tower", "ability_upgrade_tower_lv01", "ability_upgrade_tower_max"}
local function assert_no_upgrades(entity, context)
    for _, name in ipairs(upgrade_names) do
        assert(not entity:FindAbilityByName(name), "remove " .. name .. " " .. context)
    end
end
local function assert_fusion(entity, active, context)
    local ability = entity:FindAbilityByName("ability_tower_fusion")
    assert(ability and not ability:IsNull() and not ability:IsHidden(), "visible fusion " .. context)
    assert(ability.active == active, "fusion activation " .. context)
    return ability
end
for class_number = 1, 7 do
    fusion_by_player[0] = false
    local entity = unit(class_number)
    local state = {unit = entity, player_id = 0, building_id = "arrow_tower", definition = definition}
    for level = 1, 25 do
        state.level = level
        state.tower_class = level > 5 and "class_" .. class_number or nil
        local row = routes.current(state)
        local before = entity:FindAbilityByName("ability_upgrade_tower_lv01")
        update(state, row)
        local upgrade = entity:FindAbilityByName("ability_upgrade_tower_lv01")
        assert((upgrade ~= nil) == (level ~= 5 and level < 25), "Q visibility at " .. level)
        local configured_max = false
        for _, name in ipairs(row.active_skill_ids or {}) do
            if name == "ability_upgrade_tower_max" then configured_max = true end
        end
        assert((entity:FindAbilityByName("ability_upgrade_tower_max") ~= nil)
            == (configured_max and routes.can_upgrade_max(state)), "W visibility class " .. class_number .. " level " .. level)
        if before and upgrade then assert(before == upgrade, "preserve active batch ability instances") end
        for _, skill in ipairs(row.skill_ids or {}) do assert(entity:FindAbilityByName(skill), "retain passive " .. skill) end
        assert(entity:FindAbilityByName("ability_destroy_arrow_tower"), "retain destroy")
        assert(entity:FindAbilityByName("ability_building_blink"), "retain movement")
        if level == 5 then assert(entity:FindAbilityByName(definition.class_options[class_number].ability), "retain class selection") end
        if level < 25 then
            assert(not entity:FindAbilityByName("ability_tower_fusion"), "no fusion before final route class " .. class_number .. " level " .. level)
        else
            assert_no_upgrades(entity, "at final route class " .. class_number)
            assert_fusion(entity, false, "waiting for seven routes class " .. class_number)
        end
    end
    -- Runtime enforcement also handles stale configuration and previously attached native buttons.
    local row = routes.current(state)
    local stale = {} for key, value in pairs(row) do stale[key] = value end
    stale.active_skill_ids = {"ability_upgrade_tower", "ability_upgrade_tower_lv01", "ability_upgrade_tower_max",
        "ability_building_blink", "ability_destroy_arrow_tower"}
    for _, name in ipairs(stale.active_skill_ids) do entity:AddAbility(name) end
    update(state, stale)
    assert_no_upgrades(entity, "with stale final-level configuration")
    local fusion_ability = assert_fusion(entity, false, "stale final row")
    local signature = entity.survival_tower_ability_signature
    local added, removed = entity.added, entity.removed
    local activation_writes = fusion_ability.activation_writes
    update(state, stale)
    assert(fusion_ability.activation_writes == activation_writes, "unchanged eligibility does not rewrite native activation")
    fusion_by_player[0] = true
    update(state, stale)
    assert(assert_fusion(entity, true, "seven routes ready") == fusion_ability, "eligibility activation preserves fusion instance")
    assert_no_upgrades(entity, "with eligible fusion")
    assert(entity.survival_tower_ability_signature == signature, "eligibility does not change layout signature")
    assert(entity.added == added and entity.removed == removed, "eligibility does not rebuild ability entities")
    assert(fusion_ability.activation_writes == activation_writes + 1, "ready eligibility updates native activation once")
    update(state, stale)
    assert(fusion_ability.activation_writes == activation_writes + 1, "unchanged ready eligibility does not rewrite activation")
    fusion_by_player[0] = false
    update(state, stale)
    assert(assert_fusion(entity, false, "material lost") == fusion_ability, "lost eligibility preserves fusion instance")
    assert(entity.added == added and entity.removed == removed, "lost eligibility does not rebuild abilities")
    assert(fusion_ability.activation_writes == activation_writes + 2, "lost eligibility updates native activation once")
    -- Retired fusion materials cannot keep a visible fusion action even if a
    -- delayed eligibility snapshot still says the player has seven routes.
    state.fusion_participated = true
    fusion_by_player[0] = true
    update(state, stale)
    assert(not entity:FindAbilityByName("ability_tower_fusion"), "consumed material cannot fuse again")
    assert(fusion_ability:IsNull(), "retired fusion ability handle is invalidated")
    assert_no_upgrades(entity, "on fusion-participated material")

    -- R5 and SR5 terminate their current stage but have a configured next row.
    -- A player with other full towers must still upgrade these towers normally.
    for _, level in ipairs({10, 15, 20}) do
        local growing = {unit = unit(1000 + class_number * 30 + level), player_id = 1,
            building_id = "arrow_tower", definition = definition,
            tower_class = "class_" .. class_number, level = level}
        assert(routes.can_upgrade(growing), "stage end still has next route row")
        update(growing, routes.current(growing))
        local next_upgrade = growing.unit:FindAbilityByName("ability_upgrade_tower_lv01")
        assert(next_upgrade and next_upgrade.active == true, "stage progression remains available at " .. level)
        assert(not growing.unit:FindAbilityByName("ability_tower_fusion"), "no fusion at nonfinal stage end " .. level)
    end
end
-- Eligibility changes affect only the owner and cannot leak between players.
local player_states = {}
for player_id = 0, 1 do
    player_states[player_id] = {unit = unit(2000 + player_id), player_id = player_id,
        building_id = "arrow_tower", definition = definition, tower_class = "class_1", level = 25}
end
fusion_by_player[0], fusion_by_player[1] = false, true
for player_id = 0, 1 do update(player_states[player_id], routes.current(player_states[player_id])) end
local player_zero_ability = assert_fusion(player_states[0].unit, false, "player zero missing materials")
local player_one_ability = assert_fusion(player_states[1].unit, true, "player one complete materials")
fusion_by_player[0], fusion_by_player[1] = true, false
for player_id = 0, 1 do update(player_states[player_id], routes.current(player_states[player_id])) end
assert(assert_fusion(player_states[0].unit, true, "player zero now ready") == player_zero_ability, "player zero stable ability")
assert(assert_fusion(player_states[1].unit, false, "player one now missing materials") == player_one_ability, "player one stable ability")
local runtime = require("ui/ability_runtime_builder").build("ability_destroy_arrow_tower", {})
assert(runtime.display_name == "销毁防御塔")
assert(runtime.upgrade_description == "销毁本单位，不返还成长所消耗资源")
local tooltip = require("config/generated/tooltip_definitions").by_id["ability:ability_destroy_arrow_tower"]
assert(tooltip.name == runtime.display_name and tooltip.desc == runtime.upgrade_description)
local builder = require("ui/ability_runtime_builder")
local function field(runtime, label)
    for _, item in ipairs(runtime.fields or {}) do
        if item.label == label then return item.value end
    end
end
local final_state = player_states[0]
fusion_by_player[0], routes_ready_by_player[0], ultimates_by_player[0] = false, 6, 0
local missing = builder.build("ability_tower_fusion", final_state)
assert(missing.display_name == "合成终极塔", "tooltip matches native fusion button name")
assert(missing.available == 0 and missing.can_afford == 1, "tooltip disables fusion while a route is missing")
assert(field(missing, "未参与满级路线") == "6/7", "tooltip counts final route materials")
assert(field(missing, "终极塔数量") == "0/1", "tooltip uses one ultimate limit")
assert(field(missing, "材料消耗") == "消耗七种路线各1座最终满级塔", "tooltip explains real material consumption")
fusion_by_player[0], routes_ready_by_player[0] = true, 7
local ready = builder.build("ability_tower_fusion", final_state)
assert(ready.available == 1 and field(ready, "未参与满级路线") == "7/7", "tooltip enables fusion when seven routes ready")
fusion_by_player[0], ultimates_by_player[0] = false, 1
local occupied = builder.build("ability_tower_fusion", final_state)
assert(occupied.available == 0 and field(occupied, "终极塔数量") == "1/1", "existing ultimate keeps tooltip disabled")
assert(string.find(occupied.status_text, "终极塔数量已达上限", 1, true), "tooltip explains ultimate limit")
update(final_state, routes.current(final_state))
assert(assert_fusion(final_state.unit, false, "existing ultimate") == player_zero_ability, "existing ultimate greys same fusion handle")
for index = 1, 7 do
    local state = {level = 6, tower_class = "class_" .. index}
    local max = builder.build("ability_upgrade_tower_max", state)
    assert(max.available == 1 and max.next_level == 10, "R rarity must not block quick-fill")
    state.level = 25
    assert(builder.build("ability_upgrade_tower_lv01", state).available == 0, "max route cannot upgrade")
    assert(builder.build("ability_upgrade_tower_max", state).available == 0, "max route cannot quick-fill")
end
print("TOWER_UPGRADE_VISIBILITY_PASS: 7 routes x 25 levels, final fusion always visible, eligibility updates without rebuild, stale upgrades removed, stage progression, consumed materials, player isolation, utility and tooltip")
