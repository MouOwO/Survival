# 加入方购买二维码几何修复（2026-10-27）

状态：**FIX_UPLOADED_PENDING_RESTART_OFFICIAL_DOWNLOAD_AND_GUEST_SCAN**。历史08双人登录和云档已通过，用户另报加入方二维码错位；最小修复已真实封包上传为09，官方下载、原生加入方画面复测及手机扫码均为 `NOT_RUN`，支付和到账不能标记PASS。

用户提供的189×188像素裁图中，左上定位块不同扫描行的宽度为32、33、34像素，垂直跨度35像素，证明几何并非单一等比缩放。行流式布局的宽度舍入或挤压是候选原因，仍需原生几何复核；裁图边距不足以判断完整界面的静区，后端配置仍为4模块静区。未解码、输出或发送二维码载荷。

最小修复在 `payment_test.js` 中改用固定白色画布和黑色区段绝对定位，不再依赖行流式布局；付款、身份与原矩阵限制不变。缓存和子节点清理失败时不保留已完成二维码状态。

- 源码SHA256：`2ee90ef3ca2454aa7c5e37af1473d17cc776e5117b99ec69ea764cf1906706dd`；game/content源码一致。
- 实际编译：1份成功、0份失败。编译产物 `panorama/scripts/custom_game/payment_test.vjs_c` 为55854字节，SHA256 `8cca589085ff74459f17cee9cf620a450364eb22b4395b0458a0db4cf72ed566`。
- 语法检查和46项测试通过，其中8项为新增几何检查。分数像素端点检查属于数学模型，不能代替Panorama实机画面或手机扫码。

## 09封包与上传

真实09封包共6658份资源、3767362385字节，只替换 `panorama/scripts/custom_game/payment_test.vjs_c`，180份受保护模块保持原字节。内容摘要 `1262cbe5905d760c6c15400e4051038613c6a78bffb99b64d9d2d5d609d3cf40`；索引摘要 `b09f36be87db6dc3c8f055e06a9c18438236437d0167c7634effba6707b37278`。

封包报告原始SHA256为 `041b7b4fd90500ef15e48e7fa475731455cafbe8da132499d38d6e520004fff8`。实际上传日志已返回 `uploaded=true`、`legal_agreement_required=false`，最终状态为 `SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST`。

记录时主机仍在暂停的N1旧08对局，等待退出与重启；不能把该对局或08的manifest `976725920376391555` 记为09验证结果。09尚无经官方下载核验的manifest，代理未进行手机付款。

证据：`output/native_arcade_cloud_20261027/guest_qr_raster_audit.json`、`qr_fix_source_tests.json`、`qr_fix_compile.log`、`native_cloud_v03_package.json`、`native_cloud_v03_upload.log`。修复上传不等于加入方二维码、手机扫码或到账验收完成。
