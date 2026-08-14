-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: building_definitions.csv
local M = {}
M.rows = {
    { building_id = "wall", name = "��ǽ", unit_name = "building_wall", max_count = 1, requires_city_level = 0, population_cost = 0, builder_ability = "ability_build_wall", disable_after_built = true, notes = "����ɹ���Undying�Ľ����ǽ�����ڿͻ����ûң����������֤max_count=1��" },
    { building_id = "main_city", name = "����", unit_name = "building_main_city", max_count = 1, requires_city_level = 0, population_cost = 0, builder_ability = "ability_build_main_city", disable_after_built = true, notes = "����ɹ���Undying�Ľ������Ǽ����ڿͻ����ûң����������֤max_count=1��" },
    { building_id = "arrow_tower", name = "����", unit_name = "building_arrow_tower", max_count = 7, requires_city_level = 1, population_cost = 0, unlock_condition = "main_city_level>=1", builder_ability = "ability_build_arrow_tower", disable_after_built = false, notes = "����5���������ѡһתְ��" },
    { building_id = "building_farm", name = "�˿�ũ��", unit_name = "building_farm", max_count = 1, requires_city_level = 1, population_cost = 0, unlock_condition = "main_city_level>=1", builder_ability = "ability_build_farm", disable_after_built = false },
    { building_id = "building_research_lab", name = "�о���", unit_name = "building_research_lab", max_count = 1, requires_city_level = 1, population_cost = 0, unlock_condition = "main_city_level>=1", builder_ability = "ability_build_research_lab", disable_after_built = true },
    { building_id = "building_advanced_research_lab", name = "�߼��о���", unit_name = "building_advanced_research_lab", max_count = 1, requires_city_level = 4, population_cost = 0, unlock_condition = "main_city_level>=4", builder_ability = "ability_build_advanced_research_lab", disable_after_built = true },
    { building_id = "building_challenge", name = "Challenge Building", unit_name = "building_challenge", max_count = 1, requires_city_level = 1, population_cost = 0, unlock_condition = "building_count(building_research_lab)>=1", builder_ability = "ability_build_challenge", disable_after_built = true, notes = "Requires completed research lab; no upgrades." },
    { building_id = "gold_mine", name = "���", unit_name = "building_gold_mine", max_count = 5, requires_city_level = 3, population_cost = 2, unlock_condition = "main_city_level>=3", builder_ability = "ability_build_gold_mine", disable_after_built = false, notes = "����3�����������5������������2000ľ�ģ�ռ��2�˿ڡ�" },
    { building_id = "hero_altar", name = "Ӣ�ۼ�̳", unit_name = "building_hero_altar", max_count = 1, requires_city_level = 3, population_cost = 0, unlock_condition = "main_city_level>=3", builder_ability = "ability_build_hero_altar", disable_after_built = true, notes = "����3����ɽ��죻ÿλ���ֻ���ٻ�һ��Ӣ�ۡ�Ӣ���ٻ���ɺ��̳����Ϊ��ͨ�������̵�UIͬʱ�������������300ľ��+100���Ϊ�ݶ�ֵ��" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["building_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
