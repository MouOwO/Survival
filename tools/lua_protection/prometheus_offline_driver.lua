-- Offline adapter. Based on Prometheus by Elias Oelschner,
-- https://github.com/prometheus-lua/Prometheus
-- This file runs on the build workstation, never in the Dota runtime.
local dependency, source, destination, seed = arg[1], arg[2], arg[3], tonumber(arg[4])
local isolated_data_strings = arg[5] == "generated_table_strings"
assert(dependency and source and destination and seed and seed > 0, "invalid offline adapter arguments")
package.path = dependency .. "/src/?.lua;" .. dependency .. "/src/?/init.lua"
package.cpath = ""
package.loadlib = nil
os.execute = function() error("OFFLINE_PROTECTION_SHELL_DISABLED") end
io.popen = function() error("OFFLINE_PROTECTION_SUBPROCESS_DISABLED") end
local prometheus = require("prometheus")
prometheus.Logger.logLevel = prometheus.Logger.LogLevel.Error
-- Lua 5.1 tostring normally prints only 14 significant digits. The upstream
-- unparser and NumbersToExpressions safety guards both call it, which loses
-- exact CSV doubles such as 1/3. This build-process-only adapter preserves a
-- full IEEE-754 round trip. No such override is inserted into game output.
local ordinary_tostring = tostring
tostring = function(value)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return string.format("%.17g", value)
    end
    return ordinary_tostring(value)
end
local settings = {
    LuaVersion = "Lua51", PrettyPrint = false, NameGenerator = "MangledShuffled",
    Seed = seed, VarNamePrefix = "",
    Steps = {
        {Name = "ConstantArray", Settings = {
            Threshold = 1, StringsOnly = false, Shuffle = true, Rotate = true,
            Encoding = "base64", LocalWrapperThreshold = 0, LocalWrapperCount = 0,
        }},
        {Name = "NumbersToExpressions", Settings = {
            Threshold = 1, InternalThreshold = 0.05, NumberRepresentationMutation = false,
        }},
        {Name = "WrapInFunction", Settings = {Iterations = 1}},
    },
}
if isolated_data_strings then
    -- Pool repeated CSV strings before adding per-string decoder expressions.
    -- Applying EncryptStrings first needlessly expands large repeated tables.
    table.insert(settings.Steps, 2, {Name = "EncryptStrings", Settings = {}})
end
local pipeline = prometheus.Pipeline:fromConfig(settings)
local input = assert(io.open(source, "rb"))
local code = input:read("*a"); input:close()
local transformed = pipeline:apply(code, source)
if isolated_data_strings then
    -- EncryptStrings uses math.random to initialize its character map. Keep
    -- those calls in a lexical math copy so data loading cannot move the
    -- game's global RNG. Only pure generated table modules use this wrapper;
    -- complete returned tables are checked in a restricted environment.
    transformed = "return(function(...)\nlocal shared_math=math\nlocal math={}\n"
        .. "for key,value in pairs(shared_math) do math[key]=value end\nlocal state=" .. seed .. "\n"
        .. "math.random=function(low,high) state=(state*48271)%2147483647;"
        .. "local unit=(state-1)/2147483646;if low==nil then return unit end;"
        .. "if high==nil then high=low;low=1 end;return shared_math.floor(unit*(high-low+1))+low end\n"
        .. "math.randomseed=function() error('PRIVATE_DATA_RNG_SEED_FIXED') end\n"
        .. transformed .. "\nend)(...)\n"
end
local output = assert(io.open(destination, "wb"))
assert(output:write(transformed)); output:close()
