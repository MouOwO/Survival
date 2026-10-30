# 锋刃宗师头饰与 ScenePanel 对照｜2026-10-30

用户反馈场内头部呈白色、头像呈金色兜帽。本轮在独立 Tools 离线内存局检查实际实体、Valve 原始资源及官方编译场景，调整开发版头像；未上传游廊或部署服务器。

## 查明的差异

- 两处均配置 `armor_for_the_favorite_head.vmdl`。官方物品图标本身包含兜帽、金色面具和后方白鬃；不能仅凭俯视白色、正面兜帽的差异认定换错饰品。
- 离线实际头部组件存在，alpha 为 255，owner/parent 指向正确英雄，未混入原生 wearable。9 个头部骨骼均与 Arcana 本体相容；重新 FollowEntity 不改变外观。没有修改世界装配服务。
- 原头像照用基础剑圣相机，低位仰视约 5°，与场内俯视差别明显。头像本体皮肤来自 CSV 的 1，世界配置则明确为 0，这处配置漂移已确认。
- 截图对应的 3004 候选与开发版头部配置、编译场景一致；没有把问题归咎于旧缓存或未编译资源。签名候选文件未改动。

## 最终开发修改

- 仅 `hero_permanent_hero_blademaster` 的 `model_skin` 从 1 对齐至 0，CSV 与生成 Lua 配套。
- 仅该外观头像采用接近正面的俯视镜头：位置 `321.856619 12.880622 257.916392`，角度 `25 185 0`，FOV `14`。保持完整面具和白色头部轮廓，避免侧转后肩甲遮脸。
- 保留原头饰及五件配件、骨骼合并、姿态、官方照明与背景。新场景为 `portraits/monster_1bc348e8932e1cfc065b_v1`，game 文本源/VPK、content 可编辑 VMAP、映射 JS 与官方编译资源配套；content 新 VMAP 使用 LFS。
- 原 `monster_960cd997848edbc33fde_v1` 场景保留。中间候选移到 ignored output，未纳入提交。其余 196 个外观、QOP 镜头、预热与 100ms 防闪逻辑均无变化。

## 验证和范围

- 原生离线局实际召唤锋刃宗师，重载新资源后观察两个动画时刻，面具可见、无肩甲遮脸。并非在线多人或游廊发布验收。
- `tools/test_blademaster_portrait_skin.py` 三项通过：世界/CSV/Lua/Scene 本体一致、五件配件及绑定保持、镜头焦点/取景符合配置。
- `tools/test_monster_portraits.cjs` 通过，197 外观/188 场景；`tools/test_hero_cosmetic_mirror.lua` 通过。
- 官方资源编译零失败；content 二进制回转仅有 float32 精度差。独立审阅实际 VPK 实体及编译 JS，确认与源码/manifest 相符。

本机证据目录为 `output/juggernaut_head_match_20261030/`：`appearance.lua.json`、`native_favorite_head.png`、`head_geometry_review.json`、`candidate_comparison_summary.json`、`close_front_before.png`、`camera_c_visible.png`、`camera_c_final.png`。编译核对见 `output/blademaster_portrait_skin_20261030/camera_C_implementation.json`。

需要重新加载开发资源/新局查看本次镜头；现役 3004 游廊包仍为此前版本。整体暖色照明与场内光照不同，保留官方照明，本轮没有重做材质或更换头饰。
