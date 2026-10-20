'use strict';
const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
for(const source of ['archive_theme_tokens.js','archive_parchment_data.js','archive_handoff_180de7e38b.js','archive_v10_semantics.js','common/archive_tooltip.js'])h.load(source);
h.load('daily_remaining_5d5c1152eb.js');cfg.SurvivalDaily.Open(false);
const reward={id:'daily_growth_gem',name:'成长宝石',description:'英雄每秒攻击+1',count:3,max_owned:1,owned_count:1,duplicate_points:25,duplicate_currency:'shop_points'};
const snapshot={ok:1,sequence:1,today:25004,period_id:'0',count:3,ordinary_status:'claimable',pending:0,has_pass:0,
 calendar_current_day:4,calendar_start_count:0,calendar28:Array.from({length:28},(_,index)=>({day:index+1,absolute_count:index+1,status:index<3?'claimed':index===3?'claimable':'not_open',is_today:index===3?1:0,rewards:[{...reward}]})),specials:[],missed:[]};
h.emit('survival_daily_snapshot',snapshot);
const card=nodes.DailyGW2Day_4;
assert(card.__dailyGW2Tooltip.body.includes('成长宝石 ×3'),'Scheduled reward amount remains three opportunities, not an inventory count');
assert(card.__dailyGW2Tooltip.body.includes('每种道具最多拥有1件'));
assert(card.__dailyGW2Tooltip.body.includes('重复奖励每件转化为 25 商城积分'));
assert(!card.__dailyGW2Tooltip.body.includes('999999'));
assert.equal(snapshot.calendar28[3].rewards[0].count,3,'Tooltip never rewrites the authoritative offered reward');
assert(!h.sent.some(row=>/claim|purchase|checkout/.test(row.name)),'Opening a tooltip cannot grant anything');
cfg.SurvivalDaily.Dispose();
console.log('DAILY_UNIQUE_TOOLTIP_PASS: offered rewards and unique inventory are distinguished using server metadata; no grants');
