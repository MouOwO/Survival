# 城墙旁多余“见习守望”占位塔修复

日期：2026-11-12，Asia/Shanghai。

## 原因与修复

`scripts/vscripts/systems/commerce_runtime.lua` 在玩家拥有 `lottery_orbital_cannon_core`（`orbital`）且城墙已建成时，用普通 `building_arrow_tower` 创建所谓轨道炮展示物。代码随后禁用攻击、设置无敌和相位，却没有走真正箭塔的建造、属性投影、技能和选中目录注册流程。因而原生选中仍可显示“见习守望”、模板攻击20/攻速1.0及空技能栏，与用户截图一致。创建时开启清位还可能把展示物挤到城墙旁。

移除这条占位单位创建路径及其专用缓存、清理和权益签名位。不为此新增实体、粒子、计时器、全场扫描或后台操作。真正箭塔建造入口不变，轨道炮权益及 `M.orbital` 的伤害逻辑原样保留：每波触发、10秒冷却、0.5秒一次/20次、范围1600、英雄三围总和×10物理道具伤害、仅所属玩家合法波次/挑战怪及原减甲。

## 回归与成本

树外测试位置：`D:/Survival_本地工具/tests/game/tools/`。

- `test_wall_orbital_no_placeholder.lua`：四玩家、1000次稳定刷新，创建单位0、建筑集合查询0、无攻击时范围查询0；20次轨道炮回调产生40次合法目标伤害，验证数值、物理/道具路由、减甲、冷却、同波去重、换墙、旧墙死亡回包、城墙销毁、无权益/无英雄及换局失效。
- `test_commerce_resource_lifecycle.lua`：更新原占位塔预期，保留光环、四玩家隔离、英雄/城墙精确归属、权益撤回、重复清理、粒子失败、监听器及旧世界回调回归；补齐独立测试的测试账号门禁隔离。
- `test_commerce_immediate_entitlements.lua`：19项通过；100次相同权益事件不重建光环、不重复查询建筑/英雄，固定权益读取从1400降至1300。
- Lua 5.1语法检查通过。旧HEAD源码运行新定向测试，在原第205行创建占位塔处失败；同测试对修复源码通过。
- 另运行旧综合`test_hero_logical_damage_delivery.lua`，在第179行既有`gear range changed`断言失败；切换回原HEAD的commerce模块也同样失败。该装备范围问题不在本轮修复范围内；轨道炮本身由新的定向用例验证，不能将旧综合测试列为通过。

回执：`D:/Survival_本地工具/runs/wall_orbital_placeholder_20261112/negative_control.log`、`regression.log`。以上是隔离逻辑及调用计数，不是新游廊普通客户端视觉或FPS验收。

复杂度：现有最多4玩家、每秒一次的权益协调仍为O(P)时间/O(P)存储，初始化沿用玩家与事件索引；单玩家权益变化O(1)，相同事件早退。移除每玩家最多一个原生单位及其创建/状态设置/销毁调用，稳定轮询不再检查占位单位。轨道炮原范围查询仍仅在攻击激活后每0.5秒一次，20次后结束；本轮没有增加范围扫描。

## 交付边界

**已同步原封闭游廊条目3824360109，版本2026111204，Steam manifest `6754330934111248152`。** SDK上传成功，官方完整下载验证7061个签名资源、187个保护模块及5个包文件逐一一致；最终工具返回`WORKSHOP_SYNCED`，完整运行/来源待发及阻断均为0。后台未修改/未部署，未消耗玩家道具；新普通客户端建墙视觉及FPS仍待用户开新局验收。父版为2026111202 / manifest `503273922170155206`，不作为新修复验收证据。

双仓已按stash→pull→pop恢复并同步远端检查，game分支dev、content分支master，未覆盖其他窗口原有改动。原Git代理端口失效，本次仅用命令级17789代理成功拉取，没有改写全局代理配置。content没有本轮运行修改，不创建空提交。

前一轮Dota进程21144仍在运行，因此保留待发；用户随后确认“已退出”，进程检查也确认已退出。源码推送首次被自动审核以目标未明确授权拒绝，用户后续明确“允许”推送既有`MouOwO/Survival`的dev及`MouOwO/SurvivalContent`的master并继续原游廊交付后才执行；拒绝的命令未执行。没有强制结束游戏或覆盖运行中正式包。

## 实际发行与证据

- 修复提交`19eea47a2`已推送game/dev；签名运行源绑定game `79b1e5e659778b5028b5d3b52e78149d6f2d44e7`、content `d46453edf80750d0ee0ed25f69b6329c58b00d8a`，两仓对应分支已推送。发行授权另绑定game `88403d4c3`。原有其他窗口的未提交改动及历史stash均保留。
- 正式任务`D:/Survival_本地工具/runs/packaging_jobs/pack_2026111204_8ed07060`，入口仍是专用`tools/release_packager/cli.py`及统一`tools/release_pipeline.py`。新包独立目录`D:/Survival_工坊输出/pack_2026111204_8ed07060`，总3812454334字节；3个运行资源变化，新增/删除均0，包含修复模块及配套生成目录。原始6项待发来源全部审计覆盖，没有排除历史待发。
- 最终生产模块重新运行三组回归通过，`production_1204_regression.log`保存在上述树外回归目录。其SHA256 `2759fe0cdfbe007b07f373ed96894a5c197855a2ab1e749757335d118ae71852`与实际签包视图的`commerce_runtime.lua`完全一致；官方下载随后逐资源核验同一签名包。
- 官方回执：`output/packager/pack_2026111204_8ed07060/download_evidence/20261112T115505Z_84f02ed0f6ee452a9f840da1abfc590a/verification.json`，状态`OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED`。任务内`delivery_status_1.stdout`、`checkpoint_receipt.json`、`delivery_receipt.json`保留完整收口；产物登记返回`RECORDED`，记录`D:/Survival_清理记录/records/ba4c14bbe8f684a431403ad551fc06a9761fa4359fa92a385ed3c528681996ea.json`。
- 1203失败任务完整保留：初始Python314缺少`cryptography`，收集阶段失败；切到现有安全发行venv后，同任务因解释器属于不可变请求而拒绝改写。遵循门禁新建独立1204任务完成交付；1203未上传，没有删除失败回执或通过改写旧请求绕过。最终1204无自动重传，官方核验不创建/提交其他条目。
