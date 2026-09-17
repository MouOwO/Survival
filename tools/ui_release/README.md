# survival 正式 UI 迁移与清理

已迁入验收版本 **5d5c1152eb**。正式运行入口为 `panorama/layout/custom_game/custom_ui_manifest.vxml_c`；作者源入口为 `panorama/src/layout/custom_game/custom_ui_manifest.xml`，同时同步到引擎 content/dota_addons/Survival/panorama。当前根布局引用的版本化脚本即实际加载文件，不要仅修改未被入口引用的旧同名文件。

## 接入内容

主界面、存档和新物品头像、地图抽奖主界面/详情/记录/结果、每日奖励、肉鸽卡牌、商城模拟流程及共用组件均按已验收版本移植。包括近期资源图标与等间距、商城图标尺寸、背景外延、物品栏旧阴影清理、血蓝条移除边框。

商城仍为演示模式：模拟商品、订单、本地非支付二维码和模拟状态。不请求真实支付接口，不扣款，不发放权益。本轮没有迁移测试服务器脚本，也没有改动战斗、概率、价格或奖励规则。

## 文件与验证

- `plan.json`：全部81个活动脚本/样式/布局依赖，以及图片/运行文件来源。
- `promoted.json`：实际复制文件列表。
- `verification.json`：清理后81个源码文件与1909个运行文件完整性通过；显式布局依赖无缺失。
- `compiled.json` / `compile_*.log`：正式工程根入口与布局编译通过。
- JavaScript语法、XML解析、商城模拟流程、每日奖励、抽奖及肉鸽交互检查通过；52张肉鸽插画映射通过。
- 历史 `test_archive_icons.cjs` 的第80行整段HUD等同早期版本断言已过时，因后续已验收修改失败；没有将其计入通过项。
- 发送正式工程启动命令后已看到新游戏难度选择页与迁移后的HUD（1768×992，截图见 ../../spikes/remaining_ui_handoff_v1/evidence/survival_release_hud.png）。随后游戏进程退出，未取得完整正式局跨页面验收；不能把之前隔离测试页面截图当作本轮正式验收。

## 清理与备份

清理1268个路径目标（约1211MiB）：录屏逐帧缓存、浏览器缓存、旧候选脚本，以及不再被活动入口加载的main_hud_skin/main_hud_assets源和编译文件。另归档并清理25份历史验收录像（约1147MiB）。合计约2.30GiB。清理路径与结果见 `cleanup_result.json`、`recordings_cleanup.json`；图片动态引用族、实际原图、映射表、构建脚本、交接包、静态截图均保留。

项目外备份：`D:/survival_ui_backups/release_5d5c1152eb/`。
- `before_and_removed.zip`：修改前正式UI与首批删除内容，已通过CRC和文件哈希校验。
- `manifest.json`：每个备份文件原路径、归档名、SHA256。
- `recordings/`：历史录像按原相对目录存放；`recordings_backup.json`保留路径映射。旧文档中工程内录像链接应按该映射在备份目录查找。
- `restore_ui.py`：恢复迁移前正式UI源与编译文件；恢复操作需要对引擎content目录的写入权限。清理掉的历史缓存无需恢复即可运行游戏。

## 后续修改位置

以正式XML实际include为准；当前HUD控制器 `panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js`，商城 `commerce_remaining_5d5c1152eb.js`，共用组件 `common/ui_components.js`。可复现的页面构建仍保留在 `spikes/remaining_ui_handoff_v1/prepare.cjs` 和各页面源文件；涉及重新生成时需要先核对正式工程之后新增的变更，避免覆盖。
