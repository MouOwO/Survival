package.path='scripts/vscripts/?.lua;'..package.path
-- Reuse the real archive/provider fixture setup, stopping before its legacy
-- assertions. All reward/receipt/profile code below is the shipping service.
local file=assert(io.open('scripts/vscripts/tests/test_public_beta_gift.lua','rb'));local text=file:read('*a');file:close()
local prefix=assert(text:match('^(.-)local first=query%(0%)'),'public_beta_fixture_boundary_changed')
local setup=assert(loadstring(prefix..[[
return{archive=archive,requests=requests,accounts=accounts,copy=copy,profile=profile,tasks=tasks,
 advance=function(seconds)timestamp=timestamp+seconds;game_time=game_time+1 end,
 cloud=function(value)cloud=value end,writes=function()return writes end,
 setprofile=function(id,value)accounts[id]=value end,
}
]]))()
local L=require('config/generated/ui_static_catalog_lookup');local draft=not L.public_beta
local row=require('config/generated/archive_benefit_rewards').by_id.public_beta_login
if draft then
 local sample=require('systems/archive_benefit_rewards').public_beta_snapshot(setup.accounts[0],1793307599)
 L.public_beta={ticket_id=sample.ticket_id,ticket_count=sample.ticket_count,ticket_name=sample.ticket_name,tier_id=row.reward_id,config=setup.copy(row),errors={'','claim_failed'}}
 assert(not L.fields[187]);L.fields[187]={id=187,name='source_revision_hi',kind='uint',min=0,max=2097151};L.field_by_name.source_revision_hi=187
 assert(not L.fields[188]);L.fields[188]={id=188,name='public_beta_flags',kind='uint',min=0,max=31};L.field_by_name.public_beta_flags=188
 for _,key in ipairs({'public_beta:state','public_beta:receipt'})do local id=#L.records+1;L.by_key[key]=id;L.records[id]={id=id,key=key,domain='public_beta',kind=key:match(':([^:]+)$')}end
