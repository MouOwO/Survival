# UI 统一目录

- `sources/`：实际图片源和纹理配方，按已有资源相对路径存放。
- `development/`：当前 UI 构建、测试、公共组件及交接素材。
- `00_公共组件` 等中文分类目录：源文件快捷方式，供美术快速定位。
- `../index.html`：中文搜索与缩略图入口。

根目录 ui 已删除。panorama/src/images 与正式 content/panorama/images 是指向 sources 的目录联接，保留引擎需要的资源路径。图片只需编辑 sources 中的一份；游戏仍须重新编译纹理才能看到修改。

游戏运行代码及已编译资源仍位于引擎要求的 panorama 目录。不要将生成的 .vtex_c 文件当作绘图源。

迁移前备份：D:/survival_ui_backups/release_5d5c1152eb/art_source_unification.zip。换机器或移动目录后需重建本机联接与美术快捷方式，详见 ../README.md。
