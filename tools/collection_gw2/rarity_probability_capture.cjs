'use strict';
// A focused real-pointer capture, with assertions made while the tooltip is
// still visible. All stock/currency/probabilities are explicit local fixtures.
const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const {fixture}=require('./fixture.cjs');
const {read,settle,click,hoverCard,nativeInputHits,validateArt}=require('./onepage_capture.cjs');
const {auditSources}=require('./entry_capture.cjs');
const preview='design_refs/collection_gw2_v2/work/entry_preview',out='design_refs/collection_gw2_v2/work/onepage_final';
const colors={N:'rgb(143, 196, 123)',R:'rgb(116, 200, 242)',SR:'rgb(182, 128, 238)',SSR:'rgb(245, 198, 94)',UR:'rgb(239, 83, 80)'};
function titleMatchesFrame(check){assert.equal(check.titleColor,colors[check.quality],'The actual tooltip title uses its rarity color');assert.equal(check.titleColor,check.frameColor,'Title and portrait frame show the same grade');return check;}
async function main(){
 const formal=fixture(),report={at:new Date().toISOString(),kind:'collection_rarity_live_tooltip_pointer_capture',notGameCapture:true,outboundStubs:true,assembly:JSON.parse(fs.readFileSync(preview+'/assembly.json','utf8')),checks:[],continuousTitleChecks:[],limitations:['Production sources run in an isolated browser Panorama adapter. Inventory and probability values use explicit fixture stock and formal CSV weights, not a live player account.']};
 const b=await browser();try{
  await b.go(preview+'/index.html');assert(await b.run('previewReady'));await settle(b);await click(b,'HandoffNav_collection');await nativeInputHits(b);
  for(const category of ['ex','friend','wife','beast']){
   await click(b,'CollectionGW2Tab_'+category);await b.run('entrySend('+JSON.stringify(category)+');true');await settle(b);validateArt(await read(b),category);
   const index=formal.pages[category].findIndex(row=>row.quality==='UR'&&row.draw_enabled!==0&&row.draw_probability>0);assert(index>=0,'An explicitly unowned UR provides a positive current probability');
   report.checks.push(titleMatchesFrame(await hoverCard(b,index,1920,1080,out+'/'+category+'_ur_probability_1920x1080.png')));
  }
  // Consecutive real mouse hovers reuse the same tooltip controller: a red UR
  // name must not leak its color into the next lower-grade character.
  for(const quality of ['UR','N','SSR','SR','R','UR']){const index=formal.pages.beast.findIndex(row=>row.quality===quality);report.continuousTitleChecks.push(titleMatchesFrame(await hoverCard(b,index,1920,1080)));}
  assert(!(await read(b)).calls.some(call=>/draw|claim|purchase|checkout/.test(call.name)),'No purchase/draw is sent even to the in-memory stub');
  auditSources(report);report.sourceHash=crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex');report.status=report.sourceChanged.length?'PASS_UI_WITH_EXTERNAL_SOURCE_CHANGE':'PASS_COLLECTION_RARITY_VISIBLE_TOOLTIP';
 }catch(error){report.status='FAIL_COLLECTION_RARITY_VISIBLE_TOOLTIP';report.error=error.stack||String(error);throw error;}
 finally{b.close();fs.writeFileSync(out+'/rarity_probability_proof.json',JSON.stringify(report,null,2));}
 console.log('COLLECTION_RARITY_VISIBLE_TOOLTIP_PASS '+out+'/rarity_probability_proof.json');
}
if(require.main===module)main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
