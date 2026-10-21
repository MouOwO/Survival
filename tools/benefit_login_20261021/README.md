本目录只制作和验证本地候选，不包含 SSH、上传、SQL 注册、部署或激活功能。

运行 `build_candidate.py` 会读取已核验的 `47accd81…` 父 bundle，输出到
`tmp/benefit_login_20261021/release_candidate`。候选尚待用户授权发布；不能使用上一轮
`tools/benefit_revision_20261021` 的九行修订部署脚本发布本次改动。

允许的差异只有：

- 福利表保留之前九行奖励修订，新增 `daily_time_0` 月卡登录自动领取档及
  `monthly_only`、`auto_claim` 两个可选字段。
- 轮回仙碑仅删除指定括号说明，保留物品、属性、数量、兑换价格及全部展示入口。
- bundle 仅替换 `systems/archive_benefit_rewards.lua`，其余配置和 Lua 源码沿用父版本。
- Python 待发布 overlay 以已核验线上源码为底，只移植 `profile` 和新增的
  `_grant_login_benefits`；主工作区已有的其他未发布后端差异不进入候选。

脚本拒绝超出上述范围的配置、Lua 文件或 Python 方法变化。`content_catalog` 和
`tooltip_definitions` 属于客户端本地素材，不加入服务端 bundle。父 bundle 会完整保留，
兼容别名明确排除 `benefit_claim` 且没有升级指令；旧未完成领取继续使用原 bundle，
完成回执直接返回原结果。安全回退候选只关闭福利档位，保留道具库存和堆叠支持。

验证使用本地真实 Lua worker 和内存 RPC，涵盖月卡资格、登录档每日一次、北京时间
05:00 换日、原 30/150 分钟档、旧 pending 原奖励及完成回执不变。结果写入
`validation/20261021/benefit_login_candidate.json`。没有连接数据库或读取真实账号。
脚本不修改 active hash 声明、`current.json` 或抽奖 seed，不打包任何凭据。
