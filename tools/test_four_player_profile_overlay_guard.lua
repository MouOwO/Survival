-- Reuse the existing native-boundary fixture bootstrap, then exercise the
-- real permanent projection/reset service and the real Tools wrapper guards.
local file=assert(io.open('tools/test_four_player_live_perf_wrapper.lua','rb'))
local source=file:read('*a');file:close()
local boundary=assert(source:find("tools=false;assert",1,true),'Fixture bootstrap boundary missing')
local bootstrap=source:sub(1,boundary-1)
local specification=[[
local function clone(v)
 if type(v)~='table' then return v end
 local out={};for k,x in pairs(v) do out[k]=clone(x) end;return out
end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
human.schema_version=1;human.entitlements={vip={active=true}}
human.achievements={};human.public={unchanged='public source'}
human.progression={loaded=true,clear_counts={n3=8}}
human.save.archive={clear_counts={n3=8},online={map_level=77}}
human.save.permanent_effects={}
human.save.gameplay_stats={}
for _,r in ipairs(require('config/generated/player_gameplay_stats').rows) do if r.enabled~=false then human.save.gameplay_stats[r.field_id]=r.default_value or 0 end end
human.save.gameplay_stats.map_level=77
human.save.gameplay_stats.tower_attack_per_second=16
local saved_human=clone(human)
local account_profile=clone(human)
account_profile.save.gameplay_stats.map_level=91
account_profile.save.content_inventory.account_only_item=27
local saved_account_profile=clone(account_profile)
local account_reader=profiles.get_account_profile
profiles.get_account_profile=function(id) if id==0 then return account_profile end;return account_reader(id) end
local loading=false
profiles.is_loading=function(id) return id==0 and loading end
local entry_calls={load_player=0,apply_snapshot=0,apply_incremental=0}
profiles.load_player=function(id)
 entry_calls.load_player=entry_calls.load_player+1
 if id==0 then human.revision=human.revision+1 end
 return {ok=true,pending=false}
end
profiles.apply_snapshot=function(id,snapshot)
 entry_calls.apply_snapshot=entry_calls.apply_snapshot+1
 if id==0 then human=clone(snapshot) end
 return {ok=true}
end
profiles.apply_incremental=function(update)
 entry_calls.apply_incremental=entry_calls.apply_incremental+1
 if type(update)=='table' and update.account_id==human.account_id then human.revision=human.revision+1 end
 return {ok=true}
end
for k,v in pairs(profiles) do originals[k]=v end
loading=true;admitted=false
local waiting=wrapper.prepare_activity_fixture('A')
assert(waiting.waiting and waiting.status=='waiting_profile_load' and waiting.pending_player_ids[1]==0)
assert(not _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF and hook_installs==0 and equal(human,saved_human))
for k,v in pairs(originals) do assert(profiles[k]==v,'Pending load must install no '..k..' hooks') end
loading=false;admitted=true
local subscribers,handlers,timers={},{},{}
event_bus.subscribe=function(name,fn) subscribers[name]=subscribers[name] or {};table.insert(subscribers[name],fn);return {} end
event_bus.handle_request=function(name,fn) assert(not handlers[name]);handlers[name]=fn end
local previous_emit,previous_request=event_bus.emit,event_bus.request
event_bus.emit=function(name,p)
 previous_emit(name,p)
 for _,fn in ipairs(subscribers[name] or {}) do fn(p) end
end
event_bus.request=function(name,p) if handlers[name] then return handlers[name](p) end;return previous_request(name,p) end
package.loaded['core/scheduler'].every=function(_,fn,id) timers[id]=fn;if id=='manual_four_player_live_perf' then scheduled=fn end end
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function() return false end}
local permanent=require('systems/permanent_reward_effect_service')
permanent.init()
event_bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason='native_human_admission'})
for _=1,65 do clock=clock+1;timers.star_blessing_effect_ticks() end
local before=event_bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0})
assert(before.display_totals.tower_attack_flat==0 and before.totals.tower_attack_flat==1040,
 'Reproduce drift using real per-second permanent service, not a replaced totals getter')
local state=wrapper.prepare_activity_fixture('A')
assert(state.options.reset_permanent_runtime==true and state.permanent_reset_game_time==65)
assert(equal(human,saved_human) and equal(account_profile,saved_account_profile),
 'Fresh test reset must not mutate any original private or distinct account-profile field')
