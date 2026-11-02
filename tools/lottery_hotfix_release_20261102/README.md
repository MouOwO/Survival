# 0104 四项 UI 热修复候选 2026110202

本目录仅准备 `WS4-LOTTERY-HOTFIX-02`：以实际已签并官方下载核验的0104为父，精确替换抽卡 `lottery_cinematic_v1.vjs_c/.vcss_c` 和训练提示 `ui/production_ui_service.lua`、`ui/ui_request_router.lua`。不增加／删除资源，保持6917项、184个保护模块、五账号／四人容量、原后台与支付配置。四视频和四主题纹理继承父包原字节，不重编码。

0201的17项仍未发布，本次不搭车。其全部签包、source pins、排演及原生门槛保留，未随此热修复发行不构成正式版本回退。新ledger逐项绑定0201的20个game资源／编译源与3个content镜像，状态明确为未发布延期；与旧220项历史延期分开记录。任何域内新漂移、域外未知变化、symlink或删除均拒绝。原0104仍按真实签名资源SHA认证，不能把其Git提交误当完整已发布源码。

JS与CSS分别绑定Git-LF作者源、实际CRLF官方编译输入、编译产物及正确的content scripts／styles镜像。训练Lua只审展示映射，奖励、概率、价格、交易链和内部错误码不变；原18份可信审阅加两份训练源共20份。

## 操作顺序

默认命令仅静态计划，0签名、0Steam、0进程查询、0输出目录创建。Root完成game/content双仓stash→pull→pop→验证→commit→push后，使用完整40位game、content、operator提交；operator可与运行源分开，但实际输入必须匹配该不可变提交。

唯一公共入口为 `tools/release_pipeline.py`，必须先由Root完成新authority的准确路径／SHA注册；不允许向旧0201 recipe硬塞新HEAD，也不直接调用旧SDK上传旁路。

```powershell
python -B tools/release_pipeline.py status
python -B tools/release_pipeline.py plan --source-revision GAME40 --content-source-revision CONTENT40 --operator-revision OPS40 --report output/lottery_hotfix_release_20261102/plan.json
python -B tools/release_pipeline.py prepare --source-revision GAME40 --content-source-revision CONTENT40 --operator-revision OPS40 --reviewed-plan output/lottery_hotfix_release_20261102/plan.json --reviewed-plan-sha256 PLAN64 --report output/lottery_hotfix_release_20261102/unsigned.json
```

上面大写值是待Root明确提供的占位符，不能执行为有效计划。unsigned不含签名、不能安装或上传；Root审阅具体scope和unsigned后，签名与更新原游廊须遵守用户实际授权。`build`要求显式外部key和同一真实reviewed-plan SHA，输出固定NEW `package.json`；构建不会上传。

新路径前缀为`20261102_ws4_lottery_hotfix_v09`，REPORT为`output/lottery_hotfix_release_20261102`。rehearsal复用经过原生验证的v04同handle退出、完整五包物理备份、CAS、data先／index最后、未知状态保留及0104完整恢复；独立STORE、挂载engine.log和端口29062，不修改旧工具。启动明确选`direct`或`lobby`，均普通客户端、cheats0；禁止领用手动进程或以Tools替代。

## 本轮原生门槛

新signed包先认证，再用同一owned普通进程检查四奖池无消耗Preview：各窗前／演出两阶段／结束回窗的真实截图、至少一次真实MovieError或同步错误→同主题动画、券余额不变。已有普通`lottery_film_<pool>_<stamp>`入口只做演出；Tools-only原生动画入口不能冒充普通验证。每池首错后同局熔断直走动画，固定4槽，Dispose／换局清空；不会发送抽卡、购买、领取或兑换请求。

门禁保留真实PID／CIM创建／native FILETIME、固定argv和日志、前后四data卷使用／五keeper handles、raw index false诚实记录、同handle正常退出、原五包还原及当前完整验证。不引入Boss、双PC或无关FPS门槛。只核无消耗Preview结束回窗，不要求真人抽卡结果或花券；真实ACK→卡片的Node回归是合成链路，不写成生产交易。新包普通原生和官方下载尚未发生时保持拒绝。

发布仍由common lease重验签名／source／native证据／父journal CAS后上传完整已验证五卷，成功后再独立官方完整下载；不是运行时热更新。未知Submit保留pending，不自动重发。旧0201的双PC／Boss／FPS门槛没有放宽。

## 成本与隔离测试

一次计划按约6917父row、源树和有限绑定索引O(M+S+B)，Git blob按需有界读取；unsigned只写4payload＋manifest，签包复用未变卷。额外23个0201延期源只在显式运营阶段校验，游戏稳定阶段0新增工作。rehearsal稳定等待沿用2000ms kernel wait，无CIM／全包hash／场景遍历。native证据最多固定4池、16张截图及有界元数据／日志，无游戏循环。

```powershell
python -B -X utf8 -m unittest discover -s tools/lottery_hotfix_release_20261102 -p "test_*.py" -v
```

全部测试只使用合成源／证据与临时文件，外部签名、VPK构建、OS／进程／SDK操作均不执行。测试通过不能写成签名、普通画面、消费或上传成功。合成VPK实验必须位于addon外；本目录没有生成此类实验包。
