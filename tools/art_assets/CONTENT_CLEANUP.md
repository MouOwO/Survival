# Content 清理记录（2026-09-12）

仅清理 content/dota_addons/Survival，未扩大到其他插件或引擎目录。

- 删除 82 个文件，共 8,827,620 字节（8.42 MiB）。
- 清理 archive_gothic、archive_gpu_256、archive_gpu_bgra、st2_localmount 四个未引用图片资源组、两份旧 CSS、shop_ui.js.orig 备份和 materials/example 示例纹理。
- 已检查游戏 UI 源码、脚本、配置、content 文本资源和保留纹理配方的引用；保留动态按资源组拼接路径可能使用的文件。
- content 中剩余的大量 PNG 仍被 VTEX 配方作为编译输入引用。保留实体图片目录，避免再次发生 Source 2 不识别目录链接造成的图片缺失。
- 保留地图、特效、字体及授权说明、仍使用的素材和美术索引；没有清理 Git 历史。
- art/ui/sources 中的美术原稿保留；同步脚本跳过本轮淘汰的四个图片资源组，验证同步后未重新生成。
- 备份：D:/survival_ui_backups/content_cleanup_20260912，逐文件 SHA256 校验后删除。
- 详细删除清单及哈希：content_cleanup_result.json；范围与理由：content_cleanup_plan.json。

验证：8 个正式 UI 根 XML 增量编译全部退出码 0。两次强制重编译分别遇到 slot_pressed_png.vtex_c、rogue_defense_png.vtex_c 写入失败（非本次删除资源），未宣称强制全量编译通过。未进行游戏内逐页面视觉复验。
