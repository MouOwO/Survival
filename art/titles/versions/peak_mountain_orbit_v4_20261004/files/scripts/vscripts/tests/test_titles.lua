package.path="scripts/vscripts/?.lua;"..package.path
local titles=require("systems/archive_titles")
local catalog=require("config/generated/archive_titles")
local a={}
assert(titles.rows(a)[1].unlocked==1)
assert(titles.apply({title_id="peak_perfection"},a))
assert(titles.selected(a)=="peak_perfection" and titles.rows(a)[1].equipped==1)
assert(not titles.apply({title_id="invalid"},a) and a.equipped_title=="peak_perfection")
catalog.by_id.peak_perfection.default_unlocked=false
assert(not titles.apply({title_id="peak_perfection"},a) and titles.selected(a)=="")
a.titles_owned={peak_perfection=true}
assert(titles.apply({title_id="peak_perfection"},a))
catalog.by_id.peak_perfection.enabled=false
assert(titles.selected(a)=="")
catalog.by_id.peak_perfection.enabled=true;catalog.by_id.peak_perfection.default_unlocked=true
assert(titles.apply({title_id=""},a) and titles.selected(a)=="")
local bus=require("core/event_bus");bus.reset()
local events=require("core/events")
local profile={save={archive={equipped_title="peak_perfection"}}}
local unit={entindex=function() return 10 end,GetUnitName=function() return "real_hero" end}
local current=unit
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p) assert(p.player_id==0);return {unit=current} end)
package.loaded['systems/player_profile_service']={get_account_profile=function() return profile end}
local tick
package.loaded['core/scheduler']={every=function(_,f)tick=f end}
local remote=true
package.loaded['systems/archive_http_adapter']={enabled=function()return remote end}
local tools=true
IsInToolsMode=function()return tools end
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end}
local samples={}
CustomNetTables={SetTableValue=function(_,table,key,value)assert(table=='survival_hero_health_bar');samples[#samples+1]=value end}
local service=require('systems/title_presentation_service');service.init();tick()
assert(samples[#samples].entindex==10 and samples[#samples].title_id=='peak_perfection')
assert(samples[#samples].render_mode=='layered' and samples[#samples].model_entindex==-1,'new title uses layered art, no 3D prop')
local count=#samples;tick();assert(#samples==count,'unchanged samples must not send')
assert(service.preview(0,'').ok);assert(samples[#samples].title_id=='')
assert(profile.save.archive.equipped_title=='peak_perfection','preview must never mutate cloud profile')
assert(service.rows(0,profile.save.archive)[1].equipped==0,'empty override must stay unequipped')
assert(not service.preview(0,'missing').ok)
assert(service.preview(0,'peak_perfection').ok)
current=nil;tick();assert(samples[#samples].entindex==-1)
current={entindex=function()return 22 end,GetUnitName=unit.GetUnitName};tick();assert(samples[#samples].entindex==22)
current.IsIllusion=function()return true end;tick();assert(samples[#samples].entindex==-1)
current=unit;tools=false;assert(not service.preview(0,'').ok)
profile.save.archive.equipped_title='';bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0});tick();assert(samples[#samples].title_id=='')
print('PASS title rules and runtime: unlock gate, selection, account isolation, preview, removal, replacement, clone exclusion')
