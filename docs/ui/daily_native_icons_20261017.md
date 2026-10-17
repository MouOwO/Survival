# 签到奖励原生图标

签到普通奖励和月卡奖励共 12 个资源改用当前安装的 Dota 2 原生物品画稿。图标按实际奖励效果选择；商品、存档和签到仍共用 `data/ui/item_resources.json`，没有增加界面私有映射。

| 奖励 | 原生物品 | 选择依据 |
| --- | --- | --- |
| 成长宝石 | lesser_crit | 英雄攻击成长 |
| 回血碎片 | ring_of_health | 城墙生命回复 |
| 攻击宝石 | ultimate_orb | 实际效果为英雄每秒三围成长 |
| 攻击碎片 | javelin | 箭塔攻击 |
| 生命宝石 | vitality_booster | 初始生命 |
| 木材宝石 | quelling_blade | 伐木、木材 |
| 格挡碎片 | stout_shield | 伤害格挡 |
| 属性碎片 | circlet | 初始全属性 |
| 金币宝石 | furion_gold_bag | 初始金币 |
| 聚财古符 | hand_of_midas | 资源收益 |
| 古树眷顾 | tango | 古树、资源与属性 |
| 森罗本源 | refresher | 森林、生长与资源收益 |

这些资源均由游戏提供，URI 为 `file://{images}/items/<name>.png`，实际 VPK 项为 `panorama/images/items/<name>_png.vtex_c`。原图 88×64，自带物品背景。没有涂改原始像素，也没有覆盖旧图文件；其他商品仍使用它们原来的资源。

共享渲染增加可选 `fit` 字段，12 个横向图使用 `contain` 完整等比显示。其他资源保留原有默认缩放。签到界面使用 `saturation:.65`、`wash-color:#f2e6cc`，并保留已领取、未来日期和月卡锁定的独立明暗反馈。

## 验证

- `python -B -X utf8 tools/build_item_resources.py --check`
- `python -B -X utf8 -m unittest tools.item_resources_20261016.test_fit_contract`
- `python -B -X utf8 tools/item_resources_20261016/test_generator_compat.py`
- `node tools/daily_native_icons_20261017/review_native.cjs`
- `node tools/daily_native_icons_20261017/verify.cjs`
- `powershell -File tools/daily_native_icons_20261017/compile_panorama.ps1`
- `node tools/daily_native_icons_20261017/visual_preview.cjs`
- `node tools/daily_native_icons_20261017/capture.cjs`

`review_native.cjs` 原样解码本机 Valve 资源供离线比对，PNG 留在忽略的 `output/daily_native_icons_20261017`，无需复制进游戏素材目录。`verify.cjs` 核对 VPK 指纹、PNG 指纹、尺寸及注册表范围；初次修改的快照存在时，还核对其余 1459 个资源和所有奖励身份未变。

编译仅覆盖 `common/item_resources.vjs_c`、`archive_v10_icons.vjs_c`、`daily_gw2.vcss_c`。整页截图使用真实 XML、JS、CSS 和正式 CSV 的隔离样例，验证普通/月卡奖励、1920×1080 与 1280×720，未调用领取或购买。浏览器用 RGB 乘色近似 Panorama 的暖色处理。

当前 Dota 2 窗口最小化且无有效画面尺寸，未取得实机截图；原生颜色和字体的最终观感仍需游戏内查看。可重现检查结果见 `validation/20261017/daily_native_icons.json`。
