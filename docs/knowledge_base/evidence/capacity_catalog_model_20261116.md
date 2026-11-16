# 2026-11-16 目录轮询压测模型审计与显式候选

仅修改测试工具，游戏与后台运行源码均不改。当前及已排队原实验保持原版本，以维持对照。默认baseline继续严格停用，retain-v1需显式选择。

固定dc9ada2a源证明：真实lottery_http_service在目录轮询失败后保留catalog，原30秒调度继续；CompactRooms.tick原先会将room.error永久置真，使同组4个演员随后被隔离。原始HTTP故障是真实存在的，但隔离人数是模型后果，不能直接当成真实玩家丢档人数。启动、完整性错误和未知写入另行处理。

显式候选只对已有成功校验目录后的三类周期性只读故障保留：http_0:error_unavailable、http_503:frontend_busy、http_503:backend_busy。启动无有效目录、配置摘要变化、来源/身份/解码错误、BaseException取消及其他异常仍走旧失败路径。按原30秒时序安排下一次，不增加即时HTTP、SQL或定时器。普通读档、奖励补读和所有写入异常隔离均保持。

52项回归通过，包括12项模式边界、错误原计数、无补发洪峰、启动不绕过、协议完整性拒绝、所有者换人和混合模式拒绝。compact_client旧结构及失败计数不改，旧零错误门禁仍能失败，保留行为只单列附加报告。没有原生大规模通过结论。

初始化每次加入O(1)，空闲0，稳定轮询成本不变，失败保留O(1)并只增加固定计数，汇总O(1)。原离开时最多扫描4个成员选新代表；不遍历所有玩家或场景。

证据在树外capacity_parallel_wire_20261116_01/catalog_model_audit_01、catalog_model_implementation_receipt.json、catalog_model_regression_01.log。未改写之前未通过的结果，后续若启用必须作为不同负载模型明确比较。
