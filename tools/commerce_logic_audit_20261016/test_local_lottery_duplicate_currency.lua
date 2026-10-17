-- Offline local lottery prototype only. No live accounts, HTTP, or engine.
package.path='scripts/vscripts/?.lua;'..package.path
local bus=require('core/event_bus');local ev=require('core/events')
local results={}
local function check(name,fn)
 local ok,error=xpcall(fn,debug.traceback);results[#results+1]={name=name,ok=ok,error=not ok and tostring(error) or nil}
 print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ' '..tostring(error)))
end
local function copy(v)if type(v)~='table' then return v end;local r={};for k,n in pairs(v)do r[k]=copy(n)end;return r end
local amounts={n=5,r=25,sr=100,ssr=400,ur=1000}
local function fixture(options)
 options=options or {};bus.reset()
 local quality=options.quality or 'n'
 local item={id='local_lottery_fixture',name='Explicit local fixture',quality=quality,item_weight=1,
  max_owned=options.max_owned or 1,duplicate_points=amounts[quality],exchange_points=100,exchange_enabled=true,
  effects={{field_id='tower_attack_flat',value=2}},ownership_ids={},description='fixture'}
 local pool={id='map',items={item},by_id={[item.id]=item},by_quality={},quality_weights={},pity_rules=options.guarantee and {{id='fixture_sr',threshold=10,target_quality='sr',trigger_mode='batch_only'}} or {},
  revision='fixture-v1',ticket_content_id='lottery_ticket',single_cost=1,ten_cost=10,update_notice={updated_at=0}}
 for _,q in ipairs({'n','r','sr','ssr','ur'})do pool.by_quality[q]={item};pool.quality_weights[q]=q==quality and 1 or 0 end
 local cfg={version=6,default_pool_id='map',starjoy_stat_id='starjoy_points',quality_order={'n','r','sr','ssr','ur'},
  quality_rank={n=1,r=2,sr=3,ssr=4,ur=5},pools={map=pool},pool_order={pool},by_id={[item.id]=item},
  currencies={lottery_ticket={display_name='fixture ticket'}},test_initial_tickets={},
  unlock_status=function()return {unlocked=true}end}
 local profiles={}
 for id=0,1 do profiles[id]={revision=1,save={archive={unrelated={nested='retain'},commerce={balances={u_coin=17,shop_gold=23,shop_points=options.balance==nil and 7 or options.balance},other={keep=true}}},
  gameplay_stats={starjoy_points=77,starjoy_points_earned=1000,starjoy_reward_level=5,tower_attack_flat=11},
  content_inventory={lottery_ticket=50,[item.id]=options.owned==false and 0 or (options.owned_count or 1)},lottery_applied_item_effects={[item.id]=options.owned~=false and true or nil}}}end
 local archive_writes,stat_orders,grants,transactions=0,0,0,0
 local fail_archive=options.fail_archive
 local api={get_profile=function(id)return profiles[id] end}
 function api.update_save_section(id,section,value,reason)
  if section=='archive' then
   archive_writes=archive_writes+1
   if options.raise_archive then error('fixture_persist_exception')end
   if fail_archive then return {ok=false,error='fixture_persist_failed'}end
  end
  local next_profile=copy(profiles[id]);next_profile.save[section]=copy(value);next_profile.revision=next_profile.revision+1;profiles[id]=next_profile
  bus.emit(ev.PLAYER_PROFILE_CHANGED,{player_id=id,reason=reason})
  return {ok=true,revision=next_profile.revision}
 end
 if options.missing_api then api.update_save_section=nil end
 if options.missing_archive then profiles[0].save.archive=nil end
 package.loaded['systems/player_profile_service']=api
 package.loaded['config/lottery_config']=cfg
 package.loaded['systems/player_gameplay_stats_order_service']={order=function(id,key,n)
  stat_orders=stat_orders+1;profiles[id].save.gameplay_stats[key]=(profiles[id].save.gameplay_stats[key] or 0)+n
  return {ok=true,new_value=profiles[id].save.gameplay_stats[key]}
 end}
 package.loaded['systems/lottery_service']=nil
 PlayerResource={IsValidPlayerID=function(_,id)return id==0 or id==1 end}
 bus.handle_request(ev.CONTENT_INVENTORY_GET_REQUEST,function(p)return {ok=true,snapshot={counts=copy(profiles[p.player_id].save.content_inventory)}}end)
 bus.handle_request(ev.INVENTORY_TRANSACTION_EXECUTE_REQUEST,function(p)
  transactions=transactions+1;local inv=profiles[p.player_id].save.content_inventory
  for k,n in pairs(p.consume or {})do if (inv[k] or 0)<n then return {ok=false}end end
  for k,n in pairs(p.consume or {})do inv[k]=inv[k]-n end
  for k,n in pairs(p.grant or {})do inv[k]=(inv[k] or 0)+n end
  return {ok=true,snapshot={counts=copy(inv)}}
 end)
 bus.handle_request(ev.CONTENT_INVENTORY_GRANT_REQUEST,function(p)
  if options.fail_grant and p.count==1 then return {ok=false,error='fixture_item_grant_failed'}end
  local profile=profiles[p.player_id];local markers=profile.save.lottery_applied_item_effects
  if p.count>0 then profile.save.content_inventory[p.content_id]=(profile.save.content_inventory[p.content_id] or 0)+p.count;grants=grants+1 end
  if not markers[p.effect_marker_id] then
   for _,effect in ipairs(p.gameplay_stat_effects or {})do profile.save.gameplay_stats[effect.field_id]=(profile.save.gameplay_stats[effect.field_id] or 0)+effect.value end
   markers[p.effect_marker_id]=true
  end
  return {ok=true,snapshot={counts=copy(profile.save.content_inventory)},gameplay_stat_changes={}}
 end)
 local lottery=require('systems/lottery_service')
 return {draw=function(token,count,id)return lottery._test.draw({player_id=id or 0,request_id=token,count=count or 1,pool_id='map'})end,
  profile=function(id)return profiles[id or 0]end,inspect=function()return {archive_writes=archive_writes,stat_orders=stat_orders,grants=grants,transactions=transactions}end,
  set_fail=function(v)fail_archive=v end,snapshot=function(id)return lottery._test.snapshot(id or 0,'test','map')end}
