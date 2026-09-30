const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const panels = new Map();
let styleWrites = 0;
let projectionCalls = 0;
let panelCreates = 0;
let cameraX=0, cameraY=0;
function panel(id) {
    const style = new Proxy({}, {set(target, key, value) {
        if (key === 'opacity') {
            assert(/^(?:0|1)(?:\.\d+)?$/.test(String(value)), 'Panorama rejects empty/scientific opacity: ' + value);
            assert(Number(value) >= 0 && Number(value) <= 1);
        }
        styleWrites++;
        target[key] = value;
        return true;
    }});
    const p = { style, visible: true, actualuiscale_x: 1, actualuiscale_y: 1,
        classes: new Set(), AddClass(c) { this.classes.add(c); },
        RemoveClass(c) { this.classes.delete(c); },
        SetHasClass(c, value) { value ? this.classes.add(c) : this.classes.delete(c); },
        GetParent() { return null; }, FindChildTraverse(id) { return panels.get(id); } };
    panels.set(id, p); return p;
}
for (const id of ['GridPlacementRoot', 'GridPlacementCells', 'GridPlacementFootprint', 'GridPlacementTitle',
    'GridPlacementStatus', 'GridPlacementCursorIcon', 'SurvivalPointTargetHint']) panel(id);
panels.get('SurvivalPointTargetHint').style.opacity = '0.8';
const $ = id => panels.get(id.replace(/^#/, ''));
$.CreatePanel = (_, parent, id) => { panelCreates++; return panel(id); };
$.GetContextPanel = () => panels.get('GridPlacementRoot');
$.Msg = () => {};
const scheduled = [];
$.Schedule = (_, fn) => scheduled.push(fn);
const listeners = {}, sent = [];
const particles = [], destroyed = [], released = [];
const Particles = {
    CreateParticle(path, attachment, owner) {
        const id = particles.length;
        particles.push({path, attachment, owner, controls: {}});
        return id;
    },
    SetParticleControl(id, cp, value) { particles[id].controls[cp] = Array.from(value); },
    DestroyParticleEffect(id, immediate) { assert.equal(immediate, true); destroyed.push(id); },
    ReleaseParticleIndex(id) { released.push(id); }
};
let now = 1, world = [0, 0, 384], mouse, keyboard;
const shared = {
    SurvivalPointTargetState: { active: true, name: 'build', unit: 10, ability: 20 },
    SurvivalInputDispatcher: { RegisterMouseHandler(_, fn) { mouse = fn; },
        RegisterKeyHandler(_, fn) { keyboard = fn; } }
};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_grid_placement.js', 'utf8'), {
    $, Particles, ParticleAttachment_t: {PATTACH_WORLDORIGIN: 6},
    Game: { GetGameTime: () => now, WorldToScreenX: x => { projectionCalls++; return x + 1000-cameraX; },
        WorldToScreenY: (_, y) => { projectionCalls++; return y + 1000-cameraY; } },
    GameUI: { CustomUIConfig: () => shared, GetCursorPosition: () => [500, 500],
        GetScreenWorldPosition: () => world },
    GameEvents: { Subscribe: (name, fn) => listeners[name] = fn,
        SendCustomGameEventToServer: (name, data) => sent.push({ name, data }) },
    Abilities: { GetLocalPlayerActiveAbility: () => -1 },
    Entities: { GetUnitName: () => 'builder' }, CustomNetTables: {}
});
listeners.ui_grid_placement_profiles({ cell_size: 64, profiles: [{ ability_name: 'build',
    grid_footprint_x: 2, grid_footprint_y: 2, building_id: 'tower' }] });
