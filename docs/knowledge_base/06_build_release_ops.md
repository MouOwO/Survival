# 06｜构建、签名、工坊分发与恢复

2026-10-31 游戏内商城：已按本次授权备份并将四人WS4同步到原游廊d573，原29张业务表与支付服务保持。重新登录后的真实获准身份经内部API能读126项钱包商品及48项现金商品，但用户当前游廊客户端仍显示目录未连接；对局暂停，游戏端传输仍待定位，不能称商城已修复。见[版本对齐及未完成验收](evidence/shop_catalog_sync_20261031.md)。

**地图与小地图本地同步（2026-10-30）**：按用户最新保存的Hammer源重新编译并安装，306项成功、0失败，310项包CRC与源CRC匹配；新局实际生成2048×2048小地图，材质/纹理依赖CRC与资源链通过，再次重载刷新客户端缓存。两仓配套提交推送，未执行游廊上传，原发布pending保持。见[地图与小地图同步记录](evidence/map_minimap_sync_20261030.md)。

**地图交付与待续传（2026-10-29）**：地图和配套修复已推送 game `d9f8f1eea / dev`、content `0f53fd1 / master`。新候选 `2026102902 / WS4-MAP-UPDATE-02` 官方编译、308项CRC、6695项签名资源及隔离原生启动通过；Steam清单上传超时并返回3404结果2，远端仍为2901。失败pending已保留，需退出其他离线测试局并完整验证官方2901下载后恢复，不能直接跳过pending重复推送。头像实验未发布，UI／门禁／支付／后端字节未变。详见[地图交付证据](evidence/map_update_release_20261029.md)。

事实截点：2026-10-29。**本轮配套发行（2026-10-29）**：原不公开列出条目 `3824360109` 已更新为 `2026102901 / WS4-ARCHIVE-ALL-01`，总包3,777,996,435字节（约3.78 GB），6695项签名资源、184个模块全部重新保护。Steam上传成功，官方重新下载在内容分发阶段返回 No Download Source／No connection to content servers；当前未取得新版完整下载回执，不能把新远端manifest当安装成功。 服务器已激活 `20261029-archive-d573588b64d2`，不可变bundle `d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488`，PG17 ledger37项／应用RPC19项；原玩家行未变、支付服务未改。原生仅验签名候选启动，四楼交互／多人击杀／真实云端到账待实机确认。详见[本轮发行证据](evidence/archive_all_release_20261029.md)。

## 五种身份分开记录

1. Git提交：源码历史和双仓同步结果。
2. 冻结运行清单／内容SHA：具体候选包含哪些运行字节。
3. VPK索引和各分卷SHA：容器集合身份。
4. Steam安装manifest：特定平台下载快照，必须保留为十进制字符串。
5. 原生验收：特定账号、机器、版本、启动方式真正执行的结果。

Git push 不发布游廊；上传成功不证明下载成功；下载成功不证明两人同局、登录或支付。`GetQueryUGCResult`里的内容句柄 `hFile` 不是安装manifest。manifest可能超过JavaScript安全整数，禁止转成浮点数。原平台pending／journal与验收历史不能因新提交被覆盖成“全部通过”。

## 最新可审计版本表

