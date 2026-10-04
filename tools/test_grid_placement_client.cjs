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
let moveCooldown = 0, nativeAbility = -1;
const nativeErrors = [];
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
        SendCustomGameEventToServer: (name, data) => sent.push({ name, data }),
        SendEventClientSide: (name, data) => nativeErrors.push({name, data}) },
    Abilities: { GetLocalPlayerActiveAbility: () => nativeAbility,
        GetAbilityName: id => id === 20 ? 'ability_building_blink' : '',
        GetCooldownTimeRemaining: () => moveCooldown },
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

// Relocation is the same preview/commit controller; a second D must replace the
// old session even when ability, tower and cursor anchor are unchanged.
shared.SurvivalSelectionResolver = {Resolve: () => 10};
shared.SurvivalPointTargetInput = {
    Begin(ability, unit) { shared.SurvivalPointTargetState = {
        active: true, name: 'ability_building_blink', ability, unit}; return true; },
    Cancel() { shared.SurvivalPointTargetState.active = false; }
};
const moveProfiles = {cell_size:64,profiles:[{
    ability_name:'ability_building_blink',building_id:'arrow_tower',placement_action:'relocate',
    grid_footprint_x:2,grid_footprint_y:2,preview_model:1
}]};
listeners.ui_grid_placement_profiles(moveProfiles);
const commits = () => sent.filter(e=>e.name==='ui_grid_placement_commit');
const poses = () => sent.filter(e=>e.name==='ui_grid_placement_pose');
const commitResult = (request, success) => listeners.ui_grid_placement_commit_result({
    session_id:request.session_id,success,error:success?'':'build_cell_occupied'});
world=[129,191,384]; now+=1;
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
const oldMove = requests().at(-1).data;
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
const newMove = requests().at(-1).data;
assert(Number(newMove.session_id)>Number(oldMove.session_id));
assert(sent.some(e=>e.name==='ui_grid_placement_preview_end' && e.data.session_id===oldMove.session_id));
const moveResponse = request => ({session_id:request.session_id,request_id:request.request_id,
    ability_name:'ability_building_blink',success:1,request_anchor_x:2,request_anchor_y:3,
    anchor_x:2,anchor_y:3,world_x:128,world_y:192,world_z:384,area:'',cells:[]});
listeners.ui_grid_placement_validation(moveResponse(oldMove));
const priorCommits=commits().length, priorPoses=poses().length;
world=[129,319,384]; // click a new cell before any new validation or ghost
mouse('pressed',0);
assert.equal(commits().length,priorCommits+1,'first click submits without validation/ghost readiness');
assert.equal(poses().length,priorPoses,'model creation is not a prerequisite for a valid click');
const relocationCommit=commits().at(-1).data;
assert.equal(relocationCommit.session_id,newMove.session_id);
assert.equal(relocationCommit.ability_name,'ability_building_blink');
assert.deepEqual([relocationCommit.x,relocationCommit.y,relocationCommit.z],[128,320,384],
    'commit snaps the click position, never a stale green response');
mouse('pressed',0);
update();
assert.equal(commits().length,priorCommits+1,'in-flight click is sent exactly once');
assert.equal(poses().length,priorPoses,'no late ghost requests while commit is in flight');
commitResult(oldMove,1);
assert(shared.SurvivalGridPlacement.IsRelocating(10),'old commit reply cannot close a newer D');
commitResult(relocationCommit,1);
assert(!shared.SurvivalPointTargetState.active && !shared.SurvivalGridPlacement.IsRelocating(10));
assert(!sent.some(e=>e.name==='ui_building_move_request'),'never send an unsnapped movement request');

// A rejected real landing (e.g. a unit enters it) keeps placement usable.
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
mouse('pressed',0);
const rejectedCommit=commits().at(-1).data;
commitResult(rejectedCommit,0);
assert(shared.SurvivalGridPlacement.IsRelocating(10));
world=[383,257,384]; mouse('pressed',0);
const correctedCommit=commits().at(-1).data;
assert(Number(correctedCommit.session_id)>Number(rejectedCommit.session_id));
assert.deepEqual([correctedCommit.x,correctedCommit.y],[384,256]);
commitResult(rejectedCommit,0);
mouse('pressed',0);
assert.equal(commits().at(-1).data,correctedCommit,'late rejection cannot duplicate the corrected click');
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
const repeatSession=requests().at(-1).data.session_id;
commitResult(correctedCommit,1);
assert(shared.SurvivalGridPlacement.IsRelocating(10),'D during in-flight move ignores old success');
mouse('pressed',0);
assert.equal(commits().at(-1).data.session_id,repeatSession);
commitResult(commits().at(-1).data,1);

assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
world=[0,0,384]; now+=1; update();
world=[768,128,384]; now+=0.035; update();
const sweepCommits=commits().length;
mouse('pressed',0);
assert.equal(commits().length,sweepCommits+1,'fast sweep cannot swallow a relocation click');
assert.deepEqual([commits().at(-1).data.x,commits().at(-1).data.y],[768,128]);
commitResult(commits().at(-1).data,1);
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
const invalidCommits=commits().length;
for(const invalidWorld of [null,[NaN,0,384],[Infinity,0,384]]) {
    world=invalidWorld; mouse('pressed',0);
    assert.equal(commits().length,invalidCommits,'invalid cursor coordinates are never submitted');
}
world=[65,191,384]; mouse('pressed',0);
assert.equal(commits().length,invalidCommits+1,'a valid click still works after invalid cursor samples');
commitResult(commits().at(-1).data,1);

assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
shared.SurvivalSelectionResolver.Resolve=()=>11; update();
assert(!shared.SurvivalGridPlacement.IsRelocating(10) && !shared.SurvivalPointTargetState.active,
    'changing selection cancels the movement and its grid');
shared.SurvivalSelectionResolver.Resolve=()=>10;

// First cold D can precede both profile delivery and the custom-input module.
listeners.ui_grid_placement_profiles({profiles:[]});
const pointInput=shared.SurvivalPointTargetInput;
delete shared.SurvivalPointTargetInput;
const coldCommitCount=commits().length, coldPoseCount=poses().length;
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
world=[129,191,384]; mouse('pressed',0);
world=[513,641,384]; mouse('pressed',0);
assert.equal(commits().length,coldCommitCount);
listeners.ui_grid_placement_profiles(moveProfiles);
assert.equal(commits().length,coldCommitCount,'still waiting for the actual input module');
shared.SurvivalPointTargetInput=pointInput; update();
assert.equal(commits().length,coldCommitCount+1,'cold click resumes exactly once');
const coldCommit=commits().at(-1).data;
assert.deepEqual([coldCommit.x,coldCommit.y,coldCommit.z],[128,192,384],
    'cold click saves raw coordinates until the real cell size is loaded');
assert.equal(poses().length,coldPoseCount,'cold queued click commits before starting a ghost');
commitResult(coldCommit,1); update();
assert.equal(commits().length,coldCommitCount+1);

// Repeated D, Escape, right-click and selection changes invalidate cold intent.
listeners.ui_grid_placement_profiles({profiles:[]});
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
world=[129,191,384]; mouse('pressed',0);
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
listeners.ui_grid_placement_profiles(moveProfiles);
assert.equal(commits().length,coldCommitCount+1,'repeated D discards an old queued click');
world=[193,319,384]; mouse('pressed',0);
commitResult(commits().at(-1).data,1);
for(const cancel of [() => keyboard('ESCAPE',true), () => mouse('pressed',1), () => {
    shared.SurvivalSelectionResolver.Resolve=()=>11; update();
}]) {
    listeners.ui_grid_placement_profiles({profiles:[]});
    const countBefore=commits().length;
    assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
    mouse('pressed',0); cancel();
    shared.SurvivalSelectionResolver.Resolve=()=>10;
    listeners.ui_grid_placement_profiles(moveProfiles); update();
    assert.equal(commits().length,countBefore,'canceled cold click never resumes');
    assert(!shared.SurvivalGridPlacement.IsRelocating(10));
}
// The grid controller is also entered by native ability targeting and generic
// point targeting; these paths must reject cooldown without the D adapter.
function assertNoMoveWork(before, label) {
    assert.equal(requests().length,before.requests,label+': no validation');
    assert.equal(poses().length,before.poses,label+': no ghost');
    assert.equal(commits().length,before.commits,label+': no commit');
    assert(!shared.SurvivalGridPlacement.IsRelocating(10),label+': no relocation session');
    assert(panels.get('GridPlacementRoot').classes.has('Hidden'),label+': grid stays hidden');
}
const moveWork = () => ({requests:requests().length,poses:poses().length,commits:commits().length});
moveCooldown=5;
let beforeCooldown=moveWork();
assert.equal(shared.SurvivalGridPlacement.BeginRelocation(20,10),false,'direct grid call refuses cooldown');
update(); assertNoMoveWork(beforeCooldown,'direct cooldown');
shared.SurvivalPointTargetState={active:true,name:'ability_building_blink',ability:20,unit:10};
beforeCooldown=moveWork(); update();
assertNoMoveWork(beforeCooldown,'generic point-target bypass');
assert(!shared.SurvivalPointTargetState.active,'cooldown cancels generic point targeting');
nativeAbility=20; beforeCooldown=moveWork(); update();
assertNoMoveWork(beforeCooldown,'native target bypass');
const nativeErrorCount=nativeErrors.length;
for(let frame=0;frame<10;frame++) update();
assert.equal(nativeErrors.length,nativeErrorCount,'native targeting polling does not spam the error');
nativeAbility=-1; update();
assert(nativeErrors.some(e=>e.name==='dota_hud_error_message'&&e.data.message==='移动防御塔CD中'),
    'cooldown uses the native HUD error event');

