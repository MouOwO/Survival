# 第一版素材与字体接入记录

本页复用附件 `assets` 中的 38 个正式 PNG：4 张背景、11 个公共组件、23 个物品图标。`reference` 带字切片和 `scene_exterior_reference.png` 只供对照，不进入正式 UI。图标与边框保留原 RGBA；不得把透明像素中留存的 RGB 母图文字转成不透明内容。

包内 `SourceHanSansSC-Regular.otf` 与工程已有 authoring/runtime `Radiance-Survival-SourceHanSansSC-Regular.otf` 的原字节相同，均为 16,529,832 bytes，SHA-256：

`f1d8611151880c6c336aabeac4640ef434fa13cbfbf1ffe82d0a71b2a5637256`

因此页面直接使用现有 `Source Han Sans SC` Regular 注册，不重复安装字体、不改系统 fonts.conf。原 OFL 许可证保留在附件包和现有工程字体许可证目录。PNG SHA、固有尺寸、23 处透明缺口与数量牌完整覆盖记录见 `../work/assets_audit.json`。

## 编译与原生截图工具

在项目根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/void_shadow_v1/compile.ps1
```

工具仅复制 `work/compile_scope.json` 明确列出的任务 PNG、JS、CSS、两个布局和原存档控制器。先备份 Content 及原生输出到 `output/void_shadow_v1`，再按脚本样式 → 专用素材预加载布局 → 存档布局编译。资源布局强制编译所列 PNG 依赖；所有产物都检查非空、更新时间和 SHA。失败会恢复这批文件的原 Content/runtime 状态。附件 PNG 保持原字节，不做转换、重绘或拉伸导出。

游戏已加载本页且 Workshop Tools 可用时，可运行：

```powershell
node tools/void_shadow_v1/native.cjs --menu archive_category_shadow --void-action inspect
node tools/void_shadow_v1/native.cjs --void-action "hover shadow_01" --capture void_v1_tooltip
node tools/void_shadow_v1/native.cjs --void-action "filter unlocked"
node tools/void_shadow_v1/native.cjs --void-action "filter locked"
node tools/void_shadow_v1/native.cjs --void-action "filter all"
node tools/void_shadow_v1/native.cjs --void-action hide --capture void_v1_complete
node tools/void_shadow_v1/native.cjs --void-action close
```

每个截图名只能使用一次。以上截图通过 Source 2 `screenshot` 命令生成，转存 `work/native` 并留下来源 JSON。游戏在后台时，命令返回的画面可能停留于缓存帧；必须查看截图确认实际状态，不能按文件名或控制台状态认作视觉验收通过。本轮最终主图采用前台窗口的实际客户端捕获，见 [README.md](README.md)。

游戏窗口已打开目标页时，可先将鼠标移出弹窗，再进行客户端捕获：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/void_shadow_v1/window.ps1 -Show -PointerX 80 -PointerY 280
powershell -NoProfile -ExecutionPolicy Bypass -File tools/void_shadow_v1/window.ps1 -Show -Screenshot void_v1_complete_foreground.png
```

坐标示例对应本轮 1600×900 游戏客户端。窗口工具只操作经验证的 survival Workshop 会话；截图不会合成 UI。菜单沿用现有 UI 命令；本页审阅命令仅在 ToolsMode 中注册、只读取界面，不修改真实存档。此文件是工具和素材接入说明，不代替本轮实际游戏截图验收。
