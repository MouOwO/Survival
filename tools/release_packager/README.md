# 孤城逐晓打包工具

双击项目根目录的 `打包工具.cmd` 打开窗口。双击 `一键打包.cmd` 执行默认打包。

- **打包**：固定来源、生成目录、按变化选择官方编译、生产转换、完整清单审查、签名和全包校验，结束后可打开包目录。
- **打包并发布测试包**：完成上述流程后，上传原条目 `3824360109`，下载官方完整文件进行核对，再更新完整来源检查点。保持原封闭测试范围，实机功能和帧率仍待开局验证。
- **继续上次任务**：沿用原任务和已完成阶段。SDK 已确认上传而下载失败时，只继续下载。上传结果不确定时停止，保留原发行记录，不盲目重传。
- 没有运行改动：完整校验并返回当前正式签名包，不新建版本、不重编译、不上传。
- 已打包后点击发布：在来源仍一致时直接发布这一个包，不再构建一遍。

命令行入口，工作目录固定为本项目：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/release_packager.ps1 -Action build
powershell -NoProfile -ExecutionPolicy Bypass -File tools/release_packager.ps1 -Action publish-test
powershell -NoProfile -ExecutionPolicy Bypass -File tools/release_packager.ps1 -Action resume
powershell -NoProfile -ExecutionPolicy Bypass -File tools/release_packager.ps1 -Action inspect
```

普通“打包”只生成包。发布必须选择发布按钮或 `publish-test`。新任务要求两仓运行文件已提交，保留与运行无关的工作区改动。工具按项目既定 stash、pull、恢复本次 stash、定向提交、push 顺序同步两仓；不强推或清理其他 stash。

窗口显示当前阶段和错误；实际命令输出、每次调用回执、任务状态和备份位于 `D:/Survival_本地工具/runs/packaging_jobs/<任务ID>`。运行候选、编译和签包沿用树外专用目录，并通过正式登记工具记录。不会自动清理旧产物。一个任务只允许一个执行者。

打包不修改玩法。未映射的运行变更、无法重现的生产转换、签名来源不符、Dota/Tools 尚未退出或未恢复的暂装事务会明确停止。编译/构建中断产生的半成品保留；若底层工具要求独立空目录，开始新的打包任务，不覆盖旧目录。上传成功后的下载重试继续原任务。

打包时间由编译、Lua 保护、全量读取校验和 Steam 传输组成。工具省去人工组织步骤和重复构建；变化资源按完整来源清单选择，未变化 VPK 分卷使用正式构建器已有的硬链接复用，完整文件校验保留。源码、运行删除项和历史待发项不能因追求速度而漏入包。

工具窗口不在游戏内执行。初始化按两仓文件索引 O(N) 比较来源，稳定 UI 每次只处理至多 100 条队列事件，空闲不重新扫描仓库；阶段日志最多保留约 2200 行。全包校验 O(B) 读取真实文件字节，界面刷新不会触发全包校验。
