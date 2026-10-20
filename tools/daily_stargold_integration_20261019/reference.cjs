'use strict';
const fs=require('node:fs'),path=require('node:path');
const {browser}=require('../shop_ui_12h/cdp.cjs');
process.chdir(path.resolve(__dirname,'../..'));
const keep=setInterval(()=>{},1000);
(async()=>{const b=await browser();try{
await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1000,deviceScaleFactor:1,mobile:false});
await b.go('design_refs/daily_stargold_polish_20261019/R5_星穹鎏金.html');
const data=await b.run(`(()=>{const origin=document.querySelector('.window').getBoundingClientRect(),selectors=['.window','.header','.header h1','.native-divider','.body','.section-head','.section-head h2','.summary','.weekdays','.calendar','.day','.day-head','.slot','.calendar-actions','#claim','#rules','.pass-panel','.pass-heading','.pass-heading h2','.pass-heading p','.milestones','.milestone','.when','.milestone .item-icon','.reward-name','.lock','.pass-actions','#buy','.footer'];return Object.fromEntries(selectors.map(s=>{const e=document.querySelector(s),r=e.getBoundingClientRect(),c=getComputedStyle(e);return [s,{x:r.x-origin.x,y:r.y-origin.y,w:r.width,h:r.height,font:c.fontFamily,size:c.fontSize,weight:c.fontWeight,color:c.color}]}));})()`);
fs.mkdirSync('design_refs/daily_stargold_integration_20261019',{recursive:true});fs.writeFileSync('design_refs/daily_stargold_integration_20261019/reference_geometry.json',JSON.stringify(data,null,2));
console.log(JSON.stringify(data));
}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>clearInterval(keep));
