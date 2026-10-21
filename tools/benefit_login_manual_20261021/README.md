本目录只制作和验证本地手动领取版候选，不包含 SSH、上传、SQL 注册、部署或激活功能。
候选尚待用户授权发布；之前的自动领取候选与九行修订工具保持封存，不用于发布本次改动。

运行 `build_candidate.py` 精确读取已核验的 `47accd81…` 父 bundle，输出到
`tmp/benefit_login_manual_20261021/release_candidate`。允许的差异只有：

- 福利表保留此前九行奖励修订，新增 `daily_time_0` 月卡登录档及两个可选字段。
  登录档 `monthly_only=true`、`auto_claim=false`，有效月卡玩家须显式点击领取，
  每个北京时间 05:00 开始的日周期一次，奖励为一张金色抽奖券。
- 轮回仙碑仅删除指定括号说明，保留物品、属性、数量、兑换价格及所有展示入口。
- bundle 只替换 `systems/archive_benefit_rewards.lua`，其他配置和源码沿用父版本。
- 不打包 Python overlay。脚本验证本地主工作区 `service.py` 完整恢复到自动领取前基线，
  并使用已核验线上 47 版本的 Python 服务做读取及显式领取测试。本地既有未发布服务差异不进入候选。

`content_catalog`、`tooltip_definitions` 不加入服务端 bundle。父 bundle 完整保留；
新父兼容别名排除 `benefit_claim`，不升级旧领取操作。旧 pending 使用原 bundle，
完成回执原样返回。安全回退只禁用全部福利档位，保留库存及堆叠支持。

验证使用本地真实 Lua 与内存 RPC：检查登录档可点击、非月卡不可领、读取不发奖、
显式点击才发一张、每日一次、05:00 换日、原 30/150 分钟档，以及旧 pending/完成回执不变。
结果写入 `validation/20261021/benefit_login_manual_candidate.json`。
脚本没有数据库连接或真实账号写入，不修改 active hash、`current.json`、抽奖 seed，
不打包凭据，不包含任何远程操作。
