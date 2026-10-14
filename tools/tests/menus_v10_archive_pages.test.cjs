const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
function checkFrame(view){assert.equal(view.panel.style.width,'1672px');assert.equal(view.panel.style.height,'941px');assert.equal(view.content.style.position,'407px 213px 0px');assert.equal(view.sidebar.style.width,'258px');}
function treasure(){
 const h=createHarness();h.load('treasure_history.js');const {cfg,nodes}=h,view=h.view('TreasureWindow');checkFrame(view);
 cfg.SurvivalTreasure.Open();assert.equal(nodes.TreasureCards.GetChildCount(),0);assert(nodes.TreasureEmpty.visible);assert(cfg.SurvivalTreasure.IsOpen());assert(!nodes.TreasureWindow.BHasClass('ArchiveHidden'));assert(!nodes.TreasureScrim.BHasClass('ArchiveHidden'));cfg.SurvivalTreasure.Open();
 const history={history:Array.from({length:27},(_,i)=>({name:'宝物'+i,description:'真实效果'+i,icon_name:i===0?'survival/native/frozen_wall':'lich_frost_shield',...(i===0?{quantity:3}:{})}))};
 h.net('survival_rogue_reward','1',history);assert.equal(nodes.TreasureCards.GetChildCount(),0,'another player cannot replace the local treasure history');h.setHistory(history);h.net('survival_rogue_reward','0',history);
 assert.equal(nodes.TreasureCards.GetChildCount(),20);assert.equal(nodes.TreasureCount.text,'20 / 20');assert(!nodes.TreasureEmpty.visible);const first=nodes.TreasureCards.children[0],second=nodes.TreasureCards.children[1];
 assert.equal(first.__menuV10Cell.count.text,'3');assert(!second.__menuV10Cell.countHost.visible,'a history record does not invent an inventory count');assert.equal(first.__menuV10Cell.stage.children[0].image,'file://{images}/spellicons/survival/native/frozen_wall.png');
 first.events.onmouseover();h.flushFinite();assert.equal(nodes.TreasureTooltipEffect.text,'真实效果0');assert.equal(view.detailLayer.children.find(p=>p.BHasClass('MenuV10Tooltip')).visible,true);const tooltip=view.detailLayer.children.find(p=>p.BHasClass('MenuV10Tooltip'));tooltip.Children().find(p=>p.BHasClass('MenuV10TooltipSurface')).events.onmouseover();assert.equal(tooltip.visible,false,'The shared menu surface dismisses on entry');first.events.onmouseover();h.flushFinite();assert.equal(tooltip.visible,false,'Source reentry and queued measurements cannot reopen a dismissed menu tooltip');cfg.SurvivalTreasure.Close();assert(!cfg.SurvivalTreasure.IsOpen());assert.equal(view.detailLayer.children.find(p=>p.BHasClass('MenuV10Tooltip')).visible,false);
 const old=cfg.SurvivalTreasure;h.load('treasure_history.js');assert.equal(h.cfg.SurvivalMenuV10.Entries().filter(x=>x.panel.id==='TreasureWindow').length,1);old.Open();assert(!old.IsOpen());cfg.SurvivalTreasure.Open();assert.equal(nodes.TreasureCards.GetChildCount(),20);assert.equal(nodes.TreasureContent.children.filter(x=>x.id==='TreasureEmpty').length,0,'existing empty label is moved, not duplicated on hot reload');h.assertCleanDispose(cfg.SurvivalTreasure);
 console.log('TREASURE_V10_PASS: real shared shell/cells/tooltip, local history, 20 cap, no fabricated quantity, reopen/reload and deleted subtree');
}
function vip(){
 const h=createHarness();h.load('vip_catalog.js');h.load('vip_window.js');const {cfg,nodes}=h,view=h.view('VIPWindow');checkFrame(view);assert.equal(cfg.VIPRewardCatalog.rewards.length,33);assert.equal(nodes.VIPGrid.GetChildCount(),0);assert.equal(cfg.SurvivalVIP.Open(),false);
 const closed={...h.counts};for(let i=0;i<1000;i++){h.setProfile({vip_badge:i===999?1:0,revision:i});h.net('survival_player_public_profiles','0');}assert.deepEqual(h.counts,closed,'1000 hidden public profile updates do not rewrite or traverse UI');
 const snapshot={ok:true,level:2,balance:19,recharge_total_fen:24999,rows:{}};cfg.VIPRewardCatalog.rewards.forEach((r,i)=>{snapshot.rows[i]={id:r.reward_id,owned:0,eligible:r.group_id==='privileges'&&r.level<=2||r.group_id==='packages'?1:0,affordable:r.price<=19?1:0};});
 for(let i=0;i<1000;i++)h.emit('survival_vip_snapshot',{...snapshot,balance:i});assert.deepEqual(h.counts,closed,'1000 hidden account updates only cache state');assert(cfg.SurvivalVIP.Open());assert.equal(nodes.VIPGrid.GetChildCount(),12);assert.equal(nodes.VIPWallet.text,'当前 VIP2    商城付费币 999');assert.equal(nodes.VIPRechargeProgress.text,'累计充值 249.99 元 · 距VIP3还差 0.01 元');assert.equal(h.sent.at(-1).payload.action,'view');assert(nodes.VIPAction.enabled);
 h.click(nodes.VIPAction);assert.equal(h.sent.at(-1).payload.action,'claim');assert.equal(h.sent.at(-1).payload.reward_id,'vip_privilege_01');assert(!nodes.VIPAction.enabled);const calls=h.sent.length;nodes.VIPAction.events.onactivate();assert.equal(h.sent.length,calls,'repeated activation during a save cannot duplicate a claim');
 snapshot.rows[0].owned=1;h.emit('survival_vip_snapshot',snapshot);assert(nodes.VIPCard_vip_privilege_01.BHasClass('VIPOwned'));assert(!nodes.VIPAction.enabled);
 h.click(nodes.VIPTab_medals);assert.equal(nodes.VIPGrid.GetChildCount(),10);assert(!nodes.VIPAction.enabled);h.click(nodes.VIPTab_packages);assert.equal(nodes.VIPGrid.GetChildCount(),11);h.click(nodes.VIPCard_vip_package_03);assert.equal(nodes.VIPActionText.text,'付费币不足');assert(!nodes.VIPAction.enabled);h.click(nodes.VIPCard_vip_little_jacket);assert(nodes.VIPAction.enabled);assert(nodes.VIPEffectsRight.text.includes('星悦积分+68'));h.click(nodes.VIPAction);assert.equal(h.sent.at(-1).payload.action,'purchase');assert.deepEqual(Object.keys(h.sent.at(-1).payload).sort(),['action','reward_id']);
 cfg.SurvivalVIP.Close();const saved={...h.counts};h.emit('survival_vip_snapshot',{...snapshot,balance:40,action_result:{ok:false,error:'保存失败，请重试'}});assert.deepEqual(h.counts,saved);cfg.SurvivalVIP.Open();assert.equal(nodes.VIPStatus.text,'保存失败，请重试');
 h.click(nodes.VIPTab_privileges);nodes.VIPCard_vip_privilege_12.events.onmouseover();h.flushFinite();assert.equal(nodes.VIPTooltipEffect.text.split('\n').length,9,'all V12 effects survive the shared tooltip');assert(nodes.VIPTooltipCondition.text.includes('12500元'));h.setProfile({vip_badge:0});h.net('survival_player_public_profiles','0');assert(!cfg.SurvivalVIP.IsOpen());
 h.setIdentity('76561198104787442',true);assert(cfg.SurvivalVIP.IsAvailable());h.setIdentity('76561198104787442',false);assert(!cfg.SurvivalVIP.IsAvailable(),'preview entitlement remains Tools-only');h.setProfile({vip_badge:1});cfg.SurvivalVIP.Open();h.load('vip_window.js');assert.equal(cfg.SurvivalMenuV10.Entries().filter(x=>x.panel.id==='VIPWindow').length,1);h.assertCleanDispose(cfg.SurvivalVIP);
 console.log('VIP_V10_PASS: real shared shell, 33 original rewards, 1000 closed updates, gates, claims/prices/busy/errors, full tooltip, revoke and reload');
}
function daily(){
 const h=createHarness();h.load('daily_remaining_5d5c1152eb.js');const {cfg,nodes}=h,view=cfg.SurvivalDailyGW2;
 assert(view&&view.canvas.id==='DailyGW2Canvas');assert.equal(h.view('DailyWindow'),undefined,'The login calendar does not adopt a global navigation shell');
 cfg.SurvivalDaily.Open(false);assert.equal(h.sent.at(-1).name,'survival_daily_request');assert.equal(nodes.DailyClaimText.text,'加载中…');assert(!nodes.DailyClaim.enabled);
 assert.equal(nodes.DailyCards.GetChildCount(),28,'The loading state reserves 28 empty reward frames without fabricating rewards');
 const calendar28=Array.from({length:28},(_,i)=>({day:i+1,absolute_count:i+1,is_today:i===3?1:0,status:i<3?'claimed':i===3?'claimable':'not_open',rewards:[{id:'reward-'+i,name:'木材',count:10+i,description:'服务端效果'}]}));
 calendar28[4].rewards.push({id:'second',name:'第二项奖励',count:3,description:'第二项真实效果'});
 const snapshot={ok:true,sequence:1,today:25004,period_id:'week-1',count:3,ordinary_status:'claimable',pending:0,has_pass:0,purchase_enabled:0,duration_days:30,price:'价格待配置',makeup_days:30,missed:[25002],rule_text:'正式奖励规则',calendar28,calendar_current_day:4,calendar_start_count:0,
 specials:[{id:'milestone',day:7,name:'正式奖励',description:'正式效果',owned:0},{id:'second-milestone',day:14,name:'第二里程碑',description:'真实十四次效果',owned:0},{id:'third-milestone',day:21,name:'第三里程碑',description:'真实二十一次效果',owned:0}],
 premium:{status:'unconfigured'},cycle:calendar28.slice(0,7)};
 h.emit('survival_daily_snapshot',snapshot);
 assert.equal(nodes.DailyCards.GetChildCount(),28);assert.equal(nodes.DailySpecials.GetChildCount(),3,'The premium column contains only the three formally configured milestones');
 assert.equal(cfg.SurvivalDaily.Inspect().layout,'daily_gw2');assert.equal(cfg.SurvivalDaily.Inspect().days,28);
 assert(nodes.DailyClaim.enabled);assert(!nodes.DailyMakeup.visible);assert(!nodes.PassPurchase.enabled,'An unconfigured server purchase remains disabled');
 assert(nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'The pass column stays locked without authoritative entitlement');
 const premiumFrame=nodes.DailyGW2Special_milestone.Children().find(x=>x.BHasClass('DailyGW2SpecialFrame'));assert.equal(premiumFrame.style.width,'100px');assert.equal(premiumFrame.style.height,'100px','Premium reward artwork keeps its square shape beside the name and status');
 const fifth=nodes.DailyGW2Day_5;assert.equal(fifth.Children().filter(x=>x.BHasClass('DailyGW2Reward')).length,2,'Both formal rewards are rendered in a multi-reward day');
 fifth.events.onmouseover();h.flushFinite();assert(nodes.DailyGW2Tooltip.visible);assert(nodes.DailyTooltipEffect.text.includes('第二项真实效果'));assert(nodes.DailyTooltipEffect.text.includes('第二项奖励 ×3'));nodes.DailyGW2Tooltip.events.onmouseover();assert(!nodes.DailyGW2Tooltip.visible,'Daily tooltip dismisses on entry');fifth.events.onmouseover();h.flushFinite();assert(!nodes.DailyGW2Tooltip.visible,'Daily source cannot immediately reopen the dismissed tooltip');
 const item=nodes.DailyGW2Day_4.Children().find(x=>x.BHasClass('DailyGW2Reward'));item.events.onmouseover();h.flushFinite();assert(nodes.DailyTooltipEffect.text.includes('数量：13'));
 h.click(nodes.DailyClaim);assert.deepEqual(JSON.parse(JSON.stringify(h.sent.at(-1))),{name:'survival_daily_claim',payload:{target_day:25004}},'Claims use the real server date rather than calendar slot 4');
 assert(!nodes.DailyClaim.enabled);const claimCalls=h.sent.length;nodes.DailyClaim.events.onactivate();assert.equal(h.sent.length,claimCalls,'pending claim is guarded');
 h.emit('survival_daily_snapshot',{...snapshot,sequence:2,claim_result:{target_day:25004,ok:false,error:'保存失败'}});
 assert.equal(nodes.DailyClaimText.text,'重试领取');assert(nodes.DailyClaim.enabled,'An explicit rejected save can be retried');
 h.click(nodes.DailyClaim);
 h.emit('survival_daily_snapshot',{...snapshot,sequence:3,count:4,ordinary_status:'claimed',has_pass:1,purchase_enabled:1,expires_at:'2000000000'});
 assert.equal(nodes.DailyClaimText.text,'今日已领取');assert(!nodes.DailyClaim.enabled);assert(nodes.DailyMakeup.visible);
 assert(!nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'Only a server entitlement unlocks the pass column');
 assert(nodes.PassPrice.text.includes('有效至'),'The pass information uses the actual server expiration');
 h.click(nodes.DailyMakeup);assert.equal(h.sent.at(-1).payload.target_day,25002,'Makeup retains the earliest real missed date');
 h.emit('survival_daily_snapshot',{...snapshot,sequence:4,count:5,ordinary_status:'claimed',has_pass:1,purchase_enabled:1,missed:[]});assert(!nodes.DailyMakeup.visible);
 cfg.SurvivalDaily.Open(true);assert(nodes.DailyGW2PassInfo.BHasClass('DailyGW2PassFocus'));assert.equal(nodes.DailyCards.GetChildCount(),28,'Opening the pass entry retains the free calendar alongside it');
 nodes.DailyGW2Special_milestone.events.onmouseover();h.flushFinite();assert(nodes.DailyTooltipEffect.text.includes('正式效果'));assert(nodes.DailyTooltipEffect.text.includes('累计签到7次'));
 h.emit('survival_daily_snapshot',{...snapshot,sequence:5,purchase_enabled:1,ordinary_status:'claimed'});
 assert(nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'));
 h.click(nodes.PassPurchase);assert.equal(h.sent.at(-1).name,'survival_pass_purchase');assert.deepEqual(Object.keys(h.sent.at(-1).payload),[]);assert(!nodes.PassPurchase.enabled);
 assert.equal(cfg.SurvivalDaily.Inspect().hasPass,false,'Creating a purchase request cannot unlock the pass locally');
 assert(nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'Pending purchase keeps the reward lane locked until the server confirms entitlement');
 h.emit('survival_daily_snapshot',{...snapshot,sequence:6,purchase_enabled:0,ordinary_status:'claimed'});
 assert(!nodes.PassPurchase.enabled);assert(nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'Revoked entitlement restores the actual lock state');
 const purchaseCalls=h.sent.length;h.click(nodes.PassPurchase);assert.equal(h.sent.length,purchaseCalls);
 h.emit('survival_daily_snapshot',{...snapshot,sequence:4,count:999});assert.notEqual(cfg.SurvivalDaily.Inspect().count,999,'older server snapshot cannot replace current rewards');
 h.click(nodes.DailyRules);assert(!nodes.DailyRulesText.BHasClass('ArchiveHidden'));assert(nodes.DailyRulesBody.text.includes('<br>补签范围'));h.click(nodes.DailyGW2RulesClose);assert(nodes.DailyRulesText.BHasClass('ArchiveHidden'));
 const owned=[{...snapshot.specials[0],owned:1},...snapshot.specials.slice(1)];h.emit('survival_daily_snapshot',{...snapshot,sequence:7,specials:owned});assert(!nodes.DailyGW2Special_milestone.BHasClass('DailyGW2Locked'),'A previously granted reward is still shown as owned after pass expiry');
 cfg.SurvivalDaily.Close();const old=cfg.SurvivalDaily,oldClaim=nodes.DailyClaim.events.onactivate,oldRules=nodes.DailyRules.events.onactivate;
 h.load('daily_remaining_5d5c1152eb.js');cfg.SurvivalDaily.Open(false);h.emit('survival_daily_snapshot',{...snapshot,sequence:1});
 assert.equal(nodes.DailyCards.GetChildCount(),28);assert.equal(cfg.SurvivalMenuV10.Entries().length,0,'Reload cannot leak a shared menu or resource strip');
 const callsBeforeRetired=h.sent.length;oldClaim();oldRules();old.Open(true);assert.equal(h.sent.length,callsBeforeRetired,'Retired callbacks cannot submit or reopen the replacement controller');
 h.click(nodes.DailyGW2Close);assert(!cfg.SurvivalDaily.Inspect().open);cfg.SurvivalDaily.Open(false);h.assertCleanDispose(cfg.SurvivalDaily);
 console.log('DAILY_GW2_PASS: independent shell, server calendar28, multi-reward cells, three real premium milestones, real claim/makeup dates, rejection/busy guards, entitlement/price authority, tooltip/rules, stale snapshots, closure and reload');
}

module.exports={treasure,vip,daily};if(require.main===module){treasure();vip();daily();}