const warm = scheduled.find(fn => fn.name === 'warmPreviewPool');
assert(warm, 'warmup is scheduled when the UI loads');
const requestsBeforeWarm=sent.length;
let maxWarmBatch=0;
for(let batch=0;batch<80;batch++) {
    const before=panelCreates;
    warm();
    maxWarmBatch=Math.max(maxWarmBatch,panelCreates-before);
}
const warmCells=[...panels.values()].filter(p=>p.__edges);
assert.equal(warmCells.length,640,'prewarm the bounded reusable pool');
assert(warmCells.every(p=>!p.visible),'warmup never displays the grid');
assert(maxWarmBatch<=90,'warmup spreads allocations across small batches');
assert.equal(particles.length,0,'warmup creates no particle');
assert.equal(sent.length,requestsBeforeWarm,'warmup sends no validation or terrain request');
const warmedCreates=panelCreates;
warm();
assert.equal(panelCreates,warmedCreates,'completed warmup is idempotent');
const update = scheduled.find(fn => fn.name === 'updateLoop');
update();
warm();
assert.equal(panelCreates,warmedCreates,'active placement reuses the pool and pauses background warmup');
assert.equal(particles.length, 1, 'native circle appears without waiting for the server');
assert.equal(particles[0].path, 'particles/ui_mouseactions/range_display.vpcf');
assert.equal(particles[0].owner, -1, 'world-origin local preview');
assert.deepEqual(particles[0].controls[1], [1280, 0, 0]);
const requests = () => sent.filter(e => e.name === 'ui_grid_placement_validate');
function response(request, extra = {}) {
    listeners.ui_grid_placement_validation({ session_id: request.session_id,
        request_id: request.request_id, ability_name: 'build', success: 1,
        request_anchor_x: 0, request_anchor_y: 0, anchor_x: 0, anchor_y: 0,
        world_x: 0, world_y: 0, world_z: 384,
        area: '0,0,384,1,384,384,384,384;2,0,384,0,384,384,384,384',
        cells: [{grid_x: 0, grid_y: 0, x: 32, y: 32, z: 384, ok: 1}], ...extra });
    update();
}
response(requests()[0].data);
assert.equal(panelCreates,warmedCreates,'first validated preview needs no panel allocation');
assert(panels.get('GridPlacementCell1').classes.has('Invalid'));
assert(panels.get('GridPlacementCell0').classes.has('Footprint'));
assert(panels.get('GridPlacementCell0').classes.has('Valid'));
assert.equal(panels.get('GridPlacementCursorIcon').abilityname, 'build');
assert.equal(panels.has('GridPlacementRing63'), false, 'remove panel-built circle');
assert.equal(panels.get('SurvivalPointTargetHint').style.opacity, '0');
world = [256, 0, 384]; now += 0.035; update();
assert.equal(particles.length, 1, 'reuse particle while moving');
assert.deepEqual(particles[0].controls[0], world, 'particle tracks live cursor even before validation');
assert.equal(requests().length, 1, 'moving across cells respects the network rate limit');
response(requests()[0].data);
assert.equal(panels.get('GridPlacementCell0').visible, false, 'old footprint stays hidden');
assert.equal(panels.get('GridPlacementCell1').visible, true, 'keep surrounding terrain while awaiting validation');
mouse('pressed', 0);
assert(!sent.some(e => e.name === 'ui_grid_placement_commit'), 'cannot place on a stale anchor');
now += 0.12; update();
assert.equal(requests().length, 2);
response(requests()[1].data, { request_anchor_x: 4, anchor_x: 4 });
world = null; update();
assert.equal(panels.get('GridPlacementCursorIcon').visible, true,'icon remains at the screen pointer when terrain tracing misses');
assert.deepEqual(destroyed, [0], 'invalid cursor destroys particle index zero');
assert.deepEqual(released, [0]);
world = [0, 0, 384]; now += 0.5; update();
response(requests()[requests().length - 1].data, {
    area: '2|128|2,0,384,1;8,0,384,1',
    cells: [
        {grid_x:0,grid_y:0,x:32,y:32,z:384,ok:1},
        {grid_x:1,grid_y:0,x:96,y:32,z:384,ok:1}
    ]
});
assert.equal(panels.get('GridPlacementCell0').style.opacity, '1.0000');
const edgeOpacity = Number(panels.get('GridPlacementCell2').style.opacity);
assert(edgeOpacity > 0 && edgeOpacity < 0.6, 'outer grid fades smoothly');
assert(panels.get('GridPlacementCell0').classes.has('Footprint'), 'one combined footprint');
assert.equal(panels.get('GridPlacementCell0').__marks.filter(m=>m.visible).length, 8,
    'four footprint corners each have the same two-stroke cross');
assert.equal(particles.length, 2, 'returning to terrain recreates native circle immediately');
mouse('pressed', 1);
assert.deepEqual(destroyed, [0, 1], 'right-click destroys range');
assert.deepEqual(released, destroyed, 'release every destroyed particle');
assert.equal(panels.get('SurvivalPointTargetHint').style.opacity, '0.8000', 'restore other targeting hints');
update();
assert.equal(particles.length, 3, 'rapidly re-enter targeting without a delayed circle');
keyboard('ESCAPE', true);
assert.deepEqual(destroyed, [0, 1, 2]);
shared.SurvivalGridRangeCleanup();
assert.deepEqual(released, destroyed, 'cleanup is idempotent');

