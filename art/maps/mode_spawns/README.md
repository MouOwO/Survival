# 模式出生点

`layout.json` 保存 `template_map` 三个独立区域的点位与建造边界，Lua 配置由 `tools/mode_spawns/patch-map.cjs` 生成。玩家编号在文件中从 0 开始。

- 丰饶：东、南、西、北四块草地，怪物从中央干地区域出现。
- 极寒：四块雪地平台从上到下排列，怪物从中央区域出现。第三平台补有雪地坡道。
- 天灾：左侧空地从上到下为 1–4 号玩家；对应右侧房间刷怪。

Hammer 中每个点都是独立的 `info_target`。运行时必须找到对应实体，缺失时不会回退到常规岛屿。建造边界与各玩家草地独立，地图通路不作为建造范围。

修改时先将**当前保存的** Hammer 源转换成文本，再应用补丁。不要用旧整图覆盖后来保存的地图：

```powershell
dmxconvert.exe -i <当前template_map.vmap> -o <before.vmap> -oe keyvalues2
node tools/mode_spawns/patch-map.cjs --source <before.vmap> --out <patched.vmap> --report <report.json>
./tools/mode_spawns/install-compile.ps1 -PatchedMap <patched.vmap> -BaselineText <before.vmap> -OutputDirectory output/mode_map_rebuild
```

安装脚本会检查源快照、备份 Hammer 源与运行地图，随后编译并核对 VPK 内记录的源校验值。`dmxconvert` 每次生成的临时前缀 ID 不参与快照比较，其他地图数据逐字节比较。补丁保留所有无关实体、网格与地形，仅添加模式标记、指定坡道及丰饶干地通路。

加载新地图后，在 Tools 控制台执行：

```text
script_reload_code tests/c6_console_generated/<由验证工具生成的请求文件>.lua
```

或者通过已连接的项目控制台运行：

```powershell
node tools/mode_spawns/verify-native.cjs output/mode_map_rebuild/native.json
```

只读检查覆盖 27 个标记、12 条 `CanFindPath` / `FindPathLength` 路线；不会生成单位、改变通关记录或发放资源。
