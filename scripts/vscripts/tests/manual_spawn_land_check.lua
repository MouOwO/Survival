-- Workshop console: script_reload_code tests/manual_spawn_land_check
-- Read-only, explicit audit: no units, orders, timers, configuration writes or
-- navigation edits. The result describes the currently LOADED map, not an
-- unsaved Hammer document. Buildings and trees can affect live IsBlocked.
-- Ground height alone does not identify water: compare these samples with the
-- saved native terrain water masks and the actual model/brush floor geometry.
-- JSON lines avoid the engine's limit on a single very large console message.
local PREFIX = "[SPAWN_LAND_CHECK] "
local DONE = "SPAWN_LAND_CHECK_DONE_V1"
if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
    or not Entities or not GridNav or not Vector then
    print(PREFIX .. '{"status":"unverified","reason":"requires Workshop server with GridNav"}')
    print(DONE)
    return
end

local json = require("core/json_encoder")
local errors, queried, cache = 0, 0, {}
local function emit(kind, value)
    value.kind = kind
    print(PREFIX .. json.encode(value))
end
local function call(fn, ...)
    if type(fn) ~= "function" then errors = errors + 1; return nil end
    local ok, value = pcall(fn, ...)
    if not ok then errors = errors + 1; return nil end
    return value
end
local function number(value)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return false end
    return math.floor(value * 100 + 0.5) / 100
end
local function vec(value)
    if not value then return false end
    return {number(value.x), number(value.y), number(value.z)}
end
local function flag(value)
    if value == true then return 1 end
    if value == false then return 0 end
    return -1
end
local function sample(x, y, z)
    local key = string.format("%.4f/%.4f/%.4f", x, y, z)
    if cache[key] then return cache[key] end
    local p = Vector(x, y, z)
    local height = call(GetGroundHeight, p, nil)
    local ground = call(GetGroundPosition, p, nil)
    local query = ground or p
    local result = {
        number(x), number(y), number(height), ground and number(ground.z) or false,
        flag(call(GridNav.IsTraversable, GridNav, query)),
        flag(call(GridNav.IsBlocked, GridNav, query)),
    }
    queried = queried + 1
    cache[key] = result
    return result
end
local classes = {
    "info_target", "info_player_start", "info_player_start_goodguys",
    "info_player_start_badguys", "info_player_deathmatch", "path_corner",
    "info_dota_spawn_area",
}
local found, seen, counts = {}, {}, {}
for _, class_name in ipairs(classes) do
    local list = call(Entities.FindAllByClassname, Entities, class_name) or {}
    counts[class_name] = #list
    for _, entity in ipairs(list) do
        if not seen[entity] then
            seen[entity] = true
            local origin = call(entity.GetAbsOrigin, entity)
            if origin then
                found[#found + 1] = {
                    entity = entity, origin = origin, class = class_name,
                    name = call(entity.GetName, entity) or "",
                    index = call(entity.entindex, entity) or -1,
                }
            end
        end
    end
end
table.sort(found, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    if a.class ~= b.class then return a.class < b.class end
    return a.index < b.index
end)

local directions = {{1,0}, {0,1}, {-1,0}, {0,-1}, {1,1}, {-1,1}, {-1,-1}, {1,-1}}
emit("header", {
    schema = 1, map = call(GetMapName) or "unknown", classes = counts,
    origin_columns = {"x", "y", "z"},
    sample_columns = {"x", "y", "ground_height", "ground_position_z", "traversable", "blocked"},
    nearby_columns = {"dx", "dy", "ground_height", "ground_position_z", "traversable", "blocked"},
    flags = "1=true; 0=false; -1=unknown; false numeric value=unavailable",
    nearby_offsets = {32,64,128},
    water_classification = "not inferred; compare native water mask and physical floor geometry",
})
local nav_clear, nav_not_clear, displaced = 0, 0, 0
for _, record in ipairs(found) do
    local p = record.origin
    local center = sample(p.x, p.y, p.z)
    local clear = center[5] == 1 and center[6] == 0
    if clear then nav_clear = nav_clear + 1 else nav_not_clear = nav_not_clear + 1 end
    local height_delta = center[3] ~= false and number(p.z - center[3]) or false
    if height_delta ~= false and math.abs(height_delta) > 32 then displaced = displaced + 1 end
    local nearby = {}
    for _, offset in ipairs({32,64,128}) do
        for _, direction in ipairs(directions) do
            local dx, dy = direction[1] * offset, direction[2] * offset
            local point = sample(p.x + dx, p.y + dy, p.z)
            nearby[#nearby + 1] = {dx, dy, point[3], point[4], point[5], point[6]}
        end
    end
    emit("point", {
        name = record.name, class = record.class, entity_index = record.index,
        origin = vec(p), sample = center, ground_delta = height_delta,
        origin_nav = {
            flag(call(GridNav.IsTraversable, GridNav, p)),
            flag(call(GridNav.IsBlocked, GridNav, p)),
        },
        nearby = nearby,
    })
end
local summary = {
    status = errors == 0 and "sampled" or "partially_unverified",
    points = #found, nav_clear = nav_clear, nav_not_clear = nav_not_clear,
    origin_ground_delta_over_32 = displaced, distinct_samples = queried,
    api_errors = errors, water_verified = false,
}
emit("summary", summary)
print(DONE)
return summary