// Regression: a tile barely inside the circle generated 4.67e-9 opacity and
// killed the scheduled input loop. Reproduce it with the actual radius math.
delete panels.get('SurvivalPointTargetHint').style.opacity;
update();
const almostEdgeX = Math.sqrt(Math.pow(1280 * (1 - 0.00001), 2) - 32 * 32) - 32;
world = [-almostEdgeX, 0, 384]; now += 0.2; update();
now+=0.13; update(); // finish the fast-motion cooldown before testing alpha
const current = requests()[requests().length - 1].data;
const anchor = Math.floor(world[0] / 64 + 0.5);
response(current, {request_anchor_x: anchor, anchor_x: anchor,
    area: '2|64|0,0,384,0', cells: [{x:world[0],y:0,z:384,ok:1}]});
assert.equal(panels.get('GridPlacementCell1').style.opacity, '0.0000');
const writesBefore = styleWrites;
update();
assert(styleWrites - writesBefore < 5, 'stationary frame does not rewrite every grid style');
const endCount = sent.filter(e => e.name === 'ui_grid_placement_preview_end').length;
mouse('pressed', 0);
assert(sent.some(e => e.name === 'ui_grid_placement_commit'), 'valid construction still submits after near-zero fade');
assert.equal(sent.filter(e => e.name === 'ui_grid_placement_preview_end').length, endCount,
    'commit is not followed by a premature preview-end');
assert.equal(panels.get('SurvivalPointTargetHint').style.opacity, '1.0000', 'unset opacity restores safely');

world = [0,0,384]; now += 0.2; update();
const many = [];
for (let x=-8;x<8;x++) for(let y=-8;y<8;y++) many.push(x+','+y+',384,0');
const countBefore = panels.size;
response(requests()[requests().length - 1].data, {area:'2|128|'+many.join(';')});
assert(panels.size-countBefore <= 24*13, 'Q does not allocate the entire overview in one frame');
for(let frame=0;frame<15;frame++) update();
const tiles = [...panels.values()].filter(p=>p.visible && p.__edges && !p.__footprint);
assert(tiles.some(p=>p.__edges.some(e=>!e.visible)), 'shared grid edges have only one owner');
assert(tiles.every(p=>parseFloat(p.style.width)<500), 'tile containers are bounded, not full-screen');

// A 64-unit-offset footprint cuts through 128-unit overview tiles. The
// remaining overview pieces must never extend underneath the green rectangle.
const wallCells=[];
for(let x=96;x<=288;x+=64) for(let y=96;y<=288;y+=64) wallCells.push({x,y,z:384,ok:1});
const overlapArea=[];
for(let x=0;x<3;x++) for(let y=0;y<3;y++) overlapArea.push(x+','+y+',384,0');
response(requests()[requests().length-1].data, {cells:wallCells,area:'2|128|'+overlapArea.join(';')});
for(const tile of [...panels.values()].filter(p=>p.visible && p.__edges && !p.__footprint)) {
    const points=tile.__geometryKey.split(':')[0].split(';').map(p=>p.split(',').map(Number));
    const left=Math.min(...points.map(p=>p[0]))-1000, right=Math.max(...points.map(p=>p[0]))-1000;
    const bottom=Math.min(...points.map(p=>p[1]))-1000, top=Math.max(...points.map(p=>p[1]))-1000;
    assert(!(left<320 && right>64 && bottom<320 && top>64), 'overview is clipped out of exact footprint');
}
const footprintPanel=panels.get('GridPlacementCell0');
assert.equal(footprintPanel.__marks.filter(m=>m.visible).length,8);
const crossCenters=new Set(footprintPanel.__marks.map(m=>{
    const [x,y]=m.style.position.split(' ').map(parseFloat);
    return (x+parseFloat(m.style.width)/2).toFixed(1)+','+(y+parseFloat(m.style.height)/2).toFixed(1);
}));
assert.equal(crossCenters.size,4,'one identical cross at each of the four corners');
const fadeArea='2|128|1,0,384,1;4,0,384,1;7,0,384,1;9,0,384,1';
response(requests()[requests().length-1].data,{area:fadeArea});
const alphas=[1,2,3,4].map(i=>Number(panels.get('GridPlacementCell'+i).style.opacity));
assert(alphas[0]===1 && alphas[1]<0.8 && alphas[2]<0.1 && alphas[3]===0,
    'broad visible feather fades out completely inside the native ring');

