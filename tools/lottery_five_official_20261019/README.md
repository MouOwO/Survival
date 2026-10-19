# 五套官方抽奖界面

入口：`design_refs/lottery_five_official_20261019/五套官方抽奖界面.html`。单个 HTML 内嵌全部图片，可离线切换五套方案、四个奖池，或查看五套完整画布对比。

五套为冠冕鎏金、幻夜紫金、熔焰赤铜、霜纹银蓝、幽林翡翠。构图沿用现有激战 2 布局的 1672×941 画布：顶部标题和余额、左侧四奖池、右侧主场景、底部奖品与抽取操作。各套分别采用真实的官方背景、按钮、选中片和宝箱原画；抽奖券和奖品沿用当前游戏的统一资源目录。

```powershell
# 需要上一轮官方 UI 图册的原图与 catalog.json；没有时先构建：
node tools/official_ui_catalog_20261019/build.cjs all
node tools/lottery_five_official_20261019/build.cjs
node tools/lottery_five_official_20261019/verify.cjs
```

依赖 Node、安装的 Dota 2、Source2Viewer CLI 和带 Pillow 的 Python。支持 `DOTA_UI_VIEWER`、`DOTA_UI_PYTHON`。`extra_native.cjs` 从安装包解码宝箱原画；`schemes.json` 固定本次挑选的官方目录项，并在构建时校验资源身份。

所有余额、开箱、补券、记录与结果仅存在当前 HTML 的本地演示状态，不调用游戏、网络、支付或档案服务。名字、品质、单抽与十连消耗和保底文案来自当前抽奖 CSV。浏览器渲染是界面评审，不是 Panorama 实机验收；未修改生产界面。

素材来源与 HTML 哈希在图册相邻 `asset_manifest.json`；检查报告及截图位于 `output/lottery_five_official_20261019/qa/`。中间图片与评审产物保持在忽略目录，不提交到 Git。
