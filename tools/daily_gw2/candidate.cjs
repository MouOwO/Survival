'use strict';
// Actual assembled production UI in the isolated browser adapter, never game.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const {inspect}=require('./acceptance.cjs');
const [name,widthValue='960',heightValue='720']=process.argv.slice(2);
assert(/^[a-z0-9_]+$/.test(name||''),'Unique candidate name');
const width=Number(widthValue),height=Number(heightValue);
assert(Number.isInteger(width)&&Number.isInteger(height)&&width>=640&&width<=3840&&height>=360&&height<=2160);
const previewRoots=['daily_gw2_v2','daily_gw2_v1'].map(version=>path.resolve(__dirname,'../../design_refs/'+version+'/work'));
const base=previewRoots.find(directory=>fs.existsSync(path.join(directory,'preview/index.html')));
assert(base,'Build the daily preview first: node tools/daily_gw2/preview.cjs');
const png=path.join(base,name+'.png'),json=path.join(base,name+'.json');
assert(!fs.existsSync(png)&&!fs.existsSync(json),'Preserve existing candidate evidence');
async function main(){const b=await browser();try{
    await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
    await b.go(path.join(base,'preview/index.html'));
    assert(await b.run('previewReady'),'Daily preview ready');
    await b.run('syncLayout();true');
    await new Promise(resolve=>setTimeout(resolve,350));
    const state=await b.run('('+inspect.toString()+')()');
    assert.deepEqual(state.errors,[],'No production or adapter errors');
    await b.shot(png,{x:0,y:0,width,height});
    const mask=await b.run('({uri:nodes.DailyGW2Background._style.opacityMask,cssMask:getComputedStyle(nodes.DailyGW2Background.el).maskImage,opacity:getComputedStyle(nodes.DailyGW2Background.el).opacity})');
    fs.writeFileSync(json,JSON.stringify({kind:'actual_production_component_browser_preview',notGameCapture:true,width,height,mask,state},null,2),{flag:'wx'});
    console.log('DAILY_CANDIDATE_CAPTURED '+path.relative(process.cwd(),png));
}finally{b.close();}}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
