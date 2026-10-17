本轮图标维护范围为统一资源表 `data/ui/item_resources.json` 中的 24 个星悦等级、12 个 VIP 等级特权礼包、10 枚现有 VIP 勋章，以及主任务另行指定的 4 个普通礼包。没有新增 VIP 权益、奖励或充值等级。原有 10 个付费专属礼包的图片保留。

星悦每三个等级使用一枚 Dota 2 原生段位徽章，叠加 1/2/3 颗原生星星；从 rank1 到 rank8。VIP 特权使用 12 种原生宝箱，勋章使用现有段位徽章逐级递进。小 LV/V 等级牌放在图标内侧，兼容存档的圆框与商城的方框。

`tier_badge` 是统一图片渲染的一种表现类型。主图与星星都通过原生 VPK URI 加载；只有小等级牌由 Panorama 原生文本绘制。不生成 46 张重复位图，不改变任何奖励配置或持有记录。

验证流程：

```powershell
node tools/archive_reward_icons_20261017/native_assets.cjs
node tools/archive_reward_icons_20261017/test_icons.cjs
node tools/archive_reward_icons_20261017/preview.cjs
node tools/archive_reward_icons_20261017/capture.cjs
```

`native_assets.cjs` 从本机 Dota VPK 精确检查并导出候选材质，仅供预览。`test_icons.cjs` 检查真实资源存在、等级唯一性、图层尺寸及实际 VIP 控制器三组切换；`preview.cjs` 从正式 XML/JS/CSS 和配置生成隔离组件预览；`capture.cjs` 检查存档星悦、存档商城道具、VIP 窗口以及商城礼包页的实际生产组件。浏览器网络全部屏蔽，不连接游戏、账号、抽奖或支付，不是游戏原生渲染截图。

`update_resources.cjs` 是本轮的精确 46 行视觉映射导入工具。未来日常维护应直接编辑统一资源表并运行 `tools/build_item_resources.py`，避免重新导入历史映射覆盖后续美术调整。

后续并行任务已将 VIP 弹窗改成被动 HUD 状态。`screens/vip_privileges_12.png` 和 `screens/vip_medals_10.png` 是该独立改动前的历史组件快照，不代表当前入口；存档中的 46 个等级图标和共享图片工厂仍适用。测试自动识别当前 VIP API，弹窗存在时验证图片接入，已退役时验证只读等级状态及旧入口无法重新打开弹窗。不要为了重新截取旧图恢复已退役的生产界面。
