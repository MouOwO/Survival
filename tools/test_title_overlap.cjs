const fs=require('fs');
let source=fs.readFileSync('tools/test_titles_world_fx.cjs','utf8').replace("['title_layered_art','world_health_bar_anchor','title_world']","['title_layered_art','title_motion_data','title_series_art','world_health_bar_anchor','title_world']");
source+=`
{
listener('survival_hero_health_bar','title_0',{entindex:-1,title_id:''});
const units={},titles={};let localPlayer=0,hero=100;
const barState=Object.freeze({bar_width:120,health:100,max_health:100,alive:1});
env.Date={now:()=>now*1000};env.Game.GetLocalPlayerID=()=>localPlayer;
env.Players={GetPlayerHeroEntityIndex:()=>hero};
env.CustomNetTables.GetTableValue=()=>barState;
env.Entities={IsValidEntity:e=>!!units[e],IsAlive:e=>!!units[e]&&!units[e].dead,
 IsDormant:e=>!!units[e]&&!!units[e].fog,IsIllusion:()=>false,GetUnitName:()=> 'hero',
 GetAbsOrigin:e=>units[e].pos,GetHealthBarOffset:()=>190};
camX=960;camY=540;hostOffset={x:0,y:0};host.actualuiscale_x=host.actualuiscale_y=1;occluded=false;
function equip(id,x,y,title='youlong'){
 const ent=100+id;units[ent]={pos:[x,y,0]};
 listener('survival_hero_health_bar','title_'+id,{entindex:ent,player_id:id,title_id:title,unit_name:'hero'});
 titles[id]=byClass('SurvivalWorldTitle').slice(-1)[0];return titles[id];
}
function unequip(id){listener('survival_hero_health_bar','title_'+id,{entindex:-1,title_id:''});}
function advance(seconds){for(let i=0;i<Math.ceil(seconds*60);i++)frame(1/60);}
function alpha(id){return Number(titles[id].style.opacity);}
function moveUnit(id,x,y=0){units[100+id].pos=[x,y,0];}
equip(0,0,0);equip(1,30,0);equip(2,500,-100);frame(0);
assert.equal(alpha(0),1,'own title always wins');assert.equal(alpha(1),0,'overlapping new peer never flashes on');assert.equal(alpha(2),1,'distant peer remains visible');
const ownPosition=titles[0].style.position;
moveUnit(1,360);advance(.18);moveUnit(1,30);advance(.03);moveUnit(1,360);advance(.18);assert.equal(alpha(1),0,'renewed contact restarts the recovery delay');moveUnit(1,30);advance(.05);
moveUnit(1,360);advance(.2);assert.equal(alpha(1),0,'recovery waits for a stable gap');
advance(.15);assert(alpha(1)>0&&alpha(1)<1,'recovery is gradual');advance(.3);assert.equal(alpha(1),1);
moveUnit(1,40);advance(.05);assert(alpha(1)>0&&alpha(1)<1,'existing title fades out smoothly');advance(.2);assert.equal(alpha(1),0);assert.equal(alpha(0),1);
moveUnit(1,195);advance(.8);assert.equal(alpha(1),0,'small edge jitter cannot release a suppressed title');
moveUnit(1,220);advance(.7);assert.equal(alpha(1),1);assert.equal(titles[0].style.position,ownPosition,'collision never moves the local title');
// Peer priority is independent of publication order and stable near equal distances.
moveUnit(0,-500);moveUnit(1,30);moveUnit(2,120);advance(.8);
assert.equal(alpha(1),1);assert.equal(alpha(2),0,'nearer center wins the peer overlap');
moveUnit(1,60);moveUnit(2,50);advance(.8);assert.equal(alpha(1),1);assert.equal(alpha(2),0,'priority hysteresis prevents oscillation');
moveUnit(1,170);moveUnit(2,0);advance(.8);assert.equal(alpha(1),0);assert.equal(alpha(2),1,'substantially nearer peer can take priority');
// Protect the local health bar even when its owner has no title equipped.
unequip(0);moveUnit(0,0);moveUnit(1,155,-100);moveUnit(2,500);advance(.8);
assert.equal(alpha(1),0,'peer touching the edge of the 120px local bar is suppressed without a local title');
moveUnit(1,230,-100);advance(.8);assert.equal(alpha(1),1);
assert.deepEqual(barState,{bar_width:120,health:100,max_health:100,alive:1},'health state is read-only');
// Scale/offset changes must use a single coordinate system for both rectangles.
equip(0,0,0);moveUnit(1,20);moveUnit(2,500);
for(const scale of [.6666667,.8333333,1,1.5]){
 host.actualuiscale_x=host.actualuiscale_y=scale;hostOffset={x:17,y:11};advance(.7);
 assert.equal(alpha(0),1);assert.equal(alpha(1),0);
 const at=cfg.SurvivalWorldHealthBarAnchor.Project(100,units[100].pos,host);
 const pos=titles[0].style.position.split(' ').map(parseFloat);
 assert(Math.abs(pos[0]+112-at.left-at.width/2)<.006&&Math.abs(pos[1]+101-at.top)<.006,'title stays attached to its own bar');
}
host.actualuiscale_x=host.actualuiscale_y=1;hostOffset={x:0,y:0};
// A fogged/dead/unequipped winner must stop suppressing peers immediately.
moveUnit(0,-500);moveUnit(1,0);moveUnit(2,100);advance(.8);assert.equal(alpha(1),1);assert.equal(alpha(2),0);
units[101].fog=true;advance(.8);assert(!titles[1].visible);assert.equal(alpha(2),1);
units[101].fog=false;advance(.8);assert.equal(alpha(1),1);units[101].dead=true;advance(.8);assert.equal(alpha(2),1);
units[101].dead=false;advance(.8);unequip(1);advance(.8);assert.equal(alpha(2),1);
// Independently hosted peak embers must disappear with their faded parent title.
moveUnit(0,0);unequip(2);equip(2,300,0,'peak_perfection');advance(.8);
for(let i=0;i<40;i++){units[102].pos[0]-=1;frame();}assert(shown().length>0);
moveUnit(2,205);advance(.05);assert.equal(shown().length,0,'no orphan residue after crowd suppression');advance(.3);assert.equal(alpha(2),0);
const count=nodes.length;advance(2);assert.equal(nodes.length,count,'crowd resolution creates no per-frame panels');
moveUnit(2,400);advance(.8);assert.equal(alpha(2),1);assert.equal(shown().length,0,'recovery does not create a teleport trail');
// Spectators have no local title; the deterministic center rule still applies.
localPlayer=-1;hero=-1;moveUnit(0,200);moveUnit(2,0);advance(.8);assert.equal(alpha(2),1);assert.equal(alpha(0),0);
console.log('PASS overlap: local priority, local bar without title, smooth fade/hold, edge/priority hysteresis, center winner, scaling, fog/death/remove cleanup, ember cleanup and no relocation');
}
`;
new Function('require',source)(require);
