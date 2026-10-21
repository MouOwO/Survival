# 福利发布与安全回退

这些工具只管理固定测试主机 `47.110.238.248` 的 archive 服务。SSH 使用既有固定主机指纹；支付服务、支付密钥、历史订单不在发布范围。

候选目录：`tmp/benefits_20261021/release_candidate`。`report.json` 固定候选与回退 bundle，`plan.json` 固定旧 release/manifest、旧数据库函数/constraint/ledger/config 哈希、支付 release/manifest/PID、每一项 overlay 和新迁移 SHA256。`source_diff.patch` 与 `config_diff.json` 是相对当前线上版本的完整可审阅差异。

1. `prepare.py --owner-files <明确名单.json>` 在现役 immutable bundle/Python 上套用记录的 before → after 差分。CSV 逐行、逐字段合并；不把本机其它未部署配置带上去。商城目录仅调用离线 compiler，支付进程不部署该 compiler。
2. `deploy.py audit` 只读核对数据库和现役来源。`deploy.py seal` 封存计划、操作器与每一项 payload。
3. `deploy.py prepare` 上传已封存文件并创建候选和安全回退两个非活动 release，完整复制旧 manifest 中的全部文件，保留旧 backend 和虚拟环境。不会改变 current 或提交数据库。
4. `deploy.py validate` 先执行纯内存 Lua cloud worker，再在一个事务里演练 001/002、精确配置注册、约束检查与 synthetic 账号真实 SQL API。synthetic 探针使用 savepoint 回退，最后整个事务 ROLLBACK，再从新连接确认旧函数/constraint/ledger/config 全部恢复。不会操作真实玩家。
5. 审阅通过后，才执行 `deploy.py activate`。它再次核对全部 pin，停止 archive API，调用既有私有数据库备份，应用两项新迁移和精确配置分支，切换候选并启动 archive API。只新增新 ledger 条目，不修改旧 ledger 哈希。支付 PID 必须仍为 5427。
6. `deploy.py verify` 核对活动来源、全部文件和两个健康检查端口。

PowerShell 中可使用：

```powershell
$pythonExe = 'C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe'
& $pythonExe tools/benefits_release_20261021/deploy.py validate
# 仅在审阅授权后：
& $pythonExe tools/benefits_release_20261021/deploy.py activate
& $pythonExe tools/benefits_release_20261021/deploy.py verify
```

回退使用 `deploy.py rollback-safe`：关闭新福利的全部 19 档发放，保留新的薪火/粽子配置、库存、属性派生、pure 投影、唯一物品排除规则和数据库约束。已确认的旧操作按不可变回执处理。候选与安全回退 bundle 的抽奖配置、reducer 完全相同，只有新福利 enabled 和无新增福利命令的旧客户端兼容别名不同；只给这一对 bundle 增加精确的抽奖旧回执兼容。

客户端可恢复本次任务前保存的**每日福利 UI 源文件和编译资源**。不要恢复旧 Lua 物品逻辑、旧 unique backend 或删除已获得的物品；这些操作会把已经叠加的薪火错误地转为积分。原 UI 备份位于 `tmp/benefits_20261021/frontend_before/manifest.json`，game/Content 编译资源备份由本次主发布流程保存。

旧 release 保持 immutable，作为版本来源和审计依据。数据库备份保存在服务器既有私有备份目录，只做灾备，不自动覆盖玩家数据。若激活提交的确认丢失，操作器先查安全回退配置是否已注册；一旦可能提交成功，恢复保留 stackable 支持的安全 release。不会在已可能发放新道具后简单切回旧 unique 代码。

已封存后不要直接修改 operator 或 payload；若验证发现问题，重新准备、封存并审阅新的计划。禁止强行复用旧 seal、修改旧 ledger、重启支付服务或把测试探针提交到真实账号。
