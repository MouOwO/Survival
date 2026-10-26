# 联机测试商城目录

该目录提供独立的静态网页商城，公开入口为 `https://pay.xiaofengnet.com/ws4-shop/`。当前只展示商品配置，不提供登录、下单、兑换或付款功能。它不连接支付库，也不向对局发放权益。

`tools/workshop_test/build_public_shop_catalog.py` 调用现有支付与兑换编译器，投影所有启用报价。同一 SKU 的人民币与游戏货币报价以不同 `offer_id` 保留；人民币价格使用分，G币、商城积分、商城金币使用各自整数单位。VIP 条件来自编译结果的 `grants.required_vip_level`。页面不显示推测的余额、持有量或剩余限购次数。

运行 `--web-output <新的输出目录>` 生成五个静态文件与 manifest；`--write --mirror-content` 则生成 game/content 配套的 Panorama 数据源码。默认操作只检查，不写文件。

`deploy_public_shop.py` 默认只做本地部署计划。显式 `--apply` 才通过既有固定 SSH 通道部署独立 Nginx 路由，并核对现有业务服务、代码与发布指针。仅允许正式编译目录及本仓库三份网页源码的精确构建产物。部署校验失败会恢复原 Nginx 配置。失败记录、源码快照、浏览器截图和发布包均不进入 Git。

启用真实支付还需要独立四账号支付服务、Steam 登录身份、冻结报价与支付回调核验，以及对局读取同一云端权益的完整验证；不能通过修改这里的 `checkout_enabled` 字段开启收款。接入状态见 `docs/payment_shop_20261026.md`。
