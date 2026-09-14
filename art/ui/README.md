# UI 统一目录

- `sources/`：实际图片源和纹理配方。
- `development/`：当前 UI 构建、测试、公共组件及交接素材。
- 中文分类目录：打开实际源图的快捷方式。
- `../index.html`：素材搜索与缩略图。

美术修改 art/ui/sources。运行 tools/art_assets/sync_content_images.ps1，将内容同步到正式 content/dota_addons/Survival/panorama/images 的实体目录，然后重新编译。正式 tools/ui_release/compile.ps1 已自动包含同步步骤。

工程内 panorama/src/images 保留兼容联接；content 图片目录不能用联接，Source 2 资源扫描曾因此将图片误判为丢失。运行纹理仍由引擎生成在 game 的 panorama/images，不能直接替代原图编辑。

修复这类缺图后，旧工具会话可能继续抑制失败资源重试。请保存 Hammer 工作并重启工具会话，再验收游戏画面。