| 版本 | 主要增量 | 运行项／总包字节 | 官方安装manifest | 实机边界 |
| --- | --- | --- | --- | --- |
| 2708 `WS4-NATIVE-CLOUD-02` | 服务端自动入口、明确名单要求、慢玩家屏障 | 6658／3767360950 | `976725920376391555` | 原游廊双人、登录及逐人云档读回PASS；加入方QR当时失败 |
| 2709 `WS4-NATIVE-CLOUD-03` | 只替换 `payment_test.vjs_c` | 6658／3767362385 | `3869894305253699960` | 官方全量PASS，原房间2人，加入方手机识码及商品金额PASS；未付款 |
| 2801 `WS4-NATIVE-CLOUD-04` | 只替换 `production_progress.vjs_c` | 6658／3767362491 | `6288215904920783611` | 官方全量PASS；客机训练队列布局回归未完成 |
| 2802 `WS4-MAP-RESOURCES-01` | 只替换 `maps/template_map.vpk` | 6658／3767361725 | `2226754158672105621` | 官方全量PASS，主机普通原游廊载图PASS；两机／完整玩法未测 |
| 2803 `WS4-REBIRTH-INSPECT-01` | 只替换转生展示modifier与service | 6658／3767364782 | 未单独重下载；已由后续版继承 | 原生10个展示实体状态/属性PASS，两份Lua与候选相同；完整候选游廊点选/两人挑战未测 |
| 2804 `WS4-TEN-SIN-STARTUP-01` | 开局预备十戒及属性刷新 | 6658／3767365890 | `8833388868921862808` | 官方全量PASS；已由2805补正英雄索引，未做原生画面验收 |
| 2805 `WS4-TEN-SIN-STARTUP-02` | 再补每段绑定当前英雄 | 6658／3767366244 | `3734424561061643436` | 官方全量PASS；原生十戒开局/多人挑战未验收 |
| 2901 `WS4-ARCHIVE-ALL-01` | 全量当前runtime、四楼／奖励回执／服务器d573配套 | 6695／3777996435 | 未取得完整安装回执；远端新manifest已观察 | 签名候选原生启动PASS；新局交互／多人真实奖励待验 |

历史领域记录包括 `publishing/workshop/native_arcade_cloud_20261027.json`、`ui_layout_20261028.json`、`map_resources_20261028.json`；当前入口总状态为 `test_listing.json`，历史十戒记录为 `ten_sin_startup_20261028_v02.json`，最新完整发行记录为 `archive_all_20261029.json`。2802继承QR和布局字节，不自动继承新版双人／支付验收。`ready_for_public_release=false`。

| 版本 | 内容SHA256 | 索引VPK SHA256 | 封包报告原始SHA256 |
| --- | --- | --- | --- |
| 2709 | `1262cbe5905d760c6c15400e4051038613c6a78bffb99b64d9d2d5d609d3cf40` | `b09f36be87db6dc3c8f055e06a9c18438236437d0167c7634effba6707b37278` | `041b7b4fd90500ef15e48e7fa475731455cafbe8da132499d38d6e520004fff8` |
| 2801 | `f20c64b00da4e9d9f1a93bd7fca23163aa3f8b203e9ae354de5f60d9a8c75503` | `8e7f22eb14bbb757702fcca0267f0dc8ce9d6c1a82a802de0265dcd1f503fa6f` | `fdd18e31dea56098a4ffe949591b3aeb2e5a3905764e6b257f42a11e5a0443ee` |
| 2802 | `310aad0a33116f29304d9ea7251524b4c1721bd5fb2b7952610d63cca2ac09d5` | `b3dbe2351798561cd8d585449a7e304822d62f0706689527285c7f41658359f8` | `4b701bce2b41d30ffe4bc5d3628dd44180778e52d70085b58ea7bde801c6a368` |
| 2803 | `7d39ab251f4c8f20d8338a49a8335b0447c0e4e8f6a196978312b40f8981ab96` | `c293d9335610df50417f3f06b86e14e9f576cee4993892c166054b7b9ef78a2e` | `a9492685a24d871dc003a02bf08b2145952f7171409e3bc7088b44c5b21c2320` |
| 2804 | `71a5d2cb2413a427c5c919724ff8384281692700b1fbf48520245525814c4d9e` | `7de376afb1380df8003dc7a5b61728cc7483433d5421e3f235090331c273c4df` | `4ea5b673fdd21fd1753dfd08d627bff0a50313a324c5063cd73e4c820d511555` |
| 2805 | `549afe0f4125a5f880884f1f5a42d1a6ae307b7b7ea97ddacc400e34dcfd0776` | `d6d2f75f530539abe58f69457c41b31f01a362546b573034c860440c9afe8fcc` | `102bbeec95e21acc777ac2418473cc652e01246981adc162c3f0bb36f7a64155` |
| 2901 | `7eee7d5b975573da3e26b2f8fcf079cbc346e33e4a06dc7f7c1c7280691e46ba` | `ccfcc45828f8ce758f43cb4749dd90edf33ed8659a1cdc259bfdc9f762786109` | `39a6877ce20132efcf96cdfb3f435ab6f759d5ba6ab5bd2258fefe2fd0501cd7` |

