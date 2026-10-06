-- Real route data, queued ability sync and native utility sync; mock engine entities only.
package.path = "scripts/vscripts/?.lua;" .. package.path
local noop = function() end
local queued = {}
package.loaded["core/scheduler"] = { after = function(_, callback) queued[#queued + 1] = callback end }
package.loaded["core/logger"] = {error = function(_, message) error(message) end}
package.loaded["systems/tower_skill_runtime"] = {get = function() return {} end}
local routes = require("config/tower_route_config")
local sync = require("systems/tower_ability_sync")
local bus, events = require("core/event_bus"), require("core/events")
local fusion = false
bus.handle_request(events.TOWER_FUSION_ELIGIBILITY_REQUEST, function() return {eligible = fusion} end)
bus.handle_request(events.TOWER_CLASS_SLOT_REQUEST, function() return {count = 0, maximum = 5} end)
local definition = {class_options = {}}
for index = 1, 7 do
    definition.class_options[index] = {id = "class_" .. index, ability = "ability_class_" .. index}
end
local function unit(index)
    local entity = {abilities = {}, index = index}
    function entity:IsNull() return false end
    function entity:entindex() return self.index end
    function entity:FindAbilityByName(name) return self.abilities[name] end
    function entity:AddAbility(name)
        if self.abilities[name] then return self.abilities[name] end
        local ability = {name = name}
        function ability:SetLevel(value) self.level = value end
        function ability:SetActivated(value) self.active = value end
        function ability:SetHidden(value) self.hidden = value end
        function ability:IsHidden() return self.hidden == true end
        function ability:IsNull() return false end
        function ability:GetAbilityName() return self.name end
        self.abilities[name] = ability
        return ability
    end
    function entity:RemoveAbility(name) self.abilities[name] = nil end
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
for class_number = 1, 7 do
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
    end
    -- Runtime enforcement also handles stale configuration and previously attached native buttons.
    local row = routes.current(state)
    local stale = {} for key, value in pairs(row) do stale[key] = value end
    stale.active_skill_ids = {"ability_upgrade_tower", "ability_upgrade_tower_lv01", "ability_upgrade_tower_max",
        "ability_building_blink", "ability_destroy_arrow_tower"}
    for _, name in ipairs(stale.active_skill_ids) do entity:AddAbility(name) end
    update(state, stale)
    for _, name in ipairs({"ability_upgrade_tower", "ability_upgrade_tower_lv01", "ability_upgrade_tower_max"}) do
        assert(not entity:FindAbilityByName(name), "remove stale max-level button")
    end
    fusion = true
    update(state, stale)
    assert(entity:FindAbilityByName("ability_tower_fusion"), "retain eligible fusion")
    fusion = false
    update(state, stale)
    assert(not entity:FindAbilityByName("ability_tower_fusion"), "refresh changed eligibility at same level")
end
local runtime = require("ui/ability_runtime_builder").build("ability_destroy_arrow_tower", {})
assert(runtime.display_name == "销毁防御塔")
assert(runtime.upgrade_description == "销毁本单位，不返还成长所消耗资源")
local tooltip = require("config/generated/tooltip_definitions").by_id["ability:ability_destroy_arrow_tower"]
assert(tooltip.name == runtime.display_name and tooltip.desc == runtime.upgrade_description)
local builder = require("ui/ability_runtime_builder")
for index = 1, 7 do
    local state = {level = 6, tower_class = "class_" .. index}
    local max = builder.build("ability_upgrade_tower_max", state)
    assert(max.available == 1 and max.next_level == 10, "R rarity must not block quick-fill")
    state.level = 25
    assert(builder.build("ability_upgrade_tower_lv01", state).available == 0, "max route cannot upgrade")
    assert(builder.build("ability_upgrade_tower_max", state).available == 0, "max route cannot quick-fill")
end
print("TOWER_UPGRADE_VISIBILITY_PASS: 7 routes x 25 levels, native removal, batch continuity, fusion, utility, Chinese tooltip")
