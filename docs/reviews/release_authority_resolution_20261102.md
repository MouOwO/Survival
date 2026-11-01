# 0201分辨率修复发行入口接入（2026-11-02）

新family为`tools/portrait_resolution_release_20261102`、候选sequence `2026110201`。它仍以真实正式0104为父，保留17路径、6919资源、184保护模块、22项审阅、五账号/四人上限及220项明确deferred历史边界。新combat含分辨率尺寸门禁修复；坏1107不发布，也不实施此前manual-GC operator-policy迁移草案。

当前仅完成代码/配置与隔离回归。没有生成新immutable source/operator审阅plan、unsigned review、签名包、原生lobby验收或官方上传。旧1107的900p双人111.08FPS/P9510.958ms不是0201的实际FPS或peer1000p验收。

## 接入范围与身份

- 新`publishing/workshop/release_authority_20261102.json` SHA `22632bf603866cf4ef7a4d13af217965140aa2abb15e51b977d5f5b0d2a126dd`，只指向新recipe/validator/rehearsal/download固定路径和摘要。旧20261101 authority保留SHA `06df3c0d9154b2866463a5e525c85997590a0b8d6f71013b98279c36405eaacb`。
- 公共SDK hook仅切换固定authority路径与SHA，当前SHA `abd8205767bf83892499eefae014724941dfaaa5c7188657d6cfeb5795783329`。调用方没有authority路径或READY覆盖选项。
- canonical CLI SHA `768d339047dc71db83e4a149c98d37787eb91c45fd3a7fe2ce9abe442d5a22fa`，新增受限`--route direct/lobby`显式转发与authority固定download委托。guard代码保持原SHA `03746fa43706549e0b76434badbf715e604cdf42d0efe7431cd66a395aa30609`。
- 新native policy SHA `2c53a44b5329e851892a0e43e8d4cb0e505088b265e2401403961e8787771397`，validator SHA `d081b93eabb8de92cec9e2e57e035dbf42237e435e39e687774141e98f1284ae`。recipe `05f52c5b…7aa859`、rehearsal `24c18c68…a68948`、download `47b1ee96…281fac`。

配置激活时短持与所有旧发布器相同的canonical`.lock`，核原0104 journal raw SHA `6e6f5f6b09995bf715d68900d2c86f871aab83ccf2998da5a8c9e7412386628e`且lineage state尚不存在，才落新authority/替换hook。该过程未写canonical journal、未创建lineage、未调用SDK或读取签名密钥。旧1107报告raw SHA `86c10bed…3878e3`保持，旧AUX pins没有回填；公共hook/CLI的授权变更将由新0201报告固定新字节，不冒充旧1107仍适用于today工具。

## 唯一入口及保持的门禁

默认/status仍纯静态。plan/prepare/build继续委托固定recipe并要求game/content/operator不可变提交；实际构造应在两仓最终同步后才审阅。bootstrap必须显式绑定真实0104混合资源父及原Git ancestry cursor，不把其source label当完整已发布源码树。

新lobby路径必须显式选择，例如以下仅为未来调用格式，未执行：

```powershell
python -B tools/release_pipeline.py rehearsal launch --transaction <new> --report-sha256 <actual0201> --route lobby
```

新ops在启动普通主菜单前持有五卷，使用确定的绝对native日志路径、`-condebug`和端口29060。用户从原条目的正常UI创建/加入Local Host、双方先到齐再开局。direct原协议仍保留；未知route、manual/adopt、错误argv或无owned launch均不能替代受控新进程。没有“接管已运行Dota并补写旧launch回执”的路径。

新native gate除原相机/饰品/背景/QWER、冷回切、真实>=30秒FPS（mean>=90且P95<=16.7ms）、正常退出/holds/full restore等约束，还强制：本机strict900p对照、peer1同新候选Alchemist安息900/1000配对、QOP09或Bane5的1000p图、真实native两人handoff/status和用户精确图片SHA同局确认。远端图实际解码/尺寸验证，不能用Root图或假CIM元数据冒充；远端身份/时间仍如实为人工确认，不声称peer FPS或kernel来源。

preflight仍完整验证但不创建pending或SDK capability；publish重新验证后持唯一lease，禁止嵌套SDK锁，真实SDK成功回执后才推进generation。原parent CAS、unknown pending拒绝、sequence递增、feature祖先、原条目/Unlisted/名单/封面及全部历史保留不变。旧1107请求即使附READY也在进入完整包或SDK前拒绝。

## 官方下载

`release_pipeline.py download`默认仅固定模块的静态计划；`--preflight --report-sha256 <actual0201>`只做完整本地检查；`--apply --report-sha256 <actual0201>`才执行已授权官方读取下载。下载不获得SDK mutation lease，不能上传；仍持canonical OS锁串行复核，保留未修改的官方1313/3406协议。

实际下载必须顶层canonical为成功0201、lineage generation1/pending null且head raw CAS/source/manifest/origins相同；父20条history及其旧previous不丢，更新后history为21条、previous为0104。旧0104只允许本地preflight，不允许当新0201下载成功；unknown状态不清除、不重试。必须真实新鲜远端详情/回调/ACF manifest及五卷6919资源全验证。冻结协议终端180摘要未改，权威verification receipt仍记录184，不混为同一数字。

## 隔离回归与后续

新增/复核：canonical CLI14、newauthority3、公共hook9隔离回归均通过；新download16通过；独立再跑新native10 whole-gate组通过。它们不调用真实SDK/原生UI/签名/发布，也不是0201现场验收。newauthority回归直接加载已pin代码，验证旧1107/READY拒绝、缺任一新combat编译pin在Git工作前拒绝；CLI覆盖direct/lobby、未知route、旧inspect shape、下载缺参/冲突和下载不授予上传lease。

```powershell
python -B -m unittest discover -s tools -p test_release_pipeline.py
python -B -m unittest discover -s tools -p test_release_authority_20261102.py
python -B -m unittest discover -s tools -p test_release_sdk_lineage_hook.py
python -B -m unittest discover -s tools/portrait_resolution_release_20261102 -p test_download.py
```

Peer当前旧1107 run02与run01 quarantine材料须保留。先原FDD Restore（显式绝对File/Bundle、原run02）回0104，再由未来已签0201固定便携器用NEW0201 backup安装；不能直接overlay。新便携器应在函数体赋Bundle默认、增加有界成员进度并另作完整lab回归，不能复用旧1107 pins。具体待签名操作设计留在ignored输出，不作为可执行交付承诺。

初始化认证是一次O(6919资源+50级工具输入+包字节)批处理；SDK setters仍仅控制JSON CAS，没有新增全包/场景遍历。完整下载/原生验收不能与ETW采样并行。下一步是Root双仓同步、最终immutable source/operator plan与具体unsigned审阅；本记录不授权或声称已完成这些后续步骤。
