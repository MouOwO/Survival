# 图片丢失修复

两份用户日志反复报告 3 个 PNG 依赖由 present 变为 missing，继而导致样式关联的纹理 ERROR_COMPILEFAIL。检查时三个文件在 Windows 中均可访问；content/panorama/images 是上一轮创建的目录联接。恢复实体 content 输入后编译器能正常读取资源并完成正式根布局编译，证据指向引擎资源扫描与目录联接不兼容。

修复：保留 art/ui/sources 为美术主源，将正式 content 图片目录恢复为实体目录，复制并校验 2,293 个文件。新增 sync_content_images.ps1，正式 compile.ps1 在编译前自动同步。setup_source_links.ps1 和历史迁移脚本已修正，不再创建 content 联接。

首次两轮强制编译遇到运行中纹理写入失败，最终一轮全部根布局编译通过（tools/ui_release/compiled.json 与 compile_*.log）。增量编译也无失败。没有关闭用户的 Hammer 或游戏。

当前会话截图 recovered_game.png 中缺图仍存在，不能宣称游戏内恢复通过。日志明确记录 already tried with this fingerprint / Suppressing on-demand recompile；需要保存 Hammer 工作后重启整个 Dota 工具会话，重新加载资源并验收。该步骤尚未执行。
