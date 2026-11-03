-- Real retained service + event_bus.reset; asynchronous provider/native sends
-- are deterministic seams. No player transaction, HTTP or SDK call is made.
local file=assert(io.open('scripts/vscripts/tests/test_compact_lottery_service.lua','rb'))
local text=file:read('*a');file:close()
local marker="local service=require('systems/lottery_http_service');service.init()"
local at=assert(text:find(marker,1,true))
local prefix=text:sub(1,at-1)
local body=[=[
package.loaded['core/test_access_policy']={enabled=function()return false end,enforce=function()return true end}
package.loaded['core/event_bus']=nil
local bus=require('core/event_bus')
local service=require('systems/lottery_http_service')
local events=require('core/events')
service.init()
local first_catalog_reply=catalog_reply
assert(first_catalog_reply)
service.init();assert(catalog_reply==first_catalog_reply,'same-world init must not reregister or rerequest')
first_catalog_reply({ok=true,catalog_md5=public_md5,config_hash=backend_hash,catalog_json='{}'})
assert(#assert(service.compact_open(0,'map'))>50)
local original_poll=poll
bus.reset()
local lost,reason=bus.request(events.LOTTERY_CATALOG_REQUEST,{})
assert(lost==nil and reason:find('no_request_handler',1,true))
service.init()
local second_catalog_reply=catalog_reply
assert(second_catalog_reply~=first_catalog_reply,'new world must authenticate its own catalogue')
local unknown=assert(service.compact_open(0,'map'));assert(#unknown==3)
local before=profile_reads
first_catalog_reply({ok=true,catalog_md5=public_md5,config_hash=backend_hash,catalog_json='{}'})
assert(#assert(service.compact_open(0,'map'))==3 and profile_reads==before,
 'old catalogue completion cannot unlock the new world')
original_poll();assert(catalog_reply==second_catalog_reply,'old scheduled poll must be inert')
second_catalog_reply({ok=true,catalog_md5=public_md5,config_hash=backend_hash,catalog_json='{}'})
assert(#assert(service.compact_open(0,'map'))>50)
local replied=false
assert(bus.request(events.LOTTERY_CATALOG_REQUEST,{md5=public_md5,complete=function(result)replied=result.ok==true end}).pending)
assert(replied,'the new real event bus must contain the catalogue request handler')
profiles[0].revision=2;profiles[0].save.content_inventory.lottery_ticket=84
before=profile_reads;sent={};bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,revision=2})
assert(#sent>0,'new-world profile subscription must refresh the active compact pool')
local ticket_updated=false
for _,packet in ipairs(sent) do for _,op in ipairs(packet.ops) do
 if op.record==lookup.by_key['lottery:pool:map'] and op.field==lookup.field_by_name.tickets then ticket_updated=op.value==84 end
end end
assert(ticket_updated and profile_reads==before+1,'a true unclassified replacement must read the authoritative account once')
before=profile_reads;local sends=#sent
for _=1,1000 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,revision=2}) end
assert(profile_reads==before and #sent==sends,'same-revision repeats must not copy accounts or publish')
assert(#commands==0 and http_reads==0 and #legacy==0)
-- Unsupported memory providers return a typed unknown view before any account
-- read, instead of calling a missing HTTP method or manufacturing ownership.
bus.reset()
package.loaded['systems/player_profile_service'].get_provider=function()
 return {resolve_account_id=function(id)return profiles[id].account_id end}
end
service.init();before=profile_reads
assert(#assert(service.compact_open(0,'map'))==3 and profile_reads==before)
assert(not service.compact_draw(0,'map',1,9).ok and #commands==0)
print('COMPACT_LOTTERY_LIFECYCLE_PASS: real bus.reset, new handlers/profile subscription, stale callbacks inert, unsupported provider known0/0transactions')
]=]
assert(loadstring(prefix..'\n'..body,'@real_compact_lottery_lifecycle'))()
