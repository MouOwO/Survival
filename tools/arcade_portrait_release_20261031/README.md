# 头像／性能／英雄传送限定发行工具

基线为原不公开条目3824360109的已发布3102，官方manifest `2484609663754935010`，6917资源/184保护模块；原package报告SHA `fede692a9d442c7ae4dc24032300d9a4620f1646e963bb7aeb758ff2866dc555`。新sequence为2026110101，revision为WS4-PORTRAIT-PERF-TELEPORT-01。本工具不会上传、部署、安装、启动Dota或操作账号。

固定12项运行资源：renderer编译物、hero_teleport_access新模块及另外三个D相关Lua、commerce_actions编译物、resource/resource-localization/panorama-localization的中英六份文案。新增文件仅hero_teleport_access，预计资源数6918。原dirty HUD、Python缓存、current bundle、头像实验及审计报告均不参与。两个编译物及其Git源码必须匹配本轮已核对的官方编译SHA，不能靠工作区临时替换冒充不可变提交。

当前准备阶段只能运行只读scope；根提交源代码后再提供40位commit建立最终计划。不要将scope作为构建计划。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/build_release.py --scope --report output/arcade_portrait_release_20261031/scope_v01.json
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/build_release.py --source-revision <immutable40> --report output/arcade_portrait_release_20261031/plan_v01.json
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/build_release.py --prepare --source-revision <same40> --reviewed-plan output/arcade_portrait_release_20261031/plan_v01.json --reviewed-plan-sha256 <planSHA> --report output/arcade_portrait_release_20261031/unsigned_v01.json
```

所有报告为NEW且限于本工具ignored输出目录。最终候选路径为外部 `D:/Survival_发布候选/20261101_ws4_portrait_perf_teleport_v01_*`，分卷路径为外部 `D:/Survival_工坊输出/20261101_ws4_portrait_perf_teleport_v01`。未签名review仅12个替换/新增文件、完整manifest及先写入的UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD标记；没有签名，不是完整可运行安装，不得安装/上传。plan/unsigned不会接受key，不存在payload_changed=false或已认证payload的虚假宣称；dry_run=true、signature_valid=false、ready_for_upload=false。

未来--build分支仅已实现而未在准备阶段执行。根须先审阅具体候选并取得本次所需签名授权，再使用同一immutable40、明确reviewed-plan及其SHA、既有外部key和NEW输出。它不生成新key、不覆盖旧目录，也不修改冻结3101/3102工具或父包。成功构建才写payload_changed=false：该SDK字段只表示已签名运行payload经完整VIEW/VPK校验后未被打包过程改变。ready_for_upload仍false，原生、线上性能及具体游廊发行验收由后续独立步骤完成。

```powershell
# 仅后续明确授权后，由根执行；本轮不执行。
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/build_release.py --build --source-revision <same40> --reviewed-plan output/arcade_portrait_release_20261031/plan_v01.json --reviewed-plan-sha256 <planSHA> --key <existing-external-key> --report output/arcade_portrait_release_20261031/package.json
```

manifest保留所有父字段和未知顶层/文件行字段，完整重算files/count/bytes/content及by_directory。原184保护模块及16项准入审阅逐字节保持，正式all_difficulties_unlocked=false、四账号、支付策略与d573保持；protected archive_http_bundle按其已签名的混淆字节验证，不能对混淆文件查找明文d573字符串。父trusted目录仅允许明确已存在的svt_s3102三份安装handoff额外记录。

完整构建的所有父/VIEW/VPK验证和最后父postcheck均包在同一头像scene_maps上下文，避免此前只在中间校验启用、最后遗漏的策略错误。`release_checks.validated_package(reportSHA,full=True)`在以后journal更新前后均可验证该冻结package，检查完整manifest/签名原始摘要、原16审阅、184保护模块沿用和全部五卷CRC/MD5/SHA；只读，不更新journal。最终签名验证和上传不能接受unsigned报告。

成本：仅显式运维阶段。N=6917父资源，K=12替换/新增；一次投影O(N)索引＋O(N log N)排序，O(N)空间；K项不可变Git blob在进程内复用，不反复读取工作区全场。只读scope不打包、读key、建立候选或启动Steam。完整构建顺序读取约3.79GB父/候选/分卷做必要完整性检查，复用未变只读硬链接，仅重打变化卷；这不是帧循环、预热或游戏定时器，不增加游戏稳定刷新成本，不据运维耗时宣称FPS。

测试入口：`python -B -m unittest discover -s tools/arcade_portrait_release_20261031 -p test_build_release.py`。覆盖未知manifest/行字段保留、目录计数、安全路径/大小写冲突、不可变commit、review SHA、未签名阶段禁签名、拒绝已存在review目录和父模块导入别名隔离；全部使用合成数据，无真实私钥、Steam或云端调用。
