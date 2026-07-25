local M = {
    -- 与 grid_placement_config 保持一致：2x2 建筑总占地为 128x128。
    cell_size = 64,
    build_z = 128,
    build_bounds = {
        min_x = -1800,
        max_x = 1800,
        min_y = -1200,
        max_y = 1200,
    },
}

return M
