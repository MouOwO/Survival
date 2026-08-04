local M = {}

local BUILD = "preserve_engine_abilities_origin_dev_v1_20260731"
local VISIBLE_REPLACEMENTS = {
    { native = "undying_decay", custom = "ability_build_wall" },
    { native = "undying_soul_rip", custom = "ability_build_main_city" },
    { native = "undying_tombstone", custom = "ability_build_arrow_tower" },
    { native = "undying_ceaseless_dirge", custom = "ability_build_gold_mine" },
}
local BUILDER_BLINK_ABILITY = "ability_survival_builder_blink"
local BUILDER_REMOVED_UTILITY_ABILITIES = {
    "ability_survival_pickup_materials",
    "ability_survival_return_home",
}

local function add_ability(hero, ability_name)
    local ability = hero:FindAbilityByName(ability_name)
    if not ability or ability:IsNull() then
        ability = hero:AddAbility(ability_name)
    end
    if ability then
        ability:SetLevel(1)
    end
    return ability
end

function M.apply(hero)
    for _, replacement in ipairs(VISIBLE_REPLACEMENTS) do
        local native = hero:FindAbilityByName(replacement.native)
        if native and not native:IsNull() then
            if math.max(0, tonumber(hero:GetAbilityCount()) or 0) <= 1 then
                print("[SURVIVAL_HERO_ABILITIES] build=" .. BUILD
                    .. " success=false reason=nonzero_guard native="
                    .. replacement.native)
                return false
            end
            hero:RemoveAbility(replacement.native)
        end

        local custom = add_ability(hero, replacement.custom)
        if not custom or custom:IsNull() then
            print("[SURVIVAL_HERO_ABILITIES] build=" .. BUILD
                .. " success=false reason=custom_add_failed custom="
                .. replacement.custom)
            return false
        end
    end

    if hero:GetUnitName() == "npc_dota_hero_undying" then
        for _, ability_name in ipairs(BUILDER_REMOVED_UTILITY_ABILITIES) do
            local ability = hero:FindAbilityByName(ability_name)
            if ability and not ability:IsNull() then
                hero:RemoveAbility(ability_name)
            end
        end
        local blink = add_ability(hero, BUILDER_BLINK_ABILITY)
        if not blink or blink:IsNull() then
            print("[SURVIVAL_HERO_ABILITIES] build=" .. BUILD
                .. " success=false reason=utility_add_failed custom="
                .. BUILDER_BLINK_ABILITY)
            return false
        end
        blink:SetHidden(false)
        blink:SetActivated(true)
        if blink.SetAbilityIndex then
            blink:SetAbilityIndex(#VISIBLE_REPLACEMENTS)
        end
    end

    local ultimate = hero:FindAbilityByName("undying_flesh_golem")
    if not ultimate or ultimate:IsNull() then
        print("[SURVIVAL_HERO_ABILITIES] build=" .. BUILD
            .. " success=false reason=native_ultimate_not_found")
        return false
    end
    ultimate:SetHidden(true)

    local ultimate_hidden = ultimate:IsHidden()
    print("[SURVIVAL_HERO_ABILITIES] build=" .. BUILD
        .. " success=" .. tostring(ultimate_hidden)
        .. " visible_replacements=" .. tostring(#VISIBLE_REPLACEMENTS)
        .. " utility_abilities=1"
        .. " native_ultimate_hidden=" .. tostring(ultimate_hidden)
        .. " engine_abilities_preserved=true"
        .. " ability_count=" .. tostring(hero:GetAbilityCount()))
    return ultimate_hidden
end

return M