-- The actual service/adapter is exercised with an asynchronous fake provider.
-- No transactions, engine send, persistence or coupons are used.
package.path='scripts/vscripts/?.lua;'..package.path
local lookup=assert(loadfile('scripts/vscripts/config/generated/ui_static_catalog_lookup.lua'))()
local bulk_mode=arg and arg[1]=='bulk'
if bulk_mode then
 local f=assert(io.open('data/ui/lottery_catalog.json','rb'));local decoder=require('core/json_decoder')
 local seed=decoder.decode(f:read('*a'));f:close();local public=decoder.decode(seed.catalog_json)
 lookup.lottery_receipt={wire_version=1,pools={},duplicate_points={}}
 for _,pool in ipairs(public.snapshots)do
  local row={id=pool.selected_pool_id,items={}}
  for _,item in ipairs(pool.items)do row.items[#row.items+1]=item.id;lookup.lottery_receipt.duplicate_points[item.id]=item.duplicate_points or 0 end
  lookup.lottery_receipt.pools[#lookup.lottery_receipt.pools+1]=row
 end
end
package.loaded['config/generated/ui_static_catalog_lookup']=lookup
local handlers,subs,legacy,sent,commands,callbacks={},{},{},{},{},{}
local session='one';local open={};local profile_reads,http_reads=0,0
local catalog_reply,poll;local public_md5=require('config/generated/lottery_catalog_manifest').catalog_md5
-- Unrelated backend bundle changes may retain the same public lottery MD5.
-- This synthetic hash deliberately differs from the real seed configuration.
local backend_hash=string.rep('a',64)
local profiles={};for id=0,3 do profiles[id]={account_id=tostring(100+id),revision=1,mode='standard',match_session_id=session,
 save={content_inventory={lottery_ticket=100},archive={lottery_state={pools={}}},gameplay_stats={}}};open[id]={[201]=true}end
local function copy(v)if type(v)~='table'then return v end local o={}for k,c in pairs(v)do o[k]=copy(c)end return o end
package.loaded['core/event_bus']={handle_request=function(k,f)handlers[k]=f end,subscribe=function(k,f)subs[k]=f end,emit=function(k,p)if not p.catalog then legacy[#legacy+1]={k=k,p=p}end end}
local scheduled_retries=0
package.loaded['core/scheduler']={every=function(_,fn)poll=fn end,after=function()scheduled_retries=scheduled_retries+1;error('successful receipt must not wait for a retry timer')end}
package.loaded['systems/match_setup_service']={get_session_id=function()return session end,get_mode=function()return 'standard'end}
package.loaded['systems/player_profile_service']={get_account_profile=function(id)profile_reads=profile_reads+1;return copy(profiles[id])end,
 get_provider=function()return{resolve_account_id=function(id)return profiles[id].account_id end,
 lottery_catalog=function(_,done)catalog_reply=done end,
 lottery_snapshot=function()http_reads=http_reads+1;error('compact path must not request legacy snapshot')end}end}
local revisions={};local bulk_calls=0;local reject_next=false
package.loaded['ui/compact_ui_transport']={is_bound=function()return true end,is_open=function(id,view)return open[id]and open[id][view]or false end,
 bulk_lottery_enabled=function()return bulk_mode end,
 bulk_lottery_binding=function(id,view)return{epoch=1,base_revision=revisions[id..':'..view]or 1}end,
 publish_bulk_lottery=function(id,view,raw,token,binding)
  local key=id..':'..view;assert(binding.base_revision==(revisions[key]or 1)and binding.next_revision==binding.base_revision+1)
  if reject_next then reject_next=false;return nil,'native_send_failed'end
  revisions[key]=binding.next_revision;bulk_calls=bulk_calls+1
  sent[#sent+1]={player=id,view=view,raw=raw,token=token,recover=binding.on_failure};assert(#raw<200,'bounded synthetic ten receipt too large');return true
 end,
 publish=function(id,view,ops,settings)sent[#sent+1]={player=id,view=view,ops=copy(ops),full=settings and settings.full};return true end}
package.loaded['systems/archive_http_adapter']={submit=function(id,command,done,hash,capability)
 assert(capability==(command.kind=='lottery_draw'),'only compact draw may request committed profile response')
 commands[#commands+1]={id=id,command=command};callbacks[#commands]=done end}
local serial=0;DoUniqueString=function(prefix)serial=serial+1;return prefix..'_'..serial end
local service=require('systems/lottery_http_service');service.init()
local events=require('core/events');local config=require('config/lottery_config');local item=config.pools.map.items[1]
assert(#service.compact_open(0,'map')==3 and profile_reads==0,'unverified catalogue must stay unknown')
assert(not service.compact_draw(0,'map',1,1).ok and #commands==0)
assert(backend_hash~=require('config/generated/lottery_catalog_manifest').config_hash,'fixture must exercise different whole-bundle hashes')
catalog_reply({ok=true,catalog_md5=public_md5,config_hash=backend_hash,catalog_json='{}'})
for id=0,3 do local ops=assert(service.compact_open(id,'map'));assert(#ops>50)end
assert(profile_reads==4 and http_reads==0 and #legacy==0)
for i=1,1000 do assert(service.compact_open(0,'map'))end
assert(profile_reads==4,'cached view must not reread or copy account inventory')
for token=1,3 do
 local before_sent=#sent
 local result=service.compact_draw(0,'map',10,token);assert(result.pending and #commands==token)
 assert(not service.compact_draw(0,'map',10,token).ok and #commands==token,'duplicate token retried a transaction')
 local rows={};for i=1,10 do rows[i]={id=item.id,quality=item.quality,owned_count=i==1 and 0 or 1,duplicate=i>1,converted_points=i>1 and item.duplicate_points or 0}end
 profiles[0].revision=profiles[0].revision+1;profiles[0].save.content_inventory.lottery_ticket=100-token*10;profiles[0].save.content_inventory[item.id]=1
 callbacks[token]({ok=true,lottery_profile_applied=true,profile=copy(profiles[0]),response={ok=true,pool_id='map',count=10,results=rows,guarantee_quality='ssr',guarantee_satisfied=true}})
 assert(http_reads==0 and #legacy==0)
 local packet=sent[#sent];assert(packet.player==0 and packet.view==201)
 assert(#sent==before_sent+1,'one successful receipt must publish once')
 if bulk_mode then assert(packet.token==token and type(packet.raw)=='string' and bulk_calls==token)
 else local has_token=false;for _,op in ipairs(packet.ops)do if op.record==lookup.by_key['lottery:receipt']and op.field==lookup.field_by_name.request_token then assert(op.value==token);has_token=true end end;assert(has_token)end
end
assert(commands[1].command.id~=commands[2].command.id and commands[2].command.id~=commands[3].command.id)
assert(not bulk_mode or bulk_calls==3,'three successful draws require three single bulk receipts')
if bulk_mode then
 local receipt=sent[#sent];local before=#sent;assert(type(receipt.recover)=='function');receipt.recover()
 assert(#sent==before+1 and sent[#sent].full and #commands==3,'asynchronous failure must only republish committed state')
 open[0][201]=false;before=#sent;receipt.recover();assert(#sent==before,'closed recovery callback must not reopen');open[0][201]=true
end
-- Other players' model/nonce namespaces never share a transaction or receipt.
assert(service.compact_draw(1,'map',1,4).pending);assert(commands[4].id==1)
profiles[1].revision=2;profiles[1].save.content_inventory.lottery_ticket=99
local count=#sent;open[1][201]=false
callbacks[4]({ok=true,lottery_profile_applied=true,profile=copy(profiles[1]),response={ok=true,pool_id='map',count=1,results={{id=item.id,quality=item.quality,owned_count=0,duplicate=false,converted_points=0}},guarantee_satisfied=true}})
assert(#sent==count,'closed view sent a full result')
open[1][201]=true;local full=assert(service.compact_open(1,'map'));local found=false
for _,op in ipairs(full)do if op.record==lookup.by_key['lottery:receipt']and op.field==lookup.field_by_name.success then found=op.value==1 end end;assert(found,'closed completion lost the authoritative receipt')
-- Real service commands must send the production revision, rather than the
-- newer local display configuration's revision. Applied reads clear flags
-- immediately without another account/snapshot read or scheduled callback.
local manifest=require('config/generated/lottery_catalog_manifest')
local production_revision=manifest.pool_revisions.map
assert(production_revision~=config.pools.map.revision)
local reads_before=profile_reads
for _,action in ipairs({{code=2,name='details',state='details_revision',flag='update_unread'},
                         {code=3,name='notice',state='notice_revision',flag='notice_unread'}})do
 local index=#commands+1
 assert(service.compact_read(0,'map',action.code).pending)
 local command=commands[index].command
 assert(command.kind=='lottery_read'and command.read_action==action.name and command.revision==production_revision)
 profiles[0].revision=profiles[0].revision+1
 profiles[0].save.archive.lottery_state.pools.map=profiles[0].save.archive.lottery_state.pools.map or{}
 profiles[0].save.archive.lottery_state.pools.map[action.state]=production_revision
 callbacks[index]({ok=true,lottery_profile_applied=true,profile=copy(profiles[0]),response={ok=true}})
 local flag;for _,op in ipairs(sent[#sent].ops)do
  if op.record==lookup.by_key['lottery:pool:map']and op.field==lookup.field_by_name[action.flag]then flag=op.value end
 end;assert(flag==0,'read completion did not immediately clear '..action.flag)
end
assert(profile_reads==reads_before and http_reads==0 and #legacy==0 and scheduled_retries==0)
if bulk_mode then
 local index=#commands+1;reject_next=true
 assert(service.compact_draw(3,'map',1,77).pending)
 profiles[3].revision=2;profiles[3].save.content_inventory.lottery_ticket=99
 callbacks[index]({ok=true,lottery_profile_applied=true,profile=copy(profiles[3]),response={ok=true,pool_id='map',count=1,results={{id=item.id,quality=item.quality,owned_count=0,duplicate=false,converted_points=0}}}})
 assert(#commands==index and sent[#sent].ops and not reject_next,'synchronous send failure must fall back without a second command')
end
-- Slot/session reuse invalidates callbacks before any presentation publication.
local stale_index=#commands+1
assert(service.compact_draw(2,'map',1,5).pending);count=#sent;session='two';profiles[2].match_session_id='two';callbacks[stale_index]({ok=true,lottery_profile_applied=true,profile=copy(profiles[2]),response={ok=true}});assert(#sent==count)
poll();catalog_reply({ok=true,catalog_md5=string.rep('f',32),config_hash=backend_hash,catalog_json='{}'})
local invalid=assert(service.compact_open(0,'map'));assert(#invalid==3)
local error_code;for _,op in ipairs(invalid)do if op.field==lookup.field_by_name.error_code then error_code=op.value end end;assert(error_code==6)
assert(not service.compact_draw(0,'map',1,6).ok and #commands==stale_index,'mismatched public MD5 must not debit')
print('COMPACT_LOTTERY_SERVICE_PASS: mode='..(bulk_mode and 'bulk' or 'legacy_cw')..' bulk_receipts='..bulk_calls..'; 4players, 3 consecutive ten-draw fake receipts, unique original authority nonce, duplicate0transactions, production revision read2/immediate flags, closed retention, old-session rejection, zero retry timers/legacy/full HTTP requests')
