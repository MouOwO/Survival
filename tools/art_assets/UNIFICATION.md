# 实际源文件统一迁移

根目录 ui 已迁入 art/ui/development，原 panorama/src/images 的 2,293 个文件已迁入 art/ui/sources。正式 content 原有 2,291 个图片输入与原图逐文件一致，删除重复物理目录后，content/panorama/images 与 panorama/src/images 均建立 Windows 目录联接，指向 art/ui/sources。游戏编译资源和资源标识保持原位。

备份及迁移清单见 unification.json，项目外全量备份为 D:/survival_ui_backups/release_5d5c1152eb/art_source_unification.zip。源文件迁移前后 SHA256 校验通过；构建模块的工程根路径和工具引用已调整到新目录深度。

删除旧目录后，每日奖励、抽奖、肉鸽、商城模拟测试，以及 52 张肉鸽插画映射/哈希检查通过。美术索引重新生成，2,901 个快捷方式目标验证通过。未重新编译或进行游戏内验收。

新构建入口：art/ui/development/remaining_ui_handoff_v1/prepare.cjs。
本机兼容联接恢复工具：tools/art_assets/setup_source_links.ps1。
本轮未操作 Git 索引或提交：现有 Git 跟踪路径可能仍通过旧兼容目录访问文件。后续提交源文件迁移时应统一采用 art/ui/sources，并移除旧路径的索引记录，避免把两条路径重复提交；本机目录联接不能代替跨机器初始化步骤。
