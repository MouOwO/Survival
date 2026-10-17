# 前端统一资源接入

正式资源源文件与生成器由根任务维护。这里仅包含正式 UI 消费者的验证代码。

- common/commerce_components 的 ProductIcon 只通过 SurvivalItemResources.Resolve 按稳定身份解析，不再包含 SKU 图片映射，也不允许已登记商品的服务器 icon 字段覆盖正式表。
- reward_presentation 的 CreateRegisteredIcon 是已登记物品的共同控件工厂，保留 hero 控件、VIP 徽标以及普通图片类型。未知项目仍使用原有回退。
- 共享奖励、旧 ItemArt、存档图标、最终存档装饰、收藏、宝物及背包 Tooltip 均优先同一资源表。抽奖装饰不再把注册资源覆盖回旧表。
- 存档、主 HUD、独立支付和独立肉鸽窗口均在消费者之前加载注册表。
- 存档卡片保留原按钮及行为，数量变化继续复用已存在的图标控件；静态称号解析表资源，特殊分层动态称号保留原有渲染组件。

运行只读面板消费者验证：

    node tools/item_resources_20261016/ui/validate_consumers.cjs

验证读取正式商城和现金商品目录，用真实生产组件测试所有商品行、详情卡及共享图标工厂；面板与账户交互完全隔离，不创建订单、不调用存档写接口。输出位于 design_refs/item_resources_20261016/ui_consumer_validation.json。

完整离线组装截图、原生编译与多窗口验证由相邻 build 目录工具负责。离线组装截图不能替代游戏内验证。

本次修改前的 UI 原文保存在 design_refs/item_resources_20261016/baseline_ui；目录还包括上轮已完成的 VIP 改动，恢复时不能使用 Git HEAD 覆盖共享工作区。
