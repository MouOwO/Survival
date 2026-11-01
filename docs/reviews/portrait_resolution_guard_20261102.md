# Boss头像分辨率门禁：现场确认与修复候选（2026-11-02）

现场已确认分辨率相关故障，源码门禁机制已由生产函数回放复现并支持该解释；peer原生layout/scale及具体拒绝分支尚未直接采集。修复已应用到game/content两仓源码，完成官方单文件编译和默认生产源回归。新尺寸普通双人局画面及FPS仍待验收；旧1107不得发布，新候选尚未签名、安装或发布。

## 现场证据与源码绑定

同一普通双人局，主机1600×900头像正常；另一位玩家1600×1000时多个Boss落回残缺的原生头像。截图中的“安息”世界模型带完整饰品，底部头像主要显示手和裤腿及原生蓝底。不能据此认定资源被覆盖或回滚。

Root请该玩家在同局改成1600×900，切另一Boss后再选“安息”。用户明确回复：“改成1600×900后恢复正常”。这把问题收敛到分辨率相关的头像锚点门禁；该玩家原生leaf的实际layout尺寸尚未直接采集。

1107源game/operator为`eaef4398383be211880423eb142eb0a1d723c69f`，content为`eb281a1398466876575a5885e60a8dd207e5f556`，report SHA为`86c10bed12d60403d31b1951cbd608a86523835bca39ef563b1f36b3fd3878e3`。读取的combat源码raw SHA `d6dbbbe8adc4d61f95ac97cc177079a080de6095af86192614657f789f70ea7a`与report compiler input一致；SIGNED VIEW编译物SHA `e9da3be3168381b63c3a7fd14f20e5561458f16f366ca9cedfe504c9968ae1f5`也与report一致。不是仅检查未发布的未来源码。

正式topnav/HandoffGeometry把原生`portraitHUD`设为264逻辑px；`portraitCandidateUsable`及`queryPortraitRejection`却各自硬拒绝物理height>240。900p原生曾实测220px（264×0.8333），1000p按原生scale应为244.444px。实际生产函数回放中，两位玩家在220px均通过，在244.444px均被拒，即使原生portrait unit与期望单位完全相等。该链路无需player0特例即可复现。现场A/B支持这条尺寸门禁根因，peer的244.444px本身仍是推导值。

## 候选范围与生命周期

采用已独立复审的v02；实际game/content源码raw SHA `2947af1a6143f8c6df18f98b6fdc35dbf95c40c8309cb8c45a5ad1101b8884f1`，Git规范LF SHA `1af65125378603ff72040c5b27651d308c1d73a603c62e2974032bcd6e10bfca`。候选只针对combat头像锚点；renderer、饰品组件、官方背景、相机、197身份/188场景目录和逻辑LRU4均不修改。

统一geometry helper先使用leaf `actualuiscale`，缺失时使用root scale，两者均缺失才按viewport-height/1080兼容。显式0、负值、NaN、Infinity不静默回退。尺寸先拒绝非有限/巨大物理placeholder，再按逻辑单位验证264px叶的有限范围；保留attached、可见、底部区域、原生单位精确相等的约束。

缺失main时保留发现过的确切`portraitHUD`/`DOTAPortrait`引用、尺寸/scale签名及最多32层祖先对象链。真实尺寸或祖先身份变化才使负缓存失效；稳定状态不重查根节点。独立审阅曾在v01发现“旧leaf仍存活但移出原容器，同数量新leaf补入”的反例；v02已覆盖直接重挂、直接parent不变而祖先移出根、祖先仍在根内重挂，以及destroyed同数量替换。正缓存沿用既有attachment检查，不新增祖先遍历。

## 复杂度与调用预算

设H为实际HUD节点数、D≤32为当前叶祖先深度、Q≤2048为既有query索引节点上限。0.1秒刷新不扫描H、197身份或188场景目录。初始化及真实重建可作既有O(H)根查找、O(Q)query建索引；稳定O(D)，新增缓存空间O(D)，只保存一个原生叶的祖先链。

