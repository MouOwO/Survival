package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

package.loaded["core/logger"] = { error = function() end }
package.loaded["core/event_bus"] = {
    request = function() return { eligible = false } end,
}
package.loaded["core/events"] = {
    TOWER_FUSION_ELIGIBILITY_REQUEST = "tower_fusion_eligibility_request",
}

local abilities = {}
local function ability(name)
    return {
        name = name,
        hidden = false,
        IsNull = function() return false end,
        GetAbilityName = function(self) return self.name end,
        IsHidden = function(self) return self.hidden end,
        SetHidden = function(self, hidden) self.hidden = hidden end,
        SetLevel = function() end,
        SetActivated = function() end,
    }
end

local unit = {}
function unit:IsNull() return false end
function unit:entindex() return 1001 end
function unit:FindAbilityByName(name)
    for _, current in pairs(abilities) do
        if current.name == name then return current end
    end
    return nil
end
function unit:AddAbility(name)
    local created = ability(name)
    local index = 0
    while abilities[index] do index = index + 1 end
    abilities[index] = created
    return created
end
function unit:RemoveAbility(name)
    for index, current in pairs(abilities) do
        if current.name == name then
            abilities[index] = nil
            return
        end
    end
end
function unit:GetAbilityByIndex(index) return abilities[index] end

for _, name in ipairs({
    "ability_upgrade_tower_lv01",
    "ability_building_blink",
    "ability_destroy_arrow_tower",
}) do
    unit:AddAbility(name)
end

local state = {
    unit = unit,
    building_id = "arrow_tower",
    player_id = 0,
    level = 1,
    tower_class = "anti_air_tower",
    fusion_participated = false,
    definition = { class_options = {} },
}
local row = {
    level = 1,
    max_level = 5,
    rarity = "N",
    active_skill_ids = {
        "ability_upgrade_tower_lv01",
        "ability_building_blink",
        "ability_destroy_arrow_tower",
    },
    skill_ids = { "anti_air_missile_lv01" },
}

package.loaded["systems/tower_ability_sync"] = nil
require("systems/tower_ability_sync").sync(state, row)

local visible = {}
for index = 0, 23 do
    local current = unit:GetAbilityByIndex(index)
    if current and not current:IsHidden() then
        visible[#visible + 1] = current:GetAbilityName()
    end
end

assert(#visible == 4, "unexpected visible ability count")
assert(visible[1] == "ability_upgrade_tower_lv01", "upgrade ability order changed")
assert(visible[2] == "anti_air_missile_lv01", "route ability was not moved left")
assert(visible[3] == "ability_building_blink", "move ability is not penultimate")
assert(visible[4] == "ability_destroy_arrow_tower", "destroy ability is not last")

print("TOWER_UTILITY_ABILITY_ORDER_PASS")