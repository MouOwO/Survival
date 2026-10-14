# 原生 Dota 2 HUD 属性图标核对

这些图标来自本机 Valve pak01_dir.vpk。已实际查看导出 PNG；未生成、重绘、裁剪或改色。正式游戏直接使用原生 s2r URI，导出 PNG 只用于浏览器预览。

|属性|原生 URI|导出尺寸|原生绑定|
|---|---|---|---|
|attack|s2r://panorama/images/hud/reborn/icon_damage_psd.vtex|32 × 32|panorama/styles/hud/dota_hud_stats_region.vcss_c #DamageIcon|
|armor|s2r://panorama/images/hud/reborn/icon_armor_psd.vtex|32 × 32|panorama/styles/hud/dota_hud_stats_region.vcss_c #ArmorIcon|
|attack_speed|s2r://panorama/images/hud/reborn/icon_attack_speed_psd.vtex|32 × 32|panorama/styles/hud/dota_hud_stats_region.vcss_c #AttackSpeedIcon|
|strength|s2r://panorama/images/primary_attribute_icons/primary_attribute_icon_strength_psd.vtex|45 × 45|panorama/styles/hud/tooltip_unit_damage_armor.vcss_c #StrengthIcon|
|agility|s2r://panorama/images/primary_attribute_icons/primary_attribute_icon_agility_psd.vtex|45 × 45|panorama/styles/hud/tooltip_unit_damage_armor.vcss_c #AgilityIcon|
|intelligence|s2r://panorama/images/primary_attribute_icons/primary_attribute_icon_intelligence_psd.vtex|45 × 45|panorama/styles/hud/tooltip_unit_damage_armor.vcss_c #IntelligenceIcon|

攻击是灰白剑、护甲是灰白盾、攻速是灰白手掌；与原生 stats_region 实际绑定一致。三围是红色力量、绿色敏捷、蓝色智力圆章，实际绑定来自原生 tooltip_unit_damage_armor；同一资源包也有 24 × 24 的 mini 版供紧凑界面比较。

manifest.json 包含原生贴图 SHA-256、原样 PNG SHA-256、图标 alpha 边界、原生 URI 到项目内 PNG 路径的映射，以及 11 个原生 XML/CSS 资源与 DATA 解码的哈希。编译资源和 DATA 可从正式 pak01_dir.vpk 再次导出，属于本机可选缓存。使用这些图标不需要新增游戏内图片。

六种属性建议使用同一尺寸与固定数字起点：攻击/护甲/攻速按 24–28 UI px；三围同样 24–28 px，可比较 full-size 45 px 源图与 mini 24 px 源图。不要按单张 alpha 可见边界重新裁图，否则盾和剑的原生画面尺度关系会改变。图标与数字用各自独立节点，资源数字的列宽与左起点固定。

本检查未修改 HUD 代码，也未操作游戏；不把原生资源存在和浏览器可读解码当作已完成游戏内布局验收。
