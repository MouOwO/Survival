-- Offline value/load-time comparison with Dota-unavailable libraries removed.
local source_root, protected_root, list_file = arg[1], arg[2], arg[3]
local rows = assert(loadfile(list_file))()
local function equal(left, right, seen, functions_allowed, trace)
    trace = trace or "probe"
    assert(type(left) == type(right), "value type changed at " .. trace)
    if type(left) ~= "table" then
        if type(left) == "function" and functions_allowed then return end
        local detail = type(left) == "number" and string.format(": %.17g / %.17g", left, right) or ""
        assert(left == right, "value changed at " .. trace .. detail)
        return
    end
    seen = seen or {}
    if seen[left] then assert(seen[left] == right, "table identity changed"); return end
    seen[left] = right
    local count = 0
    for key, value in pairs(left) do
        count = count + 1
        equal(value, right[key], seen, functions_allowed, trace .. "." .. tostring(key))
    end
    for _ in pairs(right) do count = count - 1 end
    assert(count == 0, "table key set changed")
end
local function environment(root)
    local env = {}
    for _, name in ipairs({"assert", "error", "ipairs", "pairs", "next", "select", "pcall", "xpcall",
                            "tonumber", "tostring", "type", "unpack", "setmetatable", "getmetatable",
                            "rawget", "rawset", "rawequal"}) do env[name] = _G[name] end
    env.math, env.string, env.table = {}, {}, {}
    for key, value in pairs(math) do env.math[key] = value end
    for key, value in pairs(string) do env.string[key] = value end
    for key, value in pairs(table) do env.table[key] = value end
    env.math.random = function() error("protection must not consume gameplay RNG while loading data") end
    env._G = env
    env.IsServer, env.IsInToolsMode = function() return true end, function() return true end
    local cached = {}
    env.require = function(name)
        assert(type(name) == "string" and not name:find("..", 1, true), "unsafe verification require")
        if cached[name] == nil then
            local path = root .. "/scripts/vscripts/" .. name .. ".lua"
            local chunk = assert(loadfile(path))
            setfenv(chunk, env)
            cached[name] = chunk()
        end
        return cached[name]
    end
    return env
end
local function load_value(root, path)
    local env = environment(root)
    local chunk = assert(loadfile(root .. "/" .. path))
    setfenv(chunk, env)
    return chunk(), env
end
local function probe(path, module)
    if path:find("content_id_aliases", 1, true) then
        return {module.canonical("challenge_synthesis_gem"), module.canonical("lottery_flame_crystal"),
                module.canonical("lottery_burst_crystal"), module.canonical("unmapped"), module.canonical(nil)}
    elseif path:find("armor_balance", 1, true) then
        local out = {}
        for _, value in ipairs({0, 1, 3, 30, -10, 1000, 0.125}) do
            out[#out + 1] = module.from_war3_linear(value)
        end
        return out
    elseif path:find("mode_progression", 1, true) then
        local out = {}
        local progress = {loaded = true, standard_clear_counts = {n10 = 1}, rich_clear_counts = {n5 = 1, n10 = 1},
                          cold_clear_counts = {n5 = 0, n10 = 1}, scourge_clear_counts = {n5 = 1}}
        for _, mode in ipairs({"standard", "rich", "cold", "scourge"}) do
            out[#out + 1] = {module.clear_field(mode), module.parent_mode(mode),
                            module.entry_unlocked(mode, progress), module.difficulty_unlocked(mode, "N10", progress),
                            module.difficulty_unlocked(mode, "N5", progress), module.counts(mode, progress)}
        end
        return out
    elseif path:find("release_policy", 1, true) then
        return {module.is_production(), module.development_allowed(), module.denied_result()}
    end
    error("No semantic probe for business module: " .. path)
end
local total_before, total_after = 0, 0
for _, row in ipairs(rows) do
    collectgarbage("collect")
    local before_start = os.clock()
    local before = load_value(source_root, row.path)
    local before_time = os.clock() - before_start
    local after_start = os.clock()
    local after = load_value(protected_root, row.path)
    local after_time = os.clock() - after_start
    equal(before, after, nil, row.kind == "business", row.path)
    if row.kind == "business" then equal(probe(row.path, before), probe(row.path, after)) end
    total_before, total_after = total_before + before_time, total_after + after_time
    print(string.format("VALUE_PASS\t%s\t%.9f\t%.9f", row.path, before_time, after_time))
end
print(string.format("VALUE_SUMMARY\t%d\t%.9f\t%.9f", #rows, total_before, total_after))
