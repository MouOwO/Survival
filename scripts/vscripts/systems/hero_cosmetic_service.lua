local config = require("config/hero_cosmetics_config")
local logger = require("core/logger")

local M = {}

local wearables_by_hero = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then
        return false, nil
    end
    return pcall(method, target, ...)
end

local function hide_default_wearables(hero)
    local ok, child = safe_call(hero, "FirstMoveChild")
    if not ok then
        return
    end

    local no_draw = rawget(_G, "EF_NODRAW") or 32

    while valid_entity(child) do
        local next_ok, next_child = safe_call(child, "NextMovePeer")
        local class_ok, class_name = safe_call(child, "GetClassname")
        if class_ok and class_name == "dota_item_wearable" then
            safe_call(child, "AddEffects", no_draw)
        end
        child = next_ok and next_child or nil
    end
end

local function spawn_wearable(hero, model_path)
    local ok, wearable = pcall(
        SpawnEntityFromTableSynchronous,
        "prop_dynamic",
        {
            model = model_path,
            DefaultAnim = "idle",
        }
    )
    if not ok or not valid_entity(wearable) then
        logger.warn(
            "HeroCosmetic",
            "failed to create wearable: " .. tostring(model_path)
        )
        return nil
    end

    safe_call(wearable, "SetOwner", hero)
    safe_call(wearable, "FollowEntity", hero, true)
    return wearable
end

function M.precache(context)
    for _, definition in pairs(config) do
        for _, model_path in ipairs(definition.wearables or {}) do
            local ok, error_message = pcall(
                PrecacheResource,
                "model",
                model_path,
                context
            )
            if not ok then
                logger.warn(
                    "HeroCosmetic",
                    "precache failed: "
                    .. tostring(model_path)
                    .. " / "
                    .. tostring(error_message)
                )
            end
        end
    end
end

function M.apply(hero, hero_id)
    if not valid_entity(hero) then
        return
    end

    local definition = config[hero_id]
    if not definition then
        return
    end

    if definition.hide_default_wearables then
        hide_default_wearables(hero)
    end

    if definition.material_group then
        safe_call(
            hero,
            "SetMaterialGroup",
            definition.material_group
        )
    end

    local spawned = {}
    for _, model_path in ipairs(definition.wearables or {}) do
        local wearable = spawn_wearable(hero, model_path)
        if wearable then
            table.insert(spawned, wearable)
        end
    end

    wearables_by_hero[hero:entindex()] = spawned
    logger.info(
        "HeroCosmetic",
        hero_id
        .. " applied wearables="
        .. tostring(#spawned)
    )
end

return M
