const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const all=[],ids=new Map(),sent=[],listeners={},scheduled=[];
let writes=0,bridges=0,now=1,world=[0,0,384],cameraX=0,mouse,terrainMiss=false;
function panel(id,parent) {
    const p={id,parent,visible:true,actuallayoutwidth:1600,actuallayoutheight:900,actualuiscale_x:1,actualuiscale_y:1,
        classes:new Set(),style:new Proxy({},{set(o,k,v){writes++;o[k]=v;return true;}}),
        AddClass(c){this.classes.add(c);},RemoveClass(c){this.classes.delete(c);},
        SetHasClass(c,v){v?this.classes.add(c):this.classes.delete(c);},BHasClass(c){return this.classes.has(c);},
        GetParent(){return parent||null;},FindChildTraverse(id){return ids.get(id);}};
    all.push(p);if(id)ids.set(id,p);return p;
}
for(const id of ['GridPlacementRoot','GridPlacementStaticMask','GridPlacementStaticMesh','GridPlacementCells',
    'GridPlacementTerrain','GridPlacementFootprintTiles','GridPlacementFootprint','GridPlacementTitle','GridPlacementStatus','GridPlacementCursorIcon','GridPlacementPlaneRange','SurvivalPointTargetHint']) panel(id);
const shared={SurvivalPointTargetState:{active:false,name:'build',unit:10,ability:20},
    SurvivalInputDispatcher:{RegisterMouseHandler(_,f){mouse=f;},RegisterKeyHandler(){}}};
const $=s=>ids.get(s.replace(/^#/,''));
$.CreatePanel=(_,p,id)=>panel(id,p);$.GetContextPanel=()=>ids.get('GridPlacementRoot');
$.Msg=()=>{};$.Schedule=(_,fn)=>scheduled.push(fn);
const context=vm.createContext({$,GameUI:{CustomUIConfig:()=>shared,
        GetCursorPosition:()=>[world[0]+800-cameraX,world[1]*0.5+447],
        GetScreenWorldPosition:p=>p[0]===800&&p[1]===450?[cameraX,0,384]:
            (terrainMiss?null:(world[2]===384?world:[world[0]+400,world[1]-500,world[2]]))},
    Game:{GetGameTime:()=>now,WorldToScreenX:x=>{bridges++;return x+800-cameraX;},
        WorldToScreenY:(_,y,z)=>{bridges++;return y*0.5+450-(z-384)*0.5;}},
    Particles:{CreateParticle:()=>0,SetParticleControl(){},DestroyParticleEffect(){},ReleaseParticleIndex(){}},
    ParticleAttachment_t:{PATTACH_WORLDORIGIN:6},
    GameEvents:{Subscribe:(name,fn)=>listeners[name]=fn,SendCustomGameEventToServer:(name,data)=>sent.push({name,data})},
    Abilities:{GetLocalPlayerActiveAbility:()=>-1},Entities:{GetUnitName:()=> 'builder'},CustomNetTables:{}});
for(const file of ['survival_static_grid.js','survival_grid_state.js','survival_grid_placement.js']) {
    vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file,'utf8'),context);
    if(process.env.GRID_LEGACY_HELPERS==='1' && file!=='survival_grid_placement.js') {
        const api=file==='survival_static_grid.js'?shared.SurvivalStaticGrid:shared.SurvivalGridState;
        const create=api.create;
        api.create=options=>{const instance=create(options);delete instance.configureLayout;delete instance.visibleBounds;return instance;};
    }
}
listeners.ui_grid_placement_profiles({cell_size:64,static_grid:{height:384,
    bounds:{min_x:-4096,max_x:2048,min_y:-2048,max_y:2048}},profiles:[{ability_name:'build',
    grid_footprint_x:4,grid_footprint_y:4,building_id:'wall'}]});
