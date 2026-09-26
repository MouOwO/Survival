# 存档图标运行时重编译

纹理依赖 CRC 包含换行符。旧编译产物记录的是 CRLF 配方，本机 content
使用 LF 配方，触发 Source 2 在进游戏时集中重编译。
`star_blessing_014.vtex` 的 LF CRC 是 `ad1e1161`，同一文本转换成 CRLF
后为 `0adf42a2`，与报错中的实际值和期望值完全对应。

`.gitattributes` 现在固定 `*.vtex` 使用 LF，避免 `core.autocrlf` 让不同
电脑的配方字节发生变化。已用本机资源编译器更新 regular/small 两组产物。

同步作者源到 content 后，在项目根目录执行：

```powershell
.\tools\compile_archive_textures.ps1
```

仅检查（不编译）：

```powershell
.\tools\compile_archive_textures.ps1 -CheckOnly
```

脚本先核对 `art/ui/sources` 与 content 中的配方完全一致，再离线增量编译
两组存档纹理，最后逐项检查依赖。日志保存在 `output/archive_texture_fix/`。
检查失败时不能只凭编译器退出码判断成功：依赖检查模式也会跳过失效文件。
不应通过关闭资源检查或隐藏控制台日志来掩盖过期产物。

更换引擎版本、图片源或配方后需重新运行。此检查验证编译依赖一致性，
不代表已测得游戏帧率改善，也不覆盖其他 UI、材质和粒子资源。
