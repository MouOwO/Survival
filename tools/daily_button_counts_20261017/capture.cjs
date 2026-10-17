'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),base=path.join(repo,'design_refs/daily_button_counts_20261017'),out=path.join(base,'screens'),input=path.join(base,'preview/index.html');
const source='panorama/src/scripts/custom_game/daily_remaining_5d5c1152eb.js';
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(path.join(repo,file))).digest('hex');
function snapshot(){
 const rect=n=>n.el.getBoundingClientRect().toJSON(),label=nodes.PassPurchaseText,button=nodes.PassPurchase;
 const quantity=n=>n.FindChildrenWithClassTraverse('DailyGW2Quantity').map(x=>({text:x.text,bounds:rect(x),parentType:x.GetParent().id||x.GetParent().GetClasses().join(' ')}));
 const cards=nodes.DailyCards.Children().map(n=>({id:n.id,bounds:rect(n),quantities:quantity(n),tooltip:n.__dailyGW2Tooltip,rewards:n.Children().filter(c=>c.BHasClass('DailyGW2Reward')).map(c=>({bounds:rect(c),tooltip:c.__dailyGW2Tooltip}))}));
 const range=document.createRange();range.selectNodeContents(label.el);const glyph=range.getBoundingClientRect().toJSON();
 return {ready:previewState.ready,errors:previewErrors,calls:previewCalls,api:cfg.SurvivalDaily.Inspect(),button:{text:label.text,bounds:rect(button),textBounds:rect(label),glyphBounds:glyph,style:label._style,buttonBackground:button._style.backgroundImage},cards,rules:{closeExists:!!nodes.DailyGW2RulesClose,width:nodes.DailyRulesText._style.width,bodyHtml:nodes.DailyRulesBody.el.innerHTML},specialTips:nodes.DailySpecials.Children().map(n=>n.__dailyGW2Tooltip)};
}
function inside(rect,width,height){assert(rect.width>0&&rect.height>0);assert(rect.x>=-1&&rect.y>=-1&&rect.right<=width+1&&rect.bottom<=height+1);}
function centerButton(button,width,height){
 assert.equal(button.style.width,'fit-children');assert.equal(button.style.height,'fit-children');assert.equal(button.style.horizontalAlign,'center');assert.equal(button.style.verticalAlign,'center');
 const center=r=>({x:r.x+r.width/2,y:r.y+r.height/2}),a=center(button.bounds),b=center(button.textBounds),g=center(button.glyphBounds);
 assert(Math.abs(a.x-b.x)<1&&Math.abs(a.y-b.y)<1,'actual text label is centered in button');assert(Math.abs(a.x-g.x)<1&&Math.abs(a.y-g.y)<1,'actual rendered text is centered');
 assert(button.textBounds.width<button.bounds.width,'text keeps natural width');assert(button.textBounds.height<button.bounds.height,'text keeps natural height');inside(button.bounds,width,height);
 return {labelOffsetX:b.x-a.x,labelOffsetY:b.y-a.y,glyphOffsetX:g.x-a.x,glyphOffsetY:g.y-a.y};
}
async function crop(b,file,rect,width,height,padding=6){
 const x=Math.max(0,Math.floor(rect.x-padding)),y=Math.max(0,Math.floor(rect.y-padding)),w=Math.min(width-x,Math.ceil(rect.right-x+padding)),h=Math.min(height-y,Math.ceil(rect.bottom-y+padding));
 const result=await b.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x,y,width:w,height:h,scale:2}});fs.writeFileSync(path.join(out,file),Buffer.from(result.data,'base64'));return {file:'screens/'+file,captureScale:2,clip:{x,y,width:w,height:h}};
}
async function main(){
 fs.mkdirSync(out,{recursive:true});const report={kind:'daily_button_counts_production_component_preview',notGameCapture:true,fixtureOnly:true,source,sourceSha256:hash(source),screens:[],sizes:[],quantityBoundaries:[],limitations:['Browser adapter approximates Panorama layout and font rendering. Native game verification is separate.','Formal CSV rewards with synthetic local progress only; no account, external server, purchase or claim.']};
 const b=await browser();
 try{
  for(const [width,height] of [[1920,1080],[960,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(input);assert(await b.run('previewReady'));await sleep(320);
   let state=await b.run('('+snapshot.toString()+')()');assert.deepEqual(state.errors,[]);assert.equal(state.cards.length,28);assert.equal(state.button.text,'开通月卡');const centering=centerButton(state.button,width,height),initialCalls=JSON.stringify(state.calls);
   const doubles=state.cards.filter(c=>c.rewards.length===2);assert.equal(doubles.length,8);assert.deepEqual(doubles.map(c=>c.id),[5,6,12,13,19,20,26,27].map(i=>'DailyGW2Day_'+i));
   for(const card of doubles){assert.deepEqual(card.quantities.map(q=>q.text),['3']);assert.equal(card.quantities[0].parentType,card.id,'common quantity belongs to whole card');assert.equal((card.tooltip.body.match(/×3/g)||[]).length,2,'whole card tooltip keeps both counts');assert(card.rewards.every(r=>r.tooltip.body.includes('数量：3')),'individual reward tooltips retain quantities');}
   assert(state.cards.every(c=>c.quantities.length===1&&c.quantities[0].text==='3'),'all 28 current daily cells show one three');
   assert(!state.rules.closeExists);assert.equal(state.rules.width,'567px');assert(!/[;；]/.test(state.rules.bodyHtml.split('累计7次：')[1]));assert(state.specialTips.every(t=>!/[;；]/.test(t.body)),'buff descriptions retain newline formatting');
   const full='daily_'+width+'x'+height+'.png';await b.shot(path.join(out,full),{x:0,y:0,width,height});report.screens.push({file:'screens/'+full,width,height,kind:'complete_page'});
   report.screens.push({...await crop(b,'button_'+width+'x'+height+'.png',state.button.bounds,width,height),width,height,kind:'month_card_button'});
   const fifth=state.cards[4].bounds,sixth=state.cards[5].bounds,both={x:fifth.x,y:fifth.y,right:sixth.right,bottom:Math.max(fifth.bottom,sixth.bottom)};
   report.screens.push({...await crop(b,'day5_6_'+width+'x'+height+'.png',both,width,height),width,height,kind:'double_reward_cells'});
   const normalButton=state.button;
   await b.run('dailyPreviewSend({has_pass:1});true');await sleep(120);state=await b.run('('+snapshot.toString()+')()');assert.equal(state.button.text,'续费月卡');const renewalCentering=centerButton(state.button,width,height);
   report.screens.push({...await crop(b,'renewal_button_'+width+'x'+height+'.png',state.button.bounds,width,height),width,height,kind:'renewal_button'});
   assert.deepEqual(state.errors,[]);assert.equal(JSON.stringify(state.calls),initialCalls,'rendering and synthetic state emit no server request');report.sizes.push({width,height,button:normalButton,centering,renewalButton:state.button,renewalCentering,doubleRewardDays:doubles.map(c=>({id:c.id,quantities:c.quantities,tooltip:c.tooltip})),previousRulesAndBuffFormattingRetained:true,noClaimOrPurchaseCalls:true});
  }
  const initialCalls=await b.run('JSON.stringify(previewCalls)');
  for(const [name,counts,expected] of [['different',[2,5],['2','5']],['zero',[0,0],['0']],['known_unknown',[3,undefined],['3']],['unknown_unknown',[undefined,undefined],[]]]){
   const expression='(()=>{const s=dailyPreviewSnapshot();const values='+JSON.stringify(counts)+';s.calendar28[4].rewards.forEach((r,i)=>{if(values[i]===null)delete r.count;else r.count=values[i];});dailyPreviewSend(s);return true;})()';
   await b.run(expression);await sleep(50);const state=await b.run('('+snapshot.toString()+')()'),card=state.cards[4];assert.deepEqual(card.quantities.map(q=>q.text),expected,name+' count presentation');
   assert(!card.tooltip.body.includes('undefined')&&!card.tooltip.body.includes('null'),'unknown counts do not invent quantity text');
   for(let i=0;i<2;i++){const body=card.rewards[i].tooltip.body;if(counts[i]===undefined)assert(!body.includes('数量：'),'unknown reward has no fabricated count');else assert(body.includes('数量：'+counts[i]));}
   assert.deepEqual(state.errors,[]);assert.equal(JSON.stringify(state.calls),initialCalls);report.quantityBoundaries.push({name,counts:counts.map(x=>x===undefined?'unknown':x),expected,actual:card.quantities.map(q=>q.text),cardTooltip:card.tooltip,rewardTooltips:card.rewards.map(r=>r.tooltip)});
  }
  assert.equal(hash(source),report.sourceSha256);const assembly=JSON.parse(fs.readFileSync(path.join(base,'preview/assembly.json'),'utf8'));const embedded=assembly.sourceGraph.find(r=>r.path==='scripts/custom_game/daily_remaining_5d5c1152eb.js');assert.equal(embedded.sha256,report.sourceSha256,'screens use frozen production JS');report.previewAssembly='preview/assembly.json';report.status='PASS_DAILY_BUTTON_COUNTS_BROWSER';
 }catch(error){report.status='FAIL_DAILY_BUTTON_COUNTS_BROWSER';report.failure=error.stack||String(error);try{report.failureSnapshot=await b.run('('+snapshot.toString()+')()');await b.shot(path.join(out,'failure.png'));}catch{}throw error;}
 finally{fs.writeFileSync(path.join(base,'preview_report.json'),JSON.stringify(report,null,2));b.close();}
 console.log('DAILY_BUTTON_COUNTS_PASS '+path.relative(repo,path.join(base,'preview_report.json')));
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
