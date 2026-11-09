# 四档金色抽奖券兑换码

本批新增 100、500、1000、2000 张金色券四个码，库存 ID 为 `special_lottery_ticket`，用于 `cultivation/dragon_knight/summer`。每账号每码一次、无到期时间，全服总次数 0 表示不限。使用现有 `special_lottery_ticket_single` 的零价兑换奖励，只替换冻结券数量和说明；不创建支付订单、不增加 VIP 成长、不改变普通券、金币余额、抽卡概率或已有兑换码。

与旧普通券目录独立。旧四档普通券及旧 128 码不得用本工具重导入，也不使用允许 UPSERT 的旧 `tools/redemption_codes/register.py`。

无参数运行三个入口均只显示静态计划，0 随机数、0 文件写入、0 网络：

```powershell
python -B tools/redemption_gold_ticket_codes_20261110/definitions.py
python -B tools/redemption_gold_ticket_codes_20261110/generate_private.py
python -B tools/redemption_gold_ticket_codes_20261110/ws4_register.py
```

`generate_private.py --generate` 显式生成一次私有四码 Excel、hash-only registry 与恢复记录。每码 96 位系统随机熵；明文只进入被忽略的私有工作簿，不进入 Git、客户端、知识库或普通日志。任何既有目标拒绝覆盖；中断后只允许 `--resume` 从原完整工作簿核验并恢复同一批，不自动取新随机数。本机使用已安装 openpyxl 的 Python 3.14，无需安装依赖。

`ws4_register.py` 采用现役 WS4 `127.0.0.1:15432/goufayu_ws4` 的 132 行基线与真实 `f8ab7087…` 配置。inventory 只返回定义摘要，不输出真实码或玩家记录。plan 固定库存、四行 registry 摘要、全部执行源码和 POSIX 新 stage。每个操作显式提供原文件 SHA256；执行后保留不可变回执。

```text
inventory → plan → upload --execute → clone --execute
→ backup --execute → protect-backup --execute → apply --apply → verify
```

clone 只复制数据库结构和公开配置，使用合成账号/码验证真实 PostgreSQL、应用角色、Lua 到账、四池投影、并发和丢回包。正式 apply 之前须有同计划的克隆回执、15 分钟内完整数据库备份及本机 DPAPI 密文往返核对。备份明文保留服务器 0600 文件，本机不写明文 dump。

正式登记持有既有两把维护锁及同一 advisory lock，先表锁再固定可重复读快照，只有四条 INSERT；任意冲突全部回滚，不更新旧码或领取记录。独立 verify 在同一快照核对 136 行总数、四行奖励/启用/时间和原 132 行摘要。API、两支付服务和现役配置/RPC/表结构必须保持。未知提交结果只允许 verify，不自动再次 apply。

登记成功后另存“已启用”工作簿并复制桌面，核对两份字节与原四码摘要；原待登记工作簿、生成记录和备份不覆盖。此工作无需重发客户端或重启服务，禁止代替真人兑换有效码验收。

一次定义编译 O(P+4)，P 是已有商品数；一次服务器维护摘要 O(D log D + C log C)，D 是原定义数、C 是领取记录数，四次索引插入有 10 秒 SQL / 5 秒锁超时。游戏初始化、稳定刷新和原生桥新增成本为 0，无新定时器或扫描。兑领仍用原 prepare→Lua→commit；模拟计数、隔离 PostgreSQL 并发与真人验收分别记录。

临时回归和执行日志位于树外 `D:/Survival_本地工具/runs/20261110_gold_ticket_codes01`。正式私有生成和登记控制沿用被忽略的 `output/redemption_gold_ticket_codes_20261110`；备份、stage 和原回执保留，不自动清理。
