-- Read-only Workshop probe. Does not attack/spawn/remove units or change CVars.
-- Console: script_reload_code tests/manual_tree_impact_api_probe
if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
    or not Entities or not Entities.FindAllByClassname then
    print('[TREE_IMPACT_API] {"status":"unverified","reason":"requires Workshop server"}')
    print("TREE_IMPACT_API_PROBE_DONE")
    return
end
local json = require("core/json_encoder")
local function relevant(name)
    name = tostring(name):lower()
    return name:find("blood", 1, true) or name:find("impact", 1, true)
        or name:find("suppressdamage", 1, true) or name:find("suppress_damage", 1, true)
        or name:find("combatclass", 1, true)
end
local globals, classes, units = {}, {}, {}
for name, value in pairs(_G) do
    if relevant(name) and (type(value) == "number" or type(value) == "function") then
        globals[#globals + 1] = {name = name, kind = type(value)}
    end
end
for _, name in ipairs({"CBaseEntity", "CBaseModelEntity", "CDOTA_BaseNPC", "CDOTA_Modifier_Lua"}) do
    local result = {}
    if type(_G[name]) == "table" then
        for key, value in pairs(_G[name]) do
            if relevant(key) then result[#result + 1] = {name = key, kind = type(value)} end
        end
    end
    classes[name] = result
end
local function read(unit, method)
    if type(unit[method]) ~= "function" then return false end
    local ok, value = pcall(unit[method], unit)
    return ok and value or false
end
for _, unit in ipairs(Entities:FindAllByClassname("npc_dota_creature") or {}) do
    if not unit:IsNull() and read(unit, "GetUnitName") == "enemy_tree" then
        local methods = {}
        for _, name in ipairs({"SetBloodColor", "GetBloodColor", "SetBloodType", "GetBloodType",
            "SetSuppressDamageEffects", "GetSuppressDamageEffects", "SetUnitKeyValues",
            "SetKeyValue", "GetKeyValue", "GetUnitKeyValues"}) do
            methods[name] = type(unit[name]) == "function"
        end
        local values, kv = {}, read(unit, "GetUnitKeyValues")
        if type(kv) == "table" then
            for name, value in pairs(kv) do
                if relevant(name) or name == "SoundSet" or name == "BaseClass" then
                    values[name] = type(value) == "table" and "table" or tostring(value)
                end
            end
        end
        units[#units + 1] = {entindex = unit:entindex(), classname = read(unit, "GetClassname"),
            model = read(unit, "GetModelName"), methods = methods, selected_kv = values}
    end
end
print("[TREE_IMPACT_API] " .. json.encode({globals = globals, classes = classes, units = units,
    modified_game_state = false, visual_effect_verified = false}))
print("TREE_IMPACT_API_PROBE_DONE")
