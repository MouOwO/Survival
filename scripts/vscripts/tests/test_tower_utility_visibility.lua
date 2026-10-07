package.path = "scripts/vscripts/?.lua;" .. package.path
local sync = require("systems/tower_utility_ability_sync")
local row = require("config/generated/arrow_tower_base").by_id.arrow_tower_lv05
local function fixture(count, level, class)
    local unit = { abilities = {} }
    function unit:IsNull() return false end
    function unit:FindAbilityByName(name)
        for _, a in ipairs(self.abilities) do if a.name == name then return a end end
    end
    function unit:GetAbilityByIndex(index) return self.abilities[index + 1] end
    function unit:RemoveAbility(name)
        for i = #self.abilities, 1, -1 do
            if self.abilities[i].name == name then table.remove(self.abilities, i) end
        end
    end
    function unit:AddAbility(name)
        local a = {name = name, hidden = false}
        function a:IsNull() return false end
        function a:GetAbilityName() return self.name end
        function a:IsHidden() return self.hidden end
        function a:SetHidden(value) self.hidden = value end
        function a:SetActivated(value) self.active = value end
        function a:SetLevel(value) self.level = value end
        self.abilities[#self.abilities + 1] = a
        return a
    end
    for i = 1, count do unit:AddAbility("ability_tower_class_" .. i) end
    local state = {unit = unit, building_id = "arrow_tower", level = level, tower_class = class}
    return state, unit
end
for choices = 0, 7 do
    local state, unit = fixture(choices, 5)
    sync.sync(state, row)
    sync.sync(state, row) -- Repeated refresh must not duplicate utility buttons.
    local destroy = unit:FindAbilityByName(sync.DESTROY_ABILITY)
    assert(destroy and not destroy.hidden and destroy.active, "1-5 must always allow destruction")
    assert(unit.abilities[#unit.abilities] == destroy, "destruction follows route choices")
    assert(#unit.abilities == choices + 2, "utility refresh must be idempotent")
    local move = unit:FindAbilityByName(sync.MOVE_ABILITY)
    assert(move.hidden == (choices > 4), "preserve existing movement visibility")
end
local state, unit = fixture(2, 1)
sync.sync(state, row)
assert(not unit:FindAbilityByName(sync.DESTROY_ABILITY).hidden)
assert(not unit:FindAbilityByName(sync.MOVE_ABILITY).hidden)
state, unit = fixture(6, 5, "class_1")
sync.sync(state, row)
assert(unit:FindAbilityByName(sync.DESTROY_ABILITY).hidden, "promoted towers retain their current policy")
print("TOWER_UTILITY_VISIBILITY_PASS: base 1-5 destruction with 0-7 choices, refresh order, earlier and promoted towers")

-- The disabled final upgrade must not replace the existing utility controls.
state, unit = fixture(4, 25, "class_5")
unit:AddAbility("ability_upgrade_tower_lv01")
sync.sync(state, row)
assert(not unit:FindAbilityByName(sync.MOVE_ABILITY).hidden)
assert(not unit:FindAbilityByName(sync.DESTROY_ABILITY).hidden)
