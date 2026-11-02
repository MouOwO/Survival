# 0301 run01观察与正常恢复｜2026-11-03

用户确认已进常规N1，另确认本局已完成Steam网页授权。owned PID31796/created_utc 2026-11-02T16:38:22.3229890Z，原keeper会话11420。初始截图lottery0301_n1_before01.png确见N1、建造者和第2波倒计时；不是登录截图。

before01观察4个data卷都有同进程Dota使用，index已关闭；keeper持有完整5文件。原观察status=INCOMPLETE_NATIVE_FILE_USE_EVIDENCE保留，不能把其all_five/index=false改成true；现有policy接受4个data实际使用+外部完整签名绑定，但这本身不是整轮验收通过。

存档正常点击的三张截图未得到存档窗口；后续截图有命运抉择modal遮挡，不能把点击返回ACTION_COMPLETED当界面打开/存档准入。VConsole预设29066连接拒绝，实际枚举出的54638不是VConsole协议，未取得原生命令回执；没有JS/Lua注入，没有擅自改端口或放宽准入。

日志已出现两次真实抽奖结算，不由Root本轮自动指令发起；不能据此猜测操作者，不能将此局当无交易预览或三次十连证据。仅只读观察到ACK 980.8263ms / 1030.9265ms，总fallback snapshot ready 2716.9477ms / 2046.0668ms，定位额外串行快照等待。Root自动券预算仍0/30，用户被告知画面普通券1张不足三次十连，已请求之后独立交易轮次准备足额或先做预览。

此前将券旁三角误称未同步警告已明确向用户纠正：源码LotteryGW2TicketHelp实际为普通券获取渠道说明，不是同步错误。不能以该图标推断缓存失效或否认用户授权。

run01不准入、不上传。canonical close正常WM_CLOSE，keeper11420 exit0明确CLIENT_EXITED_RESTORE_REQUIRED；随后restore真实exit0，ORIGINAL0104_FIVE_FILES_FULLY_RESTORED，所有证据/备份/旧0301签包保留。正式游廊仍0104。实际WS4回执优化仅audit通过，后续部署不修改规则或真实数据，见tools/ws4_lottery_receipt_20261103及其开发审阅。

## 后续：实际WS4已完成部署/独立复核

在本机正常退出/恢复后，实际WS4以不可变operator f32ab80b6b8780d30d7deb0fda3edbbe8a9f5312完成prepare、真实冻结Lua三轮合成probe（四池/37券不变，RPC0，695.15/686.49/692.05ms）、activate及独立verify。新发行20261103-ws4-lottery-receipt-d2c7c2e85920，API PID592495，manifest SHA256 75c7fd8fc1e95fc1a5a73e521e1d5f9cd411c271ba99028ccfef779b46e48a11。仅WorkingDirectory一行切换至新backend、只重启WS4 API；env/bundle/完整父版/unit备份保留，7个无关服务PID保持。没有迁移/真实交易/玩家数据修改；后台既有启动同步保持，工具无写SQL不等同全服务从未有正常写库。

Root自动0/30；未取得新版客户端实际三次十连/耗时/电影连续播放证明，不能发布。已通过异步问题请用户确认后续独立交易轮次能否准备至少30普通券，或先做无消耗预览，尚未收到该选择。新一轮仍须完整保留旧证据并取得原生准入，不改写旧run01。

第二轮去重10月23—24日三份展开包大美术副本，3027对/8,916,873,303字节，独立file ID和1009唯一hash全部复核通过。两轮共20,806,037,707重复字节，所有包路径/签名/地图/VPK/恢复备份保持，D盘约16.55GB可用。详见storage_dedup工具round2和output/storage_dedup_20261103/independent_verify_round2.json。
