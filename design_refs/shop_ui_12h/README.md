# Codex UI迭代参考包

本包已整合第8轮完整组件、透明物品示例、独立阴影、字体与源文件，不需要叠加之前的增量补丁。

## 如何使用

1. 将整个文件夹解压到游戏项目的`design_refs/shop_ui_12h/`等参考目录，不直接覆盖真实游戏UI文件。
2. 在Codex里打开你的游戏项目，让模型可以同时读到项目与本包。直接复制START_PROMPT.txt即可；TASK_SPEC.md是完整要求。
3. 若Codex版本支持`/goal`，可先发送下方目标，再发送START_PROMPT.txt。Goals同样受预算、运行环境与阻塞条件约束，不保证连续运行固定12小时。

目标示例：

```
/goal 按design_refs/shop_ui_12h/TASK_SPEC.md持续迭代项目商城UI，在12小时工作预算内以真实组件组装截图比较候选并保留最佳版；完成全部视觉与交互检查、资源和接入文档。遇到阻塞继续独立任务，无法继续时保存可恢复检查点。
```

不支持`/goal`时直接发送START_PROMPT.txt；中断后恢复提示：

```
读取TASK_SPEC.md与上次的Progress.md、Decisions.md，从当前最佳版本继续，先核对已有改动，继续下一个未完成实验，不重新从头做，不覆盖用户后来添加的改动。
```

## 图与组件

| 内容 | 文件 |
|---|---|
| 风格锚点 | references/01_style_anchor.png |
| 第8轮默认/悬停组装基线 | references/02_assembly_normal.png、03_assembly_hover.png |
| 商品/接缝前后对比 | references/04_cards_comparison.png、05_junction_comparison.png |
| 16项关键组件索引 | references/06_component_board.png |
| 60张PNG素材，包括独立阴影 | assets/ |
| 组件尺寸、锚点与层级 | layout.json、nav_component_layout.json、docs/COMPONENT_LAYOUT.md |
| 当前本地预览检查记录 | preview_qa.json |

01风格图中的人物和商品是示意；实际物品图是AI制作的Dota风格示例，并非Valve官方原素材。全部图仅作为设计参考与样例，真实项目商品需要保留其实际资源映射。

## 本地参考预览

这是独立浏览器组件预览，不是Dota 2的Panorama工程。安装Node依赖后运行：

```
npm install
npx playwright install chromium
npm run assets
npm run preview
```

输出位于previews/。也可直接打开source/shop.html查看组装。字体许可位于fonts/。SVG源在source/materials/，PNG由build.mjs导出。安装/渲染命令在其他电脑需要其正常网络和浏览器运行环境；游戏接入按照该项目自己的构建方式执行。

## 长任务方法来源

官方长任务说明：https://developers.openai.com/blog/run-long-horizon-tasks-with-codex

Goals使用说明：https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex

本任务的视觉评价权重和12小时时间分配是为本项目制定的建议，并非OpenAI产品保证。