2802官方完整下载回执原始SHA256：`5babf60a6c7c06bd3867dfb45f9defae57d477ac3728bedea66394ab03f3b948`。原路径为 `output/map_resources_20261028/download_evidence/20261028T010453Z_f4ad7619af99475c859dad247cb377d3/verification.json`。路径仅作证据索引，不能因文件名存在就认定证据内容有效；恢复后的文件仍须核对记录摘要。

## 冻结增量，不把开发目录全发出去

game和content是独立仓库。content存可编辑地图、Panorama与美术；game存Lua、编译资源及相应源码镜像。源码与Valve编译产物配套，遵循 `.gitattributes`，已有LFS资源继续LFS。

本轮2901使用当前完整runtime重新生成生产源、重新保护184模块，并配套d573后端；冻结可信门禁和仅7项生产覆盖。此前增量版本链使用安装目录外的新建候选、薄overlay、trusted source和完整view。builder默认只读，显式构建才写新目录；不覆盖旧候选、旧builder、旧verifier或运行addon。每版固定基准内容、源hash、实际编译hash、允许变化路径、清单和总大小，构建前后防漂移。报告／内容／索引／总大小未填实际pins的verifier必须在SDK之前拒绝，不拿旧manifest补空。

2708至2805的历史增量链逐字节沿用180份受保护Lua，认证、支付、四账号门禁与名单要求不随当时的资源修复重建。2901改为全量受审源码重新保护184模块，旧保护模块复用数为0；本轮review source精确为14份代码加policy／公钥，共16项，按实际清单校验。新入口与玩法代码经生产配置覆盖和完整源清单审阅后构建，不能用未审工作区文件或明文保护模块临时覆盖已签候选。

老工具曾以 `git diff HEAD` 取补丁，提交后差异变空；现有候选应固定明确的任务起始基准，并另外记录当前HEAD／工作区身份。“补丁比较基准”和“构建时HEAD”不得混用。构建candidate成功不表示当前开发玩法变更全已发布。

独立工具：

- `tools/native_arcade_cloud_20261027/build_qr_fix.py` 与 `verify_qr_fix_download.py`：2709冻结QR增量与官方下载验证。
- `tools/ui_layout_20261028/build_layout_fix.py` 与 `verify_layout_fix_download.py`：2801单UI增量。
- `tools/map_resources_20261028/build_map_resources.py` 与 `verify_map_resources_download.py`：2802单地图增量。
- `tools/stream_workshop_vpk.py`、`tools/steam_workshop_upload.py`：分卷与官方UGC上传原语。

新项目可复用固定输入、限制差异、签名、完整view与官方重下验证，但需要新的条目、信任策略、公钥与私有签名环境。不能复制本项目密钥、Bearer、测试身份或第三方保护代码。

## Lua保护与签名不是同一件事

Lua保护基于固定版本Prometheus，目的是提高逆向成本，不是密码学保密。可执行客户端所需值仍可恢复；商户密钥和业务权威必须留服务端。AES-GCM只用于外部私有源码备份；清单真实性来自固定信任策略下的Ed25519签名，VPK本身没有作者RSA签名。

保护构建检查Lua5.1语法、完整纯数据深层同值、四业务探针、无io/os/debug加载、私有随机数不推进游戏全局随机、前后开发源hash不变。任何选中模块失败即停止，不能回退明文后继续发布。保护Lua树不是完整运行包，完整组装后必须重做全清单双hash、验证和签名。最低序号不能为回退而降低或关闭；需要旧行为时用批准旧内容生成新的合规候选。

## 大VPK读取故障与五文件集合

历史约3.77GB inline VPK的字节、CRC、SHA和MD5均正确，但Valve原生工具仍报 `Failed to read 16 bytes / Unknown read error 87`；仅改VPK v1可列目录，大偏移读取仍失败。同内容改小目录＋四个不超过1GiB资源卷后，原生读取和包尾资源通过。证据支持大包读取兼容性问题，未定位Valve源码缺陷，不能解释为“代码没提交”。

