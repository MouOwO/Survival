-- Read-only presentation adapter. No rewards, persistence, timers or transport.
-- Updates require authoritative changed paths; never build a full legacy page
-- and diff it. The caller owns player authentication, stream tokens and sends.
local M={}
local rules=require("config/generated/archive_daily_rules").by_id.default
local items=require("config/generated/archive_daily_items")
local benefits=require("config/generated/archive_benefit_rewards")
local aliases=require("config/content_id_aliases")
local stackables=require("systems/archive_stackable_items")
local UINT,MAX_SAFE=4294967295,9007199254740991
local TRACKS={"daily_time","daily_wins","weekly_time"}
local owned_dependencies,dependency_set={},{}
for _,row in ipairs(benefits.rows) do if row.enabled and (row.track=="daily_time" or row.track=="daily_wins" or row.track=="weekly_time") then
    for _,ids in ipairs({row.base_item_ids or {},row.pass_item_ids or {}}) do for _,id in ipairs(ids) do
        local definition=stackables.definition(id)
        if definition and not dependency_set[definition.id] then
            dependency_set[definition.id]=true;owned_dependencies[#owned_dependencies+1]=definition.id
        end
    end end
end end
M.error_text={ [0]="",[1]="操作未完成，请重试",[2]="档案尚未载入",[3]="签到日期无效",
    [4]="请先开通月卡",[5]="该奖励已领取",[6]="尚未达到领取条件",[7]="操作处理中，请稍后重试",
    [8]="保存未完成，请重试",[9]="对局身份已变更，请重新打开",[10]="到账尚未确认，请稍后查询" }
local errors={profile_not_loaded=2,["档案尚未载入"]=2,["签到日期无效"]=3,["请先开通月卡"]=4,
    ["该日期已领取"]=5,["该奖励已领取"]=5,["尚未达到领取条件"]=6,
    archive_busy=7,["操作过于频繁，请稍后重试"]=7,archive_provider_timeout=8,archive_save_failed=8}
local function need(ok,reason) if not ok then error(reason,0) end end
local function integer(value,minimum,maximum)
    return type(value)=="number" and value==value and value==math.floor(value) and value>=minimum and value<=maximum
end
local function guard(fn,...)
    local ok,result,detail=pcall(fn,...)
    if ok then return result,detail end
    return nil,tostring(result)
end
local function count(value)
    if value==nil then return 0 end
    value=tonumber(value);need(integer(value,0,MAX_SAFE),"daily_count_invalid");return value
end
local function flag(value)
    need(value==true or value==false or value==0 or value==1,"daily_flag_required")
    return value==true or value==1
end
local function array(value,maximum)
    if value==nil then return {} end
    need(type(value)=="table","daily_changeset_array_required")
    local size=#value;need(size<=maximum,"daily_changeset_limit")
    local actual=0;for key in pairs(value) do need(integer(key,1,size),"daily_changeset_sparse");actual=actual+1 end
    need(actual==size,"daily_changeset_sparse");return value
end
local function bit(mask,power,on)
    if (math.floor(mask/power)%2==1)~=on then mask=mask+(on and power or -power) end
    return mask
end
local function upper_bound(rows,value)
    local first,last=1,#rows+1
    while first<last do
        local middle=math.floor((first+last)/2)
        if middle<=#rows and rows[middle].required<=value then first=middle+1 else last=middle end
    end
    return first-1
end
local function make(lookup)
    need(type(lookup)=="table" and type(lookup.by_key)=="table" and type(lookup.field_by_name)=="table","daily_lookup_required")
    local F=lookup.field_by_name
    for _,name in ipairs({"known","count","count_hi","completed","has_pass","expires_at","pending","enabled",
        "day","missed_mask","unique_owned_mask","progress","progress_hi","period","status","can_claim",
        "owned_count","owned_count_hi","request_token","success","terminal","target_record","error_code"}) do
        need(F[name] and lookup.fields[F[name]] and lookup.fields[F[name]].name==name,"daily_field_missing:"..name)
    end
    local function record(key)
        local id=lookup.by_key[key];local row=id and lookup.records[id]
        need(row and row.key==key and not row.tombstone,"daily_record_missing:"..key);return id
    end
    local state_record=record("daily:state")
    local ack_records={daily=record("daily:ack:claim"),benefit=record("daily:ack:benefit")}
    local unique,unique_by_id={},{}
    for _,item in ipairs(items.rows) do if item.enabled~=false then
        unique[#unique+1]={id=item.item_id,record=record("daily:item:"..item.item_id)}
    end end
    need(#unique==12 and integer(rules.makeup_days,1,30),"daily_static_layout_changed")
    table.sort(unique,function(a,b) return a.record<b.record end)
    for index,row in ipairs(unique) do row.power=2^(index-1);unique_by_id[row.id]=row end
    local tracks,tiers,monthly,owned={},{},{},{}
    for _,name in ipairs(TRACKS) do tracks[name]={name=name,record=record("daily:track:"..name),rows={}} end
    for _,row in ipairs(benefits.rows) do if row.enabled and tracks[row.track] then
        local tier={id=row.reward_id,record=record("daily:benefit:"..row.reward_id),track=row.track,
            required=row.required,monthly=row.monthly_only==true,automatic=row.auto_claim==true}
        need(integer(tier.required,0,MAX_SAFE),"daily_threshold_invalid")
        tiers[tier.id]=tier;local rows=tracks[tier.track].rows;rows[#rows+1]=tier
        if tier.monthly then monthly[#monthly+1]=tier end
        for _,ids in ipairs({row.base_item_ids or {},row.pass_item_ids or {}}) do for _,id in ipairs(ids) do
            local definition=stackables.definition(id)
            if definition and not owned[definition.id] then
                owned[definition.id]={record=record("archive:points:"..definition.id)}
            end
        end end
    end end
    for _,track in pairs(tracks) do table.sort(track.rows,function(a,b)
        return a.required==b.required and a.record<b.record or a.required<b.required
    end) end
    local status=lookup.fields[F.status].labels
    need(status and status.claimed==3 and status.claimable==2 and status.locked==1,"daily_status_schema_changed")
    local factory={}
    function factory.initialize(profile,context)
        return guard(function()
            local values,raw_owned,raw_groups,totals,intents,used_tokens={},{},{},{},{},{}
            local completed_ring,completed_cursor,active_intents={},0,0
            local eligible_tiers=0
            local a={known=false,tracks={},owned_mask=0,missed_mask=0}
            local last_metrics={}
            local api={}
            local function stage()
                local order,writes={},{}
                local function put(rec,name,value)
                    local field=assert(F[name]);local key=rec*128+field
                    if not writes[key] then order[#order+1]=key end
                    writes[key]={record=rec,field=field,value=value}
                end
                local function big(rec,name,value)
                    put(rec,name,value%4294967296);put(rec,name.."_hi",math.floor(value/4294967296))
                end
                local function commit()
                    local out={}
                    for _,key in ipairs(order) do
                        local write=writes[key];local row=values[write.record]
                        if not row or row[write.field]~=write.value then
                            if not row then row={};values[write.record]=row end
                            row[write.field]=write.value
                            if write.value==nil then out[#out+1]={record=write.record,field=write.field,remove=true}
                            else out[#out+1]={record=write.record,field=write.field,value=write.value} end
                        end
                    end
                    return out
                end
                return put,big,commit
            end
            local function identity(current)
                need(type(current)=="table" and type(current.save)=="table" and current.account_id~=nil,"daily_profile_required")
                need(integer(current.revision,0,MAX_SAFE),"daily_profile_revision_invalid")
                if a.known then
                    need(current.account_id==a.account and current.mode==a.mode and current.match_session_id==a.session,
                        "daily_identity_changed_reinitialize")
                    need(current.revision>=a.revision,"daily_profile_revision_regressed")
                end
            end
            local function update(current,changes,ctx)
                identity(current)
                need(type(ctx)=="table" and integer(ctx.now,0,UINT),"daily_server_time_required")
                local pending,purchase=flag(ctx.pending),flag(ctx.purchase_enabled) and rules.purchase_enabled==true
                need(not a.now or ctx.now>=a.now,"daily_clock_regressed")
                if changes==nil then need(not a.known or current.revision==a.revision,"daily_changeset_required");changes={} end
                need(type(changes)=="table","daily_changeset_required")
                for key,value in pairs(changes) do
                    need(key=="initialize" or key=="daily_state" or key=="daily_claimed_days" or key=="daily_items"
                        or key=="benefit_tracks" or key=="benefit_claims" or key=="inventory" or key=="entitlement"
                        or key=="calendar" or key=="unrelated","daily_changeset_key_unknown")
                    if key=="initialize" or key=="daily_state" or key=="entitlement" or key=="calendar" or key=="unrelated" then
                        need(value==true,"daily_changeset_flag_invalid")
                    end
                end
                local initial=not a.known or changes.initialize==true
                local day=math.floor((ctx.now+10800)/86400);local week=math.floor((day+3)/7)
                local calendar_changed=initial or day~=a.day or changes.calendar==true
                local metrics={inventory_entries_scanned=0,inventory_index_reads=0,tier_evaluations=0,
                    track_reads=0,daily_item_reads=0,missed_day_reads=0}
                if not initial and next(changes)==nil and day==a.day and pending==a.pending and purchase==a.purchase
                    and not (a.has_pass and a.expires and ctx.now>=a.expires) then
                    a.now,a.revision=ctx.now,current.revision;last_metrics=metrics;return {},metrics
                end
                local changed_days=array(changes.daily_claimed_days,30)
                local changed_items=array(changes.daily_items,12)
                local changed_tracks=array(changes.benefit_tracks,3)
                local changed_tiers=array(changes.benefit_claims,64)
                local inventory=array(changes.inventory,65535)
                for _,id in ipairs(changed_items) do need(unique_by_id[id],"daily_unique_item_unknown") end
                for _,name in ipairs(changed_tracks) do need(tracks[name],"daily_track_unknown") end
                for _,id in ipairs(changed_tiers) do need(tiers[id],"daily_tier_unknown") end
                for _,date in ipairs(changed_days) do need(integer(date,0,UINT),"daily_claimed_day_invalid") end
                local w={};for key,value in pairs(a) do w[key]=value end
                w.tracks={};for name,value in pairs(a.tracks) do
                    w.tracks[name]={period=value.period,progress=value.progress,ready=value.ready}
                end
                w.now,w.day,w.week,w.pending,w.purchase=ctx.now,day,week,pending,purchase
                w.account,w.mode,w.session,w.revision=current.account_id,current.mode,current.match_session_id,current.revision
                local archive=current.save.archive or {}
                local daily=archive.daily_rewards or {first_day=day,count=0,claimed={},item_counts={}}
                local claimed,item_counts=daily.claimed or {},daily.item_counts or {}
                local put,big,commit=stage()
                if initial or changes.daily_state or calendar_changed then
                    w.count=count(daily.count);w.first_day=daily.first_day or day
                    need(integer(w.first_day,0,UINT),"daily_first_day_invalid")
                    w.claimed=claimed[tostring(day)]==true
                else for _,date in ipairs(changed_days) do if date==day then w.claimed=claimed[tostring(day)]==true end end end
                if initial or calendar_changed or w.first_day~=a.first_day then
                    w.missed_mask=0
                    for offset=1,rules.makeup_days-1 do
                        metrics.missed_day_reads=metrics.missed_day_reads+1
                        if day-offset>=w.first_day and not claimed[tostring(day-offset)] then w.missed_mask=w.missed_mask+2^(offset-1) end
                    end
                else for _,date in ipairs(changed_days) do
                    local offset=day-date
                    if offset>=1 and offset<rules.makeup_days and date>=w.first_day then
                        w.missed_mask=bit(w.missed_mask,2^(offset-1),not claimed[tostring(date)])
                    end
                end end
                local function unique_item(row)
                    metrics.daily_item_reads=metrics.daily_item_reads+1
                    w.owned_mask=bit(w.owned_mask,row.power,count(item_counts[row.id])>0)
                end
                if initial then for _,row in ipairs(unique) do unique_item(row) end
                else for _,id in ipairs(changed_items) do unique_item(unique_by_id[id]) end end
                if initial or changes.entitlement or calendar_changed or a.has_pass and a.expires and ctx.now>=a.expires then
                    local entitlement=(current.entitlements or {})[rules.pass_entitlement_id] or {}
                    w.expires=entitlement.expires_at~=nil and tonumber(entitlement.expires_at) or nil
                    need(entitlement.expires_at==nil or integer(w.expires,0,UINT),"daily_expiry_invalid")
                    w.has_pass=entitlement.active==true and (w.expires==nil or w.expires>ctx.now)
                end
                put(state_record,"known",1);put(state_record,"day",day);big(state_record,"count",w.count)
                put(state_record,"completed",w.claimed and 1 or 0);put(state_record,"has_pass",w.has_pass and 1 or 0)
                put(state_record,"expires_at",w.expires);put(state_record,"pending",pending and 1 or 0)
                put(state_record,"enabled",purchase and 1 or 0);put(state_record,"missed_mask",w.missed_mask)
                put(state_record,"unique_owned_mask",w.owned_mask)
                local dirty,track_changes={},{ }
                for _,id in ipairs(changed_tiers) do dirty[id]=true end
                for _,name in ipairs(changed_tracks) do track_changes[name]=true end
                if initial or calendar_changed then for _,name in ipairs(TRACKS) do track_changes[name]=true end end
                local function bucket(name,period)
                    local saved=archive.benefits or {}
                    return ((name=="weekly_time" and saved.weeks or saved.days) or {})[tostring(period)] or {}
                end
                for name in pairs(track_changes) do
                    metrics.track_reads=metrics.track_reads+1
                    local track=tracks[name];local period=name=="weekly_time" and week or day
                    local saved=bucket(name,period)
                    local progress=name=="daily_wins" and count(saved.wins) or math.floor(count(saved.seconds)/60)
                    local previous=a.tracks[name];local ready=upper_bound(track.rows,progress)
                    if not previous or previous.period~=period or initial then
                        for _,tier in ipairs(track.rows) do dirty[tier.id]=true end
                    elseif previous.ready~=ready then
                        for index=math.min(previous.ready,ready)+1,math.max(previous.ready,ready) do dirty[track.rows[index].id]=true end
                    end
                    w.tracks[name]={period=period,progress=progress,ready=ready}
                    put(track.record,"known",1);put(track.record,"period",period);big(track.record,"progress",progress)
                end
                if initial or a.has_pass~=w.has_pass then for _,tier in ipairs(monthly) do dirty[tier.id]=true end end
                local next_eligible=eligible_tiers
                for id in pairs(dirty) do
                    metrics.tier_evaluations=metrics.tier_evaluations+1
                    local tier=tiers[id];local track=w.tracks[tier.track]
                    local done=(bucket(tier.track,track.period).claimed or {})[id]~=nil
                    local ready=track.progress>=tier.required and (not tier.monthly or w.has_pass)
                    local can_claim=not tier.automatic and not done and ready and 1 or 0
                    local old=values[tier.record] and values[tier.record][F.can_claim] or 0
                    if old~=can_claim then next_eligible=next_eligible+can_claim-old end
                    put(tier.record,"known",1);put(tier.record,"completed",done and 1 or 0)
                    put(tier.record,"can_claim",can_claim)
                    put(tier.record,"status",done and status.claimed or ready and status.claimable or status.locked)
                end
                put(state_record,"can_claim",(not w.claimed or next_eligible>0) and 1 or 0)
                local raw_updates,deltas,dirty_owned={},{},{}
                local source=current.save.content_inventory or {}
                local function inventory_value(raw,new_value)
                    need(type(raw)=="string","daily_inventory_key_invalid")
                    if raw_updates[raw]~=nil then return end
                    local canonical=aliases.canonical(raw)
                    if not owned[canonical] then return end
                    metrics.inventory_index_reads=metrics.inventory_index_reads+1
                    local value=count(new_value);local old=initial and 0 or raw_owned[raw] or 0
                    deltas[canonical]=(deltas[canonical] or 0)+value-old
                    raw_updates[raw]=value;dirty_owned[canonical]=true
                end
                if initial then
                    for raw,value in pairs(source) do metrics.inventory_entries_scanned=metrics.inventory_entries_scanned+1;inventory_value(raw,value) end
                    for id in pairs(owned) do dirty_owned[id]=true end
                else for _,raw in ipairs(inventory) do
                    inventory_value(raw,source[raw])
                    local canonical=aliases.canonical(raw)
                    if raw==canonical then for alias in pairs(raw_groups[canonical] or {}) do inventory_value(alias,source[alias]) end end
                end end
                local new_totals={}
                for id in pairs(dirty_owned) do
                    local value=(initial and 0 or totals[id] or 0)+(deltas[id] or 0)
                    need(integer(value,0,MAX_SAFE),"daily_owned_total_invalid");new_totals[id]=value
                    put(owned[id].record,"known",1);big(owned[id].record,"owned_count",value)
                end
                local ops=commit();w.known=true;a=w;eligible_tiers=next_eligible
                if initial then raw_owned,raw_groups,totals={},{},{} end
                for raw,value in pairs(raw_updates) do
                    raw_owned[raw]=value~=0 and value or nil
                    local canonical=aliases.canonical(raw);raw_groups[canonical]=raw_groups[canonical] or {}
                    raw_groups[canonical][raw]=value~=0 and true or nil
                end
                for id,value in pairs(new_totals) do totals[id]=value end
                metrics.ops=#ops;last_metrics=metrics
                return ops,metrics
            end
            function api.update(current,changes,ctx) return guard(update,current,changes,ctx) end
            function api.full_ops()
                local out={};for rec,row in pairs(values) do for field,value in pairs(row) do
                    out[#out+1]={record=rec,field=field,value=value}
                end end;return out
            end
            function api.inspect()
                return {known=a.known,revision=a.revision,day=a.day,active_intents=active_intents,metrics=last_metrics}
            end
            function api.hint()
                local row=values[state_record] or {}
                return {known=row[F.known]==1,can_claim=row[F.can_claim]==1,pending=row[F.pending]==1}
            end
            function api.bind_intent(token,intent)
                return guard(function()
                    need(a.known and integer(token,1,16383) and type(intent)=="table","daily_intent_invalid")
                    local existing=intents[token]
                    if existing then
                        need(existing.kind==intent.kind and existing.target_day==intent.target_day and existing.tier_id==intent.tier_id,
                            "daily_intent_token_conflict");return true
                    end
                    need(not used_tokens[token],"daily_intent_token_reused");need(active_intents<32,"daily_intent_limit")
                    local bound={kind=intent.kind,target_day=intent.target_day,tier_id=intent.tier_id,day=a.day}
                    if intent.kind=="daily" then
                        need(integer(intent.target_day,0,UINT),"daily_intent_target_invalid")
                        bound.period=math.floor(math.max(0,a.count-(a.claimed and 1 or 0))/7)
                    else
                        local tier=tiers[intent.tier_id]
                        need(intent.kind=="benefit" and tier,"daily_intent_target_invalid")
                        bound.period=a.tracks[tier.track].period;bound.target_record=tier.record;bound.track=tier.track
                    end
                    intents[token]=bound;used_tokens[token]=true;active_intents=active_intents+1;return true
                end)
            end
            function api.ack(token,result,current,ctx)
                return guard(function()
                    identity(current);need(type(result)=="table" and type(ctx)=="table","daily_receipt_required")
                    local intent=intents[token];need(intent,"daily_intent_unknown")
                    if intent.done then return {} end
                    local pending=flag(ctx.pending) or result.pending==true or result.pending==1
                    local ok=result.ok==true or result.ok==1
                    local saved=current.save.archive or {};local confirmed=false
                    if ok and not pending then
                        if intent.kind=="daily" then confirmed=((saved.daily_rewards or {}).claimed or {})[tostring(intent.target_day)]==true
                        else
                            local archive_benefits=saved.benefits or {}
                            local map=intent.track=="weekly_time" and archive_benefits.weeks or archive_benefits.days
                            confirmed=((((map or {})[tostring(intent.period)] or {}).claimed or {})[intent.tier_id])~=nil
                        end
                    end
                    local code=ok and 0 or errors[result.error] or 1
                    if ok and not confirmed then pending=true;code=10 end
                    if not ok and result.terminal==false then pending=true end
                    local terminal=not pending and (confirmed or result.terminal~=false)
                    local put,_,commit=stage();local rec=ack_records[intent.kind]
                    put(rec,"known",1);put(rec,"request_token",token);put(rec,"day",intent.target_day or intent.day)
                    put(rec,"period",intent.period);put(rec,"target_record",intent.target_record or 0)
                    put(rec,"pending",pending and 1 or 0);put(rec,"success",confirmed and 1 or 0)
                    put(rec,"terminal",terminal and 1 or 0);put(rec,"error_code",code)
                    local ops=commit()
                    if terminal then
                        intent.done=true;active_intents=active_intents-1
                        completed_cursor=completed_cursor%32+1
                        local previous=completed_ring[completed_cursor];if previous then intents[previous]=nil end
                        completed_ring[completed_cursor]=token
                    end
                    return ops
                end)
            end
            if profile==nil then
                values[state_record]={[F.known]=0}
                return api,{{record=state_record,field=F.known,value=0}}
            end
            local ops,error_message=api.update(profile,{initialize=true},context)
            need(ops~=nil,error_message);return api,ops
        end)
    end
    return factory
end
function M.new(lookup) return guard(make,lookup) end
-- Derive presentation invalidation from the real server command, not a client
-- claim about changed data. Unknown replacement commands request an explicit
-- indexed rebuild; known online/claim paths never scan an account inventory.
function M.command_changes(command,result)
    command=command or {};local kind=tostring(command.kind or "")
    local changed={};local inventory,seen={},{}
    local function add(id)
        if type(id)~="string" then return end
        local canonical=aliases.canonical(id)
        if stackables.definition(canonical) and not seen[canonical] then seen[canonical]=true;inventory[#inventory+1]=canonical end
    end
    if kind=="online_checkpoint" then changed.benefit_tracks={"daily_time","weekly_time"}
    elseif kind=="daily_claim" or kind=="daily_init" then
        changed.daily_state=true
        if command.target_day then changed.daily_claimed_days={command.target_day} end
        changed.daily_items={};for _,item in ipairs(items.rows) do if item.enabled~=false then changed.daily_items[#changed.daily_items+1]=item.item_id end end
    elseif kind=="benefit_claim" then
        local row=benefits.by_id[command.tier_id]
        if row and (row.track=="daily_time" or row.track=="daily_wins" or row.track=="weekly_time") then
            changed.benefit_claims={row.reward_id}
            for _,ids in ipairs({row.base_item_ids or {},row.pass_item_ids or {}}) do for _,id in ipairs(ids) do add(id) end end
        else changed.unrelated=true end
    elseif kind=="clear" or kind=="standard_clear" or kind=="rich_clear" or kind=="cold_clear"
        or kind=="scourge_clear" or kind=="mode_clear" then
        changed.benefit_tracks=command.test_only and nil or {"daily_wins"}
        changed.unrelated=command.test_only and true or nil
    elseif kind=="lottery_draw" or kind=="lottery_read" or kind=="lottery_exchange" or kind=="challenge"
        or kind=="endless" or kind=="commerce_purchase" or kind=="redemption_redeem" then changed.unrelated=true
    elseif kind=="title_equip" or kind=="boss_kill" or kind=="building_upgrade" or kind=="work_upgrade"
        or kind=="welfare_reconcile" or kind=="starjoy_reconcile" or kind=="endless_reconcile"
        or kind=="vip_claim" or kind=="vip_purchase" or kind=="social_draw" or kind=="promotion"
        or kind=="commerce_catalog" then changed.unrelated=true
    else return {initialize=true} end
    local response=result and result.response
    if type(response)=="table" then
        for _,rows in ipairs({response.results or {},response.rewards or {},response.granted or {}}) do
            if type(rows)=="table" then for _,row in ipairs(rows) do if type(row)=="table" then add(row.id or row.item_id) end end end
        end
    end
    if kind=="challenge" or kind=="endless" or kind=="commerce_purchase" or kind=="redemption_redeem"
        or kind=="lottery_draw" and not (type(response)=="table" and type(response.results)=="table") then
        -- These command families may grant either of the two stackable rewards
        -- shown by this page. Refresh their direct keys, never all inventory.
        for _,id in ipairs(owned_dependencies) do add(id) end
    end
    if #inventory>0 then changed.inventory=inventory;changed.unrelated=nil end
    return changed
end
return M
