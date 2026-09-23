# 新版游戏与 ECS 测试后端兼容性

## 当前结论（2026-09-20）

新版存档、抽奖后端已部署至 **`20260920-test05`**，当前目录为
`/opt/goufayu/releases/current`，指向 `/opt/goufayu/releases/20260920-test05`。
服务器本机健康、数据库、真实 HTTP/Lua 抽奖及存档重启持久化已验证。
**真实游戏客户端尚未验证**，不能将服务器验收等同于游戏已成功连接。

游戏生成配置与服务器结算包使用相同哈希：

```text
4b28247fa0bbabf0d220b4f178a9d8379fc54d362792b031fbfcd5a71c8bf20d
```

旧结算包仍保留，用于按原 `config_hash` 恢复历史未完成操作。
原 Supabase 环境和数据没有修改，源 Supabase 玩家数据尚未导入 ECS。
API 使用非 root 用户 `goufayu`，仅监听 `127.0.0.1:8765`；原数据库
`goufayu-db` / `goufayu_test` 保持 `127.0.0.1:5432`，支付仍为测试模式。

## 已完成的兼容适配与真实验证

- 新后端提供 `/v1/lottery/snapshot` 及抽奖结算、回执；PostgreSQL 适配器
  支持 `archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)`。
- `goufayu_test` 当前有 **23 项迁移/加固账本记录、12 个应用 RPC**。
  保留原历史 SQL 和账本校验值，追加 4 个业务升级及独立抽奖权限加固。
  运行账号没有表访问、建表权限或 owner 成员资格。
- 先备份并恢复到独立库 `goufayu_restore_upgrade_20260920`，核对 15 张表、
  函数、触发器、约束和索引，再在恢复库试升级；通过后才升级 `goufayu_test`。
  两个库重复执行均新增 0 项迁移，业务数据不再变化。
- 木材默认秒产移除在 4 个原测试账号上各执行一次：
  `greatest(0, wood_per_second - 1)`，同时增加对应 revision。重复迁移不再扣减。
  攻击/属性成长调整只修改默认值，原玩家已有值和奖励回执保持不变。
- 两个库均通过真实 PostgreSQL 回滚事务验收：97 项 CSV 默认值、6 类越权拒绝、
  领奖/存档/在线检查点幂等、抽奖回执保留、旧 revision 库存拒绝以及 outbox 只结算一次。
  这些 SQL 验收提交测试行数为 0。
- test05 真实 HTTP 存档 9 项、抽奖 7 项及故障保护 2 项通过。抽奖使用两个新建
  合成账号、普通地图券与真实 Lua 十连；同一操作重试不重复扣券或发奖，玩家间隔离，
  永久内容保留，旧存档上传被拒绝。管理员凭据只用于测试账号夹具，不用于后端运行。
- 手动重启 PID `15435 → 15885`，随后模拟 API 进程异常，systemd 自动恢复到
  PID `15959`，`NRestarts: 0 → 1`。每次均复读原 4 个合成账号，完整存档和抽奖
  快照摘要一致。数据库 PID 始终为 `6590`，未重启数据库。
- `/health` 实际判断 HTTP 200 且 JSON `ok=true`；`/ready` 还要求 Bearer
  认证及真实数据库探测 `database=ready`。`manage.py health` 同时核对归档包哈希。
  故障保护用独立测试实例的失败数据库连接验证 503 和无空存档返回，未停止真实数据库。

本次服务器报告位于 `/var/lib/goufayu/upgrade-20260920`。
本地脱敏过程记录在 `output/ecs_upgrade_20260920/`，包括
`upgrade_clone.log`、`upgrade_test_database.log`、`activate_test05.log`、
`http_acceptance_test05.log` 和 `restart_test05.log`；该输出目录不提交仓库。

## 游戏接入与仍未完成项

- 当前游戏默认 provider 为 `http_fishing`，不自动回退到本地模拟档案。
  CSV 默认 URL 仍为 `http://127.0.0.1:8765`。异机 localhost 不指向 ECS，
  需要测试 SSH 隧道或之后配置的 HTTPS 地址。本次已建立本机 `127.0.0.1:8765`
  到 ECS 同端口的隧道；通过隧道验证认证 `/ready` 和游戏配置哈希，均通过。
  这仍不等于实际游戏联调完成。
- token 仅通过 Dota 服务器 ConVar `survival_fishing_api_token` 提供，不进入
  Panorama、公开配置或仓库。现有 pepper 和 token 保持不变，玩家 ID 协议未变。
- 升级后 16 张表的一致性备份已复制到本地电脑，并将本地副本重新上传至全新目录，
  恢复到独立库 `goufayu_restore_postupgrade_20260920`。数据指纹、函数、触发器、
  约束和索引一致；重新应用权限加固后，12-RPC 最小权限校验通过。
  这是已验证的手动异地副本，定时异地同步仍未配置。
- 域名、Nginx/HTTPS、自动异地备份仓库及该仓库恢复、真实游戏联调、真实支付均未完成。
  当前无须开放数据库或 Python 端口到公网。

完整部署记录见 [部署手册第 13 节](ALIYUN_TEST_MIGRATION.md#13-新版存档与抽奖实际升级2026-09-20)，
脱敏验收结果见 [ecs_upgrade_20260920.json](../server/aliyun/validation/ecs_upgrade_20260920.json)。

## 回退边界

遇到问题先 `systemctl stop goufayu-api.service`，保留数据库、发布目录和备份；
如需同时取消开机自启，使用 `systemctl disable --now goufayu-api.service`。

**不能直接激活 test03 连接当前已升级数据库。** test03 严格要求旧 11-RPC
权限集合，与当前 12-RPC 状态不兼容；`previous-release` 仅是路径记录，不能作为
数据库兼容性的证明。当前 test05 仅需停止后恢复时，可重新启动同一版本并检查 health。

必须恢复旧版本行为时，先停止写入、备份升级后的数据库，在新独立恢复库中还原
升级前 `/var/backups/goufayu/preupgrade_20260920_005800Z`，验证旧后端及权限，
再制定测试连接切换和升级后新增数据的保留/对账方案。不要把旧快照直接覆盖
`goufayu_test`，也不执行 down migration 或删除 `/data/postgres17`。
