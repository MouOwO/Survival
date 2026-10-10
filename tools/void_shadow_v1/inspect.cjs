'use strict';
const {browser}=require('../shop_ui_12h/cdp.cjs');
(async()=>{const b=await browser();try{
 await b.call('Emulation.setDeviceMetricsOverride',{width:1672,height:941,deviceScaleFactor:1,mobile:false});
 await b.go('design_refs/void_shadow_v1/work/preview/index.html','?state=edges');await b.run('previewReady');
 console.log(JSON.stringify(await b.run(`({texts:[...document.querySelectorAll('.VoidShadowText')].filter(e=>e.getBoundingClientRect().width&&(e.classList.contains('VoidShadowCount')||e.classList.contains('VoidShadowName'))).slice(0,8).map(e=>{const s=getComputedStyle(e);return {text:e.textContent,font:s.fontFamily,weight:s.fontWeight,overflow:s.overflow,fontSize:s.fontSize};}),images:[...document.querySelectorAll('.VoidShadowQuantityPlate')].slice(0,5).map(e=>({objectFit:getComputedStyle(e).objectFit,width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height})),filters:['all','unlocked','locked'].map(mode=>({mode,count:cfg.SurvivalArchiveVoidV1.Rows().filter(r=>mode==='all'||(r.count_known===1&&(mode==='unlocked'?r.count>0:r.count===0))).length}))})`),null,2));
 }finally{b.close();}})().catch(e=>{console.error(e.stack||e);process.exitCode=1;});
