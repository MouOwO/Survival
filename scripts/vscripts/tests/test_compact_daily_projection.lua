-- Real daily/benefit configuration and legacy projectors; synthetic accounts.
package.path="scripts/vscripts/?.lua;"..package.path
local json=require("core/json_encoder")
local lookup=assert(loadfile("scripts/vscripts/config/generated/ui_static_catalog_lookup.lua"))()
local daily=require("systems/archive_daily_rewards")
local benefits=require("systems/archive_benefit_rewards")
local calendar=require("systems/archive_calendar")
local stackables=require("systems/archive_stackable_items")
local rules=require("config/generated/archive_daily_rules").by_id.default
local items=require("config/generated/archive_daily_items")
local day,now=25000,25000*86400
calendar.set_clock(function() return now end)
local legacy_daily,legacy_benefits=daily.snapshot,benefits.snapshot
local legacy_calls=0
daily.snapshot=function(...) legacy_calls=legacy_calls+1;return legacy_daily(...) end
benefits.snapshot=function(...) legacy_calls=legacy_calls+1;return legacy_benefits(...) end
local module=require("ui/compact_daily_projection")
local adapter=assert(module.new(lookup))
local F,R=lookup.field_by_name,lookup.by_key
local state_id=assert(R["daily:state"])
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for key,child in pairs(value) do out[key]=copy(child) end;return out
end
local function profile(account,inventory_size)
    local out={account_id=account or "synthetic_0",mode="standard",match_session_id="synthetic_daily_projection",
        revision=1,entitlements={},save={content_inventory={},archive={daily_rewards={first_day=day-10,count=8,
            claimed={[tostring(day-2)]=true},item_counts={daily_growth_gem=1,daily_wealth_talisman=1}},
            benefits={days={[tostring(day)]={seconds=1799,wins=0,claimed={}}},
                weeks={[tostring(benefits.week(now))]={seconds=7199,claimed={}}}}}}}
    for index=1,inventory_size or 0 do out.save.content_inventory["irrelevant_"..index]=index end
    out.save.content_inventory.welfare_zongzi=stackables.definition("welfare_zongzi").max_owned-1
    out.save.content_inventory.lottery_ember_of_legacy=3
    return out
end
local ctx={now=now,pending=false,purchase_enabled=true}
local source=profile(nil,10000)
local state,initial=assert(adapter.initialize(source,ctx))
assert(legacy_calls==0,"compact adapter called the full legacy snapshot")
local initial_metrics=copy(state.inspect().metrics)
assert(initial_metrics.inventory_entries_scanned==10002 and initial_metrics.daily_item_reads==12)
local model={}
local function apply(ops)
    for _,op in ipairs(ops) do
        assert(type(op.record)=="number" and type(op.field)=="number")
        assert(op.remove==true or type(op.value)=="number","wire contains dynamic text/static metadata")
        model[op.record]=model[op.record] or {};model[op.record][op.field]=op.remove and nil or op.value
    end
end
local function read(key,name)
    local row=model[R[key]];return row and row[F[name]]
end
local function big(key,name)
    local low=read(key,name);return low and low+(read(key,name.."_hi") or 0)*4294967296 or nil
