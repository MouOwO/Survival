local M = {}

-- Preview, tooltip and the final spend use the same quote. This is read-only;
-- construction still performs an atomic spend immediately before creating it.
function M.for_player(definition, player_id)
    local cost = definition.build_cost or {}
    local slots = 1
    if definition.id == "gold_mine"
        and require("systems/commerce_effects").owned(player_id, "giant_mine") then
        slots = math.max(1, (tonumber(definition.max_count) or 1)
            + require("systems/building_count_limit_service").bonus(player_id, "gold_mine"))
    end
    local free_altar = definition.id == "hero_altar"
        and require("systems/rogue_effect_state_service").numeric(player_id, "builder_free_hero_altar") > 0
    local free_wall = definition.id == "wall"
        and require("systems/archive_endless_service").can_rebuild_wall(player_id)
    local free = free_altar or free_wall
    return {
        wood = free and 0 or (tonumber(cost.wood) or 0) * slots,
        gold = free and 0 or (tonumber(cost.gold) or 0) * slots,
        population = free_wall and 0 or (tonumber(definition.population_cost) or 0) * slots,
        mine_slots = slots, free_altar = free_altar, free_wall = free_wall,
    }
end

return M