超过 `0x7fffffff` 时分卷；打包逐项核对大小、CRC、双hash并独立解析复核。先发布数据卷，最后发布目录包；已有目标拒绝覆盖，失败只清理本次产物。目录和分卷必须同版齐全，不只发小索引，也不混放不同版本。

2802五文件大小：

| 文件 | 字节 |
| --- | ---: |
| `3824360109.vpk` | 274380 |
| `3824360109_000.vpk` | 1073604434 |
| `3824360109_001.vpk` | 1068730788 |
| `3824360109_002.vpk` | 1072379183 |
| `3824360109_003.vpk` | 552372940 |

全部6658项签名资源、180保护模块、16review source、5个VPK与签名均通过作者官方下载验证。只比这五个大小及索引SHA是较弱的安装诊断，不是全量载荷验包；加入方工具明确保留 `full_payload_hashes_verified=false`。

## 2801布局与2802地图的准确范围

2801针对其他PC训练／生产队列错位，仅编译 `production_progress.js`；不改认证、支付或玩法。源码SHA `136ce07fcebc36c7c27ffc428ab05c0d7f63837902f5c7dfdb885b553810cc27`，编译SHA `36dd249135d8c650ea0055023c33e4df2cc7b068a77e7521b32ba82cbac5b4ce`。12视口、72物理缩放组合及10选择切换通过本地回归，冻结09负对照能检出原问题。用户客机分辨率2560×1440，但实际UI缩放／显示模式未知；仍未做客机实机验证。冻结09已有tooltip测试失败单独保留。

2802按用户明确要求发布当前地图更新。读取实际editable源、依赖闭包后运行既有 `tools/map_c6/compile-main.ps1`，不使用SourceMap参数改源。真实编译302成功、0失败、1跳过，地图内部307项CRC通过，编译来源CRC与原始source匹配：

- `content/.../maps/template_map.vmap`：72574022字节，SHA `4e62350c1bf08e663f5217885f26652918c2e09296a829f29a987ba8a14dccdc`，CRC32 `3557144492`。
- `game/maps/template_map.vpk`：65142294字节，SHA `f868f295a01b78f63dbeb9fe9edfc6a7591b3889ace84f0892f595ac46f22186`。
- 4个builder、4个monsterborn、12个archive标记无意外缺失；相关overview／valley编译依赖与冻结包已相同，不重复加入无差异资源。
- compile log SHA `be9a1899a5f39ada3bef977e5d53a77f0da794efa8464f7f083b6947878450c4`；地图验证报告SHA `ddcd2dd519777e56e7fca1d5ee8849f58d8939bbe0c795aaa36e5f5636ba777f`。

构建器强校验真实编译证据、来源CRC和307项验证，verifier拒绝伪造报告flag／hash。主机载图通过不代表建筑、波次、两人布局或整局玩法均通过。

## 官方上传、下载与失败恢复顺序

标准流程：核验不可变基准→定向叠加→审核允许路径与保护字节→Valve编译／来源DATA核对→全清单双hash与签名→分卷→上传只读preflight→一次明确更新原条目→官方新鲜查询与下载→核验安装manifest／字节／签名→原生玩家验收→分别更新发布记录和验收状态。

上传使用原条目，显式 `--apply --update-existing`；不自动新建条目，不因pending异常删除journal。`3404/EResult=2` 或manifest timeout是失败／待核对，不写uploaded成功。恢复须在锁内根据原pending身份、新鲜官方查询与实际完整下载证据做compare-and-swap；保留旧pending、失败包和失败回执。2707失败与2708成功、2703超时与2705成功都是独立版本，不能改写失败历史。

SDK流程核对当前账号与条目作者角色；发布工具需要作者，客机诊断不能复用作者硬限制或把OWNER常量改掉。fresh详情query设置cache0，但只排除该查询缓存，不证明所有平台传播和账号权限相同。已经订阅时幂等Subscribe等待1313，下载等待目标App／item的3406；回调成功还要比安装信息与实际字节，历史已出现3406成功却仍装旧版。只恢复正式证据，不能手改ACF或用内容句柄当manifest。

