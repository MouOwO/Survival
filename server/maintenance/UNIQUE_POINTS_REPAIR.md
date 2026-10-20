# 唯一积分道具库存修复

此维护工具只处理已启用的 `item_type=积分道具`，包含薪火余烬。九种可叠加签到材料、月卡奖励、抽奖券、其他库存、历史永久属性和星悦积分均保留。旧别名合并到同一个永久物品；正数数量变为 1，多余份数按经过校验的 bundle 中 `duplicate_points` 转为商城积分。

**发布前必须审阅预览。** 历史商城曾出售薪火余烬 100 份包，100 份转换会一次补偿 99000 积分。不能在未审阅总额时运行 apply，也不能在旧 100 份包仍可购买时启用此规则。当前 HTTP 归一代码只在成功抽取/兑换的同一个存档事务内执行；启用新 bundle 前应完成全量维护，避免玩家下一次抽奖才触发旧数据转换。

1. 按已有发布流程备份数据库及服务。以数据库 owner 应用 `202610180001_unique_points_inventory.sql`；该 SQL 仅创建不向应用角色开放的备份表，不修改玩家数据。
2. 使用现有 libpq owner service 和已审核的 bundle 只读预览：

   ```powershell
   python -m server.maintenance.reconcile_unique_points --service OWNER_SERVICE --bundle SERVER_BUNDLE_DIRECTORY
   ```

   结果包含 `plan_digest`、受影响账号数、各物品历史总份数、多余份数和补偿积分；不会打印账号标识或认证信息。
3. 审阅后使用同一 bundle 和预览的精确摘要：

   ```powershell
   python -m server.maintenance.reconcile_unique_points --service OWNER_SERVICE --bundle SERVER_BUNDLE_DIRECTORY --apply-plan REVIEWED_SHA256
   ```

   如果自预览后任何待修复账号或其库存发生变化，整次 apply 拒绝。每个变更账号的原始库存、archive、变更后状态、规则 hash 和修复版本与修复同一事务写入备份表。玩家 revision 递增，正在进行的旧结算会重试读取新状态。重复运行不会重复补偿。
4. 必须回滚时，使用返回的 `run_id`：

   ```powershell
   python -m server.maintenance.reconcile_unique_points --service OWNER_SERVICE --rollback-run RUN_UUID
   ```

   回滚只有在所有待回滚账号的 revision、库存及 archive 仍与修复后的状态完全一致时才成功；后续消费、奖励或其他存档变更均会拒绝回滚，防止覆盖玩家新数据。revision 保持递增。已回滚批次重试为空操作。

本地维护适配器回归不替代真实 PostgreSQL 验收；正式部署应在隔离数据库中验证 DDL、owner 权限和事务回滚，再操作已获授权的线上目标。
