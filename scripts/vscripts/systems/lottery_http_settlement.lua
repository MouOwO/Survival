-- Executed by the authenticated HTTP worker. No engine state or local grants.
local config=require('config/lottery_config')
local definitions=require('config/generated/player_gameplay_stats')
local aliases=require('config/content_id_aliases')
local M={}
local function copy(v)
    if type(v)~='table' then return v end
    local r={};for k,x in pairs(v) do r[k]=copy(x) end;return r
end
local function public_item(item,counts)
    local r={}
    for _,k in ipairs({'id','name','description','quality','item_type','duration_type','duration_text','icon','icon_type','effect_status','duplicate_points','exchange_points','exchange_enabled','max_owned'}) do r[k]=item[k] end
    r.owned_count=tonumber(counts[aliases.canonical(item.id)]) or 0
    r.owned=r.owned_count>0;r.at_max_owned=r.owned_count>=item.max_owned
    return r
end
local function pool_public(pool,counts,state)
    local s=state.pools[pool.id] or {}
    local pity={}
    for _,rule in ipairs(pool.pity_rules) do pity[#pity+1]={quality=rule.target_quality,trigger_mode=rule.trigger_mode,batch_size=rule.threshold,label=tostring(rule.threshold)..'连保底 '..string.upper(rule.target_quality)} end
    return {id=pool.id,revision=pool.revision,update_notice=pool.update_notice,
        update_unread=s.details_revision~=pool.revision,notice_unread=s.notice_revision~=pool.revision,
        display_name=pool.display_name,description=pool.description,pool_group=pool.pool_group,
        ticket_content_id=pool.ticket_content_id,ticket_name=config.currencies[pool.ticket_content_id].display_name,
        tickets=tonumber(counts[pool.ticket_content_id]) or 0,single_cost=pool.single_cost,ten_cost=pool.ten_cost,pity=pity}
end
function M.snapshots(profile)
    local counts=profile.save.content_inventory or {}
    local state=(profile.save.archive or {}).lottery_state or {pools={}};state.pools=state.pools or {}
    local stats=profile.save.gameplay_stats or {};local pools={};local snapshots={}
    for _,pool in ipairs(config.pool_order) do pools[#pools+1]=pool_public(pool,counts,state) end
    for _,pool in ipairs(config.pool_order) do
        local selected=pool_public(pool,counts,state);local items={}
        for _,item in ipairs(pool.items) do items[#items+1]=public_item(item,counts) end
        table.sort(items,function(a,b) if a.quality==b.quality then return a.id<b.id end return config.quality_rank[a.quality]>config.quality_rank[b.quality] end)
        local snapshot={version=config.version,reason='http',selected_pool_id=pool.id,selected_pool=selected,pools=pools,items=items,
            starjoy_points=tonumber(stats.starjoy_points) or 0,map_level=tonumber(stats.map_level) or 0,draws=tonumber((state.pools[pool.id] or {}).draws) or 0}
        for _,k in ipairs({'ticket_content_id','ticket_name','tickets','single_cost','ten_cost','pity'}) do snapshot[k]=selected[k] end
        snapshots[#snapshots+1]=snapshot
    end
    return snapshots
end
local function add(stats,field,delta)
    local spec=assert(definitions.by_id[field],'lottery_unknown_stat')
    local old=tonumber(stats[field]) or tonumber(spec.default_value) or 0
    local value=old+delta
    if spec.min_value then value=math.max(value,spec.min_value) end
    if spec.max_value then value=math.min(value,spec.max_value) end
    stats[field]=value
    if field=='map_level' then
        for _,rule in ipairs(require('config/generated/map_level_effect_rules').rows) do
            if rule.enabled~=false and rule.source_field_id==field then add(stats,rule.target_field_id,(value-old)*rule.value_per_level) end
        end
    end
end
local function grant(item,counts,stats)
    local id=aliases.canonical(item.id);local owned=tonumber(counts[id]) or 0
    local result=public_item(item,counts);result.duplicate=owned>=item.max_owned;result.converted_points=0
    if result.duplicate then result.converted_points=item.duplicate_points;add(stats,'starjoy_points',item.duplicate_points)
    else counts[id]=owned+1;for _,effect in ipairs(item.effects) do add(stats,effect.field_id,effect.value) end end
    return result
end
local function roll(pool,forced)
    local quality=forced
    if not quality then
        local n=RandomInt(1,10000);local cursor=0
        for _,q in ipairs(config.quality_order) do cursor=cursor+(pool.quality_weights[q] or 0);if n<=cursor then quality=q;break end end
    end
    local items=assert(pool.by_quality[quality]);local total=0
    for _,item in ipairs(items) do total=total+item.item_weight end
    local n=(RandomInt(1,1000000000)-1)/1000000000*total;local cursor=0
    for _,item in ipairs(items) do cursor=cursor+item.item_weight;if n<cursor then return item end end
    error('lottery_pool_empty')
end
function M.settle(profile,command)
    if command.kind=='lottery_snapshot' then return {ok=true,snapshots=M.snapshots(profile)} end
    local pool=config.pools[command.pool_id];if not pool then return {ok=false,error='lottery_pool_invalid'} end
    local archive=copy(profile.save.archive or {});local counts=copy(profile.save.content_inventory or {});local stats=copy(profile.save.gameplay_stats or {})
    archive.lottery_state=archive.lottery_state or {pools={}};local state=archive.lottery_state
    state.pools=state.pools or {};state.pools[pool.id]=state.pools[pool.id] or {draws=0};local current=state.pools[pool.id]
    local response={ok=true,pool_id=pool.id,request_id=command.request_id}
    if command.kind=='lottery_read' then
        local field=({visit='visited_revision',details='details_revision',notice='notice_revision'})[command.read_action]
        if not field or command.revision~=pool.revision then return {ok=false,error='lottery_revision_invalid'} end
        current[field]=pool.revision
    elseif command.kind=='lottery_draw' then
        local count=command.count;if count~=1 and count~=10 then return {ok=false,error='lottery_count_invalid'} end
        local cost=count==10 and pool.ten_cost or pool.single_cost
        if (tonumber(counts[pool.ticket_content_id]) or 0)<cost then return {ok=false,error='lottery_ticket_insufficient'} end
        counts[pool.ticket_content_id]=counts[pool.ticket_content_id]-cost
        local guarantee=nil;local hit=false;local results={}
        for _,rule in ipairs(pool.pity_rules) do if rule.trigger_mode=='batch_only' and rule.threshold==count and (not guarantee or config.quality_rank[rule.target_quality]>config.quality_rank[guarantee]) then guarantee=rule.target_quality end end
        for i=1,count do
            local item=roll(pool,i==count and not hit and guarantee or nil)
            results[#results+1]=grant(item,counts,stats)
            if guarantee and config.quality_rank[item.quality]>=config.quality_rank[guarantee] then hit=true end
        end
        current.draws=(tonumber(current.draws) or 0)+count
        response.count=count;response.results=results;response.state_persisted=true
        response.guarantee_quality=guarantee or '';response.guarantee_satisfied=not guarantee or hit
    elseif command.kind=='lottery_exchange' then
        local item=pool.by_id[command.item_id]
        if not item or item.exchange_enabled==false or item.exchange_points<=0 then return {ok=false,error='lottery_item_invalid'} end
        if (tonumber(counts[aliases.canonical(item.id)]) or 0)>=item.max_owned then return {ok=false,error='lottery_item_owned'} end
        if (tonumber(stats.starjoy_points) or 0)<item.exchange_points then return {ok=false,error='starjoy_points_insufficient'} end
        add(stats,'starjoy_points',-item.exchange_points);response.item=grant(item,counts,stats);response.item.exchanged=true;response.cost=item.exchange_points
    else return {ok=false,error='lottery_command_invalid'} end
    return {ok=true,archive=archive,content_inventory=counts,gameplay_stats=stats,response=response}
end
return M
