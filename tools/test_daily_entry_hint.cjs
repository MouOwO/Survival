'use strict';
// Real daily controller + complete production HUD in separate Panorama contexts.
// Only the native APIs, transport, and account snapshots are synthetic.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {createRequire}=require('node:module');
const {createHarness}=require('./tests/fixtures/menus_v10_harness.cjs');
const {fixture:calendar}=require('./daily_gw2/fixture.cjs');
const hudHarness=path.resolve('tools/test_topnav_refresh_context.cjs');
let hudPrefix=fs.readFileSync(hudHarness,'utf8').split('function run(code) {')[0];
assert(hudPrefix.includes('function fixture(code)'), 'Complete HUD fixture boundary exists');
// That test compares an old ignored snapshot; this independent test needs only
// its native fixture, so do not require a workstation-only historical file.
assert(/^const before = .*;$/m.test(hudPrefix));
hudPrefix=hudPrefix.replace(/^const before = .*;$/m,'const before = "";');
const hudContext={require:createRequire(hudHarness),__dirname:path.dirname(hudHarness),process,console};
vm.runInNewContext(hudPrefix+'\nglobalThis.makeHUD=()=>fixture(source);',hudContext,{filename:hudHarness});
const clone=value=>JSON.parse(JSON.stringify(value));
const reward={id:'lottery_ticket',name:'普通抽奖券',count:1};
function snapshot(overrides={}){
 const f=calendar();
 return {ok:true,sequence:1,today:25004,period_id:'0',count:0,pending:0,ordinary_status:'claimable',
  premium:{status:'unconfigured'},has_pass:0,purchase_enabled:0,missed:[],specials:f.specials,
  calendar_current_day:1,calendar_start_count:0,
  calendar28:Array.from({length:28},(_,i)=>({day:i+1,is_today:i===0?1:0,status:i===0?'claimable':'not_open',rewards:f.rewards[i%7].rewards})),
  benefits:{daily_time:{period_id:'25004',progress:30,rows:[]},daily_wins:{period_id:'25004',progress:0,rows:[]},weekly_time:{period_id:'3572',progress:120,rows:[]}},
  ...overrides};
}
function tier(id,extra={}){return {id,required:30,status:'claimable',can_claim:1,base_rewards:[reward],monthly_rewards:[],...extra};}
function setup({admitted=true}={}){
 const daily=createHarness();
 for(const source of ['common/ui_registry.js','common/ui_components.js','ui_layers.js',
  'archive_theme_tokens.js','archive_parchment_data.js','archive_handoff_180de7e38b.js',
  'archive_v10_semantics.js','common/archive_tooltip.js','daily_gw2_data.js','daily_remaining_5d5c1152eb.js'])daily.load(source);
 const hud=hudContext.makeHUD();hud.cfg.SurvivalDaily=daily.cfg.SurvivalDaily;
 if(admitted)daily.setLoading({admission_complete:1});
 const button=()=>hud.ctx.FindChildTraverse('HandoffNav_benefit');
 function light(expected,message){hud.advance(100);assert.equal(button().BHasClass('HandoffNavRewardReady'),expected,message);}
 return {daily,hud,button,light,send(value){daily.emit('survival_daily_snapshot',clone(value));}};
}
const results=[];
{
 const t=setup({admitted:false});t.light(false,'No profile snapshot must not glow');
 assert.equal(t.daily.sent.length,0,'No eligibility query before admission');
 t.send(snapshot());t.light(false,'Even a cached snapshot cannot light an unadmitted HUD');
 t.daily.setLoading({admission_complete:1});t.send(snapshot({sequence:2}));
 t.light(true,'Authoritative claimable ordinary reward lights the real closed HUD entry');
 let writes=0;const button=t.button(),set=button.SetHasClass;
 button.SetHasClass=function(name,value){if(name==='HandoffNavRewardReady')writes++;return set.call(this,name,value);};
 t.hud.advance(1000);assert.equal(writes,0,'Stable HUD ticks do not rewrite the reward class');
 t.daily.cfg.SurvivalDaily.Open(false);t.daily.click(t.daily.nodes.DailyClaim);
 assert.equal(t.daily.sent.at(-1).name,'survival_daily_claim');
 t.light(true,'Submitting a claim does not extinguish the reward');
 t.send(snapshot({sequence:3,pending:1,ordinary_status:'claimed',count:1,claim_result:{target_day:25004,ok:1,pending:1}}));
 t.light(true,'Optimistic claimed state with pending save is not an ACK');
 t.send(snapshot({sequence:4,ordinary_status:'claimed',claim_result:{target_day:25004,ok:0,error:'保存失败'}}));
 t.light(true,'Failed save cannot extinguish the previous confirmed unclaimed state');
 t.send(snapshot({sequence:5}));t.daily.click(t.daily.nodes.DailyClaim);
 t.send(snapshot({sequence:6,count:1,ordinary_status:'claimed',claim_result:{target_day:25004,ok:1,pending:0}}));
 t.light(false,'Saved success with no other rewards extinguishes the entry');
 t.send(snapshot({sequence:5}));t.light(false,'Late older sequence cannot restore the light');
 t.send(snapshot({sequence:7,today:25003}));t.light(false,'An older day cannot restore the light');
 t.send(snapshot({sequence:8,today:25005}));t.light(true,'Server 05:00 rollover makes the next daily reward visible');
 results.push('ordinary submit/pending/failure/retry/ACK, stale packets and stable ticks');
}
{
 const t=setup(),s=snapshot({ordinary_status:'claimed'});
 s.benefits.daily_time.rows=[tier('time_a'),tier('time_b')];
 s.benefits.daily_wins.rows=[tier('win_a',{required:1})];
 s.benefits.weekly_time.rows=[tier('week_a')];
 t.send(s);t.light(true,'Multiple manual benefit tiers light the closed entry');
 t.daily.cfg.SurvivalDaily.Open(false);t.daily.cfg.SurvivalDaily.SelectPage('daily');
 t.daily.click(t.daily.nodes.DailyGW2BenefitClaim_daily_time_time_a);
 assert.equal(t.daily.sent.at(-1).name,'survival_benefit_claim');
 s.sequence++;s.benefits.daily_time.rows[0].status='claimed';s.benefits.daily_time.rows[0].can_claim=0;
 s.benefit_claim_result={track:'daily_time',tier_id:'time_a',ok:true,pending:false};
 t.send(s);t.light(true,'Claiming one tier keeps the light while another tier is available');
 s.sequence++;s.benefits.daily_time.rows[1].status='claimed';s.benefits.daily_time.rows[1].can_claim=0;
 delete s.benefit_claim_result;t.send(s);t.light(true,'A weekly reward also keeps the shared welfare entry lit');
 s.sequence++;s.benefits.weekly_time.rows[0].status='claimed';s.benefits.weekly_time.rows[0].can_claim=0;
 t.send(s);t.light(true,'A victory reward keeps the shared welfare entry lit');
 s.sequence++;s.benefits.daily_wins.rows[0].status='claimed';s.benefits.daily_wins.rows[0].can_claim=0;
 t.send(s);t.light(false,'All current manual reward tiers claimed extinguishes the entry');
 results.push('multiple daily/win/weekly tiers retain until the final saved claim');
}
{
 const t=setup(),s=snapshot({ordinary_status:'claimed'});
 s.benefits.daily_time.rows=[tier('automatic',{auto_claim:1,can_claim:0}),tier('already_claimed',{status:'claimed',can_claim:1})];
 s.benefits.daily_wins.rows=[tier('locked',{status:'locked',can_claim:0})];
 s.benefits.public_beta_login={rows:[tier('popup_only')]};
 t.send(s);t.light(false,'Automatic, claimed, locked and popup-only rewards create no manual hint');
 s.sequence++;s.premium.status='claimable';t.send(s);t.light(true,'A genuinely claimable monthly reward lights the entry');
 s.sequence++;s.premium.status='claimed';t.send(s);t.light(false);
 s.sequence++;s.ordinary_status='claimable';t.send(s);t.light(true);
 t.send({ok:false,error:'档案尚未载入'});t.light(false,'Unavailable profile must not advertise cached eligibility');
 s.sequence++;t.send(s);t.light(true);
 t.daily.setLoading({admission_complete:0});t.light(false,'Admission loss clears eligibility display');
 t.daily.setLoading({admission_complete:1});t.light(false,'Readmission requires a fresh confirmed snapshot');
 s.sequence++;t.send(s);t.light(true);
 t.hud.load();t.light(true,'A rebuilt native HUD reads the same confirmed daily state');
 t.daily.cfg.SurvivalDaily.Dispose();t.light(false,'Disposed daily controllers cannot leave a glowing entry');
 results.push('monthly, auto/unknown exclusions, unreadable profile, admission and HUD rebuild/disposal');
}
{
 const t=setup();const requests=()=>t.daily.sent.filter(row=>row.name==='survival_daily_request').length;
 assert.equal(requests(),1,'Admission bootstraps the first query without opening the window');
 function runRetry(){const index=t.daily.scheduled.findIndex(task=>task.delay===5&&!task.cancelled);assert(index>=0);t.daily.scheduled.splice(index,1)[0].fn();}
 runRetry();runRetry();runRetry();assert.equal(requests(),3,'Bootstrap retries are capped at three');
 assert.equal(t.daily.scheduled.filter(task=>task.delay===5&&!task.cancelled).length,0,'No permanent eligibility polling loop');
 const s=snapshot();t.send(s);t.light(true);
 assert.equal(t.daily.sent.filter(row=>/claim|purchase/.test(row.name)).length,0,'Bootstrap never claims, purchases, or emits inventory deltas');
 results.push('admission bootstrap, bounded retries, no award action or high frequency poll');
}
const css=fs.readFileSync('panorama/src/styles/custom_game/handoff_v1.css','utf8');
const rule=css.match(/\.HandoffNavUnified\.HandoffNavRewardReady \.HandoffNavGlow\s*\{([^}]+)\}/);
assert(rule&&/opacity\s*:\s*1/.test(rule[1]),'The real hint class paints the existing halo');
assert(!/animation|transition/.test(rule[1]),'Reward light has no animation work');
console.log('DAILY_ENTRY_HINT_PASS '+results.length+' flows: '+results.join('; '));