end
for quality,amount in pairs(amounts)do check('duplicate_'..quality..'_shop_points',function()
 local f=fixture({quality=quality});local before=copy(f.profile());local other=copy(f.profile(1));local r=f.draw('duplicate-'..quality)
 assert(r.ok,r.error);local p=f.profile()
 assert(p.save.archive.commerce.balances.shop_points==7+amount,'duplicate must credit persistent commerce shop_points')
 assert(p.save.archive.commerce.balances.u_coin==17 and p.save.archive.commerce.balances.shop_gold==23,'other currencies unchanged')
 assert(p.save.archive.unrelated.nested=='retain' and p.save.archive.commerce.other.keep,'archive siblings retained')
 assert(p.save.gameplay_stats.starjoy_points==77 and p.save.gameplay_stats.starjoy_points_earned==1000 and p.save.gameplay_stats.starjoy_reward_level==5,'starjoy balance/progression unchanged')
 assert(p.save.content_inventory.local_lottery_fixture==1 and p.save.content_inventory.lottery_ticket==49)
 assert(r.results[1].converted_points==amount and r.results[1].converted_currency=='shop_points')
 assert(r.snapshot.shop_points==7+amount and r.snapshot.starjoy_points==77)
 assert(f.inspect().stat_orders==0 and f.inspect().archive_writes==1)
 local after=copy(p);local writes=f.inspect().archive_writes;assert(f.draw('duplicate-'..quality)==r)
 assert(f.profile().revision==after.revision and f.inspect().archive_writes==writes,'same request never grants twice')
 assert(f.profile(1).revision==other.revision and f.profile(1).save.archive.commerce.balances.shop_points==other.save.archive.commerce.balances.shop_points,'owner isolation')
end)end
check('duplicate_persist_failure_never_confirms_or_mutates_archive',function()
 local f=fixture({quality='ssr',fail_archive=true});local before=copy(f.profile());local archive=f.profile().save.archive
 local r=f.draw('failed-write');assert(not r.ok and r.error=='shop_points_persist_failed')
 assert(f.profile().save.archive==archive and archive.commerce.balances.shop_points==7,'failed write retains live archive identity and balance')
 assert(f.profile().save.content_inventory.lottery_ticket==50,'existing refund behavior retained')
 assert(f.profile().save.gameplay_stats.starjoy_points==77)
 local writes=f.inspect().archive_writes;f.set_fail(false);assert(f.draw('failed-write')==r and f.inspect().archive_writes==writes,'failed receipt cache does not replay rewards')
end)
check('nonduplicate_then_nine_duplicates_ten_pull',function()
 local f=fixture({quality='n',owned=false});local r=f.draw('ten-mixed',10);assert(r.ok,r.error)
 assert(#r.results==10 and not r.results[1].duplicate)
 assert(f.profile().save.content_inventory.local_lottery_fixture==1)
 assert(f.profile().save.gameplay_stats.tower_attack_flat==13,'first item effect once')
 assert(f.profile().save.archive.commerce.balances.shop_points==7+9*5 and f.profile().save.content_inventory.lottery_ticket==40)
 local sum=0;for _,row in ipairs(r.results)do sum=sum+(row.converted_points or 0)end;assert(sum==45)
 assert(f.inspect().grants==1 and f.inspect().stat_orders==0)
end)
check('stackable_item_still_uses_its_configured_max_owned',function()
 local f=fixture({quality='n',owned_count=2,max_owned=3});local r=f.draw('stackable-one');assert(r.ok and not r.results[1].duplicate)
 assert(f.profile().save.content_inventory.local_lottery_fixture==3 and f.profile().save.archive.commerce.balances.shop_points==7)
 local second=f.draw('stackable-two');assert(second.ok and second.results[1].duplicate)
 assert(f.profile().save.archive.commerce.balances.shop_points==12)
end)
check('new_item_grant_failure_cannot_create_points',function()
 local f=fixture({owned=false,fail_grant=true});local r=f.draw('grant-failed');assert(not r.ok)
 assert(f.profile().save.archive.commerce.balances.shop_points==7 and f.inspect().archive_writes==0 and f.profile().save.content_inventory.lottery_ticket==50)
end)
for _,value in ipairs({-1,'7',7.2,math.huge,0/0,9007199254740991})do check('invalid_or_overflow_balance_'..tostring(value),function()
 local f=fixture({balance=value});local r=f.draw('bad-balance')
 assert(not r.ok and r.error=='shop_points_balance_invalid')
 assert(f.inspect().archive_writes==0 and f.profile().save.content_inventory.lottery_ticket==50)
end)end
check('missing_archive_initializes_only_commerce_points',function()
 local f=fixture({missing_archive=true});local r=f.draw('archive-first');assert(r.ok,r.error)
 assert(f.profile().save.archive.commerce.balances.shop_points==5 and r.snapshot.shop_points==5)
 assert(f.profile().save.gameplay_stats.starjoy_points==77)
end)
for _,flag in ipairs({'missing_api','raise_archive'})do check(flag..'_rejects_without_reward_confirmation',function()
 local options={[flag]=true};local f=fixture(options);local archive=f.profile().save.archive
 local r=f.draw('archive-failure-'..flag);assert(not r.ok and r.error=='shop_points_persist_failed')
 assert(f.profile().save.archive==archive and archive.commerce.balances.shop_points==7 and f.profile().save.content_inventory.lottery_ticket==50)
end)end
check('ten_pull_existing_sr_guarantee_unchanged',function()
 local f=fixture({quality='sr',guarantee=true});local r=f.draw('sr-ten',10)
 assert(r.ok and r.guarantee_quality=='sr' and r.guarantee_satisfied and #r.results==10)
 assert(f.profile().save.archive.commerce.balances.shop_points==1007 and f.profile().save.content_inventory.lottery_ticket==40)
end)
LOCAL_LOTTERY_DUPLICATE_RESULTS=results
for _,row in ipairs(results)do assert(row.ok,'local duplicate currency regressions failed')end
print('LOCAL_LOTTERY_DUPLICATE_CURRENCY_PASS')