keyboard('ESCAPE',true);
listeners.ui_grid_placement_profiles({cell_size:64,profiles:[{ability_name:'build',
    grid_footprint_x:4,grid_footprint_y:4,building_id:'wall'}]});
world=[160,160,384]; now+=0.2; update();
const wallRequest=requests()[requests().length-1].data;
const packed=[];
for(let x=-20;x<=20;x++) for(let y=-20;y<=20;y++) {
    packed.push(Math.hypot((x+0.5)*64,(y+0.5)*64)<=1280 ? 2 : 0);
}
let hex='';
for(let i=0;i<packed.length;i+=2) hex+=(packed[i]+4*(packed[i+1]||0)).toString(16);
const viewport=panels.get('GridPlacementRoot');
viewport.actuallayoutwidth=1600; viewport.actuallayoutheight=1600;
response(wallRequest,{request_anchor_x:3,request_anchor_y:3,anchor_x:3,anchor_y:3,
    world_x:192,world_y:192,cells:wallCells,area:'3|64|-20|-20|41|41|384|'+hex});
for(let i=0;i<60;i++) update();
assert.equal(panels.get('GridPlacementCell0').__dividers.filter(p=>p.visible).length,6,
    'wall shows four rows and four columns: 16 complete 64-unit cells');
const visibleOverview=[...panels.values()].filter(p=>p.visible && p.__edges && !p.__footprint);
assert(visibleOverview.length<700,'offscreen/faded cells do not render');
assert(visibleOverview.every(p=>p.__fills.filter(f=>f.visible).length===2),'overview uses two fill strips');
const beforeProjection=projectionCalls;
const beforeWrites=styleWrites;
for(let i=0;i<30;i++) update();
const stationaryCalls=projectionCalls-beforeProjection;
assert(stationaryCalls<=30*14,'stationary overview does not reproject hundreds of cells');
assert(styleWrites-beforeWrites<30*5,'stationary grid does not invalidate thousands of styles');
assert.equal(sent.filter(e=>e.name==='ui_grid_placement_commit').length,1);
mouse('pressed',0);
const committed=sent.filter(e=>e.name==='ui_grid_placement_commit');
assert.equal(committed.length,2,'64-unit wall preview commits normally');
assert.equal(committed[1].data.x,192);
world=[192,192,384]; now+=0.2; update();
const steppingRequest=requests()[requests().length-1].data;
response(steppingRequest,{request_anchor_x:3,request_anchor_y:3,anchor_x:3,anchor_y:3,
    world_x:192,world_y:192,cells:wallCells,area:'3|64|-20|-20|41|41|384|'+hex});
const requestsBeforeSmallMotion=requests().length;
const stylesBeforeSmallMotion=styleWrites;
const iconBeforeSmallMotion=panels.get('GridPlacementCursorIcon').style.position;
for(let step=0;step<12;step++) {
    world=[182+step,185+step/2,384]; now+=0.025; update();
}
assert.equal(requests().length,requestsBeforeSmallMotion,'same-cell cursor motion sends no validation');
assert(styleWrites-stylesBeforeSmallMotion<12*5,'same-cell movement does not restyle the overview');
assert.equal(panels.get('GridPlacementCursorIcon').style.position,iconBeforeSmallMotion,
    'fixed screen pointer keeps its icon even when mocked world coordinates change');
assert.deepEqual(particles[particles.length-1].controls[0],[192,192,384],
    'range center snaps to the cell instead of following every cursor pixel');
const slotSnapshot=new Map([...panels.entries()].filter(([,p])=>p.visible && p.__edges && !p.__footprint)
    .map(([id,p])=>[p.__geometryKey,id]));
world=[232,192,384]; now+=0.11; update();
assert.equal(panels.get('GridPlacementCursorIcon').style.position,iconBeforeSmallMotion,
    'world snapping never moves the icon away from the fixed screen pointer');
