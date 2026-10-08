const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const shared={},panels=[];
const panel=()=>({style:{},visible:false,AddClass(){},RemoveClass(){}});
const context={GameUI:{CustomUIConfig:()=>shared},
    $:{CreatePanel(){const p=panel();panels.push(p);return p;}}};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_static_grid.js','utf8'),context);
const api=shared.SurvivalStaticGrid;
const mesh=api.geometry({bounds:{min_x:-4096,max_x:2048,min_y:1024,max_y:7168},height:384},64);
assert.equal(mesh.segments.length,194,'97 rows + 97 columns, not four lines per tile');
assert.equal(mesh.xs.length*mesh.ys.length,9409);
assert(mesh.xs.every(x=>x%64===0)&&mesh.ys.every(y=>y%64===0));
assert.equal(api.geometry({bounds:{min_x:1,max_x:0,min_y:0,max_y:64},height:0},64),null);
const reference=[-512,-512,1024,1024];
function corners(project) {return [[-512,-512],[512,-512],[512,512],[-512,512]].map(p=>project(...p));}
for (const coeff of [[1,0,800,0,0.5,500,0,0,1],
    [0.67,-0.2,820,0.11,0.39,470,0.00005,0.00016,1]]) {
    const project=(x,y)=>[(coeff[0]*x+coeff[1]*y+coeff[2])/(coeff[6]*x+coeff[7]*y+1),
        (coeff[3]*x+coeff[4]*y+coeff[5])/(coeff[6]*x+coeff[7]*y+1)];
    const view=api.projection(reference,corners(project));
    assert(view);
    for(let x=-2000;x<=2000;x+=64) for(let y=-2000;y<=2000;y+=128) {
        const actual=api.point(view,x,y),expected=project(x,y);
        assert(Math.hypot(actual[0]-expected[0],actual[1]-expected[1])<1e-7,'exact perspective world-grid alignment');
        const picked=api.unproject(view,actual[0],actual[1]);
        assert(picked && Math.hypot(picked[0]-x,picked[1]-y)<1e-7,
            'screen cursor ray meets displayed construction plane for rotated/perspective cameras');
    }
    for (const line of mesh.segments) {
        const clipped=api.segment(view,line,1600,900);
        if (clipped) for(const p of clipped) assert(p[0]>=-1e-6&&p[1]>=-1e-6&&p[0]<=1600.000001&&p[1]<=900.000001);
    }
}
assert.equal(api.projection(reference,[[0,0],[0,0],[0,0],[0,0]]),null,'reject degenerate camera');
assert.equal(api.unproject(null,0,0),null);
assert.equal(api.unproject({inverse:[1,0,0,0,1,0,0,0,0]},10,10),null,'reject horizon without infinite styles');
console.log('STATIC_GRID_GEOMETRY_PASS: 194 shared lines, 64-unit alignment, exact perspective and viewport clipping');
let camera=0,projectionCalls=0,segmentCalls=0;
const mask=panel(),host=panel();
const renderer=api.create({mask,host,viewport:()=>[1600,900],
    project:p=>{projectionCalls++;return [p[0]+1000-camera,p[1]*0.5+450];},
    setStyle:(p,k,v)=>{p.style[k]=v;},positionSegment:()=>{segmentCalls++;}});
assert(renderer.configure({bounds:{min_x:-4096,max_x:2048,min_y:-2048,max_y:2048},height:384},64,
    {radius:1280,grid_z_offset:6}));
for(let i=0;i<45;i++) renderer.warm();
assert(!mask.visible,'preload creates no visible preview');
renderer.update([0,0,384]);
assert(mask.visible,'white grid is ready before any validation packet exists');
const builds=renderer.stats.view_builds,layouts=renderer.stats.layout_writes,created=panels.length;
const segmentsBefore=segmentCalls,bridgeBefore=projectionCalls;
for(let i=1;i<=30;i++) renderer.update([i*64,0,384]);
assert.equal(renderer.stats.view_builds,builds,'mouse motion never rebuilds viewport geometry');
assert(renderer.stats.layout_writes>layouts && renderer.stats.layout_writes-layouts<=30*(128+160),
    'mouse motion refreshes bounded circle-clipped endpoints and fade');
assert(segmentCalls>segmentsBefore && segmentCalls-segmentsBefore<=30*128);
assert.equal(panels.length,created,'mouse motion allocates no grid panels');
assert.equal(projectionCalls-bridgeBefore,120,'four plane probes per frame, independent of cell count');
const outer=mask.style.position.split(' ').map(parseFloat),inner=host.style.position.split(' ').map(parseFloat);
assert.deepEqual(outer,[0,0,0]);assert.deepEqual(inner,[0,0,0],
    'world projection is rendered directly in a fixed viewport');
camera+=128;renderer.update([30*64,0,384]);
assert.equal(renderer.stats.view_builds,builds+1,'camera motion updates the plane projection');
assert.equal(renderer.stats.geometry_builds,1,'fixed world geometry survives camera motion');
renderer.hide();assert(!mask.visible);
renderer.update([64,0,384]);assert(mask.visible,'cancel/re-enter reuses static mesh');
console.log('STATIC_GRID_RENDER_PASS: 30 cursor steps, zero allocations / camera rebuilds, fixed viewport');
const tiltedMask=panel(),tiltedHost=panel();
const tilted=api.create({mask:tiltedMask,host:tiltedHost,viewport:()=>[1600,900],
    project:p=>[(0.67*p[0]-0.2*p[1]+820)/(0.00005*p[0]+0.00016*p[1]+1),
        (0.11*p[0]+0.39*p[1]+470)/(0.00005*p[0]+0.00016*p[1]+1)],
    setStyle:(p,k,v)=>{p.style[k]=v;},positionSegment(){}});
