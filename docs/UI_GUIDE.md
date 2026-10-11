# 当前 UI 接入与文档入口

当前普通菜单采用 V10 紫色外壳。存档、宝物、抽奖、商城、生存商店、每日奖励、VIP，以及兑换和支付确认复用已确认的组件。几何、素材与验证范围见 [V10 菜单交付](../design_refs/menus_v10/DELIVERY.md)，存档原组件说明见 [素材导入](../design_refs/archive_v10/ASSET_IMPORT.md)和[存档数据与交互](../design_refs/archive_v10/Delivery/DATA_AND_INTERACTIONS.md)。旧哥特、月光、青玉窗口和 C19/C25 的尺寸、CSS 与整套恢复点不再是当前菜单的接入依据。

## 实际入口

入口由 [custom_ui_manifest.xml](../panorama/src/layout/custom_game/custom_ui_manifest.xml)及三个活动布局决定：`archive.xml`、`survival_hud.xml`、`payment_test.xml`，均位于 `panorama/src/layout/custom_game/`。公共 V10 实现在 `panorama/src/scripts/custom_game/common/menu_v10.js`、`panorama/src/styles/custom_game/common/menu_v10.css`；存档由 `archive_v10.js`、`archive_v10_data.js` 等适配真实控制器。应沿 XML 的实际 include 顺序检查依赖，不能按历史文件名推断入口。

作者源码位于 `panorama/src/`；运行资源位于 `panorama/layout/`、`panorama/scripts/`、`panorama/styles/`。后缀分别为 `.vxml_c`、`.vjs_c`、`.vcss_c`。资源编译成功后仍需确认新 HUD 执行链已加载，避免把旧闭包和旧截图当成本版效果。

## 素材、编译与验证

批准的原始包保留在 `design_refs/archive_v10/package/archive_ui_final_v1/`，包括 PNG、SVG 编辑稿、布局、资源清单和字体许可。`tools/archive_v10/import.cjs` 逐项校验清单与哈希，再生成源图片、数据脚本和资源预载布局；不能删除原包或拿示例数量替代正式配置。

从项目根目录按需要执行：

```powershell
node tools/archive_v10/import.cjs
& tools/archive_v10/compile.ps1
& tools/menus_v10/compile.ps1
node tools/archive_v10/preview.cjs
node tools/menus_v10/preview.cjs
```

编译范围清单分别位于 `tools/archive_v10/compile_scope.json` 和 `tools/menus_v10/compile_scope.json`，应先审阅再执行。`design_refs/*/work/` 仅保存可重建的预览、截图与报告。编译需要同步到引擎 Content 目录；仅拉取 Game 仓库不会自动更新 Content。保留每次具名备份、源文件与产物哈希，不用旧整套检查点覆盖当前 XML 和其他功能。图标配方的 LF 与编译依赖问题另见 [存档纹理重编译](ARCHIVE_TEXTURE_BUILD.md)。

浏览器预览运行实际 XML、JS、CSS，使用明确标记的隔离状态；其截图、缓存和报告可以重建。原生图标预览首次导出及自动检查命令见 [存档工具说明](../tools/archive_v10/README.md)。浏览器通过、Lua/Node 测试通过、资源编译通过分别记录，均不能替代游戏内鼠标、滚轮、字体、裁切和热重载验收。当前完整实机矩阵的边界以 V10 交付说明为准。

## 保留的业务边界

- 存档的分类、数量、进度、升级、神兵晋升、社交抽取与称号操作继续使用原服务端接口。未知数量、期限和资格不填造默认值；同局共享奖励按[联机奖励规则](COOPERATIVE_REWARD_RULES_20261011.md)结算。
- 生存商店保留真实目录、金币/木材、前置条件、库存、冷却、自动购买和科技队列；商城保留账户币种、原 SKU、价格和权益。悬停与选中不创建交易，只有原明确购买动作提交请求。
- 钱包兑换重试使用原未确认 token；现金订单的 pending 金额与奖励不随目录变化而重算。二维码、可信付款入口和到账凭据沿原支付流程处理。
- 每日奖励、补签、通行证、VIP 的资格、防重和领取状态保持个人隔离。队友权益不用于本人发奖；没有配置的价格和奖励不冒充已经开放。
- 普通菜单关闭与切换尊重现有层栈、pending 和 mandatory 守卫。难度选择、英雄/肉鸽必选、瞄准输入、建筑销毁确认与 TAB 战斗属性层保持各自输入流程；官方返回、设置等入口继续使用原生界面。排行榜没有权威数据时保持未开放。
- 生命周期检查使用所属有效上下文；关闭、删除和重载后取消旧定时器与订阅，迟到响应不得访问已删除面板。底部战斗 HUD、头像与生产队列仍有独立接入规则。

需要修改规则时优先阅读[存档业务契约](archive_data_contract.md)、[抽奖数据契约](lottery_data_contract.md)、[奖池更新](lottery_pool_updates.md)、[存档服务器接入](archive_server_integration.md)、[商城 CSV 说明](payment_shop_csv_guide.md)、[U 币兑换](payments/ucoin_checkout_20261011.md)和[建筑生产队列](BUILDING_PRODUCTION.md)。菜单外观文档不取代支付、奖励或战斗配置。
