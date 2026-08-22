-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: shop_condition_schema.csv
local M = {}
M.rows = {
    { field_name = "requires_hero_summoned", value_type = "boolean", evaluation_order = 10, disabled_reason_template = "请先在英雄祭坛召唤英雄", notes = "商店整体也会在英雄召唤前隐藏。" },
    { field_name = "required_city_level", value_type = "number", evaluation_order = 20, disabled_reason_template = "需要主城达到Lv.{value}" },
    { field_name = "requires_vip", value_type = "boolean", evaluation_order = 30, disabled_reason_template = "需要VIP权限" },
    { field_name = "required_rebirth_level", value_type = "number", evaluation_order = 40, disabled_reason_template = "需要完成{value}转" },
    { field_name = "requires_building_id", value_type = "string", evaluation_order = 50, disabled_reason_template = "需要建筑：{value}" },
    { field_name = "requires_content_id", value_type = "string", evaluation_order = 60, disabled_reason_template = "需要前置内容：{value}" },
    { field_name = "purchase_limit", value_type = "number", evaluation_order = 70, disabled_reason_template = "已达到购买上限" },
    { field_name = "purchase_cooldown_seconds", value_type = "number", evaluation_order = 75, disabled_reason_template = "购买冷却中（{value}秒后可再次购买）" },
    { field_name = "encounter_id", value_type = "string", evaluation_order = 80, disabled_reason_template = "遭遇或出生点尚未配置", notes = "grant_type=start_encounter时不能为空。" },
    { field_name = "resource", value_type = "number", evaluation_order = 90, disabled_reason_template = "木材或金币不足" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["field_name"]
    if key ~= nil then M.by_id[key] = row end
end
return M
