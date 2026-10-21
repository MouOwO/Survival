# 福利奖励修订：本地候选，尚未发布

父版本是已上线的 `47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e`，本次候选是 `e62df5c96ee353713b923a43b1167fab9c8bf25be4fbded74cbf8b8a57784d7f`。候选只修改 `archive_benefit_rewards` 的 9 行、17 个字段及对应 CSV 哈希和精确兼容别名；全部 Lua reducer、Python、抽奖规则、日上限、pure/stackable 支持保持父版本。没有新 migration。

当前状态：已完成本地封存、8 项本地 scope/Lua 测试和现役来源的只读核对。远程 `prepare` 在执行前被自动审批拒绝，尚未上传、尚未远程 prepare/validate、尚未注册配置、尚未激活。自动审批指出上传到远程测试机需要用户明确授权该目的地；没有重试或绕过。本轮不能把候选标记为已上线。

本机 `archive_http_bundle.lua`、运行指针 `server/bundles/current.json` 和抽奖种子继续保留父版本，避免向尚未注册的新 hash 发请求。`current.json` 是已有未提交运行指针，不加入本轮提交。

得到用户对 `47.110.238.248` 这台既有测试机的本次发布明确授权后，再按顺序执行：

```powershell
$pythonExe = 'C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe'
& $pythonExe tools/benefit_revision_20261021/deploy.py prepare
& $pythonExe tools/benefit_revision_20261021/deploy.py validate
# validate 必须报告整体事务回滚，并经审阅后才能继续：
& $pythonExe tools/benefit_revision_20261021/deploy.py activate
& $pythonExe tools/benefit_revision_20261021/deploy.py verify
```

`prepare` 完整复制父 manifest 的全部文件，只覆盖两个 immutable bundle、福利 CSV 和当前 bundle 指针，另建禁用福利的安全回退版本。`validate` 只在同一事务里演练两个精确配置分支注册，然后全部 ROLLBACK；旧 ledger、其它 SQL 函数及玩家/订单行必须不变。`activate` 先私有备份，只重启 archive API；支付服务 PID 必须保持 5427。

服务端成功激活并 verify 后，才同步新的客户端配置声明和抽奖种子：`data/ui/lottery_catalog.json`、`panorama/src/scripts/custom_game/lottery_catalog_seed.js`、`scripts/vscripts/config/generated/lottery_catalog_manifest.lua`，以及 `scripts/vscripts/config/generated/archive_http_bundle.lua` 和本机运行指针。需要编译的 Panorama 源码同时配套编译与提交，不能只提前更新新 hash。

父 hash 的精确兼容别名排除 `benefit_claim`，跨 hash 的新领奖必须刷新。已经准备的旧福利操作保留原 `config_hash`、事件时间和原 bundle 奖励；profile/drain 继续按旧承诺结算。已领取档位不清零、不补发、不扣回。未给新 hash 增加 lottery guard 例外，旧抽奖请求可以要求刷新。

安全回退命令是 `deploy.py rollback-safe`，目标 bundle 为 `271d9f09bb34fe577df58551b29d40fb7e0b6d8b9de018b81812729f65b3c3bf`：禁用福利发放，保留全部 claims、库存、计数、薪火/粽子支持和现役 Python。不要切回旧 unique backend，不回滚玩家数据。

本地候选、父 manifest/SQL sync/ledger 只读基线、seal 位于 `tmp/benefit_revision_20261021/release_candidate`。正式状态与拒绝记录保存在 `validation/20261021/benefit_revision.json`。
