本轮只读组件预览工具。须等待生产源与统一表冻结后运行。

```powershell
node tools/vip_bundle_icons_20261017/preview.cjs --expected-hash <item_resources.json的SHA256> --native-aliases <导出PNG的manifest.json>
node tools/vip_bundle_icons_20261017/capture.cjs
```

原生贴图 manifest 支持 `aliases: { "s2r://…vtex": "本地PNG路径" }`，或 `records/rows: [{uri, export_png}]`。

预览从正式 XML / JS / CSS 快照加载，商品与权益来自正式配置；持有数量、余额、VIP 等级为隔离样例，不连接游戏或账号，不创建订单。不替代游戏内验收。

最终截图及 source hash 报告位于 `design_refs/vip_bundle_icons_20261017`。