| 生产函数fixture路径 | 初始化/变化 | 稳定刷新 |
| --- | --- | --- |
| 初次真实selection | 9次root查找；0/10000无关节点时总访问84/50084 | 后续不重复该发现流程 |
| 已有有效main跨分辨率 | 直接复用原生leaf，0次root查找 | 300及10000次刷新：root查找0、重复style写0 |
| missing-main真实尺寸/scale恢复 | 一次root查找（fixture） | 恢复后10000次：root查找0、anchor子树查找0、style写0 |
| 存活旧probe/祖先重挂 | 固定D链识别变化，再一次发现 | 正确恢复后10000次：root查找0、style写0 |
| 完整portraitUpdate | 相同状态不重复桥写入 | 0/10000无关节点的计数相同；既有overlay局部访问12节点/次 |

完整portraitUpdate的同一900p fixture：旧源为GetParent34、IsValid58、child-count4、position8、layout属性读10；候选为34、60、4、8、30。增加的是2次有效性检查与20次固定layout属性读取/次，没有新增根查询；10Hz下对应每秒20次检查、200次layout读取。这里只是模拟原生对象调用/属性计数，不是桥耗时或FPS。已有overlay局部12次访问也没有冒称为“全部递归零”。missing-main稳定期只比较一条最多32层原生祖先链，不检查兄弟或全树。

## 可提交回归与当前边界

`tools/test_portrait_resolution_layout.cjs`执行真实combat源码函数，包含72例：player0/1、900/1000/1080/1440/2160高viewport、DPI1/1.25/1.5/2、scale优先级/兼容回退、坏scale/尺寸/root、隐藏/opacity/错身份、同HUD恢复、存活及销毁重挂、换root、稳定300/10000次及无关节点数量不变性。`tools/test_portrait_resolution_costs.cjs`复用相同生产fixture，独立约束零根查询/零重复写入及固定调用预算。测试只读取源码，不写回执/运行输出。

应用前，默认测试对旧生产源明确拒绝，显式传入v02候选时通过；应用后，两个新领域测试和既有callbacks、anchor identity、HUD lookup lifecycle已全部直接对默认生产源通过。独立复审也重复通过存活leaf/祖先重挂反例。官方编译与领域回归已经完成，但它们不代替玩家1000p画面或FPS验收。

本轮实际运行并通过：

```powershell
node tools/test_portrait_resolution_layout.cjs
node tools/test_portrait_resolution_costs.cjs
node tools/test_combat_stats_callbacks.cjs
node tools/test_portrait_anchor_identity_cache.cjs
node tools/test_combat_hud_lookup_lifecycle.cjs
```

canonical game源为`panorama/src/scripts/custom_game/combat_stats.js`；content镜像为`D:\SteamLibrary\steamapps\common\dota 2 beta\content\dota_addons\Survival\panorama\scripts\custom_game\combat_stats.js`。本轮写入前先确认两者原raw均为d6db，再写入已审阅字节。两者现CRLF原始字节相同；官方compiler输入为content镜像。已执行以下命令，exit0，1 compiled / 0 failed / 0 skipped：

```powershell
& 'D:\SteamLibrary\steamapps\common\dota 2 beta\game\bin\win64\resourcecompiler.exe' `
  -i 'D:\SteamLibrary\steamapps\common\dota 2 beta\content\dota_addons\Survival\panorama\scripts\custom_game\combat_stats.js' `
  -game 'D:\SteamLibrary\steamapps\common\dota 2 beta\game\dota' -f -nop4
```

实际配套产物是game的`panorama/scripts/custom_game/combat_stats.vjs_c`，SHA `5f3d0fc3ba8639d438cd973af7bdea5369004e5d65e202dd22830624a3c09b93`，233620字节。两份source均为232772字节、4415个CRLF换行；Git规范LF摘要`1af65125378603ff72040c5b27651d308c1d73a603c62e2974032bcd6e10bfca`，实际compiler input摘要`2947af1a6143f8c6df18f98b6fdc35dbf95c40c8309cb8c45a5ad1101b8884f1`。原始备份、日志及三份摘要回执保存在ignored输出，本轮没有改AUX/recipe、执行Git、签名或启动客户端。

新候选仍需普通双人局900p/1000p或更高分辨率实机、原生相机/饰品/加载遮罩、有效30秒FPS、退出/holds/完整恢复等门禁；旧1107及其900p采样不能作为这次尺寸修复的性能验收。