end
local handlers,sent,results={}, {},{}
local handles={[0]={id=0},[1]={id=1}}
PlayerResource.GetPlayer=function(_,id)return handles[id]end
local open,alive=true,true
local T={register_view=function(view,handler)assert(view==10);handlers[10]=handler end,is_open=function()return open end,is_bound=function()return true end,
 publish=function(id,view,ops,opts)sent[#sent+1]={id=id,ops=setup.copy(ops),full=opts.full};return{queued=true}end}
local factory=require('ui/compact_public_beta_view')
local bridge
local function snapshot(id,profile)
 local value=setup.archive.public_beta_gift_snapshot(id,profile);value.claim_result=results[id];return value
end
local function create()
 return factory.new({lookup=L,transport=T,current=function()return alive end,player=function(id)return handles[id]end,
  snapshot=snapshot,config=function()return row end,
  claim=function(id,nonce)local result=setup.archive.public_beta_gift_claim(id,nonce);results[id]=result;return result end})
end
bridge=create()
setup.archive.send_public_beta_gift=function(id,result,profile)if result then results[id]=result end;return bridge.changed(id,result,profile)end
local initial=handlers[10].snapshot(0)
local initial_day=setup.archive.public_beta_gift_snapshot(0).day_key
local count=#sent;for n=1,1000 do bridge.changed(0)end;assert(#sent==count,'unchanged source sequence/revision alone cannot cause repeated snapshots')
assert(setup.writes()==0,'opening and repeated reads never grant inventory')
local intent={request_token=1,session_token=41}
assert(handlers[10].intent(0,'public_beta_claim',intent));local claimed=sent[#sent].ops
assert(setup.accounts[0].save.content_inventory.special_lottery_ticket==2 and setup.writes()==1)
assert(handlers[10].intent(0,'public_beta_claim',intent));assert(setup.writes()==1,'wire replay cannot submit another claim')
local recovery=handlers[10].snapshot(0)
-- Client-supplied item/count/day/account fields are not part of this handler;
-- the same immutable original session+public_beta_gift+serverday operation is
-- sent to the real reducer/backend adapter.
setup.advance(86400);setup.cloud(true)
local next_day=handlers[10].snapshot(0)
assert(handlers[10].intent(0,'public_beta_claim',{request_token=2,session_token=41,arg_a=999999,arg_b=999999,arg_c=999999}))
assert(#setup.requests==1);local waiting=sent[#sent].ops
local request=setup.requests[1];assert(request.command.track=='public_beta_login'and request.command.tier_id=='public_beta_login')
assert(not request.command.count and not request.command.ticket_id and request.command.id:match(':public_beta_gift:%d+$'))
local day=setup.archive.public_beta_gift_snapshot(0).day_key
request.complete({ok=true,terminal=true,response={ok=true,track='public_beta_login',tier_id='public_beta_login',period_id=day,rewards={{id='special_lottery_ticket',count=2}}}})
assert(setup.archive.public_beta_gift_snapshot(0).claim_pending==1,'ACK without applied profile stays pending')
local ack_only=sent[#sent].ops
setup.tasks.archive_retry();local retry=setup.requests[#setup.requests];assert(retry.command.id==request.command.id,'backend retry keeps the exact original operation')
local fresh=setup.profile('100');fresh.revision=9007199254740991;fresh.save.content_inventory.special_lottery_ticket=4
fresh.save.archive={benefits={days={[day]={claimed={public_beta_login={at=1793307599+86400}}}}}}
setup.setprofile(0,fresh)
retry.complete({ok=true,terminal=true,profile=setup.copy(fresh),response={ok=true,track='public_beta_login',tier_id='public_beta_login',period_id=day,rewards={{id='special_lottery_ticket',count=2}}}})
local terminal=sent[#sent].ops;assert(setup.archive.public_beta_gift_snapshot(0).claim_pending==0)
local terminal_full=handlers[10].snapshot(0)
-- The exact fixed award structure is checked against the actual current
-- server config, independently of the DTO's hardcoded display count.
local previous=row.base_counts[1];row.base_counts[1]='3';local writes=setup.writes();local requests=#setup.requests
assert(handlers[10].intent(0,'public_beta_claim',{request_token=3,session_token=41}));assert(setup.writes()==writes and #setup.requests==requests)
local bad_config=handlers[10].snapshot(0);row.base_counts[1]=previous
local F,R=L.field_by_name,L.by_key
local function value(ops,key,name)for _,op in ipairs(ops)do if op.record==R[key]and op.field==F[name]then return op.value end end end
assert(value(bad_config,'public_beta:state','known')==0,'mismatched actual reward config fails closed')
-- Reset/rebuild in the same Lua/world cannot reuse its prior archive-login
-- display alias. It never changes the original archive operation ID.
local period=value(terminal_full,'public_beta:state','period')
setup.archive.init();results={};bridge.reset();local restarted=handlers[10].snapshot(0)
assert(value(restarted,'public_beta:state','period')>period,'archive reload uses a module-lifetime monotonic alias')
-- Closed views stop streaming; authoritative receipts remain in archive and
-- are recovered by a later Open rather than resubmitting a consume action.
open=false;count=#sent;bridge.changed(0);assert(#sent==count);open=true
bridge.disconnect(0);count=#sent;local before_disconnect_writes=setup.writes()
assert(bridge.inspect(0).retired)
assert(bridge.changed(0));assert(#sent==count,'late profile cannot stream even if a stale transport view still reports bound/open')
assert(not handlers[10].intent(0,'public_beta_claim',{request_token=4,session_token=41}));assert(setup.writes()==before_disconnect_writes,'retired connection cannot execute a late consume')
assert(handlers[10].snapshot(0));assert(not bridge.inspect(0).retired,'an explicit authenticated Open can rebind after reconnect')
local wire=require('ui/compact_wire');local schema=assert(wire.compile_lookup(L,1))
local function metrics(ops,full)
 for _,op in ipairs(ops)do assert(op.remove or type(op.value)=='number','no runtime string/identity/catalogue may enter the compact operation list')end
 local packets=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=41,epoch=1,view=10},1,ops,{full=full,value_budget=24}))
 local total,max=0,0;for _,packet in ipairs(packets)do assert(#packet.d<=24);local size=25+#packet.d;total=total+size;max=math.max(max,size)end
 return{frames=#packets,calibrated_native_bytes=total,max_calibrated_native_bytes=max,actual_native_measurement=false}
end
local output={draft_registry=draft,seed=L.public_beta,fields=L.fields,records=L.records,initial=initial,claimed=claimed,recovery=recovery,next_day=next_day,waiting=waiting,ack_only=ack_only,terminal=terminal,terminal_full=terminal_full,restarted=restarted,
 initial_day=initial_day,terminal_day=day,revision_exact='9007199254740991',metrics={initial=metrics(initial,true),claim=metrics(claimed,false),recovery=metrics(terminal_full,true)}}
if arg and arg[1]=='emit'then print(require('core/json_encoder').encode(output))else print('PASS compact beta: real archive/reducer, ACK/profile gate, fixed award config, retry operation, uint53, stable1000, sameworld reload, closed view')end
