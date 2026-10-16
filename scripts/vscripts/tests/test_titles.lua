package.path="scripts/vscripts/?.lua;"..package.path
local titles=require("systems/archive_titles")
local catalog=require("config/generated/archive_titles")
local json=require("core/json_encoder")
local ids={"peak_perfection","jinghong","youlong","jian_tianya","tianxia_diyi","cangqiong","sihai","daoyuan","chushen"}
assert(#catalog.rows==#ids)
for level,id in ipairs(ids) do
 local row=catalog.rows[level]
 assert(row.title_id==id,"the approved CSV order defines title levels")
 assert(row.title_level==level and row.required_wave==(level-1)*80+1)
end
local function expected(wave)
 return wave<1 and "" or ids[math.min(#ids,math.floor((wave-1)/80)+1)]
end
for _,wave in ipairs({0,1,80,81,160,161,240,241,640,641,720,721,1000}) do
 -- Old equipped values do not prevent automatic migration to the earned tier.
 local archive={endless_best_wave=wave,equipped_title="peak_perfection",titles_owned={chushen=true}}
 assert(titles.selected(archive)==expected(wave),"automatic title boundary at "..wave)
 local rows=titles.rows(archive)
 local equipped=0
 for level,row in ipairs(rows) do
  local unlocked=wave>=((level-1)*80+1)
  assert(row.level==level and row.required_wave==(level-1)*80+1)
  assert(row.target==row.required_wave)
  assert((row.unlocked==1)==unlocked,"earned tier at "..wave)
  assert(titles.unlocked(archive,row.id)==unlocked)
  if row.equipped==1 then equipped=equipped+1;assert(row.id==expected(wave)) end
 end
 assert(equipped==(wave<1 and 0 or 1),"only the highest earned title is selected by default")
 titles.sync(archive)
 assert(archive.equipped_title==expected(wave) and archive.title_selection_manual~=true)
 assert(not titles.needs_reconcile(archive),"synced title must not queue another reconciliation")
end
local legacy={endless_best_wave=161,equipped_title="peak_perfection"}
assert(titles.needs_reconcile(legacy),"legacy equipped fields must migrate to automatic highest")
titles.sync(legacy);assert(legacy.equipped_title=="youlong")
local automatic={endless_best_wave=80}
titles.sync(automatic);assert(automatic.equipped_title=="peak_perfection")
automatic.endless_best_wave=81
assert(titles.needs_reconcile(automatic));titles.sync(automatic)
assert(automatic.equipped_title=="jinghong")
automatic.endless_best_wave=math.max(automatic.endless_best_wave,1)
titles.sync(automatic);assert(automatic.equipped_title=="jinghong","a lower new run cannot downgrade the saved best tier")
automatic.endless_best_wave=161;titles.sync(automatic)
assert(automatic.equipped_title=="youlong","automatic selection advances with saved progress")

-- Saved ownership or the former free-first-title flag cannot bypass wave gates.
local first=catalog.by_id.peak_perfection
local default=first.default_unlocked
first.default_unlocked=true
local unearned={endless_best_wave=0,titles_owned={peak_perfection=true,chushen=true}}
assert(not titles.unlocked(unearned,"peak_perfection") and not titles.unlocked(unearned,"chushen"))
assert(not titles.apply({title_id="peak_perfection"},unearned))
first.default_unlocked=default
local manual={endless_best_wave=161}
assert(titles.apply({title_id="peak_perfection"},manual))
assert(manual.title_selection_manual==true and titles.selected(manual)=="peak_perfection")
manual.endless_best_wave=1000;titles.sync(manual)
assert(manual.equipped_title=="peak_perfection","an explicit lower title remains selected after progress grows")
assert(titles.apply({title_id=""},manual))
assert(manual.title_selection_manual~=true and manual.equipped_title=="chushen","empty choice restores automatic highest")
for _,invalid in ipairs({"missing",false,1,{}}) do
 local before=json.encode(manual)
 assert(not titles.apply({title_id=invalid},manual))
 assert(json.encode(manual)==before,"invalid choices must not mutate the archive")
end
assert(not titles.apply({},manual))
catalog.by_id.chushen.enabled=false
assert(not titles.unlocked(manual,"chushen") and not titles.apply({title_id="chushen"},manual))
assert(titles.selected(manual)=="daoyuan","disabled highest title falls back to the highest available earned tier")
catalog.by_id.chushen.enabled=true
print("PASS title tiers: exact 80-wave boundaries, nine-tier cap, legacy migration, automatic advancement, manual selection and gate authority")

-- Real title settlement must change only cosmetic state and remain idempotent.
local settlement=require("systems/archive_settlement")
local saved={save={archive={endless_best_wave=161},gameplay_stats={initial_wood=37,initial_gold=11}}}
local stats=json.encode(saved.save.gameplay_stats)
local command={id="title:test:manual",kind="title_equip",title_id="peak_perfection"}
local result=settlement.settle(saved,command,false)
assert(result.ok and result.archive.equipped_title=="peak_perfection" and result.archive.title_selection_manual==true)
assert(json.encode(result.gameplay_stats)==stats,"equipping never grants or reconciles gameplay stats")
saved.save.archive=result.archive
local duplicate=settlement.settle(saved,command,false)
assert(duplicate.ok and duplicate.duplicate and json.encode(duplicate.gameplay_stats)==stats)
local restored=settlement.settle(saved,{id="title:test:auto",kind="title_equip",title_id=""},false)
assert(restored.ok and restored.archive.equipped_title=="youlong" and restored.archive.title_selection_manual~=true)
assert(json.encode(restored.gameplay_stats)==stats)
print("PASS title settlement: manual and automatic choices persist without stat grants; repeated receipts are idempotent")

local bus=require("core/event_bus");bus.reset()
local events=require("core/events")
local profile={save={archive={endless_best_wave=1,equipped_title="peak_perfection"}}}
local other_profile={save={archive={endless_best_wave=81,equipped_title="jinghong"}}}
local unit={entindex=function() return 10 end,GetUnitName=function() return "real_hero" end}
local current=unit
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p)
 if p.player_id==0 then return {unit=current} end
 return nil
end)
package.loaded['systems/player_profile_service']={get_account_profile=function(id)return id==0 and profile or other_profile end}
local tick
package.loaded['core/scheduler']={every=function(_,f)tick=f end}
local remote=true
package.loaded['systems/archive_http_adapter']={enabled=function()return remote end}
local tools=true
IsInToolsMode=function()return tools end
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end}
local samples={}
CustomNetTables={SetTableValue=function(_,name,key,value)
 assert(name=='survival_hero_health_bar');samples[#samples+1]=value
end}
local service=require('systems/title_presentation_service');service.init();tick()
assert(samples[#samples].entindex==10 and samples[#samples].title_id=='peak_perfection')
assert(samples[#samples].render_mode=='layered' and samples[#samples].model_entindex==-1,'titles use layered art, not a 3D prop')
local count=#samples;tick();assert(#samples==count,'unchanged presentation samples must not send')
assert(not service.preview_active(0),'normal Workshop Tools play does not implicitly enter title preview')
for level,row in ipairs(service.rows(0,profile.save.archive)) do
 assert(row.unlocked==(level==1 and 1 or 0),'ordinary Tools rows obey the real endless gates')
end
for _,remote_enabled in ipairs({true,false}) do
 remote=remote_enabled
 for level=2,#ids do
  local id=ids[level]
  assert(not titles.unlocked(profile.save.archive,id))
  local before=json.encode(profile.save.archive)
  assert(service.preview(0,id).ok,'explicit Tools preview may display an unearned cosmetic')
  assert(service.preview_active(0) and samples[#samples].title_id==id)
  assert(json.encode(profile.save.archive)==before,'preview never changes cloud progress, manual choice or ownership')
  local found=false
  for _,row in ipairs(service.rows(0,profile.save.archive)) do
   if row.id==id then found=true;assert(row.unlocked==1 and row.preview_only==1 and row.equipped==1) end
  end
  assert(found)
  for other_level,row in ipairs(service.rows(1,other_profile.save.archive)) do
   assert(row.unlocked==(other_level<=2 and 1 or 0),'another player does not inherit the preview overlay')
   assert(row.equipped==(row.id=='jinghong' and 1 or 0))
  end
 end
end
assert(service.preview(0,'').ok and service.preview_active(0))
assert(samples[#samples].title_id=='','explicit empty Tools preview may temporarily hide the title')
assert(profile.save.archive.equipped_title=='peak_perfection')
assert(service.rows(0,profile.save.archive)[1].equipped==0,'empty preview does not fall back to the automatic account title')
assert(not service.preview(0,'missing').ok and not service.preview(0,{}).ok)
catalog.by_id.jinghong.enabled=false
assert(not service.preview(0,'jinghong').ok)
catalog.by_id.jinghong.enabled=true
assert(service.preview(0,'peak_perfection').ok)
current=nil;tick();assert(samples[#samples].entindex==-1)
current={entindex=function()return 22 end,GetUnitName=unit.GetUnitName};tick();assert(samples[#samples].entindex==22)
current.IsIllusion=function()return true end;tick();assert(samples[#samples].entindex==-1)
current=unit;tools=false;assert(not service.preview(0,'').ok)
service.refresh(0);service.publish(0)
assert(samples[#samples].title_id=='peak_perfection','Tools preview never leaks into production selection')
profile.save.archive.endless_best_wave=81;titles.sync(profile.save.archive)
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0});tick()
assert(samples[#samples].title_id==profile.save.archive.equipped_title and samples[#samples].title_id=='jinghong',
 'the head title follows the effective saved automatic choice on profile refresh')
assert(titles.apply({title_id='peak_perfection'},profile.save.archive))
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0});tick();assert(samples[#samples].title_id=='peak_perfection')
assert(titles.apply({title_id=''},profile.save.archive))
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0});tick();assert(samples[#samples].title_id=='jinghong')
service.init();tick()
assert(not service.preview_active(0) and samples[#samples].title_id=='jinghong','reinitialization uses the saved effective selection and clears preview state')
print('PASS title runtime: ordinary Tools gates, explicit local/remote previews, account isolation, profile refresh, manual/auto switching, replacement and clone exclusion')

-- Load the real profile publisher as well: stale remote public metadata must
-- agree with the title selected from the account's saved endless progress.
bus.reset()
package.loaded['systems/player_profile_service']=nil
package.loaded['systems/title_presentation_service']=nil
package.loaded['core/logger']={info=function()end,warn=function()end}
package.loaded['systems/player_entitlement_service']={replace_all=function()end}
local public_samples,head_samples={},{}
CustomNetTables={SetTableValue=function(_,name,key,value)
 if name=='survival_player_public_profiles' then public_samples[key]=value
 elseif name=='survival_hero_health_bar' then head_samples[key]=value
 else error('unexpected title projection '..name) end
end}
local function snapshot(revision,wave,manual_choice)
 return {schema_version=1,account_id='1000',revision=revision,entitlements={},achievements={},
  public={title_id='chushen'},save={content_inventory={},gameplay_stats={},
   archive={endless_best_wave=wave,equipped_title='peak_perfection',title_selection_manual=manual_choice}}}
end
local real_profiles=require('systems/player_profile_service')
real_profiles.init({provider={init=function()end,resolve_account_id=function()return '1000' end,
 fetch_snapshot=function(_,success)success(snapshot(1,81))end}})
local real_presentation=require('systems/title_presentation_service');real_presentation.init()
real_profiles.load_player(0)
local function public_title(id)
 assert(real_profiles.get_public_profile(0).title_id==id)
 assert(public_samples['0'].title_id==id,'published public profile must ignore stale remote title metadata')
 assert(head_samples['title_0'].title_id==id,'public profile and head title must use the same effective selection')
end
public_title('jinghong')
assert(real_profiles.apply_snapshot(0,snapshot(2,161,true),'title_manual').ok)
public_title('peak_perfection')
assert(real_profiles.apply_snapshot(0,snapshot(3,161,false),'title_automatic').ok)
public_title('youlong')
assert(real_profiles.apply_snapshot(0,snapshot(4,0,false),'title_no_progress').ok)
public_title('')
local pure=snapshot(5,0,false)
pure.account_profile=snapshot(5,161,false)
assert(real_profiles.apply_snapshot(0,pure,'title_separate_account').ok)
assert(real_profiles.get_profile(0).save.archive.endless_best_wave==0)
assert(real_profiles.get_account_profile(0).save.archive.endless_best_wave==161)
public_title('youlong')
print('PASS public title consistency: real profile load, stale public data, manual selection, automatic advancement, no progress and separate account view')
