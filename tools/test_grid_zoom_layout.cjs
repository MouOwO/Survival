const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const shared={},panels=[];
function panel(host){const p={host,style:{},visible:false,classes:new Set(),writes:0,
 AddClass(c){this.classes.add(c);},RemoveClass(c){this.classes.delete(c);},
 SetHasClass(c,v){v?this.classes.add(c):this.classes.delete(c);}};panels.push(p);return p;}
const context={GameUI:{CustomUIConfig:()=>shared},$:{CreatePanel:(_,host)=>panel(host)}};
for(const file of ['survival_static_grid','survival_grid_state'])
 vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),context);
let distance=1200,center=[-1024,4096],bridgeCalls=0;
function project(p){const x=p[0]-center[0],y=p[1]-center[1],w=distance+0.4*y;
 if(w<=0)return null;return [800+900*x/w,450-550*y/w];}
function style(p,k,v){p.style[k]=v;p.writes++;}
const mask=panel(),host=panel(),terrainHost={},footHost={};
const grid=shared.SurvivalStaticGrid.create({mask,host,viewport:()=>[1600,900],
 referenceWorld:()=>center,project:p=>{bridgeCalls++;return project(p);},setStyle:style,
 positionSegment(p,a,b){p.points=[a,b];p.writes++;}});
const state=shared.SurvivalGridState.create({terrainHost,dynamicHost:{},footHost,
 visibleBounds:()=>grid.drawBounds(),coverageKey:()=>grid.coverageKey(),cameraKey:()=>grid.cameraKey(),
 range:()=>grid.range(),projectPolygon:points=>grid.projectPolygon(points),
 project:p=>grid.project(p),setStyle:style,cellSize:()=>64,zOffset:()=>6,viewport:()=>[1600,900]});
grid.configure({bounds:{min_x:-16384,max_x:16384,min_y:-16384,max_y:16384},height:384},64,{radius:1280,grid_z_offset:6});
state.configure('3|64|-64|16|96|96|384|'+'5'.repeat(96*96/2));
for(let n=0;n<80;n++){distance=1200+n*10;grid.prewarm();state.prewarmTerrain();}
assert.equal(bridgeCalls,0,'hidden prewarm does not query the camera');
assert.equal(grid.stats.view_builds,0);assert.equal(grid.stats.layout_writes,0);assert.equal(state.stats.terrain_layouts,0);
assert(grid.stats.mark_panels<=160,'hidden prewarm keeps the corner pool small');
function frame(world){grid.update([...world,384]);state.update([...world,384],{grid_footprint_x:4,grid_footprint_y:4});}
function contains(p,screen){
 const position=(p.style.position||'').split(' ').map(parseFloat),side=parseFloat(p.style.width);
 if(!side)return false;
 const local=[screen[0]-position[0],screen[1]-position[1]];
 function wedge(clip){if(!clip||clip==='none')return true;const n=clip.match(/-?\d+(?:\.\d+)?/g).map(Number);
  const angle=Math.atan2(local[0]/side-n[0]/100,n[1]/100-local[1]/side)*180/Math.PI;
  return ((angle-n[2]+720)%360)<=n[3]+1e-3;}
 return local[0]>=0&&local[1]>=0&&local[0]<=side&&local[1]<=side&&(p.__clips||[p,p.__fill]).every(c=>wedge(c.style.clip));
}
function checkCoverage(world){
 const terrain=panels.filter(p=>p.host===terrainHost&&p.visible&&p.classes.has('TerrainBlocked'));
 const lines=new Set(panels.filter(p=>p.host===host&&p.visible&&p.classes.has('StaticGridLine')).map(p=>p.__gridKey));
 for(let x=world[0]-1216;x<=world[0]+1216;x+=64)for(let y=world[1]-1216;y<=world[1]+1216;y+=64){
  if(Math.hypot(x-world[0],y-world[1])>1216)continue;
  const screen=project([x,y,390]);if(!screen||screen[0]<0||screen[0]>1600||screen[1]<0||screen[1]>900)continue;
  assert(lines.has('l'+((x+16384)/64)),'every vertical grid line through the preview is retained');
  assert(lines.has('l'+(513+(y+16384)/64)),'every horizontal grid line through the preview is retained');
  const interior=project([x+20,y+20,390]);
  if(interior[0]>=0&&interior[0]<=1600&&interior[1]>=0&&interior[1]<=900)
   assert(terrain.some(p=>contains(p,interior)),'visible atlas red cells remain filled after range culling');
 }
 const foot=panels.filter(p=>p.host===footHost&&p.visible&&p.classes.has('FootprintTile'));
 assert.equal(foot.length,16);assert(foot.every(p=>p.classes.has('Blocked')));
 assert(grid.stats.visible_marks<=160,'corner layout population is bounded during zoom');
}
distance=1200;frame(center);checkCoverage(center);
const whiteBefore=grid.stats.layout_writes,redBefore=state.stats.terrain_layouts;
const moves=[1200,1400,1600,1800,2000,2200,2400,2200,2000,1800,1600,1400,1200,1400,1600,1800,2000,2200,2400,2200,2000,1800,1600,1400,1200];
for(const d of moves){distance=d;frame(center);checkCoverage(center);}
const zoomWhite=grid.stats.layout_writes-whiteBefore,zoomRed=state.stats.terrain_layouts-redBefore;
assert(zoomWhite<7000,'25 zoom steps keep corner and line layout work bounded');
assert(zoomRed<24*144,'red runs outside the visible buffered patch are not processed');
const layoutBefore=grid.stats.layout_writes,coverageBefore=grid.stats.coverage_builds,redLayoutsBefore=state.stats.terrain_layouts,strideBefore=grid.stats.mark_stride;
for(const delta of [64,128,192,256])frame([center[0]+delta,center[1]]);
assert(grid.stats.layout_writes>layoutBefore && grid.stats.layout_writes-layoutBefore<=4*(128+160),
 'cursor motion refreshes a bounded set of world-circle endpoints and fade');
assert.equal(grid.stats.coverage_builds,coverageBefore);
assert(state.stats.terrain_layouts-redLayoutsBefore<4*144,'mouse motion only refreshes terrain near the moving circle boundary');
const retained=new Map(panels.filter(p=>p.host===host&&p.visible).map(p=>[p.__gridKey,{p,writes:p.writes}]));
frame([center[0]+320,center[1]]);checkCoverage([center[0]+320,center[1]]);
for(const p of panels.filter(p=>p.host===host&&p.visible)){
 const old=retained.get(p.__gridKey);if(old)assert.equal(p,old.p,'crossing a patch keeps existing world nodes');
}
assert.equal(grid.stats.mark_stride,strideBefore,'mouse motion does not change decoration density');
// A camera jump invalidates projection while picking and full-size footprint remain exact.
center=[-512,4608];frame(center);checkCoverage(center);
const screen=project([center[0]+192,center[1]-64,390]),picked=grid.worldAtScreen(screen);
assert(Math.hypot(picked[0]-center[0]-192,picked[1]-center[1]+64)<1e-6);
console.log(JSON.stringify({result:'GRID_ZOOM_LAYOUT_PASS',zoom_steps:25,white_layout_operations:zoomWhite,
 red_layout_attempts:zoomRed,cached_corners:grid.stats.mark_panels,hidden_camera_queries:0,footprint_cells:16}));
