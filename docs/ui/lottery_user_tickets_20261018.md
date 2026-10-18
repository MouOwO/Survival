# 用户票券原图接入（2026-10-18）

普通抽奖券使用用户提供的银色（silver）原图，特殊抽奖券使用金色（gold）原图。
两张图分别保存为 `lottery_ticket_user_v1/normal.png` 与 `special.png`。
`art/ui/sources/custom_game` 保留来源，`panorama/src/images/custom_game` 保存编译依赖。

两处 PNG 均与桌面原文件逐字节一致：1536×1024、8bit RGBA。
没有重绘、裁切、烘焙文字或覆盖原图透明通道。
普通原图 SHA256：`b7b9e059ad52bae51af4b5ca1a5924fb2089f3f0ea99510b10560a2045743d45`。
特殊原图 SHA256：`11c0551a0f0ef5dfe52fcd95388f45bf2d7cc9f876db0b5c01cf807c3082e10b`。

唯一资源权威仍是 `data/ui/item_resources.json`；仅更新三个现有身份：

- `lottery_ticket`：普通图，无 aliases。
- `commerce_p001`：特殊图；aliases 为 `P001`、`special_lottery_ticket`、`video_p001`。
- `pay_special_lottery_ticket_single`：同一特殊图；alias 为 `special_lottery_ticket_single`。

三个身份均使用 `fit:contain`；原有名称及协议身份保持原样。

资源生成器同步 Panorama JS 和 Lua；商城商品、详情及共享奖励图自动复用该表。
抽奖页余额、单抽、十连和旧 handoff 控件按奖池券内容 ID 解析相同资源。
券图使用等比 contain，清除旧 tint/wash-color 与 silhouette opacity-mask。
奖励预览及 tooltip 尊重共享 FillIcon 的 contain；缺少共享助手时保留原 cover 回退。

Source2 将纹理限制为最大边 512，生成 512×341 的等比取整纹理。
原 PNG 不变；编译配方使用带透明通道的 BGRA8888，已检查透明像素存在。
候选与完整工作区编译均通过：各 2 张纹理、3 个脚本，无额外资源编译。
`post_compile_validation.json` 确认编译时完整运行资源与源码一致，并保留独立候选快照。

`node --test tools/tests/lottery_user_ticket_icons.test.cjs tools/tests/lottery_ticket_rules.test.cjs`：5/5 通过。
覆盖切池绑定、特殊券别名、无旧遮罩染色、共享 contain、缺表回退及既有券规则；两个 JS 语法检查通过。
不修改券数量、解锁条件、抽奖规则、商品价格、支付流程、奖励或服务端接口。
本次未启动 Dota 2；已核对两种奖池及商城离线预览，尚未实机验证。
`output/lottery_user_tickets_20261018/` 内提供 sizes.png、lottery_map.png、lottery_dragon_knight.png。
浏览器使用原始 PNG；旧 Source2Viewer 无法解码新 RED2，因此不将离线图声明为编译纹理或实机截图。
两奖池各三处背景图均通过真实加载、非零尺寸及无遮罩检查。商城两个 SKU 券图加载通过；无关原生货币图未镜像。
机器验证记录见 `validation/20261018/lottery_user_tickets.json`。
