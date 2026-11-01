# 2026-11-01 原游廊展示封面更新

用户指定聊天中的“我在刀塔2苟发育”图片，并给出Pictures目录。已在该目录找到并视觉核对“苟发育.png”，原图1672×941、RGB、2722916字节。不是按截图重新生成的图，也没有修改插画或字样。

## 素材与发布结果

- 原图完整复制为`publishing/workshop/gou_fayu_cover_master.png`，SHA256 `7d4bbd0865782c8469b964b75a9c299b8f150d95ac59246511e3c49b65b8c351`。
- 上传版`gou_fayu_workshop.jpg`仅转换编码，仍为1672×941，JPEG质量94、4:4:4，936610字节；SHA256 `00714bb69b9c400231f88112673b2fd881d50680a0a76ab63a1792256b679aa1`。
- 原条目`3824360109`的官方SubmitItemUpdate回调EResult=1。fresh UGC查询取得新primary preview，下载官方CDN图片的大小及SHA256与上传版完全一致，状态`PREVIEW_VERIFIED_CDN`。新图为[Steam官方CDN原图](https://images.steamusercontent.com/ugc/14913131426160410278/2CBCF2EB49661EE459A235D9CC42F8E6956941E3/)。
- 原412015字节封面下载备份SHA256 `571cc75655cfa3db9cb6c05aca61d9522d65ee98ed827768f257b8d897d188fa`；本机备份位于`tmp/workshop_cover_20261101/previous_preview.jpg`，仓库旧素材也保留。
- canonical `publishing/workshop/test_listing.json`仅更新`cover/cover_master`、对应哈希、大小和宽高七个字段，未来发布沿用新图。历史发布JSON不回写。

本次只调用`SetItemPreview`这个变更setter，没有调用SetItemContent或上传游戏VPK。更新前后条目身份、应用、所有者、可见性、内容文件/大小、总内容大小、标题说明摘要、标签和developer metadata摘要均相同，总内容仍3788092110字节。封面图片上的文案不构成修改条目标题的授权，工具没有更改标题。本次不代表14文件候选或新增准入包已发布。

## 工具与验证

`tools/workshop_cover/update_preview.py`复用项目已固定版本/哈希及账号校验的官方Steam SDK封装，独立图片操作不走完整包发布器。默认只读；`--inspect`取得新鲜详情；`--apply`持有现有发布互斥锁，并在Submit前写独立pending回执；已有pending或已提交回执均停止，禁止不明结果自动重传；`--verify`重新查询/下载，禁止把旧CDN图当成功。原游戏包发布恢复日志只读，图片日志位于`output/workshop_cover_20261101/preview_state.json`。

八项隔离测试通过：只调用图片setter、提交前pending持久化、超时不重传、成功不重复提交、非预期元数据变化保留并报错、可见性错误在修改前拒绝、真实图片尺寸/大小/SHA固定、官方CDN精确字节/错误图片/错误域名检查。准备阶段使用独立图像环境解码验证，SDK运行环境无需安装新依赖。game/content的原图、JPEG及素材JSON逐字节一致。

复杂度：一次性离线素材编码按像素数O(P)，固定少数JPEG质量档位；不进入游戏热路径。一次发布操作仅处理一个固定条目和一个小于1MB图片，详情缓冲固定9784字节、metadata上限64KiB、CDN下载上限1000001字节，额外空间有界。官方异步等待沿用固定0.1秒回调泵/时间上限；没有新增游戏帧循环、场景遍历、网络轮询或后台守护。这些是操作工具边界，不是原生FPS证据。

实际官方查询/上传/CDN下载均完成；尚未在普通Dota游廊列表采样每一处缓存缩略图，不宣称客户端缩略图缓存已立即刷新。完整脱敏摘要见[机器回执](../validation/20261101/workshop_cover.json)，本机详细日志位于`tmp/workshop_cover_20261101/`。不记录用户凭据或raw session。
