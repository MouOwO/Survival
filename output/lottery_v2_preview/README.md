# 地图抽奖 v2 交付

本目录 `index.html` 是可交互的浏览器组件预览。四池截图：`pool-map.png`、`pool-cultivation.png`、`pool-dragon_knight.png`、`pool-summer.png`；功能图标五态对照：`icon-states.png`。截图是浏览器组件运行结果，**不是 Dota 游戏内截图**。持有数量未接玩家快照，预览显示破折号；游戏内读取 owned_count / max_owned。

原生布局已更新为四池页签、左侧滚动奖励网格、右侧所选物品信息与独立长文本滚动区、固定底部规则和确认按钮。切池清空上一池奖励及选择，加载时保留遮罩；首次加载选择当前池首项。关闭后迟到数据不重新打开弹窗。所有信息弹窗均在按钮状态和 draw 入口两处阻止底层抽奖。关闭/确认不发抽取请求。

图标源位于 `panorama/src/images/custom_game/lottery_handoff/icons/`，逐个来自 v2 原 SVG。主界面、结果页、余额、购买、首充、记录、公告、确认/再抽、跳过、关闭和动态页签标记都已替换引用；功能图标没有字体符号或旧图兜底。未删除其他模块可能共用的旧文件。`resource-inventory.json` 列出源文件哈希及编译资源；部署脚本显式编译 icons 下 SVG，覆盖动态路径。

物品名称、属性、品质、成员关系和消耗来自项目 CSV / 游戏公开快照。当前四池均配置 `item_id=*`，所以列表相同是现有配置。各池规则仍分别来自选中池，概率没有公开可靠数据，正式界面不显示概率行。没有把原始服务端权重发送到客户端。代达罗斯的 Dota 纹理资源名为 greater_crit，在抽奖展示适配层映射 item_daedalus → item_greater_crit，不更改奖励 ID、效果或发奖。预览的四张真实物品图片来自 Valve CDN，对应 greater_crit、crimson_guard、ogre_axe、mjollnir；不使用通用占位。

验证命令：

- `node tools/test_lottery_ui.js`：原抽奖回归、层级恢复以及四池、选择、空态、加载、迟到快照、遮罩期间禁止抽奖、关闭。
- `node tools/test_lottery_v2_assets.js`：14 个必需图标的源和编译产物、布局与动态引用、旧符号和旧路径检查。
- `node output/lottery_v2_preview/verify.cjs`：四池截图、真实图像加载、滚动/选择、图标五态对照；在 16/24/32 像素下读取 SVG 光栅化 Alpha 和边缘。低于 16/255 Alpha 的边缘像素不用于黑色判断，避免反预乘的舍入噪声。24/32 像素为正式功能图标范围。

编译日志为 `compile.log`，浏览器验证为 `verification.json`。原生脚本、布局和资源已编译同步到本地测试地图，未发布 Workshop。没有可操控的 Dota 录屏/截图会话，原生点击遮挡与实际渲染边缘仍需游戏内验收，不能用浏览器结果代替。原有思源字体缺失、购买/首充/跨局记录接口缺失保持原状态；未在本次图标更新中编造业务功能。
