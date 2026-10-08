const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const shared={},panels=[];
let styleWrites=0,projectionCalls=0,distance=2400,rotation=0,center=[0,0],quantized=false;
const viewport=[1600,900],radius=1280;
function panel(parent) {
    const p={parent,style:{},visible:false,classes:new Set(),
        AddClass(c){this.classes.add(c);},RemoveClass(c){this.classes.delete(c);},
        SetHasClass(c,v){v?this.classes.add(c):this.classes.delete(c);}};
    panels.push(p);return p;
}
const context={GameUI:{CustomUIConfig:()=>shared},$:{CreatePanel:(_,parent)=>panel(parent),Msg(){}}};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_static_grid.js','utf8'),context);
function engineProject(p) {
    projectionCalls++;
    const dx=p[0]-center[0],dy=p[1]-center[1],c=Math.cos(rotation),s=Math.sin(rotation);
    const x=c*dx-s*dy,y=s*dx+c*dy,w=distance+0.4*y;
    if(w<=0)return null;
    const screen=[800+900*x/w,450-550*y/w];
    return quantized?screen.map(Math.round):screen;
}
const mask=panel(),host=panel(mask),outline=panel();
const grid=shared.SurvivalStaticGrid.create({mask,host,outline,viewport:()=>viewport,
    referenceWorld:()=>center,project:engineProject,
    setStyle(p,k,v){p.style[k]=v;styleWrites++;},
    positionSegment(p,a,b,thickness){p.points=[Array.from(a),Array.from(b)];p.thickness=thickness;}});
grid.configure({bounds:{min_x:-16384,max_x:16384,min_y:-16384,max_y:16384},height:384},
    64,{radius,grid_z_offset:6});
grid.setPlaneRange(true);
for(let i=0;i<80;i++)grid.prewarm();
assert.equal(projectionCalls,0,'hidden prewarm performs no camera projections');

function visibleLines(){return panels.filter(p=>p.visible&&p.classes.has('StaticGridLine'));}
function distanceToSegment(p,a,b) {
    const dx=b[0]-a[0],dy=b[1]-a[1],length2=dx*dx+dy*dy;
    const t=Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/length2));
    return Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy);
}
function gradientAlpha(line,screen) {
    const a=line.points[0],b=line.points[1],dx=b[0]-a[0],dy=b[1]-a[1];
    const t=((screen[0]-a[0])*dx+(screen[1]-a[1])*dy)/(dx*dx+dy*dy);
    const pattern=/color-stop\(([\d.]+),rgba\(213,230,211,([\d.]+)\)\)/g;
    const stops=Array.from(String(line.style.backgroundColor).matchAll(pattern),m=>[Number(m[1]),Number(m[2])]);
    assert(stops.length>=2,'world-clipped lines carry their own finite fade gradient');
    assert.equal(stops[0][0],0);assert.equal(stops[stops.length-1][0],1);
    for(let i=1;i<stops.length;i++)if(t<=stops[i][0]+1e-8) {
        const left=stops[i-1],right=stops[i],f=(t-left[0])/(right[0]-left[0]);
        return left[1]+f*(right[1]-left[1]);
    }
    return stops[stops.length-1][1];
}
function check(world) {
    assert(mask.visible,'preview remains visible while the circle crosses the camera horizon');
    for(const container of [mask,host]) {
        assert.equal(parseFloat(container.style.width),viewport[0],'container width never follows an unbounded ellipse');
        assert.equal(parseFloat(container.style.height),viewport[1],'container height stays at viewport size');
        assert.equal(container.style.position,'0px 0px 0px');
        assert.equal(container.style.transform,'none');
    }
    for(const p of panels)for(const value of Object.values(p.style))
        assert(!/NaN|Infinity/.test(String(value)),'all native styles remain finite');
    const lines=visibleLines(),screen=engineProject([...world,390]);
    assert(lines.length>0);
    const central=lines.filter(p=>distanceToSegment(screen,p.points[0],p.points[1])<1e-5);
    assert(central.length>=2,
        'both world-aligned grid boundaries through the cursor remain present');
    for(const line of central)assert(gradientAlpha(line,screen)>0.999,
        'the actual interpolated cursor gradient stays opaque even when the world circle crosses the horizon');
    for(const line of lines) {
        assert.equal(line.thickness,2,'white lines retain screen-space thickness while zooming');
        for(const p of line.points) {
            assert(p.every(Number.isFinite));
            assert(p[0]>=-1e-5&&p[0]<=viewport[0]+1e-5&&p[1]>=-1e-5&&p[1]<=viewport[1]+1e-5,
                'every line endpoint is clipped to the viewport');
            const w=grid.worldAtScreen(p);
            assert(w,'visible screen endpoints can be projected back to the construction plane');
            assert(Math.hypot(w[0]-world[0],w[1]-world[1])<=radius+1e-5,
                'every visible line endpoint remains inside the actual world circle');
        }
    }
    const picked=grid.worldAtScreen(screen);
    assert(Math.hypot(picked[0]-world[0],picked[1]-world[1])<1e-5,'cursor picking retains exact perspective');
    assert.equal(picked[2],384);
    assert(grid.stats.visible_marks<=160,'decoration count stays bounded');
    const before={styles:styleWrites,layouts:grid.stats.layout_writes,nodes:panels.length,views:grid.stats.view_builds};
    for(let i=0;i<10;i++)grid.update([...world,384]);
    assert.equal(styleWrites,before.styles,'a still preview performs no native style updates');
    assert.equal(grid.stats.layout_writes,before.layouts,'a still preview does not relayout lines or corners');
    assert.equal(panels.length,before.nodes,'a still preview allocates no panels');
    assert.equal(grid.stats.view_builds,before.views);
}

