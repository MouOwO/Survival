# 加入方购买二维码几何修复（2026-10-27）

状态：**VERIFIED_NATIVE_GUEST_SCAN**。修复版09已通过官方完整下载校验。2026-10-28，加入方用手机实测后明确确认“可以识别，商品和金额正确”，本轮二维码目标验收通过；实际付款、到账和权益刷新仍未验收。

用户提供的189×188像素裁图中，左上定位块不同扫描行的宽度为32、33、34像素，垂直跨度35像素，证明几何并非单一等比缩放。行流式布局的宽度舍入或挤压是候选原因；固定画布修复后，加入方手机已能识别。尚未独立测量修复后客户端每个色块的像素边界；原裁图边距不足以判断完整界面的静区，后端配置仍为4模块静区。未解码、输出或发送二维码载荷。

最小修复在 `payment_test.js` 中改用固定白色画布和黑色区段绝对定位，不再依赖行流式布局；付款、身份与原矩阵限制不变。缓存和子节点清理失败时不保留已完成二维码状态。

- 源码SHA256：`2ee90ef3ca2454aa7c5e37af1473d17cc776e5117b99ec69ea764cf1906706dd`；game/content源码一致。
- 实际编译：1份成功、0份失败。编译产物 `panorama/scripts/custom_game/payment_test.vjs_c` 为55854字节，SHA256 `8cca589085ff74459f17cee9cf620a450364eb22b4395b0458a0db4cf72ed566`。
- 语法检查和46项测试通过，其中8项为新增几何检查。分数像素端点检查属于数学模型，不能代替Panorama实机画面或手机扫码。

## 09封包与上传

真实09封包共6658份资源、3767362385字节，只替换 `panorama/scripts/custom_game/payment_test.vjs_c`，180份受保护模块保持原字节。内容摘要 `1262cbe5905d760c6c15400e4051038613c6a78bffb99b64d9d2d5d609d3cf40`；索引摘要 `b09f36be87db6dc3c8f055e06a9c18438236437d0167c7634effba6707b37278`。

封包报告原始SHA256为 `041b7b4fd90500ef15e48e7fa475731455cafbe8da132499d38d6e520004fff8`。实际上传日志已返回 `uploaded=true`、`legal_agreement_required=false`，最终状态为 `SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST`。

2026-10-28 07:05:07（UTC+08）完成09官方完整下载校验，实际manifest为字符串 `3869894305253699960`；6658份签名资源、180份受保护模块、5个VPK及签名核验通过，官方回调为 `3406 / result=1`。08的manifest `976725920376391555` 仍仅作为历史证据。

下载回执：`output/native_arcade_cloud_20261027/download_evidence_v03/20261027T230507Z_68b94b8d9b024315b779eca43305e5e3/verification.json`，原始SHA256为 `15177b4c943afa61619ea8be892b431fa8bbf6c50a4a2a7e480c5bd84d212f45`。下载日志 `native_cloud_v03_official_download_20261028.log` 实际退出码为0，下载器未改写发布日志。

编译与发布证据：`output/native_arcade_cloud_20261027/guest_qr_raster_audit.json`、`qr_fix_source_tests.json`、`qr_fix_compile.log`、`native_cloud_v03_package.json`、`native_cloud_v03_upload.log`。

本轮主机实际观察到原工坊房间2/4，两名玩家为“是无话吖”和“天才琪露诺”；随后同一普通Dota进程35164已进入N1正式游戏并打开商城。加入方手机扫码和商品、金额正确由用户确认，独立回执为 `output/native_cloud_v03_native_20261028/native09_guest_scan_acceptance.json`。本轮进程没有原生日志，未重新核验自动入口执行次数、HTTP计数或逐人云档；这些结果不沿用08数据。代理未创建订单、未操作支付；用户本轮是否创建新订单及订单总数未知。扫码通过不等于实际付款、云端到账或重启权益读回通过。
