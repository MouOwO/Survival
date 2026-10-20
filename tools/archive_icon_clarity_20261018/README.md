# 存档图标无损纹理

`texture_plan.json` 冻结23件虚空之影的原版 V10 PNG、显式配方及目标资源。PNG 文件字节与 256×256 尺寸完全保留；新 URI 使用独立的 `s2r://panorama/images/custom_game/archive_icons_hd_v1/shadow_01.vtex` 至 `shadow_23.vtex`。正式配方在 `panorama/src/images/custom_game/archive_icons_hd_v1/`，字节相同的美术源镜像在 `art/ui/sources/custom_game/archive_icons_hd_v1/`。工具没有修改 UI、正式资源表或业务代码，中央资源表由集成任务统一更新。

```powershell
node tools/archive_icon_clarity_20261018/prepare.cjs --all
node tools/archive_icon_clarity_20261018/build_textures.cjs
node tools/archive_icon_clarity_20261018/build_textures.cjs --audit
# 原生编译会复制到 Dota Content 并更新本机 runtime，先备份，失败回滚。
node tools/archive_icon_clarity_20261018/build_textures.cjs --apply
# 只对首张做普通 PNG 自动构建隔离实验，其他22件不重编。
node tools/archive_icon_clarity_20261018/build_textures.cjs --ids shadow_01 --apply --probe-auto
node tools/archive_icon_clarity_20261018/export_probe.cjs
```

全部23张实际 VTEX DATA 均为 BGRA8888、256×256、单 mip、NO_LOD。工具逐字节核对每张 65,536 个像素及透明度，PNG、配方、美术镜像和 Content 副本均核对冻结 SHA-256。全部23张无损 payload 总计 6,029,312 字节（5.75 MiB），较原 DXT5 增加4.3125 MiB，没有扩大源图分辨率。

`--probe-auto` 使用只包含原 PNG 的 XML 并以 `resourcecompiler -f` 强制编译依赖；PNG 本身没有独立编译器。新独立 HD runtime 在探测前后 SHA-256 不变，且再次通过像素审计；探针 XML、探针 runtime 和受影响的旧 PNG runtime 均有备份，探测后恢复，避免无意义的工作区变化。

之前单图实验实测：直接生成与普通 PNG 同路径的 `virtual_01_png.vtex_c`，即使 Content 存在同名显式配方，XML强制依赖编译仍会把它覆盖为DXT5。这条失败方案的报告保留在 `same_uri_probe.json`，旧 `virtual_01_png.vtex_c` 和临时配方已精确恢复。最终采用不同路径的HD资源，避免这种覆盖。

完整编译结果：`design_refs/archive_icon_clarity_20261018/textures_compile.json`；独立单图防覆盖结果：`texture_probe.json`；原生纹理解码：同目录 `pixels/`。旧DXT5由现有Source2Viewer解码，新BGRA8888由已有 `portrait_quality_preview.cjs` 直接读取DATA payload转换，避免旧版Source2Viewer不支持当前RED2元数据的问题。解码图片是实际 runtime 资源的格式转换，不是游戏截图。实机外观由主代理单独验收。
