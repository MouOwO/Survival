# 商城兑换码

游戏入口位于商城标题右侧，复用购买按钮。弹窗只有官方输入框、兑换与取消，错误采用原生 HUD 提示。服务器按账号每码一次，重试复用请求；错误码不发奖，过期/停用/次数上限均由数据库判定。

所有已实现的非 VIP 商城商品均可作为奖励，含两种抽奖券、G币与签到月卡。VIP等级/充值成长、VIP权限、VIP礼包和勋章被禁止。未实现或暂停的历史批量商品保留在 Excel 排除清单，不创建无法兑现的码。礼包拆为单品，永久商品复用商城与抽奖的身份去重，已拥有部分不阻断其余奖品。全奖码每种消费券给一份，G币给一个标准充值份额100，签到月卡30天。

生成运营表（会创建真实随机码，输出目录应在被忽略的 `output/` 下）：

```powershell
python -B -X utf8 tools/redemption_codes/export_excel.py --output output/redemption_codes_private
```

表格第一条为 `ALL_NON_VIP` 全奖码；其余每个商品一条。每账号次数固定1，全服总次数0不限，开始/截止时间按北京时间解释。实际码仅在运营 Excel 中，客户端没有有效码表；服务器只存SHA256与冻结奖励。不要提交运营 Excel 或真实码到Git。

修改 Excel 后先只校验，再登记到服务器；现有账号领取记录和已接受的奖励快照不会被覆盖：

```powershell
python -B -X utf8 tools/redemption_codes/register.py "C:/Users/Administrator/Desktop/孤城逐晓_兑换码配置_20261029.xlsx"
python -B -X utf8 tools/redemption_codes/register.py "C:/Users/Administrator/Desktop/孤城逐晓_兑换码配置_20261029.xlsx" --apply --via-local-proxy
```

`--via-local-proxy` 仅在直连SSH超时时使用现有127.0.0.1:7890代理，继续校验固定SSH主机密钥。不会更改系统/VPN配置。停用旧码需保留原码行并将“启用”设为0，改码会新增记录。月卡按当前到期时间续期，已有永久月卡不会变成有限期。

首次部署使用 `deploy.py build → prepare → validate → activate → verify`。它以实际远端源码为基线加入两处存档钩子和两个最小权限RPC，在独立数据库克隆验证后增加三张专用表；旧SQL函数、旧存档配置、支付进程与历史玩家数据保持。正式服务器激活不代替原游廊包更新或真人兑换验收。

回归：`python -B -X utf8 -m unittest server.tests.test_redemption_codes.RedemptionTests`（设置`PYTHONPATH=server`与`LUA_EXECUTABLE`）、`lua5.1 scripts/vscripts/tests/test_redemption_service.lua`、`node --test tools/redemption_codes/test_ui.cjs`。`database_checks.py` 只接受明确命名的克隆数据库，真实SQL并发与事务检查不会在正式玩家档案上试发全奖。
