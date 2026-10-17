local bus=require('core/event_bus')
local events=require('core/events')
local scheduler=require('core/scheduler')
local effects=require('systems/commerce_effects')
local M={}
local source_name='modifier_commerce_titan_aura'
local effect_name='modifier_commerce_titan_aura_effect'
local sources,subscriptions={},{}
local initialized_world,epoch
local function world() return GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity() end
local function alive(unit) return unit and not unit:IsNull() and unit:IsAlive() end
local function clear(id)
    local state=sources[id];sources[id]=nil
    if state and state.world==world() and state.modifier then
        pcall(function() if not state.modifier:IsNull() then state.modifier:Destroy() end end)
    end
end
local function owned_source(id)
    local response=bus.request(events.HERO_SUMMON_GET_REQUEST,{player_id=id})
    local hero=response and (response.unit or response.hero)
    if alive(hero) and tonumber(hero.survival_player_id)==id
        and not hero.survival_monkey_king_clone then return hero end
    response=bus.request(events.BUILDER_GET_REQUEST,{player_id=id})
    local builder=response and (response.builder or response.unit)
    if alive(builder) and tonumber(builder.survival_player_id)==id then return builder end
end
local function reconcile(id)
    id=tonumber(id)
    if not id then return end
    local context=require('systems/player_context_service')
    if context.is_defeated(id) or not effects.owned(id,'commerce_p016') then clear(id);return end
    local unit=owned_source(id)
    local old=sources[id]
    if old and old.unit==unit and alive(unit)
        and old.modifier and not old.modifier:IsNull() then return end
    clear(id)
    if not alive(unit) then return end
    local modifier=unit:FindModifierByName(source_name)
        or unit:AddNewModifier(unit,nil,source_name,{})
    if modifier then sources[id]={unit=unit,modifier=modifier,world=initialized_world} end
end
function M.init()
    -- Engine-only component; independent commerce transport tests have no
    -- native modifier API and can keep testing without an engine fixture.
    if type(LinkLuaModifier)~='function' or not world() then return false end
    for id in pairs(sources) do clear(id) end
    for _,subscription in ipairs(subscriptions) do bus.unsubscribe(subscription) end
    sources,subscriptions={},{};initialized_world=world();epoch=(epoch or 0)+1
    local generation=epoch
    LinkLuaModifier(source_name,'modifiers/modifier_commerce_titan_aura',LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier(effect_name,'modifiers/modifier_commerce_titan_aura',LUA_MODIFIER_MOTION_NONE)
    local function listen(event,callback)
        subscriptions[#subscriptions+1]=bus.subscribe(event,function(payload)
            if epoch==generation and world()==initialized_world then callback(payload or {}) end
        end)
    end
    for _,event in ipairs({events.PLAYER_PROFILE_CHANGED,events.HERO_SUMMONED,events.HERO_REMOVED,events.BUILDER_READY}) do
        listen(event,function(payload) reconcile(payload.player_id) end)
    end
    listen(events.PLAYER_DEFEATED,function(payload) clear(tonumber(payload.player_id)) end)
    scheduler.cancel('commerce_titan_aura')
    scheduler.every(1,function()
        if epoch~=generation or world()~=initialized_world then return false end
        local seen={}
        for _,id in ipairs(require('systems/player_context_service').active_player_ids()) do
            seen[tonumber(id)]=true;reconcile(id)
        end
        local stale={};for id in pairs(sources) do if not seen[id] then stale[#stale+1]=id end end
        for _,id in ipairs(stale) do clear(id) end
        return true
    end,'commerce_titan_aura')
    return true
end
return M
