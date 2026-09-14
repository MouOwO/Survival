const fs=require('fs'),vm=require('vm'),assert=require('assert');
const cfg={},root={actuallayoutwidth:1920,actuallayoutheight:1080,GetParent:()=>null,GetPositionWithinWindow:()=>({x:0,y:0})};
const parent={...root,actualuiscale_x:1,actualuiscale_y:1,GetParent:()=>root};
const slot=(x,y)=>({actuallayoutwidth:116,GetParent:()=>root,GetPositionWithinWindow:()=>({x,y})});
const upper=slot(1100,800),tip={style:{},GetParent:()=>parent};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/tooltip_position.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg},$:{Schedule:()=>{throw Error('deferred position');}}});
const positions=[];
for(const scale of [1,.75]){
 parent.actualuiscale_x=parent.actualuiscale_y=scale;
 for(const y of [800,916])for(const x of [1100,1216,1332])for(const height of [90,380]){
  tip.actuallayoutheight=height;
  cfg.SurvivalTooltipPosition.PlaceInventoryAbove(tip,slot(x,y),upper);
  assert.equal(tip.style.verticalAlign,'bottom');
  assert.equal(Number.parseFloat(tip.style.marginBottom)*scale,285);
  positions.push(tip.style.position);
 }
}
assert(new Set(positions).size>=3,'horizontal anchor follows hovered slot');
const code=fs.readFileSync('panorama/src/scripts/custom_game/inventory_tooltip.js','utf8');
let created=0;const env={$:{CreatePanel:()=>{created++;return {AddClass(){}};}}};
vm.runInNewContext(code.slice(code.indexOf('    function addField('),code.indexOf('    function itemView(')),env);
const fields={};env.addField(fields,'attack',12);env.addField(fields,'armor',20);const count=created;
for(let i=0;i<10;i++){
 fields.__fieldCursor=0;fields.__fieldRows.forEach(row=>row.visible=false);
 env.addField(fields,'attack',i);
 assert.equal(created,count);assert.equal(fields.__fieldRows[0].__right.text,String(i));
 assert.equal(fields.__fieldRows[1].visible,false);
}
const css=fs.readFileSync('panorama/src/styles/custom_game/inventory_tooltip.css','utf8');
assert(css.includes('transition-duration: 0.1s'));
assert(/\.Hidden\s*\{\s*visibility: visible; opacity: 0;/.test(css));
const render=code.slice(code.indexOf('    function render('),code.indexOf('    function inventoryRoot('));
assert(render.indexOf('positioner.PlaceInventoryAbove(')<render.indexOf('tooltip.RemoveClass("Hidden")'));
assert(!code.includes('RemoveAndDeleteChildren'));
console.log('INVENTORY_TOOLTIP_STABILITY_PASS: both rows, variable heights/scales, horizontal follow, synchronous placement, reusable fields, opacity transition');
