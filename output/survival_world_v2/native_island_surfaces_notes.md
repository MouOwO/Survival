# 四座主岛统一原生石材铺装

四座主岛的全部可用地面统一铺设官方天辉旧石板，包括原有城门庭院、防御塔层、新增平台及连接台阶。

复用官方 materials/blends/mod_radiant_path_000.vmat 的旧石板纹理、法线、反射和色调参数。主岛专用 island_native_paving.vmat 将全部地形混合槽统一为该石材，防止原生地形自动混回草地；没有新绘制贴图。新增部分立面使用 materials/blends/mod_radiant_000.vmat 的岩壁层。

原有岛屿通过修改本项目专用的 radiant_basic 地形模板和地形绘制数据完成铺装，无额外覆盖平面；原有草面改选石板层，关闭草叶。新增部分沿用已经验证的几何轮廓、台阶与高度。岛边树木、岩石、灯笼作为装饰保留。

地图生成流程停止调用旧 world_v2_island_material.cjs，新地图不再引用浅色 island_stairs.vmat。旧文件保留供历史版本回退。

本轮保持前一轮的明亮月夜光照、三层结构与水道收口。修改前文件与截图位于 before_native_island_surfaces/。打开 native_island_surfaces_review.html 查看相同机位前后对比；实机通行、高度及截图时间以 verification.json 为准。
