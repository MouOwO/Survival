local M = {
    -- 每格为 64 码；大多数建筑为 2x2，城墙使用建筑配置中的 4x4。
    -- 客户端预览和服务端校验均读取各建筑的实际 footprint。
    cell_size = 64,
    footprint_subdivision = 1,
    minimum_footprint = { x = 2, y = 2 },
    max_height_delta = 48,
    unit_block_radius_scale = 1.25,
    -- 单位查询先使用此上限扩大候选范围，再按每个单位的实际 Hull 精确过滤。
    max_unit_hull_radius = 512,
    tree_block_radius_scale = 0.72,
    -- 以下参数仅用于客户端预览，不参与服务端吸附、校验或最终建造坐标。
    preview_visual = {
        grid_z_offset = 6,
        preview_alpha = 125,
        edge_thickness = 2,
        fill_strip_count = 6,
    },
    build_bounds = {
        min_x = -1800,
        max_x = 1800,
        min_y = -1200,
        max_y = 1200,
    },

    -- 业务禁区统一来自build_forbidden_regions.csv。

    -- 可选 Hammer info_target 标记。标记不存在时只记录日志，不阻断启动。
    -- { id = "lane", marker_name = "grid_no_build_lane", radius = 256 }
    forbidden_markers = {},
}

return M
