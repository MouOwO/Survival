# 生产面板 tooltip 前景层（2026-11-08）

仅本地更新，后台未改。两仓源码、两个官方编译资源及源码/编译DATA回归完成；普通客户端的新版本显示、完整签包和游廊交付仍待。本轮SDK调用0，未关闭当前Tools对局或切换正式安装。正式游廊沿用0104记录，本轮没有重新查询远端。

## 原因与行为

用户截图中的训练提示被生产面板遮住。生产面板的完整文字、取消当前任务、当前任务、排队任务、训练入口五类悬停原先直接DOTAShowTextTooltip，绕过项目的SurvivalTooltipPosition。单独提高原生tooltip自身的z-index无法越过更低的祖先层；共享接口原本已将整条原生祖先路径提高到2100000000，这五类入口未使用它。

production_progress.js统一通过ShowText/HideText显示和隐藏；保留原生锚点、内容、排版和外观。按实际悬停面板持有ownership，旧A的mouseout不关闭新的B；选择切换和Dispose释放本面板的tooltip。没有新增背景复制、重挂父节点或改动hittest。

tooltip_position.js按真实root/host面板身份缓存原生容器，容器销毁或根重建才重新发现。冷容器允许一次即时发现及一次有代际保护的下一帧发现；始终不存在时负缓存，不在后续悬停反复全扫。已知容器不再调度发现回调。相邻来源切换复用层级lease，不先恢复再写回同一z-index；离开时保留其他modal后来取得的层级。已Dispose的旧模块拒绝重新显示。

## 成本与验证

首次发现沿用固定9个已知ID查找及最多512节点的匿名容器后备检查，最多一次下一帧补发现，初始化成本与实际原生树规模N有关。实际HUD的N本轮未采样，不能把模拟规模写成实机规模。稳定悬停只读持有面板和有界祖先链H（上限64），不随N增长；没有全场单位/面板集合查询，也没有新增后台轮询。隐藏/容器重建按实际祖先路径恢复或重建。空间为一个容器引用和最多64项lease，旧模块/延迟回调受代际失效保护。

树外专项脚本`D:/Survival_本地工具/runs/20261108_production_tooltip_front/test_tooltip_front.cjs`，固定game工作目录运行。实际完整生产JS与共享JS联端49项检查通过，覆盖五类入口、先后悬停、过期mouseout、Dispose、原生容器销毁和布局重建。N=10/1000/10000各连续1000次悬停，稳定段场景搜索0、Children读取0、重复样式写0、新调度0；测试中的祖先读取均6000，原生show各1000。没有把这些替身调用计数当作原生耗时/FPS或截图验收。

既有test_native_tooltip_layer.cjs通过，覆盖原生text/title不同类型、祖先lease、懒创建、失效锚点、modal及重载；响应式选择的10组视口/UI缩放回归通过。旧helper在同一专项中因重复查询失败，旧production在同一专项中因绕过共享前景层失败。旧test_production_hud.cjs引用已经移除的ProductionResearchAuto0，在HEAD原源码和当前源码均于115行失败，单独保留，不以修改生产逻辑取绿。

## 来源、编译和登记

源码game/operator `52ffdd29a1664edc3f642ce4d2cad74c9e87217b` / dev；content `534c3c8a2c5ed0871d9d699a7b3dd9a4a7d78bb0` / master，均已推送。两仓按唯一stash→pull→精确pop同步，89份game、2份content原始改动字节核对；一份.txt发生Git换行转换，已从记录的精确stash blob按事前SHA恢复，其他历史stash未动。此前队列显示修改已由其独立任务提交，本轮只提交前景层差异。

官方隔离编译proof：`output/tooltip_foreground_compile_20261108_v01/proof.json`，SHA256 `12c8c680cc22fc57f2d84284e6cc3aa1cccc914d07dc788154c8ffc3888f8d1d`。两个资源的DATA均逐字节等于不可变作者输入；提取编译DATA后同一层级/生产联端测试通过。没有读取主工作区临时字节作为编译来源，临时编译挂载已由原工具核验移除。

| 资源 | 字节 | SHA256 |
| --- | ---: | --- |
| tooltip_position.vjs_c | 21649 | 6095d3c930e98549b9da33ba17643c8c33d4db5ac659c5913c74650b34ec552e |
| production_progress.vjs_c | 61982 | 05cdc30c806dc3522d22652275227db6db24df18393dc56e4808174ab10ea831 |

导入前原编译资源完整保存在树外artifact_backup_before_import，导入后重核上述SHA。实际compile_import_receipt.json和回归日志位于同一树外专项根。

按新规则使用release_storage_ledger.py record登记真实编译proof和实际备份回执：编译记录4854c8cf…、导入前备份e8b2eabd…、已有源码/编译前备份cec57174…，完整JSON/complete摘要均保存在`D:/Survival_清理记录/records`。已有备份的补登记明确为本次观察，不伪造原生成日期。首轮编译登记已成功，读取其中文控制台输出时解码失败；显式UTF-8重读同回执返回ALREADY_RECORDED，没有重编译或覆盖原回执。没有运行全盘refresh、清理或删除产物。

## 全部待发边界

本轮运行变更是上述两个vjs_c，作者源是两仓各两个JS，运行删除0。全量当前双仓待发以树外`pending_inventory.json`记录为准；本轮两资源编译scope不是完整发行计划。历史全部未发布项、其他来源/素材/编译变更、运行删除以及本轮前景层均需以实际已发布签名manifest重新收集，不沿用固定PAYLOADS或旧延期表默默漏发。

当前完整新版未签且缺新普通客户端实机准入，其他工作区修改/未映射或未验证生产转换仍须收口，不能复用0803旧绑定或称已同步游廊。后续须新候选、新原生遮挡/快速切换及必要多人验证，再取得SDK成功和该版本官方完整下载逐文件一致证据。当前对局没有自动退出，后台保持原状。
