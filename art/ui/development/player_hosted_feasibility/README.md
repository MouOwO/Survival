# 玩家托管与付费可行性验证

日期：2026-09-11。目标是判断是否值得继续投入；本轮仅检查和运行既有本地测试，不改奖励、概率、价格、支付规则，不进行实际扣款。

## 已执行的基线

所有命令从项目根目录执行，退出码均为 0。

| 命令 | 结果 | 证据边界 |
| --- | --- | --- |
| Python 3.14 `-X utf8 -m unittest discover -s server/tests -p test_archive_backend.py -v` | 13 项通过；含 HTTP 401/200/400、重复请求、并发同收据、响应丢失、冲突重试、恢复及账号隔离 | 实际本机 HTTP 和 Lua worker，数据库为测试替身；不代表生产数据库或玩家托管认证通过 |
| `node art/ui/development/remaining_ui_handoff_v1/test_commerce.cjs` | COMMERCE_COMPONENT_PASS | 模拟 UI/订单回调；不是支付网关、到账或发货测试 |
| Lua 5.1 `scripts/vscripts/tests/test_archive_online.lua` | ARCHIVE_ONLINE_PASS、ZAIXIAN_PASS、XINYANG_PASS | 模拟时钟/档案/连接；日志中 disk_failed 是预设故障注入 |
| Lua 5.1 `scripts/vscripts/tests/test_archive_http_adapter.lua` | ARCHIVE_HTTP_ADAPTER_PASS | 模拟 provider |
| Lua 5.1 `scripts/vscripts/tests/test_archive_live_effects.lua` | ARCHIVE_LIVE_EFFECTS_PASS、BOSS_PASS_EFFECT_EXPIRY_PASS、MAP_LEVEL_EFFECTS_PASS | 模拟游戏实体；不是实机实时发奖证明 |

## 当前发现

- 已有档案后台、在线奖励结算和档案更新入口，可复用。
- `http_fishing_provider.lua` 从 Convar 读取共享 Bearer Token。不得将生产共享凭证放入发布地图或交给玩家主机。
- `archive_service.lua` 有通行证 create_order provider 预留；当前未发现真实支付 provider 注册实现。
- 商城显示组件接受外部商品目录及订单适配器，目前缺真实服务。详见 `../remaining_ui_handoff_v1/COMMERCE_ADAPTER.md`。
- 地图抽奖仍由对局 Lua 选择结果；玩家托管下不能直接把该环境作为可信付费抽奖结算服务器。
- 本地模拟通过不说明公开游廊可运行，不说明玩家身份或通关上报可信，也不代表取得收费授权。

## 后续验证顺序与通过条件

1. **公开玩家托管连接**：在隔离测试地图中，以两个真实账号建房、交换房主，记录实际托管类型、配置加载、HTTP 状态、超时和 UI。使用测试后台与无价值测试资产，不使用生产凭证。仅在工具里启动 localhost 不算通过。
2. **账号和会话边界**：确定当前地图环境可用的认证方式；不能假定有 Dota AppID 的 Steamworks 发行商权限。验证不能靠修改 account_id 读取私有档案、消费其他账号资产或发奖。仅共享 Bearer Token 验证通过不满足此项。
3. **实时福利闭环**：后台确认一笔测试奖励，游戏内数量和属性更新；关闭重开、断线重连、重复请求、回包丢失均不重复发放。生产领取条件保持原样。记录客户端和后台同一 request_id。
4. **受控故障**：测试后台不可用、房主退出、请求超时和旧档案回包。离线成长与正式资产隔离；失败不能显示成功或覆盖云端档案。哪些福利允许本地发放作为后续产品决策，不擅自改变。
5. **支付沙箱闭环**：取得服务商测试环境后，验证服务端商品价格、订单与账号绑定、回调验签、金额/币种核对、重复及乱序通知、查单补偿、失败/过期/退款状态。发货只依据可信服务端确认。二维码必须来自测试订单并明确标识，不放示例收款码。当前无服务商，未执行。
6. **实际付款验证**：商业授权及服务商准入明确、上述通过后，再确定受控交易和退款方案。当前未创建订单、未扣款、未验证真实收款。

## 投入决策

建议继续进行小范围验证。先过玩家托管连接和账号认证两关，再投入支付网关。若可信账号会话无法建立，暂不开放正式付费资产写入；继续可验证的本地玩法部分。若基础玩法可运行但成绩不可验证，不能把未经验证的成绩直接合并到商业经济。

技术可行性、商业许可、用户留存和盈利能力分别验收。不能以组件测试、收款二维码存在或其他地图曾收费作为盈利证明。
