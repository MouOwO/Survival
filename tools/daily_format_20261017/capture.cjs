'use strict';
// Actual daily controller/XML/CSS under the existing isolated Panorama adapter.
// All server events are in-memory stubs; no game or account interaction.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),base=path.join(repo,'design_refs/daily_format_20261017'),input=path.join(base,'preview/index.html');
const source='panorama/src/scripts/custom_game/daily_remaining_5d5c1152eb.js';
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(path.join(repo,file))).digest('hex');
function snapshot(){
 const visible=n=>!!n&&!n.el.hidden&&getComputedStyle(n.el).display!=='none'&&n.el.getBoundingClientRect().width>0;
 const desc=n=>n?{id:n.id,visible:visible(n),rect:n.el.getBoundingClientRect().toJSON(),text:n.text,renderedText:n.el.innerText,html:n.el.innerHTML,style:n._style,scrollHeight:n.el.scrollHeight,clientHeight:n.el.clientHeight,scrollTop:n.el.scrollTop,overflowY:getComputedStyle(n.el).overflowY}:null;
 return {ready:previewState.ready,errors:previewErrors,rules:desc(nodes.DailyRulesText),rulesBody:desc(nodes.DailyRulesBody),closeExists:!!nodes.DailyGW2RulesClose,tooltip:desc(nodes.DailyGW2Tooltip),tooltipBody:desc(nodes.DailyGW2TooltipBody),tooltipTitle:desc(nodes.DailyGW2TooltipTitle),tooltipViewport:desc(nodes.DailyGW2TooltipViewport),calls:previewCalls,specials:nodes.DailySpecials.Children().map(n=>({id:n.id,definition:n.__dailyGW2Tooltip})),api:cfg.SurvivalDaily.Inspect()};
}
function inViewport(rect,width,height){assert(rect.x>=-1&&rect.y>=-1&&rect.right<=width+1&&rect.bottom<=height+1,'visible panel stays in viewport');}
async function main(){
 const out=path.join(base,'screens');fs.mkdirSync(out,{recursive:true});
 const report={kind:'daily_format_production_components_browser_preview',notGameCapture:true,fixtureOnly:true,source,sourceSha256:hash(source),screens:[],sizes:[],limitations:['Browser Panorama adapter approximates native layout/font rendering; game verification is separate.','Formal daily CSV rewards with synthetic progress, no account or network; outgoing events stay in memory.']};
 const b=await browser();
 try{
  for(const [width,height] of [[1920,1080],[960,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(input);assert(await b.run('previewReady'),'preview ready');await sleep(350);
   const initial=await b.run('('+snapshot.toString()+')()');assert.deepEqual(initial.errors,[]);assert(initial.api.open);assert(!initial.closeExists);
   const beforeCalls=JSON.stringify(initial.calls);
   await b.run('nodes.DailyRules.events.onactivate();syncLayout();true');
   let state=await b.run('('+snapshot.toString()+')()');assert(state.rules.visible);assert.equal(state.rules.style.width,'567px');assert(!state.closeExists);assert(state.rules.rect.width>0&&state.rules.rect.height>0);inViewport(state.rules.rect,width,height);const openRulesBounds=state.rules.rect;
   assert(!/[;；]/.test(state.rulesBody.renderedText.split('累计7次：')[1]));assert.equal(state.rules.overflowY,'auto');assert(state.rules.scrollHeight>state.rules.clientHeight,'long rules remain scrollable');
   assert(state.rulesBody.text.includes('累计7次：聚财古符'));assert(state.rulesBody.text.includes('累计14次：古树眷顾'));assert(state.rulesBody.text.includes('累计21次：森罗本源'));
   const top='rules_'+width+'x'+height+'.png';await b.shot(path.join(out,top),{x:0,y:0,width,height});report.screens.push({file:'screens/'+top,kind:'rules',width,height});
   await b.run('nodes.DailyRulesText.el.scrollTop=99999;true');state=await b.run('('+snapshot.toString()+')()');assert(state.rules.scrollTop>0,'can reach final reward effects');
   const bottom='rules_bottom_'+width+'x'+height+'.png';await b.shot(path.join(out,bottom),{x:0,y:0,width,height});report.screens.push({file:'screens/'+bottom,kind:'rules_scrolled_bottom',width,height});
   await b.run('nodes.DailyRules.events.onactivate();syncLayout();true');assert(!(await b.run('('+snapshot.toString()+')()')).rules.visible,'same ? closes rules');
   await b.run('nodes.DailySpecials.Children()[2].events.onmouseover();syncLayout();true');await sleep(430);
   state=await b.run('('+snapshot.toString()+')()');assert(state.tooltip.visible);inViewport(state.tooltip.rect,width,height);assert(state.tooltipTitle.text.includes('森罗本源'));assert(!/[;；]/.test(state.tooltipBody.text));
   const expected=['开局木材+200','开局金币+200','伐木效率+1','金矿收益+5%','人口+1','英雄全属性加成+8%','星悦积分+88'];
   const lines=state.tooltipBody.text.split('\n');for(const line of expected)assert(lines.includes(line),'each configured effect occupies one line: '+line);
   assert.equal(JSON.stringify(state.calls),beforeCalls,'opening/closing/hover emits no request');assert.deepEqual(state.errors,[]);
   const tooltip='tooltip_'+width+'x'+height+'.png';await b.shot(path.join(out,tooltip),{x:0,y:0,width,height});report.screens.push({file:'screens/'+tooltip,kind:'month_card_buff_tooltip',width,height});
   report.sizes.push({width,height,noCloseButton:true,authoredRulesWidth:567,rulesBounds:openRulesBounds,canToggleClose:true,rulesScrollable:true,tooltipBounds:state.tooltip.rect,tooltipLines:lines,noClaimOrPurchaseCalls:true,errors:state.errors});
  }
  assert.equal(hash(source),report.sourceSha256,'production source frozen throughout capture');
  const assembly=JSON.parse(fs.readFileSync(path.join(base,'preview/assembly.json'),'utf8'));report.previewAssembly='preview/assembly.json';
  const record=assembly.sourceGraph.find(r=>r.path==='scripts/custom_game/daily_remaining_5d5c1152eb.js');assert(record);assert.equal(record.sha256,report.sourceSha256,'embedded source equals frozen production source');
  report.status='PASS_DAILY_FORMAT_BROWSER';
 }catch(error){report.status='FAIL_DAILY_FORMAT_BROWSER';report.failure=error.stack||String(error);try{report.failureSnapshot=await b.run('('+snapshot.toString()+')()');await b.shot(path.join(out,'failure.png'));}catch{}throw error;}
 finally{fs.writeFileSync(path.join(base,'preview_report.json'),JSON.stringify(report,null,2));b.close();}
 console.log('DAILY_FORMAT_PREVIEW_PASS '+path.relative(repo,path.join(base,'preview_report.json')));
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