// Cooldown can begin while the first D is waiting for profiles/input; a queued
// click must be discarded before the delayed modules can create a preview.
moveCooldown=0; listeners.ui_grid_placement_profiles({profiles:[]});
delete shared.SurvivalPointTargetInput;
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
world=[129,191,384]; mouse('pressed',0);
beforeCooldown=moveWork(); moveCooldown=5;
listeners.ui_grid_placement_profiles(moveProfiles);
shared.SurvivalPointTargetInput=pointInput; update();
assertNoMoveWork(beforeCooldown,'cold cooldown race');
moveCooldown=0; update();
assertNoMoveWork(beforeCooldown,'canceled cold intent never resumes after cooldown');

assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
beforeCooldown=moveWork(); moveCooldown=3; update();
assertNoMoveWork(beforeCooldown,'active cooldown transition');
assert(!shared.SurvivalPointTargetState.active);

moveCooldown=0;
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
beforeCooldown=moveWork(); moveCooldown=3;
mouse('pressed',0);
assertNoMoveWork(beforeCooldown,'cooldown begins just before landing click');

// A stale local cooldown snapshot still cannot preserve or reopen targeting
// after the authoritative server reports that the move ability is cooling down.
moveCooldown=0;
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
const serverCooldownRequest=requests().at(-1).data;
beforeCooldown=moveWork();
listeners.ui_grid_placement_validation({...moveResponse(serverCooldownRequest),
    success:0,error:'move_ability_cooldown'});
update(); assertNoMoveWork(beforeCooldown,'server validation cooldown');
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
mouse('pressed',0);
const serverCooldownCommit=commits().at(-1).data;
beforeCooldown=moveWork();
listeners.ui_grid_placement_commit_result({session_id:serverCooldownCommit.session_id,
    success:0,error:'move_ability_cooldown'});
update(); assertNoMoveWork(beforeCooldown,'server commit cooldown');
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10),'ready ability recovers after rejection');
shared.SurvivalGridPlacement.CancelRelocation();
nativeAbility=20; update();
const nativeCooldownRequest=requests().at(-1).data;
beforeCooldown=moveWork();
listeners.ui_grid_placement_validation({...moveResponse(nativeCooldownRequest),
    success:0,error:'move_ability_cooldown'});
for(let i=0;i<5;i++) update();
assertNoMoveWork(beforeCooldown,'server cooldown blocks persistent native target with stale local snapshot');
nativeAbility=-1; update(); nativeAbility=20; update();
assert(!panels.get('GridPlacementRoot').classes.has('Hidden'),'fresh native intent recovers after target clears');
nativeAbility=-1; update();
console.log('TOWER_RELOCATION_COOLDOWN_PASS direct/custom/native entry, polling dedup, cold race, active transition, authoritative rejection and recovery');

listeners.ui_grid_placement_profiles({profiles:[]});
const retiredCommitCount=commits().length;
assert(shared.SurvivalGridPlacement.BeginRelocation(20,10));
mouse('pressed',0);
shared.SurvivalGridControllerEpoch++;
listeners.ui_grid_placement_profiles(moveProfiles);
assert.equal(commits().length,retiredCommitCount,'retired controller cannot replay a queued cold click');
console.log('TOWER_RELOCATION_CLIENT_PASS immediate/once-only click, fresh target, cold profile+input queue, retry, stale replies, D/Esc/right/selection cancel, retired controller');
