# 商城 UI 与模拟流程完成

当前测试构建：b55c534252，部署目标 survival_ui_handoff_v1。正式商城支付适配器未接通，也没有修改。

## 实现与复用

- 左上新增独立商城入口，保留宝物入口。购物袋使用原生线框控件，避免新增贴图热加载留空。
- 使用项目 shop_categories.csv 的五个分类与独立礼包分类；每类8件模拟商品，礼包4个，保持2×2布局。
- 复用 RemainingHandoff.Window/SizeWindow/Tab/Action/Image、SurvivalUI.ModalShell/ProductCard/PriceLabel/State，以及已有字体、层级和遮罩关闭方式。
- 名称、图标、价格、币种、正常/已拥有/售罄状态；悬停显示黑色介绍层和购买按钮。商品与效果均为模拟，不代表正式规则。
- 数量与金额同步，模拟微信/支付宝切换；重复确认仅生成一个本地订单。
- 本地二维码编码 UI_PREVIEW_ONLY；264×264原图，四模块完整白色留边，保持正方形显示。
- 加载、等待、二维码失败、过期、模拟成功、模拟失败均有独立开发预览按钮。模拟成功只改变UI。
- 返回商城保留当前分类与现有列表实例；关闭清理订单与计时器，重新打开从新订单开始。无网络调用、服务端事件、扣款、发奖或外链。

## 修改文件与数据替换位置

- art/ui/development/shop_preview_v1/prepare.py：读取现有分类、打包模拟目录与本地二维码。vendor/内qrcode仅供离线构建。
- catalog.json：集中模拟商品、礼包、价格和状态；未来以正式目录响应替换。
- data.js：独立本地数据提供者，包含catalog、methods、qr和createOrder；未来在这里接入经确认的接口适配层。异步接口需通过其完成回调推动展示，不能沿用本地确认即生成订单的模拟语义。
- view.js：商城、订单、二维码渲染及生命周期；PreviewState仅供开发预览，正式接入时应移除/关闭手动结果控制，由验证过的订单响应驱动。
- style.css：商城专属补充样式，不覆盖其他页面。
- panorama/src/images/custom_game/shop_preview_v1/：本地测试二维码、购物袋SVG/PNG参考。
- art/ui/development/remaining_ui_handoff_v1/prepare.cjs：组合预览脚本/样式、新入口和资源依赖。顺带修正上一轮空白肉鸽卡底未加入编译依赖的问题，未改肉鸽布局或逻辑。
- test.cjs：模拟行为检查；record.ps1：实际客户端鼠标操作与录屏。

旧commerce.js/commerce.css仍保留。本轮版本通过独立预览脚本接管测试入口；before/和remaining_ui_handoff_v1/backups/保存修改前版本。

## 实际验收

在1768×992 Dota测试客户端完成：六分类切换、正常/拥有/售罄卡片、悬停、四礼包、数量变化、付款方式、订单确认、付款码、六种模拟状态、返回、关闭、切换不同商品、重新打开。

[截图索引](evidence/index.html)、[51秒实际操作录像](evidence/final.avi) 与 evidence/final_*.png 对应最终b55c534252构建的真实画面；没有合成页面冒充运行结果。[商城入口](evidence/entry_icon.png)已补拍确认。

运行行为测试通过：金额更新、重复提交拦截、全部状态、取消计时器、关闭重开与数据清空；源码检查无HTTP/服务器事件调用。资源编译全部0失败。二维码四边留白检查通过。

限制：未验证第二分辨率；未扫描物理手机（二维码生成内容固定可检查）；自然180秒到期使用同一过期分支，游戏中通过预览开关验收，未等满180秒。没有真实支付接口，这是本轮预期而非阻塞。部分早期art/ui/development/remaining_ui_handoff_v1/evidence/shop_*试拍受窗口关闭影响，不作为最终验收图。

后续验收请重点看：购物袋入口、商品密度与长名称、礼包4格、二维码留边、状态文案。真实数据接入须另行确认接口、鉴权、支付协议与可信订单结果。

