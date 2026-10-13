'use strict';
// Only the daily controller is opened. GameEvents are local adapter stubs.
const dailyParams=new URLSearchParams(location.search),dailyState=dailyParams.get('state')||'normal';
let dailySequence=100;
window.previewState={page:'daily',state:dailyState,kind:'daily_gw2_production_component_browser_preview',ready:false,fixtureOnly:true};
window.dailyPreviewSnapshot=function(overrides={}){
 const source=DAILY_GW2_FIXTURE,claimed=Number(overrides.claimed||0)===1,count=Number(overrides.count===undefined?2:overrides.count),anchor=Math.max(0,count-(claimed?1:0));
 const start=Math.floor(anchor/28)*28,current=anchor-start+1,cycleCurrent=anchor%7+1;
 const status=(day,today)=>day<today?'claimed':day===today?(claimed?'claimed':'claimable'):'not_open';
 const snapshot={ok:1,sequence:++dailySequence,today:25000,count,claimed:claimed?1:0,ordinary_status:claimed?'claimed':'claimable',has_pass:0,expires_at:'',next_day:count%7+1,pending:0,current_day:cycleCurrent,period_id:String(Math.floor(anchor/7)),cycle_mode:'claim_count',calendar_current_day:current,calendar_start_count:start,
  cycle:source.rewards.map(row=>({...structuredClone(row),is_today:row.day===cycleCurrent?1:0,status:status(row.day,cycleCurrent)})),
  calendar28:Array.from({length:28},(_,index)=>({day:index+1,absolute_count:start+index+1,rewards:structuredClone(source.rewards[index%7].rewards),is_today:index+1===current?1:0,status:status(index+1,current)})),
  specials:structuredClone(source.specials),missed:[],makeup_days:Number(source.rules.makeup_days),duration_days:Number(source.rules.duration_days),price:source.rules.price_text,purchase_enabled:Number(source.rules.purchase_enabled),
  subtitle:'每日领取 · 七次循环',rule_text:'每日零点刷新；断签不重置累计进度。通行证奖励按累计签到次数发放。',premium:{status:'unconfigured',name:'周末高级装备',description:'周周期与装备候选池尚未配置；现有累计签到通行证奖励仍按原规则发放。'},...overrides};
 return snapshot;
};
window.dailyPreviewSend=function(overrides={}){const snapshot=dailyPreviewSnapshot(overrides);window.dailyCurrentSnapshot=snapshot;emit('survival_daily_snapshot',snapshot);syncLayout();return snapshot;};
function closeOtherWindows(){
 for(const api of ['SurvivalArchive','SurvivalShop','SurvivalCommerceView','SurvivalLottery','SurvivalDaily','SurvivalTreasure','SurvivalVIP'])if(cfg[api]?.Close)cfg[api].Close();
 for(const id of ['PreviewContext_payment_test','PaymentEntry','PaymentScrim','PaymentDialog','ArchiveEntry','TreasureEntry','DailyEntry','PassEntry','EndlessStatus','VIPScrim','VIPWindow','SurvivalHUDTopRight','HandoffTopNavigation','CustomShopButton','HeroStatsPanel','SurvivalProductionPanel'])if(nodes[id])nodes[id].visible=false;
}
window.previewReady=(async()=>{
 await previewLoad();closeOtherWindows();if(!cfg.SurvivalDaily)throw Error('Active production daily controller unavailable');
 cfg.SurvivalDaily.Open(dailyState==='pass');
 if(dailyState!=='loading'){
  const changes=dailyState==='pass'?{has_pass:1,count:8,missed:[24999],expires_at:String((25000+30)*86400)}:dailyState==='claimed'?{count:28,claimed:1}:dailyState==='rollover'?{count:28}:dailyState==='unavailable'?{ordinary_status:'not_open'}:{};
  if(dailyState==='pass')changes.specials=structuredClone(DAILY_GW2_FIXTURE.specials).map((row,index)=>({...row,owned:index===0?1:0}));
  if(dailyState==='long'){
   const sample=dailyPreviewSnapshot(changes);sample.calendar28[2].rewards[0].description+='\n'+Array.from({length:24},(_,index)=>'第'+(index+1)+'行：明确标记的隔离长文本布局样例，不新增奖励效果。').join('\n');dailyPreviewSend(sample);
  }else dailyPreviewSend(changes);
 }
 syncLayout();await new Promise(resolve=>setTimeout(resolve,300));syncLayout();previewState.ready=true;return true;
})().catch(error=>{previewErrors.push({scope:'daily_gw2_state',message:String(error),stack:error.stack});previewState.failure=String(error);return false;});