assert.equal(requests().length,requestsBeforeSmallMotion+1,'crossing one cell sends one validation');
assert.equal(requests()[requests().length-1].data.x,256,'request coordinates are grid snapped');
response(requests()[requests().length-1].data,{request_anchor_x:4,request_anchor_y:3,
    anchor_x:4,anchor_y:3,world_x:256,world_y:192,
    cells:wallCells.map(c=>({...c,x:c.x+64})),area:'3|64|-20|-20|41|41|384|'+hex});
let retained=0;
for(const [id,p] of panels) if(p.visible && p.__edges && !p.__footprint && slotSnapshot.has(p.__geometryKey)) {
    assert.equal(id,slotSnapshot.get(p.__geometryKey),'unchanged world cells keep their panel slot'); retained++;
}
assert(retained>300,'most of the grid stays in place across a cursor step');
const validBeforeStale=panels.get('GridPlacementCell0').__geometryKey;
listeners.ui_grid_placement_area({session_id:0,ability_name:'build',area:''});
update();
assert.equal(panels.get('GridPlacementCell0').__geometryKey,validBeforeStale,'stale background results are ignored');
// A distant jump receives a partial near-cursor snapshot first. Never spend
// one frame laying out the entire cold circle; all later batches must drain.
keyboard('ESCAPE',true);
world=[9984,0,384]; cameraX=9984; now+=0.3; update();
const distantRequest=requests()[requests().length-1].data;
const nearIndices=[];
for(let x=-20;x<=20;x++) for(let y=-20;y<=20;y++) {
    nearIndices.push({index:(x+20)*41+y+20,distance:(x+0.5)**2+(y+0.5)**2});
}
nearIndices.sort((a,b)=>a.distance-b.distance);
const partialStates=packed.map(()=>0);
for(const tile of nearIndices.slice(0,128)) partialStates[tile.index]=2;
let partialHex='';
for(let i=0;i<partialStates.length;i+=2) partialHex+=(partialStates[i]+4*(partialStates[i+1]||0)).toString(16);
const distantCells=[];
for(const x of [-96,-32,32,96]) for(const y of [-96,-32,32,96]) distantCells.push({x:x+9984,y,z:384,ok:1});
response(distantRequest,{request_anchor_x:156,request_anchor_y:0,anchor_x:156,anchor_y:0,
    world_x:9984,world_y:0,cells:distantCells,area_complete:0,area:'3|64|136|-20|41|41|384|'+partialHex});
assert(shared.SurvivalGridPerformance.new_tiles<=48,'first partial draw caps expensive new tile layouts');
assert(shared.SurvivalGridPerformance.pending,'cold tile drawing is spread over frames');
assert.equal(panels.get('GridPlacementCells').style.opacity,'0.0000',
    'incomplete batches remain hidden: no radial reveal animation');
for(let i=0;i<5;i++) update();
assert.equal(panels.get('GridPlacementCells').style.opacity,'0.0000',
    'finished partial layout still waits for complete area');
assert.equal(panels.get('GridPlacementFootprint').style.opacity,'1.0000',
    'exact footprint remains independent of hidden overview loading');
listeners.ui_grid_placement_area({session_id:distantRequest.session_id,ability_name:'build',
    complete:1,area:'3|64|136|-20|41|41|384|'+hex});
let peakNewTiles=0;
for(let i=0;i<30;i++) {
    update(); peakNewTiles=Math.max(peakNewTiles,shared.SurvivalGridPerformance.new_tiles);
    assert(shared.SurvivalGridPerformance.new_tiles<=48,'each following frame stays within new tile budget');
}
assert(!shared.SurvivalGridPerformance.pending,'progressive snapshot rendering eventually drains');
assert.equal(panels.get('GridPlacementCells').style.opacity,'1.0000','complete prepared grid appears together');
assert([...panels.values()].filter(p=>p.visible&&p.__edges&&!p.__footprint).length>300,'full grid arrives after distant jump');
const beforeCamera=panels.get('GridPlacementCell0').__geometryKey;
const beforeCameraCalls=projectionCalls;
cameraX+=50; now+=0.11; update();
assert.notEqual(panels.get('GridPlacementCell0').__geometryKey,beforeCamera,'camera motion invalidates cached projection');
assert(projectionCalls>beforeCameraCalls+6,'camera motion reprojects visible world grid');
world=null; update();
world=[9984,0,384]; now+=0.8; update();
response(requests()[requests().length-1].data,{request_anchor_x:156,request_anchor_y:0,
    anchor_x:156,anchor_y:0,world_x:9984,world_y:0,cells:distantCells,
    area:'3|64|136|-20|41|41|384|'+hex});
