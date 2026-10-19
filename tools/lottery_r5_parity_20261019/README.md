# 抽奖 R5 参考与生产界面对照

批准参考是项目中的 `design_refs/lottery_emerald_buttons_20261019/round_5.html`。工具直接打开该文件，记录其 SHA256，并将实际浏览器矩形换算到 `1672 × 941` 逻辑坐标。原参考 HTML、生产源码和编译资源均不会被这些工具修改。

当前正式版本按用户要求保留四个奖池原背景 `custom_game/lottery_cinematic_v1/<pool>.png` 和原过场电影，不启用备用森林背景，移除右侧大 T10 装饰。这些是与历史 R5 原图允许存在的差异。主界面的四张卡是精选预览，完整奖池详情仍由真实控制器提供。

## 运行

在项目根目录执行，需 Node.js、已安装的 Chrome、可用的本机 CDP，以及 Source2Viewer CLI。工具将临时文件和浏览器配置写入 D 盘项目的 `output`；可通过 `SOURCE2VIEWER_CLI` 指定解码程序。

```powershell
node tools/lottery_r5_parity_20261019/reference.cjs --run
node tools/lottery_r5_parity_20261019/verify.cjs --run
```

不带 `--run` 时只显示用法，不开始验收。应在生产修改、编译和相关功能测试完成，且源码稳定后运行 `verify`。验收前后会核对实际源码依赖的哈希，避免把不同版本混在同一份报告中。

`reference` 提取正常、悬停、禁用三种参考状态的矩形、字号、颜色、材质与官方素材来源，并保存原参考场景截图。`verify` 重新组装当前实际 XML / JS / CSS 和 CSV 奖池数据，从安装 VPK 解码本轮使用的官方材质；不把旧 QA 资源清单当作输入。

## 输出与判定

产物位于 `output/lottery_r5_parity_20261019/`：

- `reference_geometry.json`、`reference_stage*.png`：批准参考的逻辑矩形和截图。
- `production/preview/assembly.json`：实际源码依赖、哈希及离线传输说明。
- `report.json`：两种视口、四个奖池、零券保护、悬停、真实回调样例单/十连结果的自动检查。
- `captures/comparison_map_*.png`：参考与生产场景并排图；`result_1.png`、`result_10.png` 是结果页截图。
- `visual_review.json`：人工逐图目检的结论，必须与报告中的同一批源码哈希对应。

几何检查读取实际 `getBoundingClientRect()`，不能用源码中写了某个尺寸代替实测。结果检查还包括可见祖先、卡片不重叠、不溢出、真实奖励身份与确认回调；名称必须以自然宽度在固定且裁剪的名称行内居中，并与奖励图中心轴对齐。主回归另行验证结果和详情继续复用原控制器 Label、重复 Compact 不增节点以及 Dispose 恢复原父节点；零券样例不能发出抽奖请求。

**几何或自动检查 PASS 不等于视觉还原 PASS。** 必须再检查并排图、零券图及单/十连结果，确认材质、层次、文本、透明图标、遮罩和压暗符合要求。修复后应重新运行并更新目检结论，不能沿用旧版本的 PASS。

## 离线与原生边界

浏览器只运行真实生产代码的离线 Panorama 适配，不连接游戏、账号、支付或奖励服务。余额、资格和结果是明确的本地样例；发出的游戏事件只进入内存日志。报告中的 `gameVerified: false` 不能改写为真实游戏验证。

离线传输将实际 `opacityMask` 映射为浏览器 `mask-image`，使用项目 SVG 的相同字节并记录哈希；`opacity` 保持生产值。嵌套 `rgba()` 渐变按括号深度解析，保留原色停，不允许默默丢成透明。悬停后显式同步适配器，将原生 brightness / saturation 属性转换为浏览器滤镜。结果页还会对奖励区外的截图像素做亮度抽样。这些验证传输是否生效，仍不能证明 Source 2 的字体栅格、透明合成、边框画刷和电影解码完全一致。

当前生产针对原生画面偏亮显式补偿压暗：ResultShade opacity 为 `0.995`，SceneWash 左右 alpha 为 `#f7` / `#21`，FloorWash 的下部 alpha 为 `0.94` / `0.999`。底栏采用不透明 `#111f18ff`，避免原奖池的金色圆盘透出；自动检查实际 computed color 为 `rgb(17, 31, 24)` 且 opacity 为 `1`。这些数值有意不与历史 HTML alpha 强行相等，记录在 `nativeCompositingCompensation`；自动检查逐一绑定渐变方向、色停位置与 alpha，并验证原有几何。浏览器的暗底像素通过只能证明离线传输有效，不能用来验收原生 alpha、颜色或最终亮度；原生截图确认后才能报告该外观修复完成。补偿值若再次迭代，需同步本工具预期并重跑同一版本。

**原生验收需要另行获取真实客户端截图**，至少核对四个奖池、真实零券禁用状态、侧栏文字/纹章层级、主区渐变、结果暗底与全屏层次。不能把本目录的浏览器截图标为实机截图。并行任务操作游戏时应等独占时段，防止切页或关闭窗口污染证据。

取得原生主界面、单抽及十连结果截图后，可执行 `node tools/lottery_r5_parity_20261019/native_compare.cjs main <native-main.png> single <native-single.png> ten <native-ten.png>`。工具将 R5 实际参考与原生截图裁切、等比缩放后生成并排图及哈希清单，不改原图；输出状态为 `REQUIRES_VISUAL_REVIEW`，需人工逐图确认才能给出原生视觉结论。
