'use strict';
// Explicit browser fixtures only; this never connects to the game or submits a draw.
const fs=require('node:fs'),{browser}=require('../shop_ui_12h/cdp.cjs');
const preview=process.argv[2]||'design_refs/menus_v10/work/preview_lottery/index.html';
const out='design_refs/menus_v10/work/browser_lottery';fs.mkdirSync(out,{recursive:true});
const hold=setInterval(()=>{},1000);
(async()=>{const b=await browser(),reports=[];try{
 for(const state of ['idle','details','unknown','reward_known']){
  await b.go(preview,'?page=lottery&state='+state);await b.run('previewReady');await b.run('syncLayout();true');
  const r=await b.run(`({ready:previewState.ready,errors:previewErrors,calls:previewCalls,title:nodes.LotteryGW2Title?.text||cfg.SurvivalPurpleLottery?.Inspect()?.title||nodes.LotteryTitle?.text||''})`);
  await b.shot(out+'/'+state+'.png');reports.push({state,...r});
 }
 await b.go(preview,'?page=lottery');await b.run('previewReady');
 await b.run(`(()=>{const ids=PREVIEW_FIXTURE.lottery.members.filter(x=>x.pool_id==='map').slice(0,10).map(x=>x.item_id);const rewards=ids.map(id=>{const row=PREVIEW_FIXTURE.lottery.items.find(x=>x.item_id===id);return{...row,id,name:row.display_name,count:1,description:row.description};});nodes.LotterySkipAnimation.checked=true;cfg.SurvivalLottery.SetSkipAnimation();emit('ui_lottery_result',{ok:1,pool_id:'map',count:10,results:rewards,request_id:'LOCAL_BROWSER_TEN_RESULT'});cfg.SurvivalLottery.SkipReveal();syncLayout();return true;})()`);
 await b.shot(out+'/ten_results.png');
 reports.push({state:'ten_results',...await b.run(`({errors:previewErrors,count:nodes.LotteryItemList.Children().length,positions:nodes.LotteryItemList.Children().map(c=>c.style.position),calls:previewCalls})`)});
 await b.run(`cfg.SurvivalLottery.Feature('history');syncLayout();true`);await b.shot(out+'/history.png');
 reports.push({state:'history',...await b.run(`({errors:previewErrors,rows:nodes.LotteryInfoList.Children().length,calls:previewCalls})`)});
 fs.writeFileSync(out+'/report.json',JSON.stringify({kind:'active_lottery_production_component_browser_preview',gameVerified:false,reports},null,2));
 console.log('LOTTERY_V10_BROWSER_SAVED '+out);
 }finally{b.close();clearInterval(hold);}})().catch(e=>{clearInterval(hold);console.error(e);process.exitCode=1;});
