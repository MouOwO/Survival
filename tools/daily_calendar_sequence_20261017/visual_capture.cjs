'use strict';
// Small screenshot check of the seven actual production column headings.
const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const base='output/daily_calendar_sequence_20261017',source='panorama/src/scripts/custom_game/daily_remaining_5d5c1152eb.js';
const sha=()=>crypto.createHash('sha256').update(fs.readFileSync(source,'utf8').replace(/^\uFEFF/,'')).digest('hex');
async function main(){
 const frozen=sha(),assembly=JSON.parse(fs.readFileSync(base+'/visual_preview/assembly.json','utf8'));
 assert.equal(assembly.sourceGraph.find(r=>'panorama/src/'+r.path===source).sha256,frozen);
 const b=await browser(),report={kind:'daily_calendar_sequence_header_browser_preview',notGameCapture:true,fixtureOnly:true,source,sha256:frozen,screens:[]};
 try{for(const [width,height]of[[1920,1080],[1280,720]]){
  await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(base+'/visual_preview/index.html');assert(await b.run('previewReady'));
  const state=await b.run(`(()=>{const headers=Array.from({length:7},(_,i)=>{const n=nodes['DailyGW2Weekday_'+i],s=getComputedStyle(n.el),r=n.el.getBoundingClientRect(),c=nodes['DailyGW2Day_'+(i+1)].el.getBoundingClientRect();return {id:n.id,text:n.text,bounds:r.toJSON(),textAlign:s.textAlign,font:s.fontFamily,fontSize:s.fontSize,columnCenter:c.x+c.width/2,center:r.x+r.width/2,interactive:n.hittest};});return {headers,errors:previewErrors,fontLoaded:document.fonts.check('27px "Source Han Sans SC"','ⅠⅡⅢⅣⅤⅥⅦ')};})()`);
  assert.deepEqual(state.errors,[]);assert.deepEqual(state.headers.map(r=>r.text),['Ⅰ','Ⅱ','Ⅲ','Ⅳ','Ⅴ','Ⅵ','Ⅶ']);assert(state.fontLoaded);
  for(const row of state.headers){assert.equal(row.textAlign,'center');assert(Math.abs(row.center-row.columnCenter)<.1);assert(row.bounds.width>0&&row.bounds.height>0);assert.equal(row.interactive,false);}
  const first=state.headers[0].bounds,last=state.headers[6].bounds,file=base+'/visual_header_'+width+'x'+height+'.png';
  const clip={x:Math.floor(first.x-12),y:Math.floor(first.y-10),width:Math.ceil(last.right-first.x+24),height:Math.ceil(first.height+20)};
  await b.shot(file,clip);report.screens.push({width,height,file,clip,...state});
 }
 assert.equal(sha(),frozen);report.status='PASS_ROMAN_COLUMN_HEADERS';fs.writeFileSync(base+'/visual_report.json',JSON.stringify(report,null,2)+'\n');console.log(report.status+' '+base+'/visual_report.json');
 }finally{b.close();}
}
let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('ROMAN_HEADER_CAPTURE_INCOMPLETE');process.exitCode=1;}});main().then(()=>{settled=true;},e=>{settled=true;console.error(e.stack||e);process.exitCode=1;});
