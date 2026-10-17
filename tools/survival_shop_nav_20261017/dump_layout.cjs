'use strict';
// Native APIs are doubles. All navigation panels/styles are created by the
// complete production scripts; this artifact is not a live game capture.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {makeFixture}=require('./fixture.cjs');
const root=path.resolve(__dirname,'../..'),f=makeFixture();
function node(panel){
    return {id:panel.id,type:panel.paneltype,visible:panel.visible,enabled:panel.enabled,
        hittest:panel.hittest,style:{...panel.style},text:panel.text||'',image:panel.image||'',
        classes:[...panel.classes],children:panel.children.filter(p=>p.IsValid()).map(node)};
}
function snapshot(name){
    return {name,viewport:{width:f.ctx.actuallayoutwidth,height:f.ctx.actuallayoutheight,scale:f.ctx.actualuiscale_x},
        top:node(f.currentTop()),collection:node(f.collection()),heroShortcut:node(f.portrait),
        worldLabelExclusions:JSON.parse(JSON.stringify(f.cfg.HandoffWorldOcclusion))};
}
const states=[snapshot('locked')];
f.unlock(true);states.push(snapshot('active'));
f.unlock(false);states.push(snapshot('relocked'));
const sources={};
for(const name of ['topnav_remaining_5d5c1152eb.js','collection_nav.js']){
    const file=path.join(root,'panorama/src/scripts/custom_game',name);
    sources[path.relative(root,file).replaceAll('\\','/')]=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}
const directory=path.join(root,'output/survival_shop_nav_20261017');
fs.mkdirSync(directory,{recursive:true});
const output=path.join(directory,'layout_states.json');
fs.writeFileSync(output,JSON.stringify({scope:'Complete production HUD/collection JS with native API doubles; browser-preview input, not a live-game screenshot',sources,states},null,2)+'\n');
console.log(output);
