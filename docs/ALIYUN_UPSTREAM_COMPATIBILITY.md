# 同步后的服务器影响检查

## 结论

本次同步不会自动改动已部署的 ECS `20260919-test03`。但当前游戏已升级 HTTP 抽奖协议，与 test03 不兼容，不能只改服务器地址后接入。

## 已核对

- Game：`1dee4607` → `696e5cc3`；Content：root 确认 `926379c`。
- test03 结算包：`9cac6534d6f5eaed17cdba596053cf0260c39655b7e0dc722101ce232b171ffb`。
- 当前游戏/新结算包已一致：`4b28247fa0bbabf0d220b4f178a9d8379fc54d362792b031fbfcd5a71c8bf20d`；旧包保留。
- 两个 backend 冲突已合并；18 项相关测试通过，包括真实 Lua 执行、mock RPC 下抽奖重试与回执、旧存档恢复。未做新抽奖 SQL 的真实 PG 验收。
- test03 发布清单中所有文件 hash 保持不变；本轮无 SSH、数据库连接、部署或密码读取。

## 接新版游戏前必须处理

1. 后端加入 `/v1/lottery/snapshot`、新版抽奖 service/reducer；当前 ECS 和 `D:/survival_database/backend` 源码都缺这些能力。
2. PostgreSQL 加入 `archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)`，同步适配器允许列表和最小权限。当前配置仅允许 11 个旧 RPC。
3. 审核 4 个新迁移的顺序、旧账本兼容和新增对象；现有 3 文件白名单会安全拒绝直接打包。`survival_data_migrations` 和新函数也需进入备份/恢复/RLS检查。
4. `wood_per_second` 与三项攻击/属性成长默认值由 1 改 0。木材迁移还会把已有玩家木材秒产减 1 并更新 revision，需要明确的数据升级验收，不能描述成只改默认值。
5. 同步发布新 bundle 与游戏 hash，保留历史包供旧未完成回执恢复。仅把新 hash 写进游戏而保留旧服务会得到 `archive_config_mismatch`。
6. 游戏默认档案 provider 已从 `local_fixture` 改 `http_fishing`，不再自动回退；URL仍是 `http://127.0.0.1:8765`。必须有匹配版本的本地服务或测试隧道，并用服务端 ConVar 传 bearer token。HTTP/抽奖架构保持上游新版。

账户协议未变：客户端传 Steam account ID，后端仍用原 pepper 做 HMAC-SHA256；不需要更换 pepper。已有账号要继续使用同一 pepper。未读取实际 `.env`，因此不声称外部后端当前运行的是哪一种数据库。

本轮建议保留现有 ECS test03，用独立新版测试发布包完成后端/迁移适配与验收，再决定接入。地图资产导入本身不需要执行数据库迁移。
