-- Execute the real online_time_service.lua with collaborators, no Dota/network.
local consumer = assert(arg[1], 'consumer path required')
local checks = 0
local original_print=print
print=function(value,...)if type(value)=='string'and value:match('^FINAL_INLINE_REAL_LUA_CHECKS ')then original_print(value,...)end end
local function equal(a,b,why) checks=checks+1; assert(a==b,(why or '')..' expected '..tostring(b)..' got '..tostring(a)) end
local function scenario(options)
 options=options or {}
 local calls={refresh=0,grants=0,applied=0,requests={},pending=nil,handlers={}}
 local account,match='100','match-1'
 local bus={subscribe=function(event,fn)calls.handlers[event]=fn end,emit=function(event,value)if event=='reward'then calls.grants=calls.grants+1 end end}
 local events={FISHING_REWARD_GRANTED='reward',HERO_READY='ready',GAME_STARTED='started'}
 local scheduler={every=function(_,fn)calls.tick=fn end,after=function(_,fn)calls.retry=fn end,cancel=function()end}
 local setup={get_mode=function()return'fishing'end,get_session_id=function()return match end}
 local provider={resolve_account_id=function()return account end}
 function provider.online_checkpoint(payload,success,failure)
  calls.requests[#calls.requests+1]=payload
  if payload.final and options.remove_cap then payload.response_capabilities=nil end
  local function reply()
   local grants={}
   if payload.final or options.regular_grant then grants={{grant_id='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',reward_id='g1',definition_version=1,amount=1}} end
   local profile=options.no_profile and payload.final and nil or {account_id=options.wrong_profile and payload.final and '999'or account}
   local value={ok=true,profile=profile,grants=grants,final_profile_committed_v1=options.marker}
   if options.no_profile and payload.final then value.profile=nil end
   success(value)
  end
  if payload.final and options.defer then calls.pending=reply else reply() end
 end
 local profiles={get_provider=function()return provider end,is_loaded_for_account=function()return true end}
 function profiles.apply_snapshot(_,snapshot)
  calls.applied=calls.applied+1
  if calls.requests[#calls.requests].final and options.apply_return~=nil then return options.apply_return end
  return {ok=true}
 end
 function profiles.load_player(_,_,success,failure)
  calls.refresh=calls.refresh+1
  if options.refresh_error then failure('synthetic_error')else success()end
 end
 package.loaded['core/event_bus']=bus;package.loaded['core/events']=events;package.loaded['core/scheduler']=scheduler
 package.loaded['config/generated/fishing_system_rules']={rows={{enabled=true,online_time_checkpoint_interval_seconds=60}}}
 package.loaded['systems/player_profile_service']=profiles
 package.loaded['config/generated/star_blessing_reward_definitions']={by_id={g1={enabled=true,effect_scope='permanent',definition_version=1,value_min=1,value_max=1}}}
 package.loaded['systems/match_setup_service']=setup;package.loaded['systems/player_context_service']={is_defeated=function()return false end}
 package.loaded['systems/startup_loading_service']={is_player_ready=function()return true end}
 package.loaded['core/release_policy']={development_allowed=function()return false end}
 package.loaded['systems/permanent_reward_effect_service']={value=function()return 1 end}
 _G.GameRules={GetGameTime=function()return 0 end,State_Get=function()return 0 end}
 local service=assert(loadfile(consumer))();service.init();assert(service.resume_fishing(0))
 calls.finish=function()service.finish('unit')end
 calls.change_account=function()account='200'end;calls.change_match=function()match='match-2'end
 calls.reset=function()service.init()end
 return calls
end
local a=scenario{marker=1};a.finish();equal(a.refresh,0,'confirmed final reuses applied snapshot');equal(a.grants,1);equal(a.requests[2].response_capabilities.final_profile_committed_v1,true);equal(a.requests[1].response_capabilities,nil,'ordinary checkpoint unchanged')
for _,case in ipairs{{},{marker=false},{marker=true},{marker=0},{marker='1'},{marker=2}}do local c=scenario(case);c.finish();equal(c.refresh,1,'non-numeric1 proof keeps real refresh');equal(c.grants,1)end
for _,value in ipairs{false,true,'ok',{ok=false},{}}do local c=scenario{marker=1,apply_return=value};c.finish();equal(c.refresh,1,'failed apply keeps refresh');equal(c.grants,1)end
for _,case in ipairs{{marker=1,no_profile=true},{marker=1,wrong_profile=true},{marker=1,remove_cap=true}}do local c=scenario(case);c.finish();equal(c.refresh,1,'profile/account/capability mismatch falls back');equal(c.grants,1)end
local r=scenario{marker=1,regular_grant=true};equal(r.refresh,1,'regular grant still refreshes');equal(r.grants,1);r.tick();equal(r.refresh,2);equal(r.grants,1,'duplicate grant not republished');r.finish();equal(r.refresh,2,'final inline avoids only duplicate HTTP');equal(r.grants,1)
for _,change in ipairs{'change_account','change_match','reset'}do local c=scenario{marker=1,defer=true};c.finish();assert(c.pending);c[change]();c.pending();equal(c.grants,0,'stale generation/account/match ignored');equal(c.refresh,0)end
local d=scenario{marker=1,defer=true};d.finish();d.pending();d.pending();equal(d.grants,1,'late duplicate callback ignored');equal(d.refresh,0)
local f=scenario{refresh_error=true};f.finish();equal(f.refresh,1);equal(f.grants,0,'failed fallback does not publish unrefreshed reward')
print('FINAL_INLINE_REAL_LUA_CHECKS '..checks)
