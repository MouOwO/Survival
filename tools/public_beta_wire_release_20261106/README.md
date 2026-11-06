# WS4 公测领取与 HTTP 引用压缩联合候选

状态：七文件候选本地整合完成，102 项相关本地回归通过。实际源码、addon 根与配置策略已只读审计；V5完整PostgreSQL临时表探针已通过：2个旧配置、7类伪造拒绝、事务回滚及生产函数规范化摘要全部一致，持久化写入0。此为冻结前排演，正式Git绑定的prepare/probe/配置登记与API激活均未执行，后台未部署。

父版本必须是 `20261106-ws4-compact-receipt-d15b405cfb16`，manifest
`5ae22761341595aa94731e6f226f598ad6665dc8c18c8db03fe857e254d8ba1c`。
候选来源和执行配方分别绑定不可变 Git 提交；本机工作区不作发布源。

## 精确业务范围

- `backend/archive_backend/service.py`：从实际父文件 `ec0748b…` 派生，仅加入已批准公测档位校验、真实会话作用域、pending 会话校验和当前活动开关；原 onboarding 路由保留。
- `backend/archive_backend/public_beta_gift.py`：已批准的公测会话/活动契约，来自冻结 Git 源。
- `backend/archive_backend/http_profile_wire.py`：显式能力协商下无损复用同份 HTTP 回复内重复字段；老客户端返回不变。
- `backend/archive_backend/match_modes.py`：只在实际父版本 `project` 包装器的两处返回调用 `pack` 并加入对应 import；未知现役差异保留，锚点漂移拒绝。
- `backend/archive_backend/http_request_timing.py` 与精确派生的 `backend/fishing_api/{server,postgres}.py`：记录授权、读取请求、上下文、业务结算、投影、序列化、写出及数据库阶段；仅固定白名单，不记录账号、请求ID、凭据或内容。每进程至多300条、每分钟至多60条、24小时后停记，不改变鉴权、SQL、连接或重试策略。
- 新的不可变公测 bundle 全部文件、候选自身 `addon/server/bundles/current.json` 及配套 `archive_http_bundle.lua`：保留旧 bundle，旧20条福利逐字段不变，仅加既定每日2金券档位及活动时窗逻辑。不得修改父发布内文件。
- 在审计确认实际 addon 根绑定后，增加独立的单一 `SURVIVAL_ADDON_ROOT` 路径覆盖文件，指向候选自身addon；原环境文件和unit备份不变。若现役实际根指向更早release，必须逐文件确认其与父addon完整清单一致，任何差异先阻断，不能默默切换到不同的运行源码。

新bundle还依赖独立的 `tools/public_beta_config_20261106/` 精确配置接纳事务：只为 `f8…` 与审核过的完整配置摘要增加一处分支并登记一条配置，旧函数正文、旧hash、owner、ACL保持不变。该事务不操作玩家数据或真实抽奖，支付/PWA和其他服务不变。

## 顺序与保护

默认 `plan` 仅打印计划。冻结源码和配方后，Root先完成本工具 `audit` → `prepare` → `probe`，以及配置工具的 `prepare` → `probe` → `activate` → `verify`，最后本工具 `activate` → `verify`。API激活前及最终核查时必须复核配置verify完整绑定，并在只读事务中重新验证实际函数与配置摘要。
复用摘要锁定的现役发行原语及同一个已审查 drain_gate：独立新目录、完整父清单、源/产物摘要、独立控制记录和unit备份、连接排空、单一WS4切换、看门狗、明确恢复。
任何前置摘要/来源/文件集合漂移均拒绝；已存在回执不可覆盖；失败保留证据，不自动重试部署。
SQL事务失败完整回滚。若配置已经登记而API随后回退，保留新增分支和配置以保护可能存在的新hash耐久回执，不自动删除数据库记录。API启动会执行既有配置同步，因此激活及恢复不宣称“数据库零写入”。

## 必须通过的测试

1. 窄bundle实际Lua+模拟耐久事务：旧错误复现、新2券、并发与重复只发一次、跨日与丢ACK恢复、错误账号/会话/金额拒绝、活动开关和旧已完成回执、旧普通福利成功回执不变。
2. 精确派生：service 的 onboarding 及方法外字节不变；match_modes 方法外字节不变；未知父文件与锚点变更拒绝。
3. HTTP能力：老客户端字节语义保持、Python→Lua真实解包、pure/advanced投影不串档、布尔与数字不混同、错误/小包不变、坏引用拒绝、余额/库存原子恢复。
4. 完整候选清单/源绑定/多余文件/原unit/进程代际/连接排空/部分失败恢复及gate清理，沿用现役部署安全测试并针对新配置hash健康检查覆盖父版与候选。
5. 远端probe仅候选中的真实Linux Lua、隔离内存事务和假账号：公测幂等、旧福利、抽奖RNG/奖励不变及wire解包相等。不得调用真实数据库或玩家交易，不把其耗时当公网实测。
6. 激活后配置hash、新模块以及完整候选文件复核；单独确认新客户端实际HTTP时延、字节及真实UI到账。
7. 精确配置SQL：真实PostgreSQL临时函数/表中验证旧hash、新hash、伪造金额/内容/NULL拒绝、重复登记与事务回滚；公开函数和配置保持原状。此项必须真实通过，内存测试不能替代。

构建/审计是一次性 O(文件字节数)，没有新增稳定刷新或后台轮询；每次低频HTTP回复引用编码 O(B)。新公测请求最多增加2次会话读取（入口及pending结算），已完成的同请求重放只做入口1次，不重复发奖；普通命令只增加 O(1) 档位判断。

本地验收入口：`python -B -m unittest server.tests.test_public_beta_wire_deploy server.tests.test_public_beta_config_release server.tests.test_http_request_timing server.tests.test_public_beta_delivery_bundle -q`，需要可用 Lua 5.1 或配置 `LUA_EXECUTABLE`。其中联合 probe 使用实际 Python/Lua 实现和隔离内存回执，不连接 SSH、数据库或真实玩家，不能当作公网耗时或游戏实机验收。

`parent_sources/` 是逐文件匹配现役审计的五份源码夹具，纳入不可变operator提交；仅用于派生和回归，不加入运行包。稳定运行没有新增扫描或定时器；诊断每个阶段只更新固定大小计数表，额外数据库/HTTP调用数为0。配置核查仅在部署阶段执行。
