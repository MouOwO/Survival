const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const scripts=path.resolve(process.argv[2]||'panorama/src/scripts/custom_game');
const geometry=require(path.join(scripts,'geometry_remaining_5d5c1152eb.js'));
const source=fs.readFileSync(path.join(scripts,'topnav_remaining_5d5c1152eb.js'),'utf8');

for(const [w,h] of [[640,480],[1280,720],[1920,1080],[2560,1440]])for(const count of [4,7,32]){
 const hero=geometry(w,h,count,false,false,{attributes:true});
 const monster=geometry(w,h,count,false,false,{monster:true});
 const builder=geometry(w,h,count,false,false,{attributes:false});
 for(const g of [hero,monster,builder]){
  assert(Math.abs(g.x+g.width*g.scale/2-w/2)<.001,'visible HUD centers at '+w+'px with '+count+' abilities');
  assert(Math.abs(g.y+g.height*g.scale-(h-6))<.001,'selected-unit HUD remains bottom anchored');
  assert(g.x>=14 && g.x+g.width*g.scale<=w-14,'HUD fits both screen edges');
  assert.equal(g.slot,116);assert.equal(g.step,120);assert.equal(g.portraitSize,264);
  assert((count-1)*g.step+g.slot<=g.centerWidth-20,'native ability row retains room for every slot');
  assert.equal(g.actionOffset,g.centerX+10);assert.equal(g.attributeX,g.centerX+g.centerWidth);
 }
 for(const key of ['scale','heroWidth','portraitSize','centerWidth','barWidth','y'])assert.equal(monster[key],hero[key],'monster retains hero '+key);
 assert.equal(hero.heroWidth-293,180);assert.equal(hero.attributeWidth,180);
 assert.equal(hero.inventoryX+401,hero.width,'complete six-item panel is retained');
 assert.equal(monster.width,monster.attributeX,'monster has no empty item columns');
 assert.equal(builder.attributeWidth,0);assert.equal(builder.inventoryX,builder.attributeX);
}

const stats=['attack','armor','attack_speed','strength','agility','intelligence'].map(key=>[key]);
const nodes={};let created=0;
function panel(id,parent=null){return {id,parent,style:{},GetParent(){return this.parent;},SetParent(next){this.parent=next;}};}
for(const [key] of stats){
 const row=nodes['HandoffStatRow_'+key]=panel('HandoffStatRow_'+key);
 for(const prefix of ['HandoffStatIcon_','HandoffStatName_','HandoffStat_','HandoffStatBonus_','HandoffStatPercent_'])nodes[prefix+key]=panel(prefix+key,row);
}
const env={stats,nodes,ctx:{actualuiscale_y:1},valid:p=>!!p,style:(p,v)=>Object.assign(p.style,v),create:(type,parent,id)=>{created++;return nodes[id]=panel(id,parent);}};
vm.createContext(env);
// Exercise production place(), including its fixed minWidth assignment.
vm.runInContext(source.slice(source.indexOf('    function cssNumber('),source.indexOf('    function create(')),env);
const place=env.place;
env.place=(p,x,y,w,h,overrides)=>{
 assert(p,'every stat component has an owned panel');
 for(const n of [x,y,w,h])assert(Number.isFinite(n),'finite layout coordinate');
 assert(w>=0 && h>=0,'hidden stat rows never receive negative dimensions');
 place(p,x,y,w,h,overrides);
};
vm.runInContext(source.slice(source.indexOf('    function layoutStats('),source.indexOf('    ["hp","mp"].forEach')),env);

for(const args of [
 [false,false,{attributes:true}],
 [false,false,{attributes:false}],
 [false,false,{monster:true}],
 [true,false,{building:true}],
 [false,true,{tree:true}],
 [false,false,{worker:true}],
 [false,false,{worker:true,lumberjack:true}],
 [false,false,{worker:true,lumberjack:true,multi:true}]
]){
 const g=geometry(1600,900,4,...args);env.layoutStats(g);
 for(const [key] of stats){
  assert.equal(nodes['HandoffStatIcon_'+key].style.height,g.worker?'64px':'48px');
  assert.equal(nodes['HandoffStat_'+key].style.verticalAlign,'center');
  for(const prefix of ['HandoffStatBonusRow_','HandoffStatBonus_','HandoffStatPercent_']){
   assert.equal(nodes[prefix+key].style.width,'fit-children');
   assert.equal(nodes[prefix+key].style.minWidth,'0px');
  }
 }
 if(g.lumberjack)for(const key of ['attack','attack_speed']){
  const row=nodes['HandoffStatRow_'+key].style;
  assert(parseFloat(row.position.split(' ')[1])+64<g.height,'visible worker rows fit below their skill row');
 }
}

