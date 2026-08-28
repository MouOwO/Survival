# Cosmetic Portrait Phase 2A spike

本尖峰隔离验证 `DOTAScenePanel` 的 Direct Unit、Portrait Background Scene 和普通 `prop_dynamic` Background Control 路径。它不会加载或修改 `survival` 的生产 HUD、世界模型或饰品服务。

## 权威阶段数据

`data/axe_stages.csv` 是尖峰地图和 Panorama 阶段数据的唯一输入：

1. Base Axe；
2. Head `22217`；
3. Head `22217` + Weapon `22218`；
4. Head `22217` + Weapon `22218` + Armor `22215` + Belt `22216` + Arms `22219`。

Base 阶段使用独立 `base_minimal` 契约：只设置 Base Axe 身份、启用、队伍、缩放和隔离开关，不生成 `item_defN`、`style_indexN`、activity 或 cosmetic 字段，且 `spawn_wearable_item_defs = 0`。后续未激活的 ItemDef 阶段仍为每个 `item_defN` 配对 `style_indexN = 0`，并设置 `spawn_wearable_item_defs = 1` 和 `EnableAutoStyles = 0`。尖峰没有 hero `skin_override`。

Renderer Sanity 的 C 控制数据单独来自 `data/renderer_sanity_control.csv`。它只生成 `phase2a_portrait/axe_prop_control`，不包含 `portrait_world_unit`、ItemDef、Weapon 或饰品实体；Axe 与红盒的 `force_hidden=0`、`editorOnly=0` 也由该 CSV 显式提供，禁止继承官方模板的隐藏/仅编辑器元数据。

## 构建

从 `D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival` 运行：

```powershell
pwsh -NoProfile -File .\tools\build_portrait_world_unit_phase2a.ps1
```

构建脚本会：

- 从本机官方 `hero_showcase_wind_ranger_default_prefab.vmap` 复制已验证的 `portrait_world_unit` 实体契约；
- 从 `axe_stages.csv` 只激活 Base Axe scene map；
- 从 `renderer_sanity_control.csv` 生成无 `portrait_world_unit` 的 C control scene map；
- 用官方 Ram's Head bundle `22214` 的 portrait camera 原点生成静态 `hero_camera`，并按 `portrait_world_unit` 原点计算瞄准角；
- 复制 Valve `addon_template` 地图作为隔离启动地图 `phase2a_lab`；
- 只重建 sibling addon `survival_phase2a`；
- 只编译 Renderer Sanity 所需的 Base 与 C scene map，不加载 Head `22217`；
- 编译独立 Panorama Manifest、layout、JS 和 CSS。

## Workshop Tools 冷启动协议

1. 关闭正在运行的自定义游戏和旧 Lua VM。
2. 在 Workshop Tools 中选择 addon `survival_phase2a`，运行 `phase2a_lab`。
3. 只检查同屏三个面板：A `DirectUnitSanity`、B `BackgroundSceneSanity`、C `BackgroundPropControl`。
4. 记录 A/B/C 的可见或纯黑结果；本轮禁止加载 Head `22217`、Weapon、其它 ItemDef 或 Phase 2B。
5. 保存 `[PHASE2A_RESULT]` 日志和红色控制台错误，然后停止实验。

静态契约、资源编译或 Lua 语法通过都不等同于 Workshop Tools 实机渲染通过。

## Renderer Sanity Check

Phase 2A 观察 UI 在 Base-only 同屏显示三个互相独立的面板：

- `DirectUnitSanity`：严格使用 `<DOTAScenePanel id="DirectUnitSanity" unit="npc_dota_hero_axe" />`，不指定 `map`、`camera`、`portrait_world_unit`、ItemDef 或 `phase2a_portrait/axe_base`，不调用现有 scene map。
- `BackgroundSceneSanity`：保留当前阶段的 background scene；Base 阶段为 `map="phase2a_portrait/axe_base" camera="hero_camera"`。
- `BackgroundPropControl`：使用 `map="phase2a_portrait/axe_prop_control" camera="hero_camera"`；场景只含 Axe `prop_dynamic`、普通 `red_box` `prop_dynamic`、无 parent 相机和直接全局灯光，明确不含 `portrait_world_unit`。

三块面板均为独立可见的 `340x340` 视口。用户已确认 `map_enable_portrait_worlds` 为 `Enabled`，所以本检查不再修改 B 的 `hero_camera`，也不把全局 Portrait World 开关作为黑屏假设。

实机判定规则：

1. A 可见、B 黑、C 可见：background map + camera PASS；`portrait_world_unit` 单独 FAIL；下一步只审计 `portrait_world_unit` 实体契约。
2. A 可见、B 黑、C 黑：`portrait_world_unit` 尚不能定罪；下一步审计 background scene 加载契约或 packaging 路径。
3. 其它组合：停止并记录，不进入 ItemDef 或后续阶段。

## 当前实机结果

2026-08-27 用户实机确认：A `DirectUnitSanity` 可见（PASS）；B `BackgroundSceneSanity` 使用 `map="phase2a_portrait/axe_base" camera="hero_camera"` 纯黑（FAIL）；C `BackgroundPropControl` 可见（PASS）。B 已改为 `portrait_world_unit` Base 最小实体契约并重新编译，修改后的 A/B/C 尚待冷启动复测；本轮不加载 Head `22217`。
