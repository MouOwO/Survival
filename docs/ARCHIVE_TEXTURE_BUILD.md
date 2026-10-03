# 存档图标运行时重编译

纹理依赖 CRC 包含换行符。源配方与编译产物记录的换行格式不一致时，
Source 2 会在使用图标时集中重新编译，即使图片像素没有变化。

2026-10-03 本机复现：`star_blessing_012.vtex` 的 CRLF CRC 为 `15783df3`，
同一内容使用 LF 后为 `cd301d5c`，与控制台的实际值和期望值完全对应。
当时两组共 876 个配方均为 CRLF，`git ls-files --eol` 显示 `i/lf w/crlf`。

`.gitattributes` 已固定 `*.vtex` 使用 LF，但新增／合并属性规则不保证
把已经存在的工作区文件重新写一遍。Git 规范化比较还可能把 CRLF 文件
判断为“未修改”，不能仅凭 `git status` 推断实际磁盘字节已符合规则。

## 本机修复及其他电脑拉取后的操作

1. 正常退出 Dota 2 和创意工坊工具。
2. 在项目根目录双击 `repair_archive_textures.cmd`。
3. 等待 `ARCHIVE_TEXTURES_READY: 876 textures passed compiler dependency checks.`
   再启动游戏。数量以实际配方文件数为准。

等效 PowerShell 命令：

```powershell
.\tools\compile_archive_textures.ps1 -Repair
```

仅检查（不编译）：

```powershell
.\tools\compile_archive_textures.ps1 -CheckOnly
```

`-Repair` 先统一作者源 `art/ui/sources`、`panorama/src/images`、引擎
`content/dota_addons/survival/panorama/images` 三处配方为 UTF-8 无 BOM / LF，
检查对应 PNG，补齐缺失的副本，再离线增量编译两组存档纹理。
三处若存在实际配方内容或图片内容差异，会在写入前中止，保留待核对的修改。
重复运行不会重写已相同的源文件。修复前的源文件和编译产物备份、编译和依赖
检查日志均位于 `output/archive_texture_fix/`。没有 `-Repair` 时仅接受已同步的 LF 输入。

引擎 content 目录位于此 Git 仓库之外，拉取 game 仓库不会自动更新它。
不能直接从另一台机器复制旧 content 覆盖当前目录。图片同步脚本也会拒绝
把 CRLF 存档配方再次复制到 content，提示先运行修复入口。

## 提交注意

修复脚本、属性规则和实际资源源文件可以正常提交。编译产物是仓库跟踪的文件，
提交后其他电脑确实会收到；若依赖字节仍不一致，可能把运行时重编译问题带过去。
不要将 `git status` 中所有 `_c` 文件一并视为功能修改提交。先同步源文件、通过
依赖检查，再区分实际资源变化与本机自动重编译。其他材质、粒子、脚本产物
需按各自源文件与编译流程另行核验，不能用本次图标检查替代。

检查失败时不能只凭编译器退出码判断成功：依赖检查模式也会跳过失效文件。
不应通过关闭资源检查或隐藏控制台日志来掩盖过期产物。

更换引擎版本、图片源或配方后需重新运行。此检查验证编译依赖一致性，
不代表已测得游戏帧率改善，也不覆盖其他 UI、材质和粒子资源。

2026-10-03 本机修复结果：三处合计规范化 2628 个配方副本，核对 438 张
原图；资源编译器输出 `269 compiled, 0 failed, 607 skipped`。随后两次依赖
检查均为 876/876 有效。示例 `star_blessing_012` 的源 CRC 恢复为
`cd301d5c`，编译后的纹理 DATA 和像素载荷与仓库版本一致，仅依赖元数据
不同。源配方经 Git 规范化后的内容无差异。本轮保留其他本机生成的产物修改，
没有将它们批量纳入修复提交。
