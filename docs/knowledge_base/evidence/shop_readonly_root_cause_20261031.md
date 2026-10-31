# 2026-10-31 游廊商城、福利的只读验收根因及兑换码缺项

状态：根因已复现，开发默认配置已修；原游廊3101仍含旧配置，需新包、新开局和真实领取ACK确认。兑换码还需要WS4后端独立接入，不把候选或模拟测试写成已上线。

## 已发布包中的实际原因

对已官方全量下载核验的3101冻结VIEW（content `b99f3ac128c6433012f419fba87b6b7b59ca2aab8c2c98339f50f24c788b3263`）读取真实文件，确认 `config/mode_release_config.lua` 的 `all_difficulties_unlocked=true`，其 `debug/mode_unlock_test.reset` 在每局初始化把该状态锁定到会话结束。此前只核对HTTP、登录和现金配置，漏查这一层业务隔离，导致排查方向走远；不再沿用“等待真实HTTP才能定位”的旧待办。

这条链不要求 `sv_cheats=true`：

- 实际HTTP provider允许认证/档案等只读路由，商城目录走的 `archive/command` 在创建HTTP前被 `mode_unlock_test_read_only` 拦下。
- archive队列在验收模式中直接返回skipped/test_only，不会产生正式每日/福利保存回执；旧UI会停留等待状态。
- cash policy的isolation判断返回false，界面不会取得现金商品能力。

所以登录与读档能成功，内部API也能返回126/48项商品，但不代表这一局能够发出目录或领取请求。此前WS4确有d573版本不一致，已按授权另行修复；它不是当前剩余问题的完整解释。旧“后台没请求”的观察与这条前置隔离一致，不能用普通health200证明游戏业务可写。

本轮普通游廊PID8216只打开菜单/设置并查询了 `survival_archive_http_enabled=1`、`sv_cheats=false`；没有修改作弊、认证或对局状态，没有领取、兑换、购买。原控制台关闭，检查期间临时启用，结束后在设置中目视确认恢复关闭并返回原局。普通客户端没有Tools的脚本执行命令；未绕过限制。截图/完整控制台仅留私有忽略目录，不进入Git。

## 最小修复及真实模块回归

正常发布默认改为false，恢复按账号真实进度/额度准入及正常持久操作。受控离线provider仍经 `is_offline_preview` 开放预览难度并隔离写入；显式只读验收开关及同局锁定不变。不能中途切换当前验收局并保存其收益，更新后必须新开局。

`tools/test_online_account_actions_20261031.lua` 使用真实配置、隔离模块、HTTP provider及现金策略，仅模拟引擎/身份边界。验收配置三类请求0次HTTP，正常配置3次HTTP，现金能力相应关闭/恢复；同局切回配置不能解除隔离，新局与离线隔离通过。把原3101目录作为源码输入，同一测试命中 `SHIPPED_READ_ONLY_ACCEPTANCE_CAUSES_EMPTY_SHOP_AND_BLOCKED_BENEFITS`。全部为模拟计数，真实网络/发奖次数0，不冒称线上领取成功。

难度解锁、每日快照、非商业支付隔离、完整离线开局及四模式发布范围检查通过。`test_mode_unlock_zero.lua:378` 和 `test_archive_service.lua:155` 在未修改HEAD的配置/服务预加载对照中同样失败，作为既有失败保留，未删除断言或虚报全套通过。

开关变更初始化/稳定查询均O(1)，不新增循环、场景遍历、计时器、原生桥或网络/数据库调用。独立构建N=6915、K=6的成本见项目 `tools/shop_recovery_20261031/README.md`。

## 兑换码并非现役开关关闭

3101的 `black_lion_market.vjs_c` 无入口，`redemption_code.vxml_c` 不存在，`commerce_service.lua` 不接受redeem动作。开发双仓已有三份配套编译UI及Lua分发，3项既有UI行为测试通过；之前没有进入当前冻结发布链。

实际现役WS4只读审计也确认：redemption模块/命令钩子缺失，`redemption_codes/redemption_claims/redemption_attempts` 三表及 `redemption_prepare/redemption_commit` 两RPC均不存在。现有部署/登记工具面向另一套原后台与5432库，不能直接对WS4运行，更不能把历史原后台授权当成本次WS4部署授权。

准备的3102候选六项范围：正常模式配置、已提交的受控离线隔离锁定、redeem分发、商城入口JS及兑换码布局/样式；184份保护模块、16项准入审阅、四账号门禁、d573合同、地图和商品价格/奖励配置保持。签名候选仍需原生及WS4后端验收，未开放真实码或发奖。WS4后端涉及新增三表/两RPC及处理代码，须完成限定候选/合成测试并取得本次明确部署授权；不复制真实玩家或订单做测试，不登记未经授权的有效码。
