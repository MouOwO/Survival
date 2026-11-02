# WS4 四档抽奖券：增量登记

此工具只向现役 WS4 的 `127.0.0.1:15432/goufayu_ws4` 新增四行。默认静态计划不连接服务器，不生成兑换码。不得使用旧的 `redemption_codes/register.py`：它指向另一套库且允许更新原定义。

服务器 stage 始终使用 `PurePosixPath` 序列化为 `/root/...`，不能在 Windows 上直接 `str(Path('/root/...'))` 传给 Linux。上传失败后必须保留原计划和 local intent，先只读核查远端；即使确认尚未创建 stage，也使用新的计划文件与新 run ID，不重跑旧 upload。

本轮只读实查已确认五账号 API 发布目录 `20261101-admission-five-ffd96ff80622`、d573 合同、128 项码定义、9 条领取记录。事实可能随正常使用变化；计划绑定发布、旧定义摘要和支付 PID，但不要求真实玩家活动完全停止。

先由专用生成器在私有目录提供四个码的哈希与 `registry.json`；本工具不接收或打印明文码。以下均需显式指定实际文件 SHA，示例中的占位符不可直接执行。

```powershell
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py inventory --output output/redemption_ticket_codes_20261102/inventory_NEW.json
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py plan --inventory <inventory> --inventory-sha <SHA> --registry <private-registry> --registry-sha <SHA> --output output/redemption_ticket_codes_20261102/plan_NEW.json
```

审阅固定计划和源码后，逐步执行，每一步只请求一次。`upload` 只创建新的服务器私有准备目录；`clone` 只恢复 schema 到新命名数据库，复制公开配置并使用合成账号／合成码运行真实应用角色、Lua、PostgreSQL 检查，不复制真人行或真实码哈希。

```powershell
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py upload --plan <plan> --plan-sha <SHA> --execute
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py clone --plan <plan> --plan-sha <SHA> --execute
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py backup --plan <plan> --plan-sha <SHA> --execute
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py protect-backup --plan <plan> --plan-sha <SHA> --execute
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py apply --plan <plan> --plan-sha <SHA> --apply
python -B -X utf8 tools/redemption_ticket_codes_20261102/ws4_register.py verify --plan <plan> --plan-sha <SHA>
```

完整 PostgreSQL 备份保留在服务器 0600 私有文件；本机仅将 DPAPI 密文写入 `output/redemption_ticket_codes_20261102/private/backups/`，加密后实际解密并比对原 SHA。备份未完成、超过 15 分钟或没有克隆回执，禁止生产写入。建议完成代码审阅及克隆后才备份并立即登记。过期、失败或不明结果均保留全部准备目录和备份，不覆盖旧回执，不自动重试。

`apply` 按固定顺序兼容持有现有 `goufayu_admission_five.lock` 和 `goufayu_ws4_redemption.lock`，非阻塞取得失败会释放已持锁；不冒称覆盖所有历史 catalog 自有 stage 锁。先取得码表锁，再执行首个 SELECT/advisory lock，避免 RR 快照在表锁前固定；四次纯 `INSERT`，任一 ID／哈希冲突全部回滚，无 UPSERT。旧 128 定义摘要在同一事务前后核对；旧领取记录在同一 REPEATABLE READ 快照中核对，正常并发领取不会被误判为本工具改写数据。SQL 不更新玩家、订单或旧领取。提交回包丢失则保留 intent，只能 `verify` 回查，不再次 `apply`。verify 在自身同一 RR 快照核旧定义、精确总数132和四行已生效时间，不拼接不同时间的成功结论。不要用整库旧备份覆盖后续玩家进度；若需撤销，应另审只停用本次四行且保留领取记录的方案。

真实克隆阶段先用生产同一 `insert_four` 路径登记四个合成哈希和原奖励，再验证应用角色／Lua发放。仅该明确命名的空 schema 克隆还会运行两连接小反例：复现 SELECT 先于锁时的旧快照，验证先锁后SELECT会阻止冲突写入、释放后写入恢复；该探针不会在真实 WS4 库创建对象或漂移定义。

不会停止 API、重启支付、改 schema/RPC、修改 d573 配置或上传游戏包。登记验证不是实际玩家兑换成功；实际到账需用户正常游戏内兑换确认。

成本：每次显式 inventory／申请阶段对 D=128 个定义聚合一次，排序 O(D log D)，空间 O(D)；登记只对四个新 ID 做索引碰撞检查和四次 INSERT。领取快照核对 C=9（实查时）仅在该短事务做两次，O(C log C)，不在在线请求循环执行，10 秒 SQL／5 秒锁等待上限。完整备份按数据库字节顺序一次，schema clone／合成 Lua 检查仅在显式维护阶段运行。稳定游戏刷新、原生桥和请求热路径新增成本为零；这些计数不是 FPS。

本地测试使用隔离替身验证拒绝、全回滚及未知提交不重放；真实 PostgreSQL/Lua 克隆阶段必须另外执行并保留实际回执，不能把本地测试当作该阶段已通过。
