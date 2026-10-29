# 存档技能单行布局、独立召唤与奖励确认（2026-10-29）

本次用户实机反馈覆盖上一轮的四列三行排版决定：每座建筑仅一行，按原相对顺序压紧，删除空白与返回技能，不需要技能快捷键。四座建筑及36项挑战、固定属性、出生点位置和原奖励资格保持既有业务规则；灵兽帕鲁继续排除。

## 当前交互约定

- 四楼实际按钮数量依次11／10／9／9，共39项，其中36项怪物挑战、3项无尽／跳关／通天塔控制。没有空白占位或返回按钮；结束本人阶段继续用顶部独立按钮。
- 普通怪物按challenge_id分别管理组和本局次数，可任意次序召唤，普通挑战之间及与已开启无尽不再互相锁住。无尽与塔仍共用同一个波次控制器，不能同时开两套；塔结束仍结束本人阶段，按原视频告知先完成其他挑战。
- 绿茵5只为一个独立组，全部死亡后给一次团队奖励；某一组生成失败只清该组且可重试，不取消其他已存在怪物。重复死亡、结束／超时清理不发重复奖励。
- 服务端只发布内容实际改变的单个技能runtime和单位metadata。前端额外定位到两个刷新器的绑定冲突：topnav按引擎slot，combat_stats按屏幕x→y收集，旧多行时会把行／列顺序交错写到同一按钮；现按真实AbilityN身份绑定。客户端保持节点、图标、背景和布局稳定，不因一次召唤重置整条技能栏。隐藏并取消存档技能的键盘绑定，普通单位选中后恢复原有快捷键行为。
- 技能说明把`<br>`和字面换行转为真正换行，只使用支持的字体颜色标签表达品质；获取碎片／材料的提示也按现有品质颜色显示，不能把颜色标签当普通文本印出来。
- 发奖由现有服务端死亡事件→合作奖励意图→可信reducer→原子保存执行；成功提示只跟随最终持久化ACK，列出实际被接受的物品及数量。资格不足／日满／集满仍按真实结果解释，不显示假奖励。首次响应丢失后恢复的重复回执可提示一次，重复callback不重放提示或发奖。

## 验证与发行边界

本地业务回归覆盖36项同时存在、40只实体按任意次序死亡、两个账号72次真实reducer结算，以及独立runtime写入、组生成失败回滚、累计100／101抽与每日额度。该40实体测试替换的是原生单位和持久化边界，并非40只怪原生同帧寻位验收。

真实factory每次独立创建／注册单位；普通模式有原生clear-space，丰饶／极寒／天灾执行mode_spawn_service放置和最多4次落点／路径复验。极度拥挤时真实出生近域可能不足；本次安全失败并只回滚受影响组，不取消其他挑战。仍需新局观察原生布局、悬停和多人同时召唤。

原远端challenge调用`archive_commit`只保存archive／stats，Python首次响应临时附带response，数据库done重试会失去奖励明细。新增`archive_commit_challenge`将真实response与奖励同事务保存，resume返回原值；沿旧锁序、revision校验和旧RPC，不写content_inventory，不补历史null回执、不重抽。`dbtool`备份白名单、hardening和外置PG transport的严格RPC签名必须配套增量，不能只加SQL授权导致旧transport整体准入拒绝。

真实隔离PostgreSQL测试使用PGlite 0.5.13／PG18.6、24份实际历史／增量SQL及pgcrypto。验证prepare→commit→resume原明细、重复回执不增revision／物品、旧null不可补写、revision冲突、无关库存不变；故意在写response时抛异常后，archive／stats／revision／done全部回滚。还实际以goufayu_app重放RPC且拒绝直接UPDATE，以anon拒绝调用。测试数据和探针trigger全事务ROLLBACK，0生产连接。证据`output/archive_layout_20261029/pglite/result.json`；可执行入口`tools/test_archive_challenge_receipts_pglite.cjs`。这是嵌入PG18兼容验收，不是生产PG17、多连接并发或真实玩家到账；部署工具的PG17硬限制未放宽。

发行须同批审阅并部署：新增target迁移与harden补丁、外部transport overlay、Python service、精确不可变bundle，以及对应游戏端hash。先离线准备新backend并排空旧进程，再应用SQL／最终hardening，切换配套service和transport后启动并检查ready。新SQL权限与旧transport不能单独热更：旧transport会拒绝额外RPC权限；仅回滚service也必须保留匹配当前数据库的transport白名单。活动bundle和游廊冻结包未因这些本地测试自动更新。

最终回归通过24个Lua程序、65项Python契约测试、10个Panorama程序及配置一致性检查。8份JS与2份XML已逐项CAS同步到content并由官方工具编译，源码／content／编译产物SHA核对通过；本地化仅替换84个受管token，保留其他601个token。完整摘要见[验证清单](../validation/20261029/archive_layout_independent.json)。

候选不可变bundle为`d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488`，34份源码与54份CSV哈希逐项匹配当前代码，含36挑战／3控制／360属性行。候选位于`output/archive_layout_20261029/bundle_candidate`；活动hash仍为`47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e`，未部署。双仓遵循stash→pull→pop→commit→push，game原有303项改动逐字节保留，不混入本次提交；提交编号由Git日志与交付报告记录。新局原生UI、拥挤区域实机寻位和真实云端到账仍需验收。
