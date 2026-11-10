# 存档首次打开预加载及 tooltip 排版（2026-11-10）

当前状态：已同步原游廊条目 3824360109，版本 2026111004，Steam manifest `392811447400751388`。本轮未部署后台；无代抽、兑换或真实玩家交易。

## 原因与行为

- 紧凑存档控制器此前只在打开/切换页面时创建订阅、请求当前分类。现改为 admission_complete 和 profiles_ready 后，沿用各客户端自己的紧凑认证会话，串行预取 20 个分类。主机、客机没有特殊分支，不携带别人的账号参数。
- 首次界面文字存在原生 Label 被字形图集替换的路径。V10 改为保持原生字体文字，提前准备一次隐藏固定外壳；不依赖纹理字形替换，也不后台构建全部行面板。截图的 GPU 纹理问题尚未取得原生帧采样，不能将路径修正称为已完成实机因果验收。
- 共享 Rich 把 `<br>` 还原成换行字符后未重新输出 HTML 换行，导致多种 tooltip 连在一起。现统一输出受限 `<br>`，仍只允许合法颜色标签并转义其他文本。商城每项加成、激活消耗、月卡加赠按行显示；收藏隐藏冗余“已拥有 X 件”，保留数量栏及单独的叠加说明。
- 抽奖名称顶对齐图片，品质落在图片下沿内；月卡专属、胜场进度与对应按钮中心对齐。未更改奖励、资格、券数、概率或领取保存规则。

## 成本和生命周期

| 路径 | 初始化 | 稳定状态 | 变化和失效 |
| --- | --- | --- | --- |
| 数据预取 | C=20 分类/1049 目录行，最大单类178行；复用模型的一次7942记录/188字段目录索引，各页 O(R)，连同分类头复制总 O(N+ΣR+C²)，缓存 O(N+ΣR+C²) | 队列结束后无定时查询、无页面扫描、无网络发送 | 每次只开一个分类；成功 Dispose，0.1s 后下一个；实测模型解码超过 3ms 时延到 0.25s；8s 超时，每分类最多两次。实际打开存档或收藏立即取消后台消费者，关闭后续接 |
| 服务端现有读取 | 每个 Open 读取本玩家已加载 profile 并投影该分类；仍包含原有 daily_limits/categories 等固定头成本，约 O(ΣR+C²+C×D log D+P×S)，P=5个社交池、S=165社交条目；既有社交投影仍有按池扫描总表成本，仅本轮有限冷加载触发，非稳定刷新。未额外拉取账号 HTTP | 隐藏页关闭后无持续完整页刷新 | 继续由原 transport 的身份、包大小及 CPU/发送预算限流；不新增 server 协议 |
| 原生显示 | 预建一次固定外壳；可见页面才建立 R 个行面板；取消整树字体图集替换和每字面板生成 | 复用原有 O(K) 紧凑增量路径 | 换局/admission 撤回清缓存；缓存必须匹配 ready 会话及 loading_identity；旧 generation、销毁后回包无效 |
| tooltip | 只对当前悬停描述做有界线性换行/标签处理，O(L) | 没有新增轮询 | 原有悬停/销毁/定位生命周期不变 |

一次正常预取逻辑为 20 次 Open/20 次 Dispose，失败最多 40 次 Open。这里统计消费者操作，不能冒充真实 native 网络包数或 FPS。最终作者源码模拟：最大后台批回调0.685ms、含首次前台176行构建的回调16.519ms；实际编译DATA回放：0.680ms/16.897ms。没有 performance.now 时用 Date.now 真实墙钟并始终保持单类最多178行工作上限，3ms仅用于下一批退避，不冒充可抢占的硬限额。以上为本机模拟，不是游戏中的 GPU、网络延迟或 FPS 验收。

## 验证与证据

- 树外 `D:/Survival_本地工具/runs/20261110_archive_startup_tooltip01`：7 组预加载检查、6 组 tooltip/福利几何检查；实际目录/真实紧凑模型，覆盖主客机独立会话、20 分类、前台抢占、未知页、40 次失败上限、同步CreateView错误的延迟清理、换局/晚回包/销毁、收藏预取缓存。
- 现有 daily 紧凑增量 7 组通过；1000 次相同状态原生创建/树查询/文本/样式写入为 0。
- 现有 archive_v10_lifecycle、archive_shared_tooltip、archive_open_profile_refresh、lottery_gw2 四套通过；抽奖永久回归更新到用户要求的新标题几何。
- 另有旧测试在未修改 HEAD 上同样失败：collection_gw2 仍期待旧“我的老婆”名称，collection_rarity_tooltip 期待旧标题颜色，daily_benefits 依赖旧请求载荷；test_compact_archive_model 的旧 Lua 引擎夹具缺 GetGameModeEntity。未改动这些无关断言或伪称通过。新测试直接使用当前目录和模型覆盖本轮路径。
- 首次主机/客机实机视觉与联网耗时仍待新版本普通客户端观察。没有自动启动游戏或消耗物品。

## 发行

- 固定工具任务：`pack_2026111004_52bdcfcd`，2026-11-10 07:52:32Z 至08:06:33Z，约14分钟；逐项完成源码同步、8资源官方编译、完整7056资源/5包文件签名、原条目SDK上传、官方完整下载及全量待发收口。
- 初始作者提交：game `c157a88acaa0e7e24b59be163c0a3809470b1f0d` / content `130de93e8d6016435350f3ff625f53bb3a70ea69`。固定运行来源和operator：game `83c155eaed4ea7d7e7c4a34f6a627e7a56613047` / content `fee40c5c5e57e14d0b7f9792bde68d1683236293`。
- 实际官方编译DATA（8资源，包括目录）与作者来源一致，重跑7预加载+6排版+7每日增量、抽奖完整套件和26奖励富文本检查均通过；日志及摘要见树外 `official_data_verification.json`。双仓来源在stash/pull/pop后按规范化文本逐文件复核一致。
- 报告 `output/packager/pack_2026111004_52bdcfcd/package.json`，SHA256 `67d75873132eedb0552d26f91b3403d7405dc96391981643092f4ed042ba881b`。
- 签名manifest `60d58edc71410ffa9c0e19ba9b0cf75181e3dfaf38edc1d29009de4a49065132`，内容 `78ace066385709d1d6810919f0a5aef56dd9a56b817893030f55171a0a781d11`。
- 官方下载 `output/packager/pack_2026111004_52bdcfcd/download_evidence/20261110T080436Z_f10d25c1ac1b40938f6db88738f78cdb/verification.json`，SHA256 `54e212d0220a049e7b10bca1af9befd769930389efba558ea01b7affea7202de`；状态 `OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED`，Steam manifest `392811447400751388`。
- `delivery_status_1.stdout`：`workshop_synchronized=true`，pending/blocking/historical_sources/dirty_runtime/pending_resources 均0。package资源7056、包文件5完整一致；源码push不是本次“已同步游廊”的替代证据。
- game/dev 与 content/master 均按 stash→pull→pop→commit→push 同步。game保留原有5项非运行改动：`server/archive_backend/__pycache__/match_modes.cpython-314.pyc`、`server/bundles/current.json`、三个既有未跟踪工具（`tools/monster_portrait_release_20261030/finalize_package.py`、`verify_download.py`、`tools/prepare_delivery_operator_20261103.py`）；content无未提交改动。
- 原始作者备份、测试及实际编译DATA均有真实回执登记，未删除旧包/旧事务。本轮后台服务未部署，普通主客机首次进局视觉仍待用户实机验证。
