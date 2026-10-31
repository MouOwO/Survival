# 孤城逐晓／Survival 统一知识库

最新城墙攻击修复：[2026-10-31 两处原生根因、四开放模式自然攻击验收与3101发行](evidence/wall_attack_hotfix_20261031.md)。

最新商城恢复：[2026-10-31 四人WS4合同版本对齐、备份与验收边界](evidence/shop_catalog_sync_20261031.md)。

最新性能规则与修复：[2026-10-31 开局移动卡顿、每日提示及复杂度](evidence/movement_daily_hint_20261031.md)。

最新登录恢复：[2026-10-31 Steam验签中转恢复](evidence/login_relay_recovery_20261031.public.json)。

最新头像对照：[2026-10-30 锋刃宗师头饰、皮肤与镜头](evidence/blademaster_portrait_match_20261030.md)。

最新决定：[2026-10-30 移除新手引导](evidence/onboarding_removed_20261030.md)。

最新专题：[2026-10-30 怪物动态头像、原版镜头与饰品实机修复](evidence/monster_portraits_20261030.md)。

快照日期：2026-10-29，Asia/Shanghai。目标是保留可复用的项目知识，减少新会话重复阅读旧聊天。先读 [00_START_HERE.md](00_START_HERE.md)，再按模块检索；不必每次把全部资料塞进上下文。

| 分类 | 内容 |
| --- | --- |
| [01 架构与协作](01_architecture_and_workflow.md) | 双仓、权威边界、配置生成、任务协作 |
| [02 核心玩法](02_core_gameplay.md) | 模式、难度、经济、建筑、英雄、装备、波次 |
| [03 成长与存档](03_progression_save_contract.md) | 永久档、纯净投影、每日上限、月卡、幂等与并发 |
| [04 联机认证](04_network_auth_official.md) | 原生多人、换图、Steam网页登录、HTTP、连接助手 |
| [05 支付发奖](05_payments_commerce_delivery.md) | 商品、订单、二维码、验签、到账、刷新与证据边界 |
| [06 构建发行](06_build_release_ops.md) | 冻结包、签名、分卷、地图编译、工坊与下载证明 |
| [07 决策事故待办](07_decisions_incidents_pending.md) | 用户决定、已废止假设、异常、下一步与风险 |
| [08 新项目复用](08_new_project_reuse.md) | 可迁移契约、必须替换的配置、独立测试方法 |
| [09 会话摘要](09_session_digest.md) | 本次长会话的需求演进和最终结论 |
| [10 引擎契约](10_runtime_engine_contracts.md) | 生命周期、事件、实体、原生API、名单屏障 |
| [11 完成工作目录](11_completed_work_catalog.md) | 全部可达Git提交索引、当前完成/待验矩阵 |
| [12 会话归档与恢复](12_sessions_archive_and_recovery.md) | C盘实测、session用途、归档/删除/恢复边界 |
| [13 美术/UI与测试索引](13_art_ui_qa.md) | 保留业务交互契约，精简像素和临时排版历史 |

机器入口：`data/context.json`；Git工作目录：`data/completed_work_index.json`；源码路径目录：`data/repository_files.json`；来源与摘要：`data/source_manifest.json`；会话空间统计：`data/session_inventory_summary.json`。`evidence/` 存筛选过的发布证明；`history/20261024/` 保留旧知识快照内容供追溯，不能当成当前状态。

覆盖范围是10/24知识包、本次可见长会话、当前两仓代码/配置、已提交文档与发行证明，并索引两仓当前主分支所有可达提交。提交说明代表代码工作已记录，不等于功能实机验收。尚未落盘、不可访问或其它聊天未展示的细节不能保证全部捕获；待确认项明确保留，不能写成完成。

库内是UTF-8 Markdown/JSON/TXT，MD5和SHA256是校验摘要而非文档格式；优先核对SHA256。在知识库目录运行 `python tools/verify_knowledge.py`，或在game仓库根运行 `python docs/knowledge_base/tools/verify_knowledge.py`，可只读验证知识库完整性。正式游戏发行的Ed25519签名策略不因本知识库改变。

原始会话、认证文件、支付证书、访问令牌和玩家完整数据不放入此库或Git。删除聊天不会让这些文档自动丢失；原文恢复仍依赖独立会话记录。归档不自动腾出C盘空间，详细说明见12。
