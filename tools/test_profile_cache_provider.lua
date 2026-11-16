package.path='scripts/vscripts/?.lua;'..package.path
local json=require('core/json_decoder');local enc=require('core/json_encoder');local cache=require('systems/http_profile_cache')
local data=json.decode(io.read('*a'))
local function eq(a,b)
 if a==json.null or b==json.null then return a==b end
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not eq(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local real_wire=require('systems/business_wire')
assert(real_wire.schema_hash()~=nil,'real encrypted catalogue not loaded')
local wirefull=assert(real_wire.decode(data.wire_full_a));local wirevalue,wirebase=cache.decode(wirefull)
assert(eq(wirevalue,data.a)and wirebase)
local wirehit=assert(real_wire.decode(data.wire_same_a));local restored=assert(cache.decode(wirehit,wirebase));assert(eq(restored,data.a))
local value,baseline=cache.decode(data.full_a,nil);assert(eq(value,data.a)and baseline)
local restored,samebase=cache.decode(data.same_a,baseline);assert(eq(restored,data.a)and samebase==baseline)
restored.save.gameplay_stats.attack=999;assert(baseline.snapshot.save.gameplay_stats.attack==0)
assert(cache.header(baseline)=='v1:'..data.full_a._hp[2])
local missing,_,why=cache.decode(data.same_a,nil);assert(missing==nil and why=='http_profile_cache_miss')
for _,marker in ipairs({{1,'bad',1},{true,data.full_a._hp[2],1},{1,data.full_a._hp[2],2},{1,data.full_a._hp[2],1,4}})do
 local v,_,err=cache.decode({_hp=marker},baseline);assert(v==nil and err=='http_profile_cache_invalid')
end
local oversized={};for k,v in pairs(data.a)do oversized[k]=v end;oversized.pad=string.rep('x',200000);oversized._hp={1,data.full_a._hp[2],0};local v,large=cache.decode(oversized);assert(v and large==nil)
local seeded,seedbase=cache.seed(json.decode(enc.encode(data.seed_b)));assert(eq(seeded,data.checkpoint_b)and seedbase)
local seedwire=assert(real_wire.decode(data.wire_seed_b));local seedwirevalue=assert(cache.seed(seedwire));assert(eq(seedwirevalue,data.checkpoint_b))
seeded.profile.save.gameplay_stats.attack=999;assert(seedbase.snapshot.save.gameplay_stats.attack==0)
for _,marker in ipairs({{true,data.full_a._hp[2],2},{1,'bad',2},{1,data.full_a._hp[2],1},{1,data.full_a._hp[2],2,4}})do
 local malformed=json.decode(enc.encode(data.checkpoint_a));malformed._hp=marker;local original,nextstate=cache.seed(malformed);assert(eq(original,data.checkpoint_a)and nextstate==nil)
end
local clock_ms=1000
function GetSystemTimeMS()return clock_ms end
local game_mode_override
local session,mode,token='test-match-session-123','standard','token-A';local requests={};local delivered={};local errors={}
package.loaded['config/generated/fishing_system_rules']={rows={{enabled=true,api_base_url='http://synthetic.invalid'}}}
package.loaded['debug/mode_unlock_test']={is_enabled=function()return false end}
package.loaded['systems/workshop_connection']={resolve=function()return 'http://synthetic.invalid',token end,failure=function(v,fallback)return fallback end}
package.loaded['systems/player_web_auth']={enabled=function()return false end}
package.loaded['systems/business_wire']={schema_hash=function()return nil end,decode=function(v)return v end}
package.loaded['systems/match_setup_service']={is_mode_selected=function()return true end,get_session_id=function()return session end,get_mode=function()return game_mode_override or mode end,get_profile_mode=function()return mode end}
function CreateHTTPRequestScriptVM(method,url)
 local r={method=method,url=url,headers={}}
 function r:SetHTTPRequestHeaderValue(k,v)self.headers[k]=v end
 function r:SetHTTPRequestRawPostBody(_,v)self.body=v end
 function r:SetHTTPRequestAbsoluteTimeoutMS(v)self.timeout_ms=v end
 function r:Send(cb)self.callback=cb;requests[#requests+1]=self end
 return r
end
local provider=require('systems/player_profile_providers/http_fishing_provider');provider.init()
local function fetch(account)provider.fetch_snapshot(account or data.a.account_id,function(v)delivered[#delivered+1]=v end,function(e)errors[#errors+1]=e end);return requests[#requests]end
local function respond(r,value)r.callback({StatusCode=200,Body=enc.encode(value)})end
local r=fetch();assert(r.url:find('/v1/session/login',1,true));respond(r,data.a)
r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1');respond(r,data.full_a)
r=fetch();assert(r.headers['X-Survival-Profile-Cache']==cache.header(baseline));respond(r,data.same_a);assert(eq(delivered[#delivered],data.a))
-- UI mutation cannot change the next pinned baseline.
delivered[#delivered].save.gameplay_stats.attack=123;r=fetch();respond(r,data.same_a);assert(delivered[#delivered].save.gameplay_stats.attack==0)
-- Older request finishing after a newer full reply cannot roll the cache back.
local first=fetch();local second=fetch();respond(second,data.full_b);respond(first,data.full_a);r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1:'..data.full_b._hp[2]);respond(r,data.same_b)
-- A complete successful checkpoint seeds a following read; no write replay.
local beforewrite=fetch();local count=#requests
provider.online_checkpoint({account_id=data.a.account_id,request_id='synthetic-checkpoint-123'},function(v)delivered[#delivered+1]=v end,function(e)errors[#errors+1]=e end)
local write=requests[#requests];assert(#requests==count+1 and write.url:find('/v1/online-time/checkpoint',1,true));assert(write.headers['X-Survival-Profile-Cache']=='v1')
respond(write,data.seed_b);assert(eq(delivered[#delivered],data.checkpoint_b)and #requests==count+1);respond(beforewrite,data.full_a)
r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1:'..data.full_b._hp[2]);respond(r,data.same_b)
-- Invalid optional seed never turns a committed write into an error/retry.
local badseed=json.decode(enc.encode(data.checkpoint_b));badseed._hp={1,'bad',2};count=#requests;local errorcount=#errors
provider.online_checkpoint({account_id=data.a.account_id,request_id='synthetic-checkpoint-124'},function(v)delivered[#delivered+1]=v end,function(e)errors[#errors+1]=e end)
respond(requests[#requests],badseed);assert(#requests==count+1 and #errors==errorcount and eq(delivered[#delivered],data.checkpoint_b))
-- Credential replacement uses a fresh context and rejects old-context fill.
local stale=fetch();token='token-B';r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1');respond(r,data.full_b);respond(stale,data.full_a);r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1:'..data.full_b._hp[2]);respond(r,data.same_b)
-- Unknown pinned baseline may cause ONE read without baseline, never a loop.
r=fetch();local count=#requests;respond(r,data.same_unknown);assert(#requests==count+1);r=requests[#requests];assert(r.headers['X-Survival-Profile-Cache']=='v1');respond(r,data.full_a)
r=fetch();count=#requests;respond(r,data.same_unknown);r=requests[#requests];respond(r,data.same_unknown);assert(#requests==count+1 and errors[#errors]=='http_profile_cache_miss')
-- Remaining timeout is consumed by an earlier read, not reset to30seconds.
r=fetch();count=#requests;clock_ms=clock_ms+10000;respond(r,data.same_unknown);local retry=requests[#requests];assert(#requests==count+1 and retry.timeout_ms==20000);respond(retry,data.full_a)
-- Read recovery shares the original30second monotonic budget.
r=fetch();count=#requests;clock_ms=clock_ms+30001;respond(r,data.same_unknown);assert(#requests==count and errors[#errors]=='http_profile_cache_recovery_timeout')
-- Another account does not inherit the first account's hash.
r=fetch(data.other.account_id);respond(r,data.other);r=fetch(data.other.account_id);assert(r.headers['X-Survival-Profile-Cache']=='v1');respond(r,data.full_other)
r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1:'..data.full_a._hp[2]);respond(r,data.same_a)
-- Mode/session/init invalidate contexts; late callbacks cannot repopulate.
local old=fetch();mode='pure';r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1');respond(r,data.full_pure);respond(old,data.full_a)
r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1:'..data.full_pure._hp[2]);respond(r,data.full_pure)
provider.init();mode='standard';r=fetch();respond(r,data.a);r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1');respond(r,data.full_a)
-- Advanced game modes share the standard profile mode but need distinct scopes.
local rich=json.decode(enc.encode(data.a));rich.game_mode='rich';rich._hp={1,string.rep('e',64),0}
local cold=json.decode(enc.encode(data.a));cold.game_mode='cold';cold._hp={1,string.rep('f',64),0}
game_mode_override='rich';r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1');respond(r,rich)
local richlate=fetch();game_mode_override='cold';r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1');respond(r,cold);respond(richlate,rich)
r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1:'..string.rep('f',64));respond(r,cold)
game_mode_override=nil

session='new-test-match-session';r=fetch();assert(r.url:find('/v1/session/login',1,true)and r.headers['X-Survival-Profile-Cache']==nil)
local fresh=json.decode(enc.encode(data.a));fresh.match_session_id=session;respond(r,fresh)
r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1');local freshframe=json.decode(enc.encode(fresh));freshframe._hp={1,string.rep('c',64),0};respond(r,freshframe)
-- At most16 indexed accounts; over-capacity contexts keep complete replies.
provider.init();session='test-match-session-123'
for i=1,18 do
 local account=i==1 and data.a.account_id or tostring(100000+i)
 local snap=json.decode(enc.encode(data.a));snap.account_id=account
 r=fetch(account);respond(r,snap);r=fetch(account)
 if i<=16 then assert(r.headers['X-Survival-Profile-Cache']=='v1');local frame=json.decode(enc.encode(snap));frame._hp={1,string.rep('d',64),0};respond(r,frame)
 else assert(r.headers['X-Survival-Profile-Cache']==nil);respond(r,snap)end
end
r=fetch();assert(r.headers['X-Survival-Profile-Cache']=='v1:'..string.rep('d',64))
print('CONDITIONAL_PROVIDER_SCENARIOS_PASS '..#requests)
