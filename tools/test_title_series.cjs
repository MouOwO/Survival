const fs=require('fs'),assert=require('assert');
// Reuse the actual world projection/fog/FX harness, retaining all peak regressions.
let source=fs.readFileSync('tools/test_titles_world_fx.cjs','utf8').replace("['title_layered_art','world_health_bar_anchor','title_world']","['title_layered_art','title_motion_data','title_series_art','world_health_bar_anchor','title_world']");
source+=`
const ids=Object.keys(cfg.SurvivalTitleSeriesArt.Config);
assert.equal(ids.length,8);
for(const id of ids){ world=[0,0,0];camX=960;
 listener('survival_hero_health_bar','title_0',{entindex:17,title_id:id,unit_name:'hero'});frame(0);
 assert.equal(byClass('SurvivalWorldTitle').length,1);
 assert.equal(byClass('SurvivalTitleDragon').length,0,'previous dragon removed on title switch');
 assert.equal(byClass('SurvivalTitleStar').length,0,'new collection has no star clutter');
 assert.equal(embers().length,0,'previous movement residue removed');
 const pictures=byClass('MotionAtlas');assert(pictures.length>=5);assert(pictures.every(p=>p.image.endsWith('/'+id+'_atlas.png')),'world receive must preserve atlas source');
 const light=byClass('MotionBand').slice(-1)[0];
 now=.2;frame(0);let y=light.style.position;
 now=.7;frame(0);assert.notEqual(light.style.position,y);
 now=1.5;frame(0);assert.equal(+light.style.opacity,0);
 now=3.2;frame(0);assert.equal(light.style.position,y,'three-second downward repeat');
 const allocated=nodes.length;
 for(let n=0;n<80;n++){world[0]+=2;frame();}
 assert.equal(nodes.length,allocated,'no per-frame allocation or particle emission');
 occluded=true;frame();assert(!byClass('SurvivalWorldTitle')[0].visible);occluded=false;
 alive=false;frame();assert(!byClass('SurvivalWorldTitle')[0].visible);alive=true;frame();
 assert(byClass('SurvivalWorldTitle')[0].visible);
}
listener('survival_hero_health_bar','title_0',{entindex:17,title_id:'peak_perfection',unit_name:'hero'});frame();
assert.equal(byClass('MotionAtlas').length,0);assert.equal(byClass('SurvivalTitleDragon').length,2);
listener('survival_hero_health_bar','title_0',{entindex:17,title_id:''});assert.equal(byClass('SurvivalWorldTitle').length,0);
console.log('PASS eight-title switching, exact asset, light timing, zero clutter allocations, fog/death/unequip and return to peak');
`;
new Function('require',source)(require);
let archive=fs.readFileSync('tools/test_archive_compact.cjs','utf8').split('const data=')[0];
archive+=`
Panel.prototype.SetPanelEvent=function(n,f){this[n]=f;};
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/title_motion_data.js','utf8'),env);
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/title_series_art.js','utf8'),env);
env.current='titles';env.titleSubmitting=false;let sent=[];
env.GameEvents.SendCustomGameEventToServer=(event,data)=>sent.push({event,data});
const rows=Object.keys(cfg.SurvivalTitleSeriesArt.Config).map(id=>({id,name:id,unlocked:1,count:1,preview_only:1,equipped:0}));
const data={category_id:'titles',categories:[],rows,title_preview:1,pending:1};
env.render(data);
rows.forEach((r,i)=>{let c=env.rowCards['titles:'+i].panel;
 assert.equal(c.children.find(p=>p.BHasClass('ArchiveTitleAction')).text,'点击试穿');
 let art=c.children.find(p=>p.BHasClass('ArchiveTitleArt'));assert.equal(art.children.length,1);
 assert.equal(art.children[0].children[0].children.filter(p=>p.BHasClass('MotionLight')).slice(-1)[0].visible,false,'archive art is static');
 env.titleSubmitting=false;c.onactivate();assert.equal(sent[sent.length-1].data.title_id,r.id);
});
rows.forEach(r=>{r.unlocked=0;r.count=0;r.preview_only=0;});data.pending=0;data.title_preview=0;env.render(data);
let count=sent.length;env.titleSubmitting=false;env.rowCards['titles:0'].panel.onactivate();assert.equal(sent.length,count);
console.log('PASS eight archive cards, test labels, preview during pending cloud save, static art, production locked rejection');
`;
new Function('require',archive)(require);
