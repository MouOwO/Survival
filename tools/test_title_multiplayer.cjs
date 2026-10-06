const fs=require('fs'),assert=require('assert');
let source=fs.readFileSync('tools/test_titles_world_fx.cjs','utf8').replace("['title_layered_art','world_health_bar_anchor','title_world']","['title_layered_art','title_motion_data','title_series_art','world_health_bar_anchor','title_world']");
source+=`
world=[0,0,0];camX=960;camY=540;now=.3;
for(let id=0;id<10;id++)listener('survival_hero_health_bar','title_'+id,{entindex:20+id,player_id:id,title_id:'youlong',unit_name:'hero'});
frame(0);
const roots=byClass('SurvivalWorldTitle');assert.equal(roots.length,10);
function band(root){const found=[];(function visit(p){if(p.classes.has('MotionBand'))found.push(p);p.children.forEach(visit);})(root);return found[found.length-1];}
const lights=roots.map(band),positions=lights.map(p=>p.style.position);
assert.equal(new Set(positions).size,10,'ten players have distinct sweep phases');
assert(lights.some(p=>+p.style.opacity>0)&&lights.some(p=>+p.style.opacity===0),'crowd does not flash in unison');
now+=3;frame(0);assert.deepEqual(lights.map(p=>p.style.position),positions,'every player retains the three-second sweep period');
const before=lights[4].style.position;
listener('survival_hero_health_bar','title_4',{entindex:104,player_id:4,title_id:'youlong',unit_name:'hero'});frame(0);
assert.equal(lights[4].style.position,before,'hero replacement keeps phase');
listener('survival_hero_health_bar','title_4',{entindex:104,player_id:4,title_id:'sihai',unit_name:'hero'});frame(0);
listener('survival_hero_health_bar','title_4',{entindex:104,player_id:4,title_id:'youlong',unit_name:'hero'});frame(0);
assert.equal(band(byClass('SurvivalWorldTitle').slice(-1)[0]).style.position,before,'re-equipping does not reset phase');
const allocationCount=nodes.length;
for(let i=0;i<90;i++)frame();assert.equal(nodes.length,allocationCount,'ten titles animate without allocating new panels');
for(const scale of [.6666667,.8333333,1,1.5]){
 host.actualuiscale_x=host.actualuiscale_y=scale;frame(0);
 const at=cfg.SurvivalWorldHealthBarAnchor.Project(20,world,host);
 for(const p of byClass('SurvivalWorldTitle')){
  assert(p.visible);const [left,top]=p.style.position.split(' ').map(parseFloat);
  assert(Math.abs(top+96+5-at.top)<.006,'five logical pixels clear of own health bar at every scale');
  assert(Math.abs(left+112-(at.left+at.width/2))<.006,'title remains centered above health bar');
 }
}
host.actualuiscale_x=host.actualuiscale_y=1;
for(let id=1;id<10;id++)listener('survival_hero_health_bar','title_'+id,{entindex:-1,title_id:''});
assert.equal(byClass('SurvivalWorldTitle').length,1,'removing crowd preserves the remaining player');
console.log('PASS ten-player phase staggering, 3s repeat, stable respawn/equip, bounded panels and health-bar gap at four scales');
`;
new Function('require',source)(require);
