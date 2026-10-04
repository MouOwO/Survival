local bus=require('core/event_bus')
local events=require('core/events')
local scheduler=require('core/scheduler')
local effects=require('systems/commerce_effects')
local M={}
local players,trees,walls={}, {}, {}
local function alive(u) return u and not u:IsNull() and u:IsAlive() end
local function hero(id)
    local r=bus.request(events.HERO_SUMMON_GET_REQUEST,{player_id=id})
    return r and (r.unit or r.hero) or nil
end
local function enemies(unit,radius)
    local result={}
    for _,target in ipairs(FindUnitsInRadius(unit:GetTeamNumber(),unit:GetAbsOrigin(),nil,radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,DOTA_UNIT_TARGET_HERO+DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_NONE,FIND_ANY_ORDER,false) or {}) do
        if alive(target) and (target.survival_is_wave_monster or target.survival_is_challenge_monster)
            and tonumber(target.survival_player_id)==tonumber(unit.survival_player_id) then result[#result+1]=target end
    end
    return result
end
local function state(id) players[id]=players[id] or {research={},used={},cooldown=0};return players[id] end
local function publish(id)
    local s=state(id)
    CustomNetTables:SetTableValue('survival_commerce_actions','player_'..id,{
        blink=effects.owned(id,'teleporter') and 1 or 0,
        copper=effects.owned(id,'copper_axe') and not s.used.copper and 1 or 0,
        bomb=effects.owned(id,'saw') and not s.used.bomb and 1 or 0,
        ultimate=effects.owned(id,'tower_seal') and 1 or 0,
        immortal=effects.owned(id,'immortal') and 1 or 0,
        barrier=effects.owned(id,'barrier') and 1 or 0,
        cooldown=s.cooldown,title=effects.owned(id,'sovereign') and '君临天下' or '',
    })
end
function M.orbital(id,key)
    local s=state(id);local wall=walls[id];local unit=hero(id);local now=GameRules:GetGameTime()
    if s.wave==key or now<(s.orbital_ready or 0) or not effects.owned(id,'orbital') or not alive(wall) or not alive(unit) then return end
    s.wave=key;s.orbital_ready=now+10
    local ticks=0
    scheduler.every(.5,function()
        if not alive(wall) or not alive(unit) then return false end
        ticks=ticks+1
        local damage=(unit:GetStrength()+unit:GetAgility()+unit:GetIntellect())*10
        local projected=bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=id})
        local strip=(projected and projected.totals or {}).hero_attack_armor_reduction or 0
        for _,target in ipairs(enemies(wall,1600)) do
            if strip>0 then target:AddNewModifier(unit,nil,'modifier_research_armor_reduction',
                {armor_reduction_per_attack=require('config/armor_balance').from_war3_linear(strip)}) end
            ApplyDamage({victim=target,attacker=unit,damage=damage,damage_type=DAMAGE_TYPE_PHYSICAL})
        end
        return ticks<20
    end,'commerce_orbital_'..id)
end
function M.action(payload)
    local id=tonumber(payload.PlayerID)
    if not id or not PlayerResource:IsValidPlayerID(id) or require('systems/player_context_service').is_defeated(id) then return end
    local action=tostring(payload.action or '');local s=state(id);local unit=hero(id)
    if not alive(unit) then
        local r=bus.request(events.BUILDER_GET_REQUEST,{player_id=id});unit=r and (r.unit or r.builder)
    end
    if not alive(unit) then return end
    local ok,reason=false,'商城权益不可用'
    if action=='blink' and effects.owned(id,'teleporter') and GameRules:GetGameTime()>=s.cooldown then
        local x,y=tonumber(payload.x),tonumber(payload.y)
        if x and y and x==x and y==y and math.abs(x)<32768 and math.abs(y)<32768 then
            local target=Vector(x,y,unit:GetAbsOrigin().z)
            target.z=GetGroundHeight(target,unit)
            ok,reason=require('systems/destination_validation_service').teleport(unit,target,true)
            if ok then s.cooldown=GameRules:GetGameTime()+10 end
        end
    elseif action=='copper' and effects.owned(id,'copper_axe') and not s.used.copper and alive(trees[id]) then
        local target=require('systems/builder_work_position_service').find(unit,{footprint={x=2,y=2}},trees[id]:GetAbsOrigin())
        if target then ok,reason=require('systems/destination_validation_service').teleport(unit,target,true) end
        if ok then s.used.copper=true end
    elseif action=='bomb' and effects.owned(id,'saw') and not s.used.bomb then
        -- Only the owner's ordinary attacking wave; bosses, challenge units and trees are excluded.
        local targets=enemies(unit,1600)
        for _,target in ipairs(targets) do
            if target.survival_is_wave_monster and not target.survival_is_boss then
                target:Kill(nil,unit);ok=true
            end
        end
        if ok then s.used.bomb=true else reason='附近没有可清除的普通进攻怪' end
    elseif action=='ultimate' and effects.owned(id,'tower_seal') then
        local x,y=tonumber(payload.x),tonumber(payload.y)
        if x and y and x==x and y==y and math.abs(x)<32768 and math.abs(y)<32768 then
            local result=require('systems/tower_fusion_service').commerce_build(id,unit,Vector(x,y,unit:GetAbsOrigin().z))
            ok=result and result.ok;reason=result and result.error
        end
    elseif action=='immortal' and effects.owned(id,'immortal') then
        local result=require('systems/worker_system').commerce_fuse_immortal(id);ok=result and result.ok;reason=result and result.error
    end
    publish(id)
    bus.emit(events.UI_NOTIFICATION,{player_id=id,message=ok and '商城技能已生效' or tostring(reason or '操作失败'),level=ok and 'info' or 'error'})