const tiltedLayout={bounds:{min_x:-1024,max_x:1024,min_y:-1024,max_y:1024},height:384};
tilted.configure(tiltedLayout,64,{radius:1280,grid_z_offset:6});
for(let i=0;i<45;i++) tilted.warm();
tilted.update([256,384,384]);
const outerPos=tiltedMask.style.position.split(' ').map(parseFloat);
const innerPos=tiltedHost.style.position.split(' ').map(parseFloat);
assert.deepEqual(outerPos,[0,0,0]);assert.deepEqual(innerPos,[0,0,0]);
for(const container of [tiltedMask,tiltedHost]) {
    assert.equal(container.style.transform,'none','rotated cameras do not rotate or resize the viewport container');
    assert.equal(parseFloat(container.style.width),1600);assert.equal(parseFloat(container.style.height),900);
}
tilted.configure(null,64,{});assert(!tilted.enabled());
tilted.configure(tiltedLayout,64,{radius:1280,grid_z_offset:6});
assert(tilted.enabled(),'same geometry can be restored after missing/invalid profiles');
console.log('STATIC_GRID_TRANSFORM_PASS: tilted camera retains fixed viewport containers');
// Whole 128-native-tile map, including ocean beyond the construction island.
const whole={bounds:{min_x:-16384,max_x:16384,min_y:-16384,max_y:16384},height:384};
assert.equal(api.geometry(whole,64).segments.length,1026);
renderer.configure(whole,64,{radius:1280,grid_z_offset:6});
for(let i=0;i<60;i++)renderer.warm();
const nodes=panels.length,buildsBefore=renderer.stats.geometry_builds;
for(const x of [-15000,-8000,6000,15000]) {
    camera=x;renderer.update([x,0,384]);renderer.warm();
    assert(mask.visible,'sea and distant land retain the range grid');
    assert(renderer.stats.line_panels<=128&&renderer.stats.mark_panels<2049,
        'full-map coverage must not allocate full-map UI cells');
    const b=renderer.visibleBounds();assert(b[0]<x&&b[2]>x);
}
assert.equal(renderer.stats.geometry_builds,buildsBefore,'camera sweep reuses whole-map geometry');
assert.equal(panels.length,nodes,'equal viewport coverage reuses the panel pool across the ocean');
console.log('STATIC_GRID_WHOLE_MAP_PASS 1026 shared lines; viewport-only UI; ocean coverage');
// Reproduce finite-resolution engine projections after jumping across islands.
let cameraWorld=[12000,13000],roundTrips=0,projectionMissing=false;
function engineProject(p) {
    if(projectionMissing)return null;
    const x=p[0]-cameraWorld[0],y=p[1]-cameraWorld[1],w=1+0.00022*y;
    if(w<=0.01)return null;
    return [Math.round((800+0.7*x+0.15*y)/w),Math.round((450-0.45*y)/w)];
}
const distantMask=panel(),distantOutline=panel();
const distant=api.create({mask:distantMask,host:panel(),outline:distantOutline,
    viewport:()=>[1600,900],referenceWorld:()=>cameraWorld,project:engineProject,
    setStyle:(p,k,v)=>{p.style[k]=v;},positionSegment(){}});
distant.configure(whole,64,{radius:1280,grid_z_offset:6});
distant.setPlaneRange(true);
for(const location of [[12000,13000],[-14000,-10000],[12000,-12000],[0,4000]]) {
    cameraWorld=location;for(let n=0;n<50;n++)distant.warm();
    distant.update([location[0],location[1],384]);
    for(const offset of [[0,0],[512,512],[-512,-384]]) {
        const w=[location[0]+offset[0],location[1]+offset[1],390],screen=engineProject(w);
        const picked=distant.worldAtScreen(screen);assert(picked);
        assert(Math.hypot(picked[0]-w[0],picked[1]-w[1])<8,
            'distant quantized engine projection must remain well below half-cell picking error');
        distant.update([w[0],w[1],384]);roundTrips++;
        assert(distantMask.visible);
        for(const container of [distantMask,distantOutline]) for(const value of Object.values(container.style))
            assert(!/NaN|Infinity/.test(String(value)),'remote grid and outline styles remain finite');
    }
    assert(distant.stats.corner_candidates<=4356,'bounded mark work even for the whole map');
}
assert(distant.stats.reference_rebases>=4);
projectionMissing=true;distant.refreshView();assert(!distantMask.visible);
projectionMissing=false;distant.update([cameraWorld[0],cameraWorld[1],384]);
assert(distantMask.visible,'same camera must recover after a temporary invalid engine projection');
distant.hide();assert(!distantOutline.visible);
console.log('STATIC_GRID_DISTANT_CAMERA_PASS quantized_projection_roundtrips='+roundTrips+'; finite outline; bounded corner work');
