每日奖励准稿组件导入与验证

`import_assets.py --source <解压后的 daily_rewards_layered> --apply` 仅导入经过审阅的九个独立组件，另复用三个项目已有的无字材质；`--check` 比对全部生成文件与来源字节。不会执行素材包内脚本，不导入准稿截图、概念道具、栅格文字/数字或有修补瑕疵的底板。

纹理均有显式 BGRA8888、无 LOD/无 mip 的 recipe，保留原始透明度和像素。运行 `python compile_assets.py --apply` 原生编译；`--audit-only` 只读核对全部原生纹理尺寸、格式、透明度和像素，报告在忽略目录 `output/daily_accepted_20261017`。

`pwsh -NoProfile -File tools/daily_accepted_20261017/compile_panorama.ps1` 只编译每日奖励数据、控制器、CSS 和预载 XML，备份在 `output/daily_accepted_compile`。需要 Dota 2 Workshop Tools，Content 目录写权限。

回归命令：

```
node tools/tests/daily_accepted_layout.test.cjs
node -e "require('./tools/tests/menus_v10_archive_pages.test.cjs').daily()"
node tools/test_monthly_pass_checkout.cjs
node tools/test_daily_reward_feedback.cjs
node tools/tests/daily_tooltip_dismiss.test.cjs
```

测试使用模拟 Panel，不代表原生渲染通过。实际游戏验证记录、数据接口和第四槽冲突见 `docs/ui/daily_accepted_20261017.md`。
