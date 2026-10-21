2026-10-21 抽奖券配置发布

修仙宝箱改用既有 `special_lottery_ticket` 库存，显示为“金色抽奖券”。地图宝箱累计开启 100 次的解锁规则保留。地图宝箱继续消耗 `lottery_ticket`。商城 `video_p001` 只修改显示名称，金额、发券数量和库存 ID 保持原值。

现役基线为 `20261020-monthly-archive-0763266ab8d3`，新版本为 `20261021-lottery-gold-bbaf4162a941`。完整 hash、封存记录、远端验证和回退位置见 `validation/20261021/lottery_gold_ticket.json`。

`prepare.py` 从指定基线 bundle 生成候选，逐字段拒绝其他修改，输出必须匹配已核验 hash；它不修改本机活动指针。四项防越界测试覆盖其他奖池改券、费用变化和增删配置行。现有 `server/tests/test_archive_backend.py` 回归覆盖修仙单抽/十连扣金券、99 次锁定、100 次解锁、金券不足及普通券不得替代。

`deploy.py` 使用仓库已有固定 SSH 主机密钥传输。先封存候选，再依次执行 `prepare`、`validate`、`activate`、`verify`。验证阶段在事务中演练配置登记与商城标题更新，确认其他数据表、商品和历史配置保持不变，然后回滚。激活阶段先备份数据库，只重启存档 API，支付服务保持运行。只读验证直接请求真实 `/v1/lottery/catalog`。

发布保留原版本与完整历史 bundle。新增 parent 兼容入口不升级旧命令。已经完成的回执保留原结果；旧 hash 的抽奖修改继续由既有保护要求客户端刷新，避免以旧普通券意图扣除金券。回退命令为 `python -X utf8 tools/lottery_gold_20261021/deploy.py rollback`；它只恢复已核对的原存档版本指针并重启存档 API，保留增量配置与商品名称，不回滚玩家数据库。

普通券来源检查：配置声明为玩法奖励，但当前生产奖励表未设置具体普通券产出。现有明确发券入口只有工具或作弊模式下的 `choujiang <数量>` 调试命令，不能把该入口当成正式玩家获取渠道。