assert(equal(state.original_account_profiles[0],saved_account_profile),'Retain the separate original full account snapshot')
for id=0,3 do
 local p=profiles.get_profile(id)
 assert(p.save.gameplay_stats.map_level==({[0]=1,[1]=9,[2]=17,[3]=24})[id])
 local projected=event_bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=id})
 assert(projected.display_totals.tower_attack_flat==0 and projected.totals.tower_attack_flat==0)
 assert(projected.test_isolation==false,'Reset must restore all permanent fields')
 assert(projected.totals.wall_initial_health==1000+p.save.gameplay_stats.map_level*100)
 assert(state.permanent_baseline[id].tower_attack_runtime_delta==0)
end
assert(profiles.get_content_inventory_count(0,'lottery_monkey_king')==1)
assert(profiles.get_content_inventory_count(1,'commerce_p012')==1)
local called_error=0
local r=profiles.load_player(0,'late_refresh',nil,function(error) assert(error=='tools_four_profile_overlay_active');called_error=called_error+1 end)
assert(not r.ok and not r.pending and called_error==1)
local malicious=clone(saved_human);malicious.save.gameplay_stats.tower_attack_flat=9999
assert(not profiles.apply_snapshot(0,malicious,'late_http_completion').ok)
assert(not profiles.apply_incremental({account_id=saved_human.account_id,changes={save={gameplay_stats={tower_attack_flat=8888}}}}).ok)
assert(not profiles.apply_incremental(require('core/json_encoder').encode({account_id=saved_human.account_id,revision=99})).ok)
assert(entry_calls.load_player==0 and entry_calls.apply_snapshot==0 and entry_calls.apply_incremental==0)
assert(equal(human,saved_human) and state.profile_blocks.apply_incremental==2)
local report=wrapper.status({quiet=true})
assert(report.permanent_baseline_started_game_time==65 and report.profile_blocks.load_player==1)
assert(report.owners[1].permanent_baseline.static_tower_attack_flat==0 and report.owners[1].permanent_baseline.total_tower_attack_flat==0)
assert(report.owners[1].permanent_baseline.tower_attack_runtime_delta==0)
-- Unknown/unselected accounts and a different current world/session keep the
-- real public behavior; the guard is never an all-account blanket rejection.
assert(profiles.apply_snapshot(4,malicious).ok and entry_calls.apply_snapshot==1)
assert(profiles.apply_incremental({account_id='other_account'}).ok and entry_calls.apply_incremental==1)
local old_world=mode;mode={}
assert(profiles.apply_snapshot(0,saved_human).ok and entry_calls.apply_snapshot==2)
mode=old_world
local old_session=session;session='another_real_match_session'
assert(profiles.apply_snapshot(0,saved_human).ok and entry_calls.apply_snapshot==3)
session=old_session
local old_guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
assert(profiles.apply_snapshot(0,saved_human).ok and entry_calls.apply_snapshot==4)
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=old_guard
-- Never overwrite a newer independent wrapper during restoration.
local owned=profiles.apply_incremental
local later=function(...) return owned(...) end
profiles.apply_incremental=later
wrapper.stop()
assert(profiles.apply_incremental==later)
profiles.apply_incremental=originals.apply_incremental
for k,v in pairs(originals) do assert(profiles[k]==v,'Exact original public reader/entry must restore: '..k) end
assert(profiles.get_profile(0)==human and equal(human,saved_human),'Full original profile/account data must restore')
assert(profiles.get_account_profile(0)==account_profile and equal(account_profile,saved_account_profile),
 'Separate account view, including fields absent from match profile, must restore exactly')
assert(profiles.load_player(4).ok and entry_calls.load_player==1)
assert(not pcall(wrapper.prepare_activity_fixture,'A'),'Do not reset volatile growth in an old benchmark world')
local old_clock=clock;timers.star_blessing_effect_ticks();clock=old_clock
local restored=event_bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0})
assert(restored.totals.tower_attack_flat==16,'Stop restores source profile; old match growth is intentionally not invented/replayed')
print('FOUR_PROFILE_OVERLAY_GUARD_PASS: real service reproduces 1040 drift and formal reset clears it; loading waits without auth/hooks; complete source preserved/restored; exact current-world/session/account async gates; unknown/other-world forwarding; later wrapper preserved; fresh-world reset only')
]]
assert(loadstring(bootstrap..specification,'@four_profile_overlay_real_service_regression'))()