let samples=0;
for(const d of [2400,1200,800,640,560,520,512,480,400,240,400,640,1200,2400]) {
    distance=d;grid.update([...center,384]);check(center);samples++;
}
for(const camera of [[12032,13056],[-14016,-9984],[12032,-12032]]) {
    center=camera;
    for(const degrees of [-30,30,65])for(const d of [2400,1200,640,520,400,320,240]) {
        rotation=degrees*Math.PI/180;distance=d;
        grid.update([...center,384]);check(center);samples++;
    }
}
// Cursor motion changes clipping and feathering, but cannot move the world
// projection or require additional native nodes once the bounded pool is warm.
center=[0,0];rotation=0;distance=800;grid.update([...center,384]);
const nodeCount=panels.length,views=grid.stats.view_builds;
for(const offset of [[64,0],[128,64],[-128,128],[0,0]]) {
    grid.update([...offset,384]);check(offset);
    assert.equal(grid.stats.view_builds,views,'mouse motion never rebuilds the camera projection');
    assert.equal(panels.length,nodeCount,'mouse motion reuses the warmed grid pool');
}
grid.hide();assert(!mask.visible);assert(!outline.visible);
grid.update([...center,384]);check(center);
assert.equal(panels.length,nodeCount,'cancel and re-entry reuse the warmed pool');

// The engine's finite pixel precision must remain accurate after a close,
// rotated view forces a smaller reference patch and then zooms out again.
quantized=true;rotation=Math.PI/4;
let maximumPickError=0;
for(const d of [240,2400]) {
    distance=d;grid.update([...center,384]);assert(mask.visible);
    for(let x=-1024;x<=1024;x+=128)for(let y=-1024;y<=1024;y+=128) {
        if(Math.hypot(x,y)>1024)continue;
        const screen=engineProject([x,y,390]);
        if(!screen||screen[0]<0||screen[0]>1600||screen[1]<0||screen[1]>900)continue;
        const picked=grid.worldAtScreen(screen);assert(picked);
        maximumPickError=Math.max(maximumPickError,Math.hypot(picked[0]-x,picked[1]-y));
    }
}
assert(maximumPickError<8,'quantized camera probes retain picking precision after close zoom and recovery');

const css=fs.readFileSync('panorama/src/styles/custom_game/survival_grid_placement.css','utf8');
assert(!/opacity-mask\s*:/.test(css),'the preview never composites its subtree into an ellipse-sized opacity mask');
console.log(JSON.stringify({result:'GRID_ZOOM_VISIBILITY_PASS',camera_samples:samples,
    minimum_distance:240,line_thickness:2,maximum_corners:160,
    still_style_writes:0,still_allocations:0,quantized_maximum_pick_error:maximumPickError,
    viewport,measurement:'mocked projection and style invariants, not live FPS'}));
