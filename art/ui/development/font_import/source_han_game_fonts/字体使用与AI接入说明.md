# 苟发育 UI：思源字体包

已从 Adobe 官方仓库下载原版字体。思源黑体版本为 2.005R，思源宋体版本为 2.003R，下载日期为 2026-09-08。全部为静态 OTF，未修改、未转格式、未裁剪字库。

这组字体用于延续我们目前的界面风格：标题有适度的东方气质，正文、按钮和数值保持清晰简洁。它们是落地字体方案，并非从 AI 效果图中识别或提取出的同款字体。

## 先用这三款

| 用途 | 字体文件 | 字重 |
| --- | --- | --- |
| 正文、tooltip、属性、进度数字 | `fonts/SourceHanSansSC-Regular.otf` | Regular，400 |
| 按钮、左侧分类、顶部入口、小标题 | `fonts/SourceHanSansSC-Medium.otf` | Medium，500 |
| 存档、商城、奖池详情等窗口标题 | `fonts/SourceHanSerifSC-Bold.otf` | Bold，700 |

另附 `SourceHanSansSC-Bold.otf`，用于少量重点信息；`SourceHanSerifSC-Heavy.otf`，用于较大的主标题。先接入前三款，需要时再增加后两款，无须将所有字重都打进最终游戏包。

这些是 SC 简体中文字形优先的泛中日韩版本，字库较完整，因此体积较大；并不是 CN 精简子集版本。如果日后换用官方 CN 子集，需要同步检查字体内部名称及游戏文案覆盖情况。

## 实际字体名称

以下名称已从下载文件的 name 表读取。字体文件名不等同于引擎使用的字体族名；不同加载器可能使用传统字体族或排版字体族。

| 文件 | 传统字体族（name ID 1） | 样式（ID 2） | 排版字体族／样式（ID 16／17） |
| --- | --- | --- | --- |
| SourceHanSansSC-Regular.otf | Source Han Sans SC | Regular | 未单独设置 |
| SourceHanSansSC-Medium.otf | Source Han Sans SC Medium | Regular | Source Han Sans SC／Medium |
| SourceHanSansSC-Bold.otf | Source Han Sans SC | Bold | 未单独设置 |
| SourceHanSerifSC-Bold.otf | Source Han Serif SC | Bold | 未单独设置 |
| SourceHanSerifSC-Heavy.otf | Source Han Serif SC Heavy | Regular | Source Han Serif SC／Heavy |

完整版本、内部名称、来源地址与 SHA-256 校验值见 `font_manifest.json`。

## 给开发 AI 的指令

```text
请将此字体包接入我们现有的 Dota 2 游廊 Panorama UI，并作为共享字体规范使用。

1. 先检查当前项目、工具版本和已有字体加载方式，确认自定义字体的打包、注册和运行时加载路径。不要只在开发者电脑安装字体后就视为接入完成，也不要直接套用浏览器的 @font-face 加载方案。
2. 正文、tooltip、属性和进度数字使用思源黑体 Regular；按钮、分类和小标题使用思源黑体 Medium；窗口标题使用思源宋体 Bold。具体内部名称参考附表和 font_manifest.json。
3. 把字体规则放入共用样式或现有主题配置，让商城、存档、抽奖、奖池详情与 HUD 共用，不要每个页面分别定义一套。保留现有布局和业务逻辑。
4. 用真实字体字重，不要通过重复叠字、描边或拉伸来模拟粗体。保留文字为动态文本，不要将标题、按钮文字和数值烘焙进图片。
5. 先在测试面板显示“奖池详情、抽奖记录、解锁条件、确认、取消、0/10、100%、×10”，检查实际字体、中文覆盖、字重、行高和裁切，再批量应用。核查实际游戏全部文案，而不只测试这几个字。
6. 验证随游廊发布后，在未安装这些字体的测试环境中也能正常显示；同时检查常用分辨率。若当前 Panorama 加载机制不支持本包的 OTF/CFF，说明实际限制和可验证的替代方案，不要仅改 .otf 扩展名为 .ttf。
7. 随游戏保留 fonts 对应的 licenses 文件和版权声明。交付接入文件清单、共享样式、实际加载结果与游戏内截图。
```

本包完成了字体文件解析、版本与名称检查，并确认上述常用 UI 测试字符存在；尚未在你们的游戏项目里验证加载。Panorama 的 `font-family` 和 `font-weight` 样式只负责选择字体，不能代替字体加载。实际选择方式以游戏内验证为准。参见 [Valve Panorama 样式文档](https://developer.valvesoftware.com/wiki/Panorama/Overview/CSS_Properties)。

## 官方来源与授权

- [思源黑体官方发行页](https://github.com/adobe-fonts/source-han-sans/releases/tag/2.005R)
- [思源宋体官方发行页](https://github.com/adobe-fonts/source-han-serif/releases/tag/2.003R)
- [思源黑体官方授权](https://github.com/adobe-fonts/source-han-sans/blob/2.005R/LICENSE.txt)
- [思源宋体官方授权](https://github.com/adobe-fonts/source-han-serif/blob/2.003R/LICENSE.txt)

两款字体使用 SIL Open Font License 1.1，可按该许可证与商业游戏一起嵌入、分发，须保留版权和许可证；不可将字体本身单独出售。许可证对修改版及保留字体名称另有要求，完整原文已放入 `licenses/`。本包保留官方字体原始字节。