for(let i=0;i<20;i++) update();
assert([...panels.values()].filter(p=>p.visible&&p.__edges&&!p.__footprint).length>300,
    'returning from HUD/off-world cursor restores unchanged cached grid');
// Large fast sweeps should only move the local icon/range: no validation
// requests, tile projection/layout, server scan restarts, or old red/green.
const beforeSweepRequests=requests().length;
const beforeSweepProjection=projectionCalls;
const beforeSweepStyles=styleWrites;
const beforeSweepPauses=sent.filter(e=>e.name==='ui_grid_placement_pause_area').length;
for(let i=0;i<20;i++) {
    world=[world[0]+256,0,384]; cameraX=world[0]; now+=0.035; update();
    assert(panels.get('GridPlacementRoot').classes.has('PlacementPending'));
    assert.equal(panels.get('GridPlacementCells').style.opacity,'0.0000');
    assert.equal(panels.get('GridPlacementFootprint').style.opacity,'0.0000');
    assert(panels.get('GridPlacementCursorIcon').visible,'icon remains available during sweep');
}
assert.equal(requests().length,beforeSweepRequests,'fast sweep sends zero validation requests');
assert.equal(sent.filter(e=>e.name==='ui_grid_placement_pause_area').length,beforeSweepPauses+1,
    'one pause event cancels the server scan for an entire fast sweep');
assert(projectionCalls-beforeSweepProjection<=20*2,'fast sweep only projects the icon');
assert(styleWrites-beforeSweepStyles<35,'fast sweep performs no grid layout work');
const lastSweepX=world[0];
now+=0.05; update();
assert.equal(requests().length,beforeSweepRequests,'short hesitation does not repeatedly restart heavy work');
now+=0.08; update();
assert.equal(requests().length,beforeSweepRequests+1,'settled mouse immediately validates newest snapped anchor');
assert.equal(requests()[requests().length-1].data.x,lastSweepX);
const finalAnchor=lastSweepX/64;
response(requests()[requests().length-1].data,{request_anchor_x:finalAnchor,request_anchor_y:0,
    anchor_x:finalAnchor,anchor_y:0,world_x:lastSweepX,world_y:0,
    cells:distantCells.map(c=>({...c,x:c.x+lastSweepX-9984})),
    area:'3|64|'+(finalAnchor-20)+'|-20|41|41|384|'+hex});
for(let i=0;i<20;i++) update();
assert.equal(panels.get('GridPlacementCells').style.opacity,'1.0000','colors return as one prepared grid after settle');
assert.equal(panels.get('GridPlacementFootprint').style.opacity,'1.0000');
// Clicking during fast movement requests a fresh check, never commits the
// previously green footprint or permanently locks input after pause.
world=[lastSweepX+256,0,384]; now+=0.035; update();
const beforeFastClick=sent.filter(e=>e.name==='ui_grid_placement_commit').length;
mouse('pressed',0);
assert.equal(sent.filter(e=>e.name==='ui_grid_placement_commit').length,beforeFastClick);
assert.equal(requests()[requests().length-1].data.x,world[0]);
const clickAnchor=world[0]/64;
response(requests()[requests().length-1].data,{request_anchor_x:clickAnchor,request_anchor_y:0,
    anchor_x:clickAnchor,anchor_y:0,world_x:world[0],world_y:0,
    cells:distantCells.map(c=>({...c,x:c.x+world[0]-9984})),area:''});
mouse('pressed',0);
assert.equal(sent.filter(e=>e.name==='ui_grid_placement_commit').length,beforeFastClick+1,
    'freshly validated click still constructs successfully');
console.log('GRID_FAST_MOTION_PASS sweep_frames=20 validation_requests=0 projection_calls='+40);
console.log('GRID_STREAM_RENDER_PASS peak_new_tiles/frame='+peakNewTiles);
console.log('GRID_PERF_FIXTURE: visible='+visibleOverview.length+' stationary projection calls/frame='+(stationaryCalls/30));
console.log('GRID_PLACEMENT_CLIENT_PASS: colors, footprint, icon, circle, throttling, stale response and missing cursor');