env.layoutStats(geometry(1920,1080,7,false,false,{attributes:true}));
for(const [key] of stats){
 const row=nodes['HandoffStatRow_'+key],main=nodes['HandoffStatMain_'+key],bonus=nodes['HandoffStatBonusRow_'+key];
 const icon=nodes['HandoffStatIcon_'+key],value=nodes['HandoffStat_'+key],amount=nodes['HandoffStatBonus_'+key],pct=nodes['HandoffStatPercent_'+key];
 assert.equal(main.style.horizontalAlign,'left');assert.equal(bonus.style.horizontalAlign,'center');
 assert.equal(icon.GetParent(),main);assert.equal(value.GetParent(),main);assert.equal(amount.GetParent(),bonus);assert.equal(pct.GetParent(),bonus);
 assert.equal(value.style.fontSize,'32px');assert.equal(value.style.textOverflow,'shrink');
 assert.equal(value.style.textAlign,'left');assert.equal(value.style.marginLeft,'4px');
 assert.equal(main.style.width,row.style.width,'fixed main columns occupy the same width for short and long values');
 assert.equal(value.style.width,value.style.maxWidth,'value columns retain their full budget');
 assert(parseFloat(value.style.maxWidth)>=100,'1291.4 retains normal font space beside the icon');
 assert(parseFloat(icon.style.width)+parseFloat(value.style.marginLeft)+parseFloat(value.style.maxWidth)<=parseFloat(row.style.width),'long numbers have a bounded shrink path inside the gutter');
 assert(parseFloat(amount.style.maxWidth)+parseFloat(pct.style.marginLeft)+parseFloat(pct.style.maxWidth)<=parseFloat(row.style.width)+.001,'bonuses and percentages have disjoint width budgets');
}
for(let row=0;row<3;row++){
 const left=nodes['HandoffStatRow_'+stats[row][0]].style,right=nodes['HandoffStatRow_'+stats[row+3][0]].style;
 assert.equal(left.position.split(' ')[1],right.position.split(' ')[1],'left and right stats share row height');
 assert.equal(left.width,right.width,'both gutters use the same icon/value columns');
 assert.equal(left.position.split(' ')[0],'295px','left rows use the reduced outer padding');
}
for(const key of ['attack','armor','attack_speed'])assert.equal(nodes['HandoffStat_'+key].style.position,'0px 0px 0px');
const cornerStart=source.indexOf('            var centerPlate=nine(');
const cornerEnd=source.indexOf('            // A filled plate',cornerStart);
assert(cornerStart>=0&&cornerEnd>cornerStart);
const plate={style:{}};
const corners={g:null,background:{},nine:()=>plate,centerOffset:g=>g.centerX,style:(p,v)=>{assert.equal(p,plate,'only background plate receives corner clipping');Object.assign(p.style,v);}};
vm.createContext(corners);
for(const [presentation,building,tree,rounded] of [
 [{attributes:true},false,false,false],
 [{monster:true},false,false,false],
 [{worker:true},false,false,true],
 [{worker:true,lumberjack:true,multi:true},false,false,true],
 [{building:true},true,false,true],
 [{tree:true},false,true,true],
 [{attributes:true},false,false,false]
]){
 corners.g=geometry(1920,1080,4,building,tree,presentation);
 vm.runInContext(source.slice(cornerStart,cornerEnd),corners);
 assert.equal(plate.style.overflow,rounded?'clip':'noclip','clipping restores when switching between compact and hero selection');
 assert.equal(plate.style.borderRadius,rounded?'14px 14px 0px 0px':'0px');
}
// The five-pixel adjustment remains exact under HUD and window scaling.
for(const [width,height] of [[1280,720],[1920,1080],[2560,1440]])for(const uiScale of [.75,1,1.25]){
 const g=geometry(width,height,7,false,false,{attributes:true});
 env.ctx.actualuiscale_y=uiScale;env.layoutStats(g);
 for(let index=0;index<6;index++){
  const row=nodes['HandoffStatRow_'+stats[index][0]].style;
  const y=parseFloat(row.position.split(' ')[1]);
  assert(Math.abs((y-(32+(index%3)*98))*g.scale*uiScale-5)<.001,'all six stats move down five physical pixels');
  assert.equal(row.position.split(' ')[1],nodes['HandoffStatRow_'+stats[(index+3)%6][0]].style.position.split(' ')[1],'opposing stats stay level');
 }
}
env.ctx.actualuiscale_y=1;
assert.equal(created,12,'layout reuses its six main/bonus groups across selection changes');
// Changing the size of a worker selection must not move its action/stats plate.
// The portrait group can reserve the full height without resizing native scenes.
for(const [w,h] of [[640,480],[960,720],[1280,720],[1600,900],[1920,1080],[2560,1440],[3440,1440]])for(const count of [1,4,8]){
 const single=geometry(w,h,count,false,false,{worker:true,lumberjack:true});
 const multi=geometry(w,h,count,false,false,{worker:true,lumberjack:true,multi:true});
 assert.equal(single.height,260);assert.equal(multi.height,single.height);
 assert.equal(single.scale,multi.scale);assert.equal(single.y,multi.y);
 assert.equal(single.actionX,multi.actionX,'native action row never moves when adding worker portraits');
 assert(Math.abs(multi.y+multi.height*multi.scale-h)<.001,'worker plate is flush with the viewport bottom');
 assert.equal(multi.portraitY,23);assert.equal(multi.portraitHeight,237);
 assert.equal(multi.portraitY+multi.portraitHeight,multi.height,'portrait area reaches the same bottom as the action plate');
 assert(multi.x>=0 && multi.x+multi.width*multi.scale<=w,'both worker plates remain within the viewport');
}
console.log('HUD_COMPACT_GEOMETRY_PASS: 640/1280/1920/2560px; four/seven/32 native abilities; six items; centered whole HUD; fixed left icon/value columns; matching row heights; compact padding; long values; worker/tree/building transitions; isolated compact top-corner clipping');