加速器切换应先完成再建房；Steam断线重连后旧大厅视为失效，重新核对原生UI并建新房。Dota队伍2人不等于房间2人；历史搜索／密码找房失败，先组队再从原条目建新局是已成功路径，最终以同一游戏两名实际玩家为准。

## 部署、安装与清理边界

网页sidecar首次安装采用 `audit → prepare → activate → verify`；已有服务更新先rollback，再prepare／activate／verify，不原地改运行文件。传输配置切换依照现有工具的rollback／prepare／configure-transport／activate／verify顺序。回退区分代码、服务、资源和数据库，不将服务回退变成删除新测试档；保留旧服务、旧账本和明确回滚记录。

Windows完整客户端分发要先验文件集和hash，再安装，最后测试网络。短解压路径不能恢复已丢的文件；0字节文件需从完整可信包修复。安装器须同时处理源和目标长路径，错误阶段区分check_layout／check_resources／install_runtime。旧加入派发器已退休至legacy，不恢复一堆根CMD。

引擎会扫描addon搜索路径中的VPK，`.gitignore`不能阻止扫描。坏包／测试夹具／输出不能留在game或content搜索范围。清理前核对跟踪状态、绝对路径、reparse、活跃进程、候选依赖和备份；默认只读，明确目标后才删除，不以磁盘紧张为由整目录删除output、私有工具或会话证据。

## 双仓交付的固定约定

每次任务均核对game与content分支、上游、未提交、未推送和已有stash。固定顺序是：`stash --include-untracked → pull → pop本次stash → 检查原改动恢复 → 只暂存任务路径 → 验证 → commit → push → 核对远端HEAD`。记录本次stash对象，不清历史stash、不强推、不丢原改动；无新改动不造空提交。签名包、私钥、缓存和运行输出不入Git。

地图2802任务已完成实际双仓交付：game提交 `ba81736bf45d0dc74373858c39d99c0f7ca1f69b` 推送 `origin/dev`，content提交 `4711503a8312d106cfa05ceb67c72e74f7d2329e` 推送 `origin/master`；原102份game开发改动保留，content当时干净。对应真实恢复后交付脚本的只读检查和显式提交均成功。这是知识归档开始前的地图任务交付，不是本知识库自己的最终提交。

本轮原有开发改动与发布任务拆开保留，不能因冻结包发布把所有dirty文件一并提交。最终由交付负责人另报知识归档的game/content提交、推送分支和保留改动；本页不编造尚未完成的编号。工作区HEAD、发行包与知识归档各自独立。

## 2026-10-28 工程目录清理第一轮

按用户明确要求删除历史地图中间导出、视频/OCR 抽帧、浏览器截图/预览副本和部分设计工作缓存，并移除零活动引用的12张 ST2 贴图及其孤立编译样式。共13,076文件、12.93 GB；工作文件约42.85 GB→29.97 GB（不计Git历史和目录链接），尚未达到10 GB目标。此次没有发布新游廊包，原2802发行与官方证据保留；当前游廊包约3.77 GB，不能当成开发目录已小于10 GB。

所有删除文件先归档至 `D:/Survival_清理归档/20261028_round1/historical_files.zip`，6.78 GB，逐文件回读SHA256核验后才精确删除。ZIP内 `_cleanup_manifest.json` 保存原路径/大小/哈希，旁边保留删除账本；历史报告引用的已归档截图/中间文件按清单取回，不整包覆盖当前工程。原102项改动、当前地图与源文件、正式UI、官方回执、运行中转和原备份均保留。另一任务并发修改三个战斗模块并新增wave规则，明确排除在清理提交和“运行字节未变”断言之外。8项清理测试及21项运行清单测试通过，1项符号链接测试受Windows权限跳过；没有新游戏内验收。详见 [清理验证摘要](evidence/directory_cleanup_20261028.public.json)。
