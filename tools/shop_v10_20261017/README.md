# 商城 V10 分层接入

现有商城继续使用 `commerce_remaining_5d5c1152eb.js` 的商品、钱包、分类、分页和购买流程，`black_lion_market.js` 负责 V10 展示。服务器协议和价格配置未改动。

## 文件与职责

- `panorama/src/images/custom_game/shop_v10_v1/`：素材包中的 48 张独立图层，保留原始 PNG 字节和透明通道。底板、标题带、页签、行带、按钮、边框和图标分别渲染。
- 同目录的 48 个 `<id>_v10.vtex` 配方保持原始非正方尺寸，使用 BGRA8888、NO_LOD 和单 mip；运行时通过显式 `s2r://panorama/images/custom_game/shop_v10_v1/<id>_v10.vtex` 加载，避免 PNG 弱引用自动生成 DXT5。
- `panorama/src/scripts/custom_game/shop_v10_assets.js`：由 manifest/坐标表生成的尺寸和路径模块，在商城脚本之前载入。
- `data/ui/shop_v10_layers.json`：素材来源、坐标、PNG 尺寸、透明度和 SHA-256 清单。
- `panorama/src/scripts/custom_game/black_lion_market.js`：原生 Image / Label / Button 组装，以及原商城回调绑定。
- `panorama/src/styles/custom_game/black_lion_market.css`：文字、控件状态、滚动与缩放布局。
- `panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js`：商品列表宽度使用皮肤提供的尺寸，并提供检查信息。
- `panorama/src/layout/custom_game/survival_hud.xml`：引入 V10 素材模块。
- `tools/tests/shop_v10_assets.test.cjs`：检查分层素材、动态文本与数据刷新。现有 `shop_purchase_filter.test.cjs` 检查筛选、购买路径及生命周期。

## 布局和数据

参考画布为 1477×1065，商城局部区域为 1380×974，原点为 (47,54)。运行时按可用宽度的 94% 和高度的 90% 取较小比例，整体等比缩放并居中。列表可见约 7 行，保留滚动和每页 40 条的原分页逻辑。

五类导航为首页、礼包、促销、VIP、全部商品；显示类型保留全部、积分兑换、U 币购买、金币购买四项。商品区仅保留物品、价格和操作，删除类型、购买渠道列，名称列使用释放出的宽度。

名称、价格、余额、拥有数量、VIP 条件、页签名称、分页和按钮文字均为真实 Label，随原数据刷新。栅格文字 PNG、game_context、reference、PSD、HTML 和整张效果图均不导入运行资源。坐标模块中的栅格文字只保留定位参考，禁止作为图像渲染。

原素材底脚及外框末尾的 5 像素包含截图残边，控件通过裁切这一区域排除；素材原文件保持不变。外框中间的透明区保留透明通道，下面始终有不透明底板。

## 检查与编译

默认素材位置为 `C:/Users/Administrator/Downloads/商城V10_分层PSD与组件素材包/shop_v10_layered`，也可通过 `--source` 指定。

```powershell
python -X utf8 tools/shop_v10_20261017/import_assets.py --check
node --test tools/tests/shop_v10_assets.test.cjs tools/tests/shop_purchase_filter.test.cjs
python -X utf8 tools/shop_v10_20261017/compile_assets.py
python -X utf8 tools/shop_v10_20261017/compile_assets.py --apply
./tools/shop_v10_20261017/compile_panorama.ps1 -CheckOnly
./tools/shop_v10_20261017/compile_panorama.ps1
python -X utf8 tools/shop_v10_20261017/compile_assets.py --audit-only
```

`import_assets.py --apply` 可从用户提供的原素材重新生成图层与坐标模块。编译工具仅更新列出的商城资源，备份原 Content 和运行产物，出现编译错误时恢复；运行记录位于忽略目录 `output/shop_v10_20261017/`。不要使用整库编译替代局部编译，也不要把该目录的缓存、参考整图或本机输出加入提交。

先运行纹理编译 `compile_assets.py --apply`，再编译 JS/CSS/XML，最后用 `--audit-only` 复查 48 张原生纹理。审计逐字节比较 BGRA 像素和透明通道，同时检查原始宽高、单 mip 和 NO_LOD；PNG 原文件始终不重新编码。纹理工具未带 `--apply` 时只检查源文件与配方，`--audit-only` 只读取现有运行产物。

离线预览仅用于检查排版，不代表原生客户端验证。实机验证不执行真实购买或支付。

## 本次验收

隔离候选源码通过 38 项检查，覆盖分层组装、动态文本、四项筛选、原支付回调、增量刷新和 tooltip；图标检查覆盖 137 件商品、49 个支付图标及 89 个原抽奖资源。48 张原生纹理的尺寸、像素和透明通道审计全部通过。

实机在现有 survival 局内以 1600×900 验证。已根据原生截图修正页签/按钮文字对齐、价格行高，以及 PNG 自动压缩资源与旧纹理缓存冲突导致的按钮白块。其他分辨率使用离线预览检查，不宣称已逐一实机测试。真实购买、扣款和支付未执行。

最终首页截图已确认上述修正。随后客户端再次重建 HUD 并删除了旧弹窗，最终版 VIP 页、筛选弹层、逐项分类导航、滚动和关开未完成实机复核，不将修复前截图计作最终通过；对应数据绑定、筛选、VIP 与购买回调由隔离候选测试覆盖。

本机截图和验收记录分别保存在 `design_refs/menus_v10/work/native/`、`output/shop_v10_20261017/`，它们是运行输出，不加入本次代码提交。
