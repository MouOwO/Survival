# 游廊商城、福利与兑换码恢复候选

2026-10-31后续：用户已明确批准使用既有私钥签名并更新原不公开游廊3824360109，以及备份/验证/接入WS4三表两RPC和现有128项码定义。先前签名审批拒绝发生在这次明确授权之前；后续签名已正常获准执行，不再等待同一授权。

签名构建最后一步遗漏了已审阅的189项头像场景策略上下文，父/候选资源实际没有缺失或变化。`recover_build.py`只在原计划和依赖hash一致、诊断证明仅策略上下文错误时复验签名、全部资源及五卷，保留已有签名/产物，不再读私钥。`release_checks.py`同时可在canonical journal更新前后验证不可变3102身份。

`native.py`安装/启动独立svt_s3102，只查询两项cvar并收集正常签名启动证明；不替用户登录、领取或购买。`ws4_deploy.py`阶段顺序为plan→upload→prepare→clone→quiesce --apply→protect-backup --apply→activate --apply→verify。只在WS4的15432库操作；clone只复制结构和公共配置，随机合成账号/码验证真实应用角色及Lua reducer，不复制真人数据或128项真实定义。仅短停WS4 API，备份在服务器保留完整dump，本机只保存经实际解密核对的DPAPI密文；迁移保留原31业务表和既有函数/ACL，登记现有128定义，不生成新码。任何后续任务不得因存在此工具便推定获得部署或登记新码授权。

`publish.py --report-sha256 <packageSHA> [--apply]`校验原生、克隆、备份、上线与复核回执，再调用冻结Steam SDK发布工具。SDK所需payload_changed字段在原增量报告中缺失，完整签名VIEW/VPK校验通过后另写带原报告hash的派生sdk_upload_report，不修改冻结报告或把ready_for_upload伪造为true。原条目、四账号、Unlisted和支付声明保持。`verify_download.py --report-sha256 <packageSHA> --download`复用未修改的官方刷新/回调/完整下载协议；不清除未知pending、不自动重试上传。4项发布准入拒绝测试和7项WS4隔离/回退测试通过，均为无外部I/O单元测试，真实SQL验收另有回执。

运维成本：显式阶段对父802份源码做一次hash/复制，新目录805份；不加入运行时定时器。生产迁移在API停机期间对32张原表、35张迁移后表各做一次摘要，共67条表摘要SQL；每表按规范JSON排序，时间O(R log R)、临时空间O(R)并受PostgreSQL工作内存/临时文件管理。实际完整备份697146字节。128项定义只在正式迁移各INSERT一次；验证构建一次code_id索引O(128)，逐项O(1)查询，总O(128)、空间O(128)。这些全量校验只在显式维护阶段运行，正常服务稳定刷新新增扫描/调用为0；兑换按现有hash和账号索引访问。构建/下载全量完整性校验与模拟计数均不代表游戏FPS或真人到账已验收。

3101实际保留 `config/mode_release_config.lua` 的 `all_difficulties_unlocked=true`。它使真实 `mode_unlock_test.reset` 锁定整局只读验收；HTTP provider在创建请求前以 `mode_unlock_test_read_only` 拒绝商城目录/存档命令，archive队列跳过奖励，现金策略返回false。不是后台商品为空，也不能从登录/HTTP开关已开推断可写。修复将正常发布默认值恢复false；普通局按真实存档解锁模式/难度，离线受控内存预览及显式验收仍隔离，旧验收局不能中途转可写。

兑换码是独立缺项：3101没有入口/布局/样式及服务端redeem分发；当前WS4也缺模块、3张表和2个RPC，原另一套后台曾部署不代表WS4已部署。六项候选包括正常模式配置、已提交的受控离线隔离锁定、redeem分发与三份已编译UI。不添加有效码表或运营Excel，不改184份保护模块、四账号门禁、鉴权、d573合同、价格/奖励配置、地图和玩法。后端仍须本次单独准备、隔离验证及明确部署授权；本工具不做云端、发奖或上传操作。

先提交源码，再用不可变提交制作只读计划：

```powershell
python tools/shop_recovery_20261031/build_release.py --source-revision <commit> --report output/shop_recovery_20261031/plan.json
python tools/shop_recovery_20261031/build_release.py --source-revision <same-commit> --prepare --report output/shop_recovery_20261031/unsigned_review.json
python tools/shop_recovery_20261031/build_release.py --source-revision <same-commit> --build --reviewed-plan output/shop_recovery_20261031/plan.json --key <existing-external-key> --report output/shop_recovery_20261031/package.json
```

全部输出必须为新的外部目录。父3101的签名/正式上传及官方下载证明、canonical journal、16项准入审阅、五份既有卷、固定替换集和签名均强制核对；不改冻结发行工具或父文件。正常产物依然 `ready_for_upload=false`，须新包原生启动与兑换码后端验收，不能直接调用旧3101发布工具伪造验收。

父信任目录的既有svt_m3101原生安装另生成三份交付回执；它们不属于审阅源。仅复制父报告固定的16项并逐字节比对，额外文件只允许该明确命名的三份回执，不修改父目录、不把回执当审阅输入。

`--prepare`只写六份替换、完整清单及明确的UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD标记，不读私钥、不复制签名，不可运行/上传。2026-10-31首次签名请求被自动审批以本轮尚未明确授权私钥签名为由拒绝，未执行；完成未签名审阅后须取得用户明确签名授权，不能绕过签名校验进行实机或发布。

`backend_plan.py --report <NEW-path>`仅在内存中对WS4现役公开源码验证两处兑换补丁并给出前后hash，查询三表/两RPC是否存在；本机现有码配置只记数量/hash，未上传或登记。它不写云端文件、不建库、迁移、部署、发奖或重启服务。正式执行仍需本次授权、服务器完整备份/本机仅DPAPI密文、仅结构及合成账号的隔离验证、原玩家/订单行摘要保护；不直接复用面向另一套5432后台的旧部署命令。

验证包括真实Lua模块链路：验收模式3类请求=0次HTTP、正常模式=3次HTTP；保留同局锁定与离线隔离。此为模拟原生边界，真实网络/发奖次数为0，不冒称线上到账。3101原样输入在相同测试中命中 `SHIPPED_READ_ONLY_ACCEPTANCE_CAUSES_EMPTY_SHOP_AND_BLOCKED_BENEFITS`。原有 `test_mode_unlock_zero.lua:378` 与 `test_archive_service.lua:155` 在未改HEAD同样失败，单独记录，不为了过测删除断言。

成本：这是显式一次构建，不加入游戏帧/计时器。N=6915个父资源、K=6个替换/新增文件；单次计划O(N log N)排序和O(N)索引，空间O(N)，K项输入每份只读一次（不可变Git缓存）。稳定游戏开关检查O(1)，不新增原生/HTTP/数据库调用或轮询。显式签名构建顺序读取必要父/候选清单和约3.79GB卷，复用未变硬链接，只重打变更所在卷；所有完整校验是一次构建阶段的完整性要求，不是循环预热。实际耗时及原生验证范围随最终回执记录。