function atlas(blocked) {
    const states=[];for(let x=-32;x<32;x++)for(let y=-32;y<32;y++)states.push(blocked(x,y)?1:2);
    let data='';for(let i=0;i<states.length;i+=2)data+=(states[i]+4*states[i+1]).toString(16);
    return '3|64|-32|-32|64|64|384|'+data;
}
listeners.ui_grid_placement_static_area({area:atlas((x,y)=>x===0&&y===0)});
const update=scheduled.find(fn=>fn.name==='updateLoop');
const warmColors=scheduled.find(fn=>fn.name==='warmPreviewPool'),warmWhite=scheduled.find(fn=>fn.name==='warmStaticGrid');
const root=ids.get('GridPlacementRoot');
root.GetParent=()=>({actuallayoutwidth:1600,actuallayoutheight:900,GetParent:()=>null});
root.actuallayoutwidth=0;root.actuallayoutheight=0;
for(let i=0;i<80;i++) {warmColors();warmWhite();}
root.actuallayoutwidth=1600;root.actuallayoutheight=900;
assert.equal(all.filter(p=>p.__colorOnly).length,0,'retired 639-cell strip pool is not instantiated');
const coldCount=all.length;
assert(coldCount<1500,'shared lines/corners and state cells fit a smaller preloaded pool');
shared.SurvivalPointTargetState.active=true;update();
assert(ids.get('GridPlacementStaticMask').visible);
assert.equal(all.length,coldCount,'Q allocates no footprint or white grid nodes');
const foot=()=>all.filter(p=>p.classes.has('FootprintTile')&&p.visible);
assert.equal(foot().length,16,'wall remains 4 by 4 complete cells');
assert.equal(foot().filter(p=>p.classes.has('Blocked')).length,1);
assert.equal(foot().filter(p=>p.classes.has('Clear')).length,15,'one bad cell must not turn the whole footprint red');
assert(foot().every(p=>p.style.clip.startsWith('radial(')),'native quad clips replace horizontal strips');
const state=shared.SurvivalGridStatePerformance;
const layoutCount=state.footprint_layouts;
let iconPosition=ids.get('GridPlacementCursorIcon').style.position;
world=[5,5,768];now+=0.035;update();
assert.equal(state.footprint_layouts,layoutCount,'movement within the same snapped cell does not repaint footprint');
assert.notEqual(ids.get('GridPlacementCursorIcon').style.position,iconPosition,'icon follows sub-cell mouse motion while footprint stays snapped');
iconPosition=ids.get('GridPlacementCursorIcon').style.position;
assert.equal(iconPosition,'781.00px 425.50px 0px','icon uses screen cursor coordinates without world projection');
for(const height of [-512,0,2048]) {
    world=[5,5,height];now+=0.035;update();
    assert.equal(ids.get('GridPlacementCursorIcon').style.position,iconPosition,
        'same screen pointer on lower/higher terrain stays on the same displayed cell, even when terrain hit X/Y differs');
}
terrainMiss=true;now+=0.035;update();
assert.equal(ids.get('GridPlacementCursorIcon').style.position,iconPosition,'cursor-plane intersection works even when terrain tracing misses');
assert(ids.get('GridPlacementStaticMask').visible);
terrainMiss=false;
const stats=shared.SurvivalStaticGridPerformance;
const beforeLayouts=stats.layout_writes,beforeViews=stats.view_builds,beforeNodes=all.length;
const beforeTerrain=state.terrain_layouts;
const requests=()=>sent.filter(e=>e.name==='ui_grid_placement_validate');
const beforeBridges=bridges,beforeRequests=requests().length;
const terrain=all.filter(p=>p.classes.has('TerrainBlocked'));
assert(terrain.length>0&&terrain.some(p=>p.visible));
for(let i=1;i<=20;i++) {
    world=[i%2?768:0,0,384];now+=0.035;update();
    assert(ids.get('GridPlacementStaticMask').visible,'white masked grid persists during fast movement');
    assert.equal(ids.get('GridPlacementCells').style.opacity,'1.0000','red cached layer stays visible');
    assert(terrain.some(p=>p.visible),'static red terrain is never cleared on cursor movement');
    assert.equal(foot().filter(p=>p.classes.has('Blocked')).length,i%2?0:1,'local lookup colors the latest snapped footprint immediately');
}
assert.equal(stats.layout_writes,beforeLayouts);assert.equal(stats.view_builds,beforeViews);
assert.equal(state.terrain_layouts,beforeTerrain,'mouse moves never relayout static red geometry');
assert.equal(all.length,beforeNodes);assert.equal(requests().length,beforeRequests);
assert(bridges-beforeBridges<=20*10,'projections reuse the cached plane transform');
now+=0.13;update();
const req=requests().at(-1).data;
const wall=[];for(const x of [-96,-32,32,96])for(const y of [-96,-32,32,96])wall.push({x,y,z:384,ok:x===32&&y===32?0:1});
listeners.ui_grid_placement_validation({session_id:req.session_id,request_id:req.request_id,
    ability_name:'build',request_anchor_x:0,request_anchor_y:0,anchor_x:0,anchor_y:0,
    world_x:0,world_y:0,world_z:384,success:0,cells:wall,area:'',area_complete:1});update();
