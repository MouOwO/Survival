-- Public display DTO only. Explicit paths bound the work independently of the
-- hero's inventory/research catalogue. The original combat projection owns math.
local M={numeric_paths={},text_paths={}}
local function add(target,prefix,names)for name in names:gmatch("%S+")do target[#target+1]=prefix..name end end
add(M.numeric_paths,"",[[level absolute_level route_level is_resource_tree max_level health max_health health_scale
 mana max_mana attack_min attack_max base_damage_outgoing_pct runtime_armor armor effective_war3_armor
 armor_mapping_version stat_units_version armor_display attack_speed attack_speed_percentage attack_speed_stat
 strength agility intellect scale weapon_growth_attack damage_gain_attack damage_gain_all_attributes
 attack_gain_per_attack stage_attack_target stage_attack_count stage_attack_remaining is_max_level refresh_version refresh_sequence
 hero_base_attack_min hero_base_attack_max weapon_base_attack_min weapon_base_attack_max attribute_attack_bonus attribute_health_bonus portrait_display_only]])
for _,name in ipairs({"attack","armor","strength","agility","intellect","health"})do
 add(M.numeric_paths,"display_"..name.."_","bonus pct base")
end
for _,name in ipairs({"attack","armor","health"})do
 add(M.numeric_paths,"building_stat_details."..name.."_","base bonus pct flat technology_flat technology_pct permanent_flat permanent_pct talent_flat talent_pct recruit_training_pct")
end
add(M.numeric_paths,"stat_tooltips.attack.","minimum maximum")
add(M.numeric_paths,"stat_tooltips.armor.","display_value logical_value runtime_value mapping_version physical_reduction_pct")
add(M.numeric_paths,"stat_tooltips.attributes.","strength agility intellect")
add(M.numeric_paths,"stat_tooltips.attack_speed.","percentage base_interval reduced_interval attack_interval attacks_per_second runtime_bonus_pct")
add(M.text_paths,"",[[unit_name display_name hero_id weapon_content_id weapon_name tower_class building_id
 model_asset_id portrait_unit_name portrait_item_def portrait_model_name]])
for _,group in ipairs({"interval_reductions","speed_bonuses"})do for index=1,8 do
 local prefix="stat_tooltips.attack_speed."..group.."."..index.."."
 add(M.numeric_paths,prefix,"value");add(M.text_paths,prefix,"label")
end end
table.sort(M.numeric_paths);table.sort(M.text_paths)
M.units={armor_unit="war3_display",["stat_tooltips.attack.unit"]="logical_damage",
 ["stat_tooltips.armor.unit"]="war3_display",["stat_tooltips.attributes.unit"]="logical_attribute",
 ["stat_tooltips.attack_speed.unit"]="percent"}
return M
