const assert=require('node:assert/strict');
const {createHarness}=require('./tests/fixtures/menus_v10_harness.cjs');

function setup(overrides={}){
 const h=createHarness(),plays=[];let cleared=0,disposed=0;
 h.cfg.SurvivalUI.RewardFX={Create(root,options){
  assert.equal(root.id,'DailyGW2Canvas');assert.equal(options.channel,'daily');
  return {Play(value){assert(value.anchor.IsValid(),'feedback uses the newly rendered card');plays.push(value);},Clear(){cleared++;},Dispose(){disposed++;}};
 }};
 h.load('daily_gw2_data.js');h.load('daily_remaining_5d5c1152eb.js');h.cfg.SurvivalDaily.Open(false);
 const days=Array.from({length:28},(_,i)=>({day:i+1,status:i<3?'claimed':i===3?'claimable':'not_open',rewards:[{name:'木材',count:10,description:'奖励'}]}));
 const snapshot={ok:true,sequence:1,today:25004,period_id:'period-1',count:3,ordinary_status:'claimable',pending:0,has_pass:1,purchase_enabled:0,
  missed:[25002],premium:{status:'unconfigured'},specials:[],calendar28:days,calendar_current_day:4,calendar_start_count:0,...overrides};
 h.emit('survival_daily_snapshot',snapshot);
 return {h,plays,snapshot,get cleared(){return cleared;},get disposed(){return disposed;},send(patch){h.emit('survival_daily_snapshot',{...snapshot,...patch});},claim(){h.click(h.nodes.DailyClaim);}};
}

{
 const t=setup();assert.equal(t.plays.length,0,'loading existing rewards never celebrates');t.claim();assert.equal(t.plays.length,0,'clicking is not success');
 t.send({sequence:2,pending:1,claim_result:{target_day:25004,ok:true,pending:true}});assert.equal(t.plays.length,0);
 t.send({sequence:3,claim_result:{target_day:25004,ok:false,error:'保存失败'}});assert.equal(t.plays.length,0);assert(!t.h.cfg.SurvivalDaily.Inspect().waiting);
 t.claim();
 const updated=t.snapshot.calendar28.map((d,i)=>i===3?{...d,status:'claimed'}:d);
 t.send({sequence:4,count:4,ordinary_status:'claimed',calendar28:updated});
 assert.equal(t.plays.length,1);assert.equal(t.plays[0].anchor,t.h.nodes.DailyGW2Day_4);assert.equal(t.plays[0].title,'领取成功');
 t.send({sequence:5,count:4,ordinary_status:'claimed',claim_result:{target_day:25004,ok:1}});assert.equal(t.plays.length,1,'duplicate confirmation does not replay');
 t.send({sequence:4,count:5});assert.equal(t.plays.length,1,'stale snapshots do not replay');
 t.h.cfg.SurvivalDaily.Close();assert(t.cleared>0);t.h.cfg.SurvivalDaily.Dispose();assert.equal(t.disposed,1);
}
{
 const t=setup({ordinary_status:'claimed',premium:{status:'claimable'},count:4});t.claim();
 t.send({sequence:2});assert(t.h.cfg.SurvivalDaily.Inspect().waiting,'already claimed ordinary reward is not a premium success');assert.equal(t.plays.length,0);
 t.send({sequence:3,pending:1,premium:{status:'claimed'}});assert.equal(t.plays.length,0,'wait for pending save to finish');
 t.send({sequence:4,premium:{status:'claimed'}});assert.equal(t.plays.length,1);assert.equal(t.plays[0].anchor.id,'DailyClaim');
}
{
 const t=setup();t.claim();
 t.send({sequence:2,count:4,ordinary_status:'claimed',pending:1});assert.equal(t.plays.length,0,'optimistic/pending state is not a saved reward');
 t.send({sequence:3,count:4,ordinary_status:'claimed',claim_result:{target_day:25004,ok:0,error:'保存失败'}});assert.equal(t.plays.length,0,'numeric false is not success');
}
{
 const t=setup();t.h.click(t.h.nodes.DailyMakeup);assert.equal(t.h.sent.at(-1).payload.target_day,25002);
 t.send({sequence:2,claim_result:{target_day:25001,ok:true}});assert.equal(t.plays.length,0,'another date cannot confirm this makeup');
 t.send({sequence:3,claim_result:{target_day:25002,ok:true}});assert.equal(t.plays.length,1,'matching saved makeup receives feedback');
}
{
 const t=setup({ordinary_status:'claimed'});t.h.click(t.h.nodes.DailyMakeup);
 t.send({sequence:2,claim_result:{target_day:25002,ok:true}});
 assert.equal(t.plays[0].text,'木材','makeup after today is claimed still shows the calendar reward');
 assert.equal(t.plays[0].anchor.id,'DailyGW2Day_4');
}
{
 const t=setup();t.claim();t.h.cfg.SurvivalDaily.Close();
 t.send({sequence:2,count:4,ordinary_status:'claimed'});assert.equal(t.plays.length,0,'hidden success is consumed without feedback');
 t.h.cfg.SurvivalDaily.Open(false);t.send({sequence:3,count:4,ordinary_status:'claimed'});assert.equal(t.plays.length,0,'reopening cannot replay hidden success');
}
{
 const t=setup();t.claim();t.h.cfg.SurvivalDaily.Close();t.h.cfg.SurvivalDaily.Open(false);
 t.send({sequence:2,count:4,ordinary_status:'claimed'});assert.equal(t.plays.length,0,'closing retires the presentation even if reopened before the reply');
}
{
 const t=setup();t.claim();t.send({sequence:2,today:25005,period_id:'period-2',count:4});assert.equal(t.plays.length,0,'day rollover cannot confirm the previous request');
 t.h.assertCleanDispose(t.h.cfg.SurvivalDaily);assert(t.disposed>0);
}
console.log('DAILY_REWARD_FEEDBACK_PASS: authoritative success, failed/pending claims, premium-only claims, makeup, duplicates, rollover, hidden updates and disposal');