assert.equal(foot().filter(p=>p.classes.has('Blocked')).length,1,'server denial preserves per-cell colors');
const layoutsBeforePan=stats.layout_writes;cameraX+=64;now+=0.11;update();
assert(stats.layout_writes>layoutsBeforePan);
assert.equal(stats.geometry_builds,1);
const iconTick=scheduled.find(fn=>fn.name==='updateCursorIconLoop');
const iconBridges=bridges,iconLayouts=stats.layout_writes,iconRequests=requests().length;
world=[70,12,0];iconTick();
assert.equal(ids.get('GridPlacementCursorIcon').style.position,'782.00px 429.00px 0px');
assert.equal(bridges,iconBridges);assert.equal(stats.layout_writes,iconLayouts);assert.equal(requests().length,iconRequests);
listeners.ui_grid_placement_profiles({cell_size:64,static_grid:{height:384,
    bounds:{min_x:-16384,max_x:16384,min_y:-16384,max_y:16384},
    build_bounds:{min_x:-128,max_x:128,min_y:-128,max_y:128}},
    profiles:[{ability_name:'build',grid_footprint_x:4,grid_footprint_y:4,building_id:'wall'}]});
world=[512,0,384];now+=0.1;update();
assert(ids.get('GridPlacementPlaneRange').visible,'distant terrain uses the grid-plane outline');
assert.equal(ids.get('GridPlacementPlaneRange').style.position,ids.get('GridPlacementStaticMask').style.position);
assert.equal(ids.get('GridPlacementPlaneRange').style.width,ids.get('GridPlacementStaticMask').style.width);
assert(shared.SurvivalGridFramePerformance.frames>0,'retain stage timings for engine-side drag diagnosis');
mouse('pressed',1);assert(!ids.get('GridPlacementStaticMask').visible);
assert.equal(foot().length,0,'cancel hides footprint while keeping cached terrain nodes');
shared.SurvivalPointTargetState.active=false;
// Model mode has an independent capped pose channel, including fast sweeps.
update();
context.poseClock=1000;
vm.runInContext('Date.now=function(){return poseClock;}',context);
listeners.ui_grid_placement_profiles({cell_size:64,static_grid:{height:384,
    bounds:{min_x:-4096,max_x:2048,min_y:-2048,max_y:2048}},profiles:[{ability_name:'build',
    grid_footprint_x:4,grid_footprint_y:4,building_id:'wall',preview_model:1}]});
shared.SurvivalPointTargetState.active=true;world=[0,0,384];now+=0.1;update();
const poses=()=>sent.filter(e=>e.name==='ui_grid_placement_pose');
assert.equal(poses().length,1);assert.equal(ids.get('GridPlacementCursorIcon').visible,false);
context.poseClock+=100;world=[5,5,-512];now+=0.035;update();
assert.equal(poses().length,1,'same snapped cell does not send another model pose');
const requestsBeforeSweep=requests().length;
context.poseClock+=10;world=[1024,1024,384];now+=0.035;update();
context.poseClock+=10;world=[2048,2048,384];now+=0.035;update();
assert.equal(poses().length,2,'rapid model updates are rate limited');
context.poseClock+=60;now+=0.035;update();
assert.equal(poses().length,3);
assert.equal(Number(poses().at(-1).data.x),2048,'latest snapped position sent after throttling');
assert.equal(requests().length,requestsBeforeSweep,'fast model movement does not start terrain scans');
mouse('pressed',1);shared.SurvivalPointTargetState.active=false;update();
const scheduledBefore=scheduled.length,writesBefore=writes;
shared.SurvivalGridControllerEpoch++;
update();warmWhite();warmColors();iconTick();
assert.equal(scheduled.length,scheduledBefore,'old controller schedules stop after hot reload');
assert.equal(writes,writesBefore,'old controller cannot compete over icon and grid positions');
console.log('STATIC_GRID_INTEGRATION_PASS preloaded_nodes='+coldCount+'; 20 fast frames, zero static relayouts/allocations/requests');
