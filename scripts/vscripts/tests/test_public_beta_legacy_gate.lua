package.path='scripts/vscripts/?.lua;'..package.path
-- Explicit draft metadata is only used before the next strict Git catalogue
-- build. Exercise the actual modern subscribe closure and real legacy request
-- handlers; a mocked bound flag alone cannot authorize an old raw snapshot.
local L=require('config/generated/ui_static_catalog_lookup')
if not L.public_beta then
 local row=require('config/generated/archive_benefit_rewards').by_id.public_beta_login
 local sample=require('systems/archive_benefit_rewards').public_beta_snapshot({revision=0,save={}},1793307599)
 L.public_beta={ticket_id=sample.ticket_id,ticket_count=sample.ticket_count,ticket_name=sample.ticket_name,tier_id=row.reward_id,errors={'','claim_failed'}}
 for _,field in ipairs({{187,'source_revision_hi',2097151},{188,'public_beta_flags',31}})do
  assert(not L.fields[field[1]]);L.fields[field[1]]={id=field[1],name=field[2],kind='uint',min=0,max=field[3]};L.field_by_name[field[2]]=field[1]
 end
 for _,key in ipairs({'public_beta:state','public_beta:receipt'})do local id=#L.records+1;L.by_key[key]=id;L.records[id]={id=id,key=key,domain='public_beta',kind=key:match(':([^:]+)$')}end
end
local bound,handlers=false,{}
local T={available=function()return false end,is_bound=function()return bound end,is_open=function(_,view)return view==10 end,
 register_view=function(view,handler)handlers[view]=handler end,publish=function()error('unbound player must not receive compact publish')end}
package.loaded['ui/compact_ui_transport']=T
local file=assert(io.open('scripts/vscripts/tests/test_public_beta_gift.lua','rb'));local source=file:read('*a');file:close()
local prefix=assert(source:match('^(.-)local first=query%(0%)'))
local fixture=assert(loadstring(prefix..[[
return{archive=archive,packets=packets,listeners=listeners,accounts=accounts,
 profile=profile}
]]))()
local archive=fixture.archive;local handles={[0]={id=0},[1]={id=1}}
PlayerResource.GetPlayer=function(_,id)return handles[id]end
local function count()local n=0;for _,packet in ipairs(fixture.packets)do if packet.name=='survival_public_beta_gift_snapshot'then n=n+1 end end;return n end
local function old_request()fixture.listeners.survival_public_beta_gift_request(nil,{PlayerID=0})end
assert(handlers[10],'actual modern view must be registered')
local before=count();archive.send_public_beta_gift(0);assert(count()==before,'unsolicited server push never activates raw legacy delivery')
bound=true;assert(handlers[10].snapshot(0));bound=false
before=count();archive.send_public_beta_gift(0);assert(count()==before,'actual modern subscription cannot authorize pre-Hello/raw fallback')
old_request();assert(count()==before+1,'actual legacy request on this handle remains supported')
bound=true;assert(handlers[10].snapshot(0));bound=false;before=count()
archive.send_public_beta_gift(0);assert(count()==before,'switching to modern retires an earlier legacy subscription on the same handle')
old_request();assert(count()==before+1)
handles[0]={id='replacement'};before=count()
require('core/event_bus').emit(require('core/events').PLAYER_PROFILE_CHANGED,{player_id=0})
archive.send_public_beta_gift(0);assert(count()==before,'replacement handle cannot inherit a previous legacy subscription')
old_request();assert(count()==before+1,'replacement may explicitly subscribe using its own real request')
before=count();require('core/event_bus').emit(require('core/events').PLAYER_DISCONNECTED,{player_id=0})
require('core/event_bus').emit(require('core/events').PLAYER_PROFILE_CHANGED,{player_id=0})
archive.send_public_beta_gift(0);assert(count()==before,'disconnect clears modern and legacy push registrations even when the engine handle persists')
old_request();assert(count()==before+1)
archive.init();before=count();archive.send_public_beta_gift(0);assert(count()==before,'archive reset clears raw subscriptions')
bound=true;old_request();bound=false;archive.send_public_beta_gift(0);assert(count()==before,'bound modern client cannot use the legacy request to arm fallback')
old_request();assert(count()==before+1,'real legacy request remains usable after reset')
print('PASS beta legacy gate: actual modern Open, explicit legacy request, pre-Hello fallback0, profile handle reuse0, disconnected handle0, reset0')
