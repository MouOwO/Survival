# 游廊商城、福利与兑换码恢复候选

3101实际保留 `config/mode_release_config.lua` 的 `all_difficulties_unlocked=true`。它使真实 `mode_unlock_test.reset` 锁定整局只读验收；HTTP provider在创建请求前以 `mode_unlock_test_read_only` 拒绝商城目录/存档命令，archive队列跳过奖励，现金策略返回false。不是后台商品为空，也不能从登录/HTTP开关已开推断可写。修复将正常发布默认值恢复false；普通局按真实存档解锁模式/难度，离线受控内存预览及显式验收仍隔离，旧验收局不能中途转可写。

兑换码是独立缺项：3101没有入口/布局/样式及服务端redeem分发；当前WS4也缺模块、3张表和2个RPC，原另一套后台曾部署不代表WS4已部署。六项候选包括正常模式配置、已提交的受控离线隔离锁定、redeem分发与三份已编译UI。不添加有效码表或运营Excel，不改184份保护模块、四账号门禁、鉴权、d573合同、价格/奖励配置、地图和玩法。后端仍须本次单独准备、隔离验证及明确部署授权；本工具不做云端、发奖或上传操作。

先提交源码，再用不可变提交制作只读计划：

```powershell
python tools/shop_recovery_20261031/build_release.py --source-revision <commit> --report output/shop_recovery_20261031/plan.json
python tools/shop_recovery_20261031/build_release.py --source-revision <same-commit> --build --reviewed-plan output/shop_recovery_20261031/plan.json --key <existing-external-key> --report output/shop_recovery_20261031/package.json
```

全部输出必须为新的外部目录。父3101的签名/正式上传及官方下载证明、canonical journal、16项准入审阅、五份既有卷、固定替换集和签名均强制核对；不改冻结发行工具或父文件。正常产物依然 `ready_for_upload=false`，须新包原生启动与兑换码后端验收，不能直接调用旧3101发布工具伪造验收。

验证包括真实Lua模块链路：验收模式3类请求=0次HTTP、正常模式=3次HTTP；保留同局锁定与离线隔离。此为模拟原生边界，真实网络/发奖次数为0，不冒称线上到账。3101原样输入在相同测试中命中 `SHIPPED_READ_ONLY_ACCEPTANCE_CAUSES_EMPTY_SHOP_AND_BLOCKED_BENEFITS`。原有 `test_mode_unlock_zero.lua:378` 与 `test_archive_service.lua:155` 在未改HEAD同样失败，单独记录，不为了过测删除断言。

成本：这是显式一次构建，不加入游戏帧/计时器。N=6915个父资源、K=6个替换/新增文件；单次计划O(N log N)排序和O(N)索引，空间O(N)，K项输入每份只读一次（不可变Git缓存）。稳定游戏开关检查O(1)，不新增原生/HTTP/数据库调用或轮询。显式签名构建顺序读取必要父/候选清单和约3.79GB卷，复用未变硬链接，只重打变更所在卷；所有完整校验是一次构建阶段的完整性要求，不是循环预热。实际耗时及原生验证范围随最终回执记录。
