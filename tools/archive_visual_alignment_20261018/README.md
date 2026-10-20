# 存档标题、图标对齐与边缘清晰度

标题背景补齐原始 GW2 透明材质的上下边，标题放在完整的深色条内。分类图标和圆框共用无边框容器；17类 SVG 的可见边界居中。所有普通条目使用单张256px矢量金环，替代会产生内容缩进的三层原生圆边框。列表、条目和图标的裁切保留。

`audit_images.cjs` 按当前正式 CSV、中央资源表、本机资源和 Dota VPK 检查391种图像。23张虚空之影已为256px无损纹理，其他169张313px无损纹理足够当前尺寸，保留原资源。官方64px物品保留真实原图及其细节上限，不做无效放大。36条福利记录共用的130×95徽章移至独立无损纹理；原PNG、条目身份及其他资源行不变，仅增加36,728字节纹理数据。

验证入口：

```powershell
node tools/archive_visual_alignment_20261018/audit_images.cjs
node tools/archive_visual_alignment_20261018/welfare_integrate.cjs --audit
node tools/archive_visual_alignment_20261018/preview.cjs
node tools/archive_visual_alignment_20261018/export_native.cjs
node tools/archive_visual_alignment_20261018/preview.cjs
node tools/archive_visual_alignment_20261018/verify.cjs
```

`export_native.cjs` 从本机 VPK 导出真实物品图，仅供浏览器解析原生 URI；不替换生产资源。预览执行生产 XML/JS/CSS 和明确的离线样例，阻断网络。1920×1080遍历全部存档分类，1280×720检查主要分类；另外检查滚动底部和提示框。它不是实机截图。

`compile.ps1` 用冻结 SHA-256 计划同步与编译本轮布局/矢量改动，备份 content 和运行资源，失败恢复。`welfare_integrate.cjs --apply` 单独编译福利纹理、逐像素核对并更新中央资源生成物，同样备份并恢复失败步骤。编译会写 Dota content 目录，需要相应文件系统权限。

报告与截图位于 `output/archive_visual_alignment_20261018/`，完整素材审计位于 `output/archive_images_audit_20261018/audit.json`。
