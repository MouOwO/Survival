const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
function checkFrame(view){assert.equal(view.panel.style.width,'1672px');assert.equal(view.panel.style.height,'941px');assert.equal(view.content.style.position,'407px 213px 0px');assert.equal(view.sidebar.style.width,'258px');}
function treasure(){ return require('./treasure_compact.test.cjs').treasure(); }
function vip(){ return require('./vip_status.test.cjs').vip(); }
function daily(){
 const h=createHarness();for(const source of ['archive_theme_tokens.js','archive_parchment_data.js','archive_handoff_180de7e38b.js','archive_v10_semantics.js','common/archive_tooltip.js'])h.load(source);h.load('daily_gw2_data.js');h.load('daily_remaining_5d5c1152eb.js');const {cfg,nodes}=h,view=cfg.SurvivalDailyGW2;
 const tooltipText=()=>nodes.DailyGW2TooltipEffect.text.replace(/<br\s*\/?\s*>/gi,'\n').replace(/<[^>]*>/g,'');
 assert(view&&view.canvas.id==='DailyGW2Canvas');assert.equal(h.view('DailyWindow'),undefined,'The login calendar does not adopt a global navigation shell');
 cfg.SurvivalDaily.Open(false);assert.equal(h.sent.at(-1).name,'survival_daily_request');assert.equal(nodes.DailyClaimText.text,'加载中…');assert(!nodes.DailyClaim.enabled);
 assert.equal(nodes.DailyCards.GetChildCount(),28,'The loading state reserves 28 empty reward frames without fabricating rewards');
 assert.equal(nodes.DailySpecials.GetChildCount(),0,'Loading draws no unconfigured monthly reward frames');
 const noSubtitle=()=>{assert(!nodes.DailySubtitle.visible);assert.equal(nodes.DailySubtitle.style.visibility,'collapse');assert.equal(nodes.DailySubtitle.text,'');assert.equal(nodes.DailySubtitle.style.height,'0px','Removed subtitle has no reserved space');};noSubtitle();
 const calendar28=Array.from({length:28},(_,i)=>({day:i+1,absolute_count:i+1,is_today:i===3?1:0,status:i<3?'claimed':i===3?'claimable':'not_open',rewards:[{id:'reward-'+i,name:'木材',count:10+i,description:'服务端效果'}]}));
 calendar28[4].rewards.push({id:'second',name:'第二项奖励',count:3,description:'第二项真实效果'});
 const snapshot={ok:true,sequence:1,today:25004,period_id:'week-1',count:3,ordinary_status:'claimable',pending:0,has_pass:0,purchase_enabled:0,duration_days:30,price:'价格待配置',makeup_days:30,missed:[25002],rule_text:'正式奖励规则',calendar28,calendar_current_day:4,calendar_start_count:0,
 specials:[{id:'milestone',day:7,name:'正式奖励',description:'正式效果',owned:0},{id:'second-milestone',day:14,name:'第二里程碑',description:'真实十四次效果',owned:0},{id:'third-milestone',day:21,name:'第三里程碑',description:'真实二十一次效果',owned:0}],
 premium:{status:'unconfigured'},cycle:calendar28.slice(0,7)};
 h.emit('survival_daily_snapshot',snapshot);
 assert.equal(nodes.DailyCards.GetChildCount(),28);assert.equal(nodes.DailySpecials.GetChildCount(),3,'Only the three configured monthly milestones produce frames');
 assert.equal(cfg.SurvivalDaily.Inspect().layout,'daily_gw2');assert.equal(cfg.SurvivalDaily.Inspect().days,28);
 assert(nodes.DailyClaim.enabled);assert(!nodes.DailyMakeup.visible);assert(!nodes.PassPurchase.enabled,'An unconfigured server purchase remains disabled');
 assert(nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'The pass column stays locked without authoritative entitlement');
 const monthlyCard=nodes.DailyGW2Special_milestone;
 assert.equal(monthlyCard.Children().filter(x=>x.BHasClass('DailyGW2SpecialFrame')).length,0,'The monthly text card has no stretched decorative frame');
 const monthlyIcon=monthlyCard.Children().find(x=>x.BHasClass('DailyGW2MonthlyIconFrame'));assert(monthlyIcon,'Monthly artwork has its own centered image container');
 assert.equal(monthlyCard.style.width,'222px');assert.equal(monthlyCard.style.height,'169px');assert.equal(monthlyIcon.style.width,'99px');assert.equal(monthlyIcon.style.height,'99px');assert.equal(monthlyIcon.style.position,'62px 35px 0px','The icon is centered inside the 222px monthly card while reserving space for its text');
 const premiumFrame=monthlyIcon.Children().find(x=>x.BHasClass('DailyGW2SpecialFrame'));assert(premiumFrame,'Decorative corners remain on the item icon');
 assert.equal(premiumFrame.GetParent(),monthlyIcon);assert.equal(premiumFrame.style.position,'0px 0px 0px');assert.equal(premiumFrame.style.width,monthlyIcon.style.width);assert.equal(premiumFrame.style.height,monthlyIcon.style.height,'The decorative frame follows the image dimensions rather than the text card');
 const fifth=nodes.DailyGW2Day_5;assert.equal(fifth.Children().filter(x=>x.BHasClass('DailyGW2Reward')).length,1,'A multi-reward day uses one complete representative icon');assert.equal(fifth.Children().filter(x=>x.BHasClass('DailyGW2RewardKinds')).length,0,'Reward-kind badges leave the representative artwork unobstructed; all rewards remain in its tooltip');
 fifth.events.onmouseover();h.flushFinite();assert(nodes.DailyGW2Tooltip.visible);assert(tooltipText().includes('第二项真实效果'));assert(tooltipText().includes('第二项奖励 ×3'));nodes.DailyGW2TooltipSurface.events.onmouseover();assert(!nodes.DailyGW2Tooltip.visible,'Daily tooltip dismisses on entry');fifth.events.onmouseover();h.flushFinite();assert(!nodes.DailyGW2Tooltip.visible,'Daily source cannot immediately reopen the dismissed tooltip');
 const item=nodes.DailyGW2Day_4.Children().find(x=>x.BHasClass('DailyGW2Reward'));item.events.onmouseover();h.flushFinite();assert(tooltipText().includes('数量：13'));
 h.click(nodes.DailyClaim);assert.deepEqual(JSON.parse(JSON.stringify(h.sent.at(-1))),{name:'survival_daily_claim',payload:{target_day:25004}},'Claims use the real server date rather than calendar slot 4');
 assert(!nodes.DailyClaim.enabled);const claimCalls=h.sent.length;nodes.DailyClaim.events.onactivate();assert.equal(h.sent.length,claimCalls,'pending claim is guarded');
 h.emit('survival_daily_snapshot',{...snapshot,sequence:2,claim_result:{target_day:25004,ok:false,error:'保存失败'}});
 assert.equal(nodes.DailyClaimText.text,'重试');assert(nodes.DailyClaim.enabled,'An explicit rejected save can be retried');noSubtitle();
 h.click(nodes.DailyClaim);
 h.emit('survival_daily_snapshot',{...snapshot,sequence:3,count:4,ordinary_status:'claimed',has_pass:1,purchase_enabled:1,expires_at:'2000000000'});
 assert.equal(nodes.DailyClaimText.text,'今日已领取');assert(!nodes.DailyClaim.enabled);assert(nodes.DailyMakeup.visible);noSubtitle();
 assert(!nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'Only a server entitlement unlocks the pass column');
 assert(nodes.PassPrice.text.includes('有效至'),'The pass information uses the actual server expiration');
 h.click(nodes.DailyMakeup);assert.equal(h.sent.at(-1).payload.target_day,25002,'Makeup retains the earliest real missed date');
 h.emit('survival_daily_snapshot',{...snapshot,sequence:4,count:5,ordinary_status:'claimed',has_pass:1,purchase_enabled:1,missed:[]});assert(!nodes.DailyMakeup.visible);
 cfg.SurvivalDaily.Open(true);assert(nodes.DailyGW2PassInfo.BHasClass('DailyGW2PassFocus'));assert.equal(nodes.DailyCards.GetChildCount(),28,'Opening the pass entry retains the free calendar alongside it');
 nodes.DailyGW2Special_milestone.events.onmouseover();h.flushFinite();assert(tooltipText().includes('正式效果'));assert(tooltipText().includes('累计签到7次'));
 h.emit('survival_daily_snapshot',{...snapshot,sequence:5,purchase_enabled:1,ordinary_status:'claimed'});
 assert(nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'));
 h.click(nodes.PassPurchase);assert.equal(h.sent.at(-1).name,'survival_pass_purchase');assert.deepEqual(Object.keys(h.sent.at(-1).payload),[]);assert(!nodes.PassPurchase.enabled);
 assert.equal(cfg.SurvivalDaily.Inspect().hasPass,false,'Creating a purchase request cannot unlock the pass locally');
 assert(nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'Pending purchase keeps the reward lane locked until the server confirms entitlement');
 h.emit('survival_daily_snapshot',{...snapshot,sequence:6,purchase_enabled:0,ordinary_status:'claimed'});
 assert(!nodes.PassPurchase.enabled);assert(nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'Revoked entitlement restores the actual lock state');
 const purchaseCalls=h.sent.length;h.click(nodes.PassPurchase);assert.equal(h.sent.length,purchaseCalls);
 h.emit('survival_daily_snapshot',{...snapshot,sequence:4,count:999});assert.notEqual(cfg.SurvivalDaily.Inspect().count,999,'older server snapshot cannot replace current rewards');
 h.click(nodes.DailyRules);assert(!nodes.DailyRulesText.BHasClass('ArchiveHidden'));assert(nodes.DailyRulesBody.text.includes('<br>补签范围'));h.click(nodes.DailyRules);assert(nodes.DailyRulesText.BHasClass('ArchiveHidden'),'The existing rules toggle closes its panel');
 const owned=[{...snapshot.specials[0],owned:1},...snapshot.specials.slice(1)];h.emit('survival_daily_snapshot',{...snapshot,sequence:7,specials:owned});assert(!nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'A previously granted reward is still shown as owned after pass expiry');
 cfg.SurvivalDaily.Close();const old=cfg.SurvivalDaily,oldClaim=nodes.DailyClaim.events.onactivate,oldRules=nodes.DailyRules.events.onactivate;
 h.load('daily_remaining_5d5c1152eb.js');cfg.SurvivalDaily.Open(false);h.emit('survival_daily_snapshot',{...snapshot,sequence:1});
 assert.equal(nodes.DailyCards.GetChildCount(),28);assert.equal(cfg.SurvivalMenuV10.Entries().length,0,'Reload cannot leak a shared menu or resource strip');
 const callsBeforeRetired=h.sent.length;oldClaim();oldRules();old.Open(true);assert.equal(h.sent.length,callsBeforeRetired,'Retired callbacks cannot submit or reopen the replacement controller');
 h.click(nodes.DailyGW2Close);assert(!cfg.SurvivalDaily.Inspect().open);cfg.SurvivalDaily.Open(false);h.assertCleanDispose(cfg.SurvivalDaily);
 console.log('DAILY_GW2_PASS: renderer VM, server calendar28, exactly three configured monthly rewards, real claim/makeup dates, rejection/busy guards, entitlement authority, no subtitle, closure and reload');
}

module.exports={treasure,vip,daily};if(require.main===module){treasure();vip();daily();}