end
apply(initial)
local unique={};for _,item in ipairs(items.rows) do if item.enabled~=false then
    unique[#unique+1]={id=item.item_id,record=R["daily:item:"..item.item_id]}
end end
table.sort(unique,function(a,b) return a.record<b.record end)
local function reconstruct()
    local count,claimed=big("daily:state","count"),read("daily:state","completed")==1
    local today,pass=read("daily:state","day"),read("daily:state","has_pass")==1
    local empty={revision=0,save={archive={},content_inventory={}},entitlements={}}
    local out=legacy_daily(empty,today,false)
    out.benefits=legacy_benefits(empty,false,ctx.now)
    local owned,mask={},read("daily:state","unique_owned_mask")
    for index,item in ipairs(unique) do owned[item.id]=math.floor(mask/2^(index-1))%2 end
    local anchor=math.max(0,count-(claimed and 1 or 0))
    out.count,out.claimed,out.today=count,claimed and 1 or 0,today
    out.current_day=(claimed and math.max(0,count-1) or count)%7+1
    out.period_id=tostring(math.floor(anchor/7));out.next_day=count%7+1
    out.calendar_start_count=math.floor(anchor/28)*28;out.calendar_current_day=anchor-out.calendar_start_count+1
    out.has_pass=pass and 1 or 0;out.expires_at=read("daily:state","expires_at")
    out.expires_at=out.expires_at~=nil and tostring(out.expires_at) or ""
    out.pending=read("daily:state","pending");out.purchase_enabled=read("daily:state","enabled")
    out.ok=true;out.ordinary_status=claimed and "claimed" or "claimable"
    local function ownership(rewards) for _,item in ipairs(rewards) do item.owned_count=owned[item.id] end end
    for _,row in ipairs(out.cycle) do
        row.status=row.day<out.current_day and "claimed" or row.day==out.current_day and (claimed and "claimed" or "claimable") or "not_open"
        row.is_today=row.day==out.current_day and 1 or 0;ownership(row.rewards)
    end
    for _,row in ipairs(out.calendar28) do
        row.absolute_count=out.calendar_start_count+row.day
        row.status=row.day<out.calendar_current_day and "claimed" or row.day==out.calendar_current_day and (claimed and "claimed" or "claimable") or "not_open"
        row.is_today=row.day==out.calendar_current_day and 1 or 0;ownership(row.rewards)
    end
    for _,row in ipairs(out.specials) do row.owned,row.owned_count=owned[row.id],owned[row.id] end
    out.missed={};local missed=read("daily:state","missed_mask")
    assert(missed<2^29,"unused high makeup bit must never be set")
    for offset=29,1,-1 do if math.floor(missed/2^(offset-1))%2==1 then out.missed[#out.missed+1]=today-offset end end
    out.benefits.has_pass=pass and 1 or 0
    local current_week=math.floor((today+3)/7)
    out.benefits.refresh_at=(today+1)*86400-10800
    out.benefits.weekly_refresh_at=((current_week+1)*7-3)*86400-10800
    for _,track in ipairs({"daily_time","daily_wins","weekly_time"}) do
        local key="daily:track:"..track;local group=out.benefits[track]
        group.progress=big(key,"progress");group.period_id=tostring(read(key,"period"))
        for _,row in ipairs(group.rows) do
            local rec="daily:benefit:"..row.id;local status=read(rec,"status")
            row.status=({[1]="locked",[2]="claimable",[3]="claimed"})[status]
            row.can_claim=read(rec,"can_claim")
            local reserved={}
            for _,rewards in ipairs({row.base_rewards,row.monthly_rewards}) do for _,item in ipairs(rewards) do
                local definition=stackables.definition(item.id)
                if definition then
                    local amount=assert(big("archive:points:"..definition.id,"owned_count"))
                    item.owned_count=amount
                    local accepted=item.count
                    if definition.max_owned>0 then
                        accepted=math.min(item.count,math.max(0,definition.max_owned-amount-(reserved[item.id] or 0)))
                        reserved[item.id]=(reserved[item.id] or 0)+accepted
                    end
                    item.actual_count,item.overflow_count=accepted,item.count-accepted
                    item.at_max_owned=definition.max_owned>0 and amount>=definition.max_owned and 1 or 0
                end
            end end
        end
    end
    return out
end
local function expected()
    local pass=calendar.has_pass(source)
    local out=legacy_daily(source,day,pass);out.benefits=legacy_benefits(source,pass,ctx.now)
    out.ok=true;out.pending=ctx.pending and 1 or 0;out.purchase_enabled=ctx.purchase_enabled and rules.purchase_enabled and 1 or 0
    return out
end
local function matches()
    local rebuilt,original=reconstruct(),expected()
    assert(json.encode(rebuilt)==json.encode(original),"compact model differs from the real daily/benefit projectors")
    return original
end
local first_expected=matches()
local initial_json_bytes=#json.encode(first_expected)
legacy_calls=0
for _=1,120 do
    ctx.now=ctx.now+1;now=ctx.now
    local ops,metrics=assert(state.update(source,{},ctx));assert(#ops==0 and metrics.inventory_entries_scanned==0
        and metrics.tier_evaluations==0 and metrics.track_reads==0 and metrics.daily_item_reads==0 and metrics.missed_day_reads==0)
end
assert(legacy_calls==0)
local base_ops=copy(initial)
local function update(changes)
    source.revision=source.revision+1
    local ops,metrics=assert(state.update(source,changes,ctx));apply(ops);return ops,metrics
end
source.save.archive.benefits.days[tostring(day)].seconds=1800
local threshold_ops,threshold_metrics=update({benefit_tracks={"daily_time"}})
assert(#threshold_ops==3 and threshold_metrics.tier_evaluations==1 and threshold_metrics.track_reads==1)
local threshold_expected=matches()
source.save.archive.benefits.days[tostring(day)].seconds=1860
local minute_ops,minute_metrics=update({benefit_tracks={"daily_time"}})
assert(#minute_ops==1 and minute_metrics.tier_evaluations==0 and minute_metrics.inventory_entries_scanned==0)
matches()
source.save.content_inventory.welfare_zongzi=source.save.content_inventory.welfare_zongzi+2
local ownership_ops,ownership_metrics=update({inventory={"welfare_zongzi","welfare_zongzi"}})
assert(#ownership_ops==1 and ownership_metrics.inventory_index_reads==1 and ownership_metrics.inventory_entries_scanned==0)
matches()
source.entitlements.archive_pass={active=true,expires_at=ctx.now+1}
local pass_ops,pass_metrics=update({entitlement=true})
assert(pass_metrics.tier_evaluations==1);matches()
ctx.now=ctx.now+1;now=ctx.now
local expired_ops,expired_metrics=assert(state.update(source,{},ctx));apply(expired_ops)
assert(expired_metrics.tier_evaluations==1 and read("daily:state","has_pass")==0);matches()

-- ACKs describe an existing local intent; an optimistic OK cannot alter counts,
-- item ownership or the saved tier state, nor claim success before persistence.
assert(state.bind_intent(1,{kind="daily",target_day=day}))
local count_before=big("daily:state","count")
local optimistic=assert(state.ack(1,{ok=true},source,{pending=false}));apply(optimistic)
assert(read("daily:ack:claim","success")==0 and read("daily:ack:claim","pending")==1
    and read("daily:ack:claim","error_code")==10 and big("daily:state","count")==count_before)
source.save.archive.daily_rewards.claimed[tostring(day)]=true;source.save.archive.daily_rewards.count=9
local claimed_ops=update({daily_state=true,daily_claimed_days={day}})
matches()
local confirmed=assert(state.ack(1,{ok=true,terminal=true},source,{pending=false}));apply(confirmed)
assert(read("daily:ack:claim","success")==1 and read("daily:ack:claim","terminal")==1)
assert(#assert(state.ack(1,{ok=true},source,{pending=false}))==0,"duplicate final ACK must emit nothing")
assert(state.bind_intent(2,{kind="benefit",tier_id="daily_time_30"}))
source.save.archive.benefits.days[tostring(day)].claimed.daily_time_30=true
local tier_ops,tier_metrics=update({benefit_claims={"daily_time_30"}})
assert(tier_metrics.tier_evaluations==1);matches()
local benefit_ack=assert(state.ack(2,{ok=true},source,{pending=false}));apply(benefit_ack)
assert(read("daily:ack:benefit","success")==1 and read("daily:ack:benefit","target_record")==R["daily:benefit:daily_time_30"])
assert(state.bind_intent(3,{kind="daily",target_day=day-1}))
local failed=assert(state.ack(3,{ok=false,terminal=true,error="synthetic private backend detail"},source,{pending=false}));apply(failed)
assert(read("daily:ack:claim","error_code")==1 and read("daily:ack:claim","success")==0)
for _,op in ipairs(failed) do assert(type(op.value)=="number" or op.remove) end
local before=json.encode(state.full_ops())
local bad,error_message=state.update(source,{daily_items={"unknown"}},ctx)
assert(bad==nil and error_message=="daily_unique_item_unknown" and json.encode(state.full_ops())==before)

local other=assert(adapter.initialize(profile("synthetic_1",0),ctx))
local other_before=json.encode(other.full_ops())
source.save.archive.daily_rewards.item_counts.daily_attack_gem=1
local unrelated=update({unrelated=true});assert(#unrelated==0 and json.encode(other.full_ops())==other_before)
source.save.archive.daily_rewards.count=4294967296+7
local large_count=update({daily_state=true});assert(big("daily:state","count")==4294967296+7);matches()
now=ctx.now+86400;ctx.now=now;day=math.floor((now+10800)/86400)
local reset_ops,reset_metrics=assert(state.update(source,{},ctx));apply(reset_ops)
assert(reset_metrics.missed_day_reads==29 and reset_metrics.track_reads==3);matches()
local unknown,unknown_ops=assert(adapter.initialize(nil,ctx))
assert(#unknown_ops==1 and unknown_ops[1].value==0 and not unknown.inspect().known)
assert(legacy_calls==0,"adapter must never call full projectors; reference calls bypass wrappers")
local online_changes=module.command_changes({kind="online_checkpoint"},{})
assert(#online_changes.benefit_tracks==2 and not online_changes.initialize and not online_changes.inventory)
local claim_changes=module.command_changes({kind="daily_claim",target_day=day},{})
assert(#claim_changes.daily_items==12 and claim_changes.daily_claimed_days[1]==day)
local benefit_changes=module.command_changes({kind="benefit_claim",tier_id="daily_time_150"},{})
assert(#benefit_changes.inventory==2 and benefit_changes.benefit_claims[1]=="daily_time_150")
assert(module.command_changes({kind="unrecognized_full_replacement"},{}).initialize)
local profile_module=package.loaded["systems/player_profile_service"]
local transport_context=require("ui/compact_profile_context")
local context_seen,completions=0,0
local fake_provider={resolve_account_id=function() return "synthetic_context" end,
    archive_submit=function(request,done)
        assert(request.command.kind=="online_checkpoint")
        done({ok=true,profile={account_id="synthetic_context"}})
    end}
package.loaded["systems/player_profile_service"]={get_provider=function() return fake_provider end,
    apply_snapshot=function(id,snapshot,reason)
        local frame=assert(transport_context.current(id))
        assert(frame.source=="archive_command" and frame.command.kind=="online_checkpoint"
            and #frame.compact_daily_changes.benefit_tracks==2 and reason=="archive_online_checkpoint")
        context_seen=context_seen+1;return {ok=true}
    end}
package.loaded["systems/archive_http_adapter"]=nil
require("systems/archive_http_adapter").submit(0,{kind="online_checkpoint"},function(result)
    assert(result.ok and transport_context.current(0)==nil);completions=completions+1
end)
assert(context_seen==1 and completions==1 and transport_context.current(0)==nil)
package.loaded["systems/player_profile_service"]=profile_module
local result={status="PASS_REAL_COMPACT_DAILY_PROJECTION_SYNTHETIC",schema_sha256=lookup.sha256,
    initial_ops=#initial,initial_legacy_json_bytes=initial_json_bytes,initial_inventory_entries=initial_metrics.inventory_entries_scanned,
    stable_seconds=120,stable_legacy_snapshot_calls=legacy_calls,minute_delta_ops=#minute_ops,threshold_delta_ops=#threshold_ops,
    one_inventory_change_scans=ownership_metrics.inventory_entries_scanned,one_inventory_change_reads=ownership_metrics.inventory_index_reads,
    failed_ack_generic=true,optimistic_ack_does_not_award=true,full_renderer_business_equality=true,
    authoritative_apply_context_scoped=true,
    native_calls=0,sdk_calls=0,http_calls=0,persistence_calls=0}
if arg and arg[1]=="emit" then
    result.initial_ops_fixture=base_ops;result.initial_expected=first_expected;result.threshold_ops_fixture=threshold_ops
    result.threshold_expected=threshold_expected;result.error_text={}
    for code,text in pairs(module.error_text) do result.error_text[tostring(code)]=text end
end
print(json.encode(result))
