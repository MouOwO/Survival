# 100/500/1000/2000 金色券兑换码（2026-11-10）

用户要求在兑换码中加入四档金色抽奖券。沿用已启用普通券四码的运营规则，每账号每码一次、全服总次数不限、无到期时间；本批权威库存为 `special_lottery_ticket`，用于修仙、龙骑、暑期三池。不要把金色券变为普通地图券，或调整实际付费单价、概率、玩家成长。

正式工具与旧批次隔离：`tools/redemption_gold_ticket_codes_20261110/`。定义从既有 `special_lottery_ticket_single` 编译零价冻结奖励，仅替换券数量与描述；客户端、后台服务代码和数据库结构不需要升级。正式码只放私有 Excel，不在此记录或 Git 中保存。

只读实查现役 WS4 API 为 `20261106-ws4-daily-refs-ed532ea60d2b`，配置 `f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42`，原兑换定义 132 行、摘要 `da82e3689f792251b3c08222dda34f2aab9ae0465275502c3724e9028ed00bc0`，观察时领取记录 12 行。原 11 月 2 日工具因旧配置绑定正确拒绝，未用它执行写入。本轮新源/新计划固定当前版本，登记前仍需复核真实状态。

45 项隔离回归通过，包含真实 Lua 四档精确到账、普通券/余额/属性不变、三种金色池与地图池投影、同账号一次、账号隔离、并发、提交丢回包、库存上限、仅四条 INSERT、冲突全回滚、先表锁再快照、私有生成/中断恢复及无参 0 副作用。数据库模拟与实际 PostgreSQL 克隆分别记录，尚未进行真人兑换。

本机 Lua 5.1 的 CRT 对 UTF-8 绝对路径有限制；测试使用同一树外夹具的既有 NTFS 短路径字符串，不移动数据、不创建挂载、不修改生产代码。旧服务接口夹具更新到当前 settlement_runner.run 边界，真实 Lua 到账与缓存路径仍实际执行；首轮失败与修正后的回执分别保留。

临时脚本、日志、合成夹具及回执：`D:/Survival_本地工具/runs/20261110_gold_ticket_codes01`。此条建立时尚未生成或启用生产码，后续必须经过独立 schema-only PostgreSQL 克隆、完整备份与 DPAPI 核验、insert-only 登记及独立只读 verify。原 132 项定义和真人领取保持，API/支付不重启；运行源码没有变更，客户端沿用已同步0902 / manifest `6445398778833066003`。

冷运营编译 O(P+4)，一次维护摘要 O(D log D+C log C)，新增 4 次索引插入；稳定游戏和新原生桥/网络刷新成本 0，无新增帧循环或场景遍历。不以本次隔离测试声称真人兑换或 FPS 通过。

## 实际登记与交付已完成

同一批四码已在现役 WS4 启用：100、500、1000、2000 张金色券，每账号每码一次，无到期时间，四码合计 3600 张。实际只新增 4 行，独立只读核验总数 132→136、四行冻结奖励和启用时间一致，原 132 项定义摘要仍为 `da82e3689f792251b3c08222dda34f2aab9ae0465275502c3724e9028ed00bc0`。同一登记事务快照中的旧领取保持；正常并发玩家领取不需要暂停。API 与两支付服务进程保持，没有后台程序部署、SQL 迁移、客户端打包或代兑真人码。

桌面交付为 `C:/Users/Administrator/Desktop/金色抽奖券四档兑换码_已启用_20261110.xlsx`，7225 字节，SHA256 `0ebfd05e77c646f0cc7e6857dccf0f5beef94e68ff3b084f136262ca9ba63abb`。另存私有已启用副本，逐码核对规范化 SHA256 与实际登记 registry 一致；原待登记工作簿、生成意图和 manifest 未覆盖，没有因修工具而重新生成码。有效明文不写入本知识库、Git、客户端或普通日志。

实际源与回执：

- 定义/生成工具提交 `fb079aaa890fcce499d7605a5c857417d9cb4a42`；最终登记解析器提交 `ba2d204768d081931bfa9a5d0fbbf73ae86c03b0`。两仓按既定 stash/pull/pop/commit/push 核对。
- 固定计划 `output/redemption_gold_ticket_codes_20261110/operation_plan_v02.json`，SHA256 `a7f3bcf03c81cfbd7d1afeab5ced073da134bffac30233c47e47caa738df22ff`。
- 第二次真实克隆回执 `output/redemption_gold_ticket_codes_20261110/run_1c1d013d5db1_clone_5f942222.json`：8 项真实 PostgreSQL/应用角色/Lua 检查通过，未复制真人行或真实码哈希到克隆数据库。
- 唯一正式 apply 回执 `output/redemption_gold_ticket_codes_20261110/run_1c1d013d5db1_apply_af313f6a.json`，SHA256 `dc1b1182756eb395c6023d99aa1b05129e2054161e0ea8f4ec0ff73226ad51e5`。
- 独立 verify 回执 `output/redemption_gold_ticket_codes_20261110/run_1c1d013d5db1_verify_9b37b008.json`，SHA256 `d48b7be24424c6a2cc604a4d926e8c221958aeb93563eba38eab175cf04cc4cb`，`FOUR_ROWS_MATCH_VERIFIED`。
- 私有交付和保留证明 `D:/Survival_本地工具/runs/20261110_gold_ticket_codes01/delivery_receipt_v01.json`，真实生成、加密备份和交付回执均已登记。

最终 48 项隔离回归通过，新增三项严格远端回复解析测试。现役服务会在最后 JSON 回执之前输出 `SURVIVAL_ARCHIVE_TIMING`：首个克隆其实成功，旧单 JSON 解析器不能读取结果，已先只读核对并保留原 stage/意图。仅接受这个已知结构化计时前缀与唯一末尾对象；未知输出、重复对象或错误 schema 拒绝。修正后源重新提交，沿用原四码创建新计划与新 stage，重新跑同计划克隆，没有复用旧 apply 或覆盖旧回执。

正式写入前完成服务器完整 PGDMP 备份与本机 DPAPI 解密往返核对。仓内密文首次清理登记被拒为 `receipt_has_no_known_storage_bindings`，原回执和密文保留；同一密文额外复制到 `D:/Survival_加密备份/redemption_gold_ticket_codes_20261110/run_1c1d013d5db1.dump.dpapi` 并核同一 SHA256 `8540abe7fa44206e2ef9b9fed1fabb0d4b19be8c399b242f46d0b70db0a0914e`，以新真实存储回执成功登记后才执行一次 apply。未修改清理工具的允许目录或伪造原登记日期。

客户端运行没有改动，继续沿用已同步游廊 0902 / Steam manifest `6445398778833066003`；本次启用不代表新增游戏包或原生兑换/FPS 验收。原有五项无关 game 工作区改动继续保留，content 无需空提交。