end
local function tick()
    for _,id in ipairs(require('systems/player_context_service').active_player_ids()) do
        local s=state(id)
        require('systems/worker_system').refresh_commerce_capacity(id)
        if not s.immortal_spawned and effects.owned(id,'immortal') then
            local buildings=bus.request(events.BUILDING_LIST_REQUEST,{player_id=id})
            for _,b in ipairs(buildings and buildings.buildings or {}) do
                if b.building_id=='main_city' and alive(b.unit) and not b.unit:HasModifier('modifier_building_under_construction') then
                    s.immortal_spawned=require('systems/worker_system').commerce_spawn_immortal(id,b.unit)
                    break
                end
            end
        end
        if effects.owned(id,'lumberyard') then
            for _,tech in ipairs({'RS-06','RS-08'}) do
                if not s.research[tech] then
                    local r=bus.request(events.RESEARCH_STATE_GET_REQUEST,{player_id=id})
                    local levels=r and r.levels or {}
                    local result=bus.request(events.RESEARCH_LEVEL_SET_REQUEST,{player_id=id,tech_id=tech,
                        level=(tonumber(levels[tech]) or 0)+5,reason='commerce_lumberyard'})
                    if result and result.ok then s.research[tech]=true end
                end
            end
        end
        local wall=walls[id]
        local h=hero(id)
        if s.aura_hero~=h or not alive(h) then
            if s.aura then ParticleManager:DestroyParticle(s.aura,true);ParticleManager:ReleaseParticleIndex(s.aura);s.aura=nil end
            s.aura_hero=h
        end
        if alive(h) and effects.owned(id,'lottery_immortal_slaying_sword_array') and not s.aura then
            s.aura=ParticleManager:CreateParticle('particles/survival/weapons/weapon_glow.vpcf',PATTACH_ABSORIGIN_FOLLOW,h)
        end
        if alive(h) and effects.owned(id,'sovereign') and not h.survival_commerce_title then
            h.survival_commerce_title=true;h.survival_display_name='【君临天下】'..tostring(h.survival_display_name or '')
        end
        if s.cannon and (s.cannon:IsNull() or not alive(wall)) then
            if not s.cannon:IsNull() then s.cannon:RemoveSelf() end;s.cannon=nil
        end
        if alive(wall) and effects.owned(id,'orbital') and not s.cannon then
            local definition=require('config/buildings_config').arrow_tower
            local cannon=CreateUnitByName(definition.unit_name,wall:GetAbsOrigin(),true,wall,wall,wall:GetTeamNumber())
            if cannon then
                cannon.survival_visual_only=true;cannon:SetHullRadius(0);cannon:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
                cannon:AddNewModifier(cannon,nil,'modifier_invulnerable',{})
                cannon:AddNewModifier(cannon,nil,'modifier_phased',{})
                cannon.survival_display_name='轨道炮';s.cannon=cannon
            end
        end
        if alive(wall) and effects.owned(id,'flame_wall') and not require('systems/gameplay_phase_guard').post_clear_frozen() then
            for _,target in ipairs(enemies(wall,800)) do
                ApplyDamage({victim=target,attacker=wall,damage=target:GetMaxHealth()*.01,damage_type=DAMAGE_TYPE_MAGICAL})
            end
        end
        publish(id)
    end
    return true
end
function M.init()
    players,trees,walls={},{},{}
    bus.subscribe(events.PLAYER_PROFILE_CHANGED,function(p) if tonumber(p.player_id) then effects.invalidate(p.player_id) end end)
    bus.subscribe(events.TREE_CHANGED,function(p) if p.entindex then trees[tonumber(p.player_id)]=EntIndexToHScript(p.entindex) end end)
    bus.subscribe(events.BUILDING_CREATED,function(p)
        if p.building_id=='wall' then walls[tonumber(p.player_id)]=p.unit or EntIndexToHScript(p.entindex) end
    end)
    bus.subscribe(events.WAVE_CHANGED,function(p)
        if tostring(p.reason or ''):find('wave_started',1,true) then
            for _,id in ipairs(require('systems/player_context_service').active_player_ids()) do M.orbital(id,'wave:'..tostring(p.current_wave)) end
        end
    end)
    bus.subscribe('commerce.endless_wave',function(p) M.orbital(p.player_id,'endless:'..tostring(p.wave)) end)
    CustomGameEventManager:RegisterListener('survival_commerce_action',function(_,p) M.action(p or {}) end)
    scheduler.every(1,tick,'commerce_runtime')
end
return M
