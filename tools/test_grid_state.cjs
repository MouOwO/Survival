const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const shared={},all=[];
function panel(host) {
    const p={host,visible:false,style:{},classes:new Set(),AddClass(c){this.classes.add(c);},RemoveClass(c){this.classes.delete(c);},
        SetHasClass(c,v){v?this.classes.add(c):this.classes.delete(c);}};all.push(p);return p;
}
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_grid_state.js','utf8'),
    {GameUI:{CustomUIConfig:()=>shared},$:{CreatePanel:(_,host)=>panel(host)}});
const api=shared.SurvivalGridState;
assert.equal(api.decode('3|64|0|0|1.5|2|384|aaa'),null);
assert.equal(api.decode('3|64|0|0|1|1|384|f'),null);
assert.equal(api.decode('3|64|0|0|2|2|384|a'),null);
const atlas=api.decode('3|64|-1|-1|2|2|384|a9');
assert.equal(api.sample(atlas,-32,-32),2);assert.equal(api.sample(atlas,32,-32),1);
assert.equal(api.sample(atlas,-96,-32),0,'unknown outside atlas is never green');
assert.equal(api.runs({size:64,x:0,y:0,w:1,h:17,states:Array(17).fill(1)}).length,3,
    'long runs are bounded so camera clipping cannot discard an entire map column');
function contains(clip,p,w,h) {
    const n=clip.match(/-?\d+(?:\.\d+)?/g).map(Number);
    const angle=Math.atan2(p[0]/w-n[0]/100,n[1]/100-p[1]/h)*180/Math.PI;
    return ((angle-n[2]+720)%360)<=n[3]+1e-4;
}
// A solid quad must contain its entire interior with no scanline seams. Verify
// off-axis, mirrored screen Y, and far-corner perspective, not just rectangles.
for(const q of [[[5,90],[110,90],[96,8],[8,8]],[[90,95],[12,70],[25,12],[115,35]]]) {
    const c0=api.wedge(q[0],q[1],q[3],128,128),c2=api.wedge(q[2],q[1],q[3],128,128);
    for(let x=0;x<128;x+=3)for(let y=0;y<128;y+=3) {
        const crosses=q.map((p,i)=>{const n=q[(i+1)%4];return (n[0]-p[0])*(y-p[1])-(n[1]-p[1])*(x-p[0]);});
        if(crosses.some(v=>Math.abs(v)<0.01))continue;
        const expected=crosses.every(v=>v>0)||crosses.every(v=>v<0);
        assert.equal(contains(c0,[x,y],128,128)&&contains(c2,[x,y],128,128),expected);
    }
}
// Keep non-square projected geometry, but give both native clipping panels a
// square padded frame. Pixel-angle and UV-angle interpretation must now agree.
for(const [w,h] of [[64,512],[512,48],[37,283]]) {
    const side=Math.max(w,h);
    const q=[[w*0.1,0],[w*0.6,0],[w,h],[w*0.3,h]];
    const c0=api.wedge(q[0],q[1],q[3],side,side),c2=api.wedge(q[2],q[1],q[3],side,side);
    for(let row=1;row<40;row++)for(let col=1;col<40;col++) {
        const x=col*w/40,y=row*h/40;
        const left=w*(0.1+0.2*row/40),right=w*(0.6+0.4*row/40);
        if(Math.min(Math.abs(x-left),Math.abs(x-right))<0.01)continue;
        assert.equal(contains(c0,[x,y],side,side)&&contains(c2,[x,y],side,side),x>left&&x<right,
            'every blocked cell in an elongated projected run must fill its entire width');
    }
}
let camera=0,writes=0;
const terrainHost={},dynamicHost={},footHost={};
const state=api.create({terrainHost,dynamicHost,footHost,project:p=>[p[0]+300-camera,p[1]*0.5+200],
    cameraKey:()=>String(camera),setStyle:(p,k,v)=>{p.style[k]=v;writes++;},
    cellSize:()=>64,zOffset:()=>6,viewport:()=>[800,600]});
state.ingestDynamic('3|64|-1|-1|2|2|384|a9');state.warm();
assert(all.some(p=>p.host===dynamicHost&&p.visible));
state.configure('3|64|-1|-1|2|2|384|a9');state.warm();
assert(!all.some(p=>p.host===dynamicHost&&p.visible),'late atlas removes duplicated red from dynamic overlay');
const before=state.stats.terrain_builds;
state.configure('3|64|-1|-1|2|2|384|a9');state.warm();
assert.equal(state.stats.terrain_builds,before,'duplicate profile/atlas delivery does not rebuild');
state.update([0,0,384],{grid_footprint_x:2,grid_footprint_y:2},null);
const foot=()=>all.filter(p=>p.host===footHost&&p.classes.has('FootprintTile')&&p.visible);
assert.equal(foot().length,4);assert.equal(foot().filter(p=>p.classes.has('Blocked')).length,1);
for(const p of all.filter(p=>p.classes.has('GridStateQuad')&&p.visible)) {
    assert.equal(p.style.width,p.style.height,'every actual fill uses a square clip frame');
    assert(p.__fill.style.clip&&p.style.clip,'both opposite-vertex clips are present');
}
const beforeWrites=writes;state.update([0,0,384],{grid_footprint_x:2,grid_footprint_y:2},null);
assert.equal(writes,beforeWrites,'unchanged footprint does not rewrite native style');
state.hideFoot();assert.equal(foot().length,0);
assert(all.some(p=>p.host===terrainHost&&p.visible),'cancel only hides footprint, not cached terrain');
// Exercise the actual paint output under off-axis perspective, rather than
// checking wedge() alone. Every sampled interior point must remain colored.
const perspective=p=>[(800+0.8*p[0]+0.24*p[1])/(1+p[1]*0.0002),
    (400+0.06*p[0]+0.5*p[1])/(1+p[1]*0.0002)];
const perspectiveHost={};
const perspectiveState=api.create({terrainHost:{},dynamicHost:{},footHost:perspectiveHost,
    project:perspective,cameraKey:()=> 'perspective',setStyle:(p,k,v)=>{p.style[k]=v;},
    cellSize:()=>64,zOffset:()=>6,viewport:()=>[1600,900]});
perspectiveState.update([0,0,384],{grid_footprint_x:4,grid_footprint_y:4},null);
const projectedCells=all.filter(p=>p.host===perspectiveHost&&p.classes.has('FootprintTile')&&p.visible);
assert.equal(projectedCells.length,16);
projectedCells.forEach((p,i)=>{
    const position=p.style.position.split(' ').map(parseFloat),side=parseFloat(p.style.width);
    assert.equal(p.style.width,p.style.height);
    const gx=Math.floor(i/4),gy=i%4;
    for(let u=0.1;u<1;u+=0.2)for(let v=0.1;v<1;v+=0.2){
        const screen=perspective([-128+(gx+u)*64,-128+(gy+v)*64,390]);
        const local=[screen[0]-position[0],screen[1]-position[1]];
        assert(contains(p.style.clip,local,side,side)&&contains(p.__fill.style.clip,local,side,side),
            'projected grid interior is covered, including the screen-side cells');
    }
});
console.log('GRID_STATE_PASS: exact native quad clips, individual colors, persistent terrain, no duplicate red');
const oceanTerrain={},oceanDynamic={},oceanFoot={};let oceanCamera=8000,oceanWrites=0;
const ocean=api.create({terrainHost:oceanTerrain,dynamicHost:oceanDynamic,footHost:oceanFoot,
    project:p=>[p[0]-oceanCamera+400,p[1]*0.5+300],cameraKey:()=>String(oceanCamera),
    visibleBounds:()=>[oceanCamera-410,-610,oceanCamera+410,610],
    setStyle:(p,k,v)=>{p.style[k]=v;oceanWrites++;},cellSize:()=>64,zOffset:()=>6,viewport:()=>[800,600]});
ocean.configureLayout({bounds:{min_x:-16384,max_x:16384,min_y:-16384,max_y:16384},
    build_bounds:{min_x:-4096,max_x:2048,min_y:1024,max_y:7168},height:384});
ocean.update([8000,0,384],{grid_footprint_x:4,grid_footprint_y:4},null);
const sea=all.filter(p=>p.host===oceanTerrain),seaFoot=all.filter(p=>p.host===oceanFoot&&p.classes.has('FootprintTile'));
assert.equal(sea.length,4,'all exterior ocean uses only four static rectangles');
assert(sea.some(p=>p.visible));assert(seaFoot.every(p=>p.visible&&p.classes.has('Blocked')),
    'ocean is known red immediately, even before the island atlas arrives');
assert(sea.filter(p=>p.visible).every(p=>parseFloat(p.style.width)<1600),'large red regions clip to the viewport');
const oceanCount=all.length,styles=sea.map(p=>JSON.stringify(p.style));
for(let i=0;i<10;i++)ocean.update([8000+i*64,0,384],{grid_footprint_x:4,grid_footprint_y:4},null);
assert.deepEqual(sea.map(p=>JSON.stringify(p.style)),styles,'mouse motion does not repaint static ocean');
assert.equal(all.length,oceanCount);
oceanCamera=-8000;ocean.update([-8000,0,384],{grid_footprint_x:4,grid_footprint_y:4},null);
assert(sea.some(p=>p.visible)&&seaFoot.every(p=>p.classes.has('Blocked')));
console.log('GRID_OCEAN_STATE_PASS 4 static rectangles; no scan wait; no mouse-driven allocations');
const dense=api.runs({size:64,x:0,y:0,w:96,h:96,states:Array(96*96).fill(1)});
assert.equal(dense.length,144,'solid static terrain merges into bounded 8x8 blocks instead of 1152 thin strips');
assert.equal(dense.reduce((n,r)=>n+(r[2]-r[0])*(r[3]-r[1])/4096,0),96*96,'merging preserves every blocked cell');
let offscreenProjections=0;
const culled=api.create({terrainHost:{},dynamicHost:{},footHost:{},project:p=>{offscreenProjections++;return p;},
    visibleBounds:()=>[8000,8000,9000,9000],cameraKey:()=> 'far',setStyle(){},
    cellSize:()=>64,zOffset:()=>6,viewport:()=>[800,600]});
culled.configure('3|64|0|0|96|96|384|'+'5'.repeat(96*96/2));
for(let i=0;i<60;i++)culled.warm();
assert.equal(offscreenProjections,0,'offscreen island terrain must not enter projection or engine fallback');
console.log('GRID_DISTANT_CULL_PASS 1152 strips -> 144 rectangles; 0 offscreen projections');

function paintedAt(p,x,y) {
    if(!p.visible)return false;
    const position=p.style.position.split(' ').map(parseFloat),side=parseFloat(p.style.width);
    const local=[x-position[0],y-position[1]];
    return local[0]>=0&&local[1]>=0&&local[0]<=side&&local[1]<=side&&
        p.__clips.every(c=>c.style.clip==='none'||contains(c.style.clip,local,side,side));
}
function inRangePolygon(x,y,range) {
    return Array.from({length:32},(_,i)=>{
        const angle=(i+0.5)*Math.PI/16;
        return Math.cos(angle)*(x-range.x)+Math.sin(angle)*(y-range.y)<=range.radius*Math.cos(Math.PI/32);
    }).every(Boolean);
}
let range={x:0,y:0,radius:220},rangeWrites=0;
const rangeTerrain={},rangeDynamic={},rangeFoot={};
const ranged=api.create({terrainHost:rangeTerrain,dynamicHost:rangeDynamic,footHost:rangeFoot,
    range:()=>range,project:p=>[p[0]+300,p[1]+300],cameraKey:()=> 'fixed',
    setStyle:(p,k,v)=>{p.style[k]=v;rangeWrites++;},cellSize:()=>64,zOffset:()=>6,viewport:()=>[600,600]});
ranged.ingestDynamic('3|64|-4|-4|8|8|384|'+'5'.repeat(32));ranged.warm();
const circularDynamic=all.filter(p=>p.host===rangeDynamic&&p.visible);
assert.equal(circularDynamic.length,1);
assert.equal(circularDynamic[0].__clips.length,16,'a complete range uses sixteen wedges for its 32 polygon edges');
for(let x=2;x<600;x+=9)for(let y=3;y<600;y+=11) {
    assert.equal(paintedAt(circularDynamic[0],x,y),inRangePolygon(x-300,y-300,range),
        'all nested native wedges fill exactly the circle polygon with no outside color');
}
ranged.configure('3|64|-4|-4|8|8|384|'+'5'.repeat(32));ranged.warm();
assert(!circularDynamic[0].visible,'late static terrain still removes duplicate dynamic range color');
const circularTerrain=all.find(p=>p.host===rangeTerrain&&p.visible);
assert(circularTerrain);
for(let x=2;x<600;x+=9)for(let y=3;y<600;y+=11) {
    assert.equal(paintedAt(circularTerrain,x,y),inRangePolygon(x-300,y-300,range));
}
const stillWrites=rangeWrites;ranged.warm();
assert.equal(rangeWrites,stillWrites,'unchanged circle and camera perform no style writes');
range={x:400,y:0,radius:220};ranged.warm();
assert(!paintedAt(circularTerrain,100,300)&&paintedAt(circularTerrain,510,300),
    'changing only the range center clips cached terrain to its new circle');

// Fill panels remain bounded even when perspective maps a cell well past every
// viewport edge. A fully visible cell must not disappear at extreme zoom.
const closeFoot={};
const close=api.create({terrainHost:{},dynamicHost:{},footHost:closeFoot,
    range:()=>({x:0,y:0,radius:1}),project:p=>[p[0]*1e7+400,p[1]*1e7+300],cameraKey:()=> 'close',
    setStyle:(p,k,v)=>{p.style[k]=v;},cellSize:()=>64,zOffset:()=>6,viewport:()=>[800,600]});
close.update([0,0,384],{grid_footprint_x:1,grid_footprint_y:1},null);
const closeCell=all.find(p=>p.host===closeFoot&&p.classes.has('FootprintTile')&&p.visible);
assert(closeCell,'a footprint remains complete even when it extends beyond the terrain range');
assert.equal(closeCell.style.width,'800px');
assert.equal(closeCell.style.height,'800px');
for(let x=10;x<800;x+=31)for(let y=10;y<600;y+=29)assert(paintedAt(closeCell,x,y));

// The viewport turns a projected quad into a polygon with more than four edges.
// Check actual fill membership against the inverse projection, including the
// clipped edges, rather than only counting panels or testing bounds.
const slicedFoot={},affine=p=>[p[0]*12+p[1]*7+120,-p[0]*6+p[1]*13+300];
const sliced=api.create({terrainHost:{},dynamicHost:{},footHost:slicedFoot,
    project:affine,cameraKey:()=> 'sliced',setStyle:(p,k,v)=>{p.style[k]=v;},
    cellSize:()=>64,zOffset:()=>6,viewport:()=>[600,500]});
sliced.update([0,0,384],{grid_footprint_x:1,grid_footprint_y:1},null);
const slicedCell=all.find(p=>p.host===slicedFoot&&p.classes.has('FootprintTile')&&p.visible);
assert(slicedCell.__clips.length>2,'viewport clipping can produce more than four polygon edges');
assert(parseFloat(slicedCell.style.width)<=600);
for(let sx=3;sx<600;sx+=11)for(let sy=5;sy<500;sy+=13) {
    const x=(13*(sx-120)-7*(sy-300))/198,y=(6*(sx-120)+12*(sy-300))/198;
    if(Math.min(Math.abs(Math.abs(x)-32),Math.abs(Math.abs(y)-32))<0.001)continue;
    assert.equal(paintedAt(slicedCell,sx,sy),Math.abs(x)<32&&Math.abs(y)<32,
        'clipped convex polygons retain every interior pixel and no outside pixel');
}

let cachingRange={x:0,y:0,radius:900};
const cachingTerrain={},cachingFoot={};
const caching=api.create({terrainHost:cachingTerrain,dynamicHost:{},footHost:cachingFoot,
    range:()=>cachingRange,project:p=>[p[0]*0.2+300,p[1]*0.2+300],cameraKey:()=> 'range-cache',
    setStyle:(p,k,v)=>{p.style[k]=v;},cellSize:()=>64,zOffset:()=>6,viewport:()=>[600,600]});
caching.configure('3|64|-16|-16|32|32|384|'+'5'.repeat(512));
caching.update([0,0,384],{grid_footprint_x:2,grid_footprint_y:2},null);
const beforeRangeTerrain=caching.stats.terrain_layouts,beforeRangeFoot=caching.stats.footprint_layouts;
cachingRange={x:8,y:8,radius:900};
caching.update([0,0,384],{grid_footprint_x:2,grid_footprint_y:2},null);
assert.equal(caching.stats.footprint_layouts,beforeRangeFoot,'range motion never invalidates an unchanged footprint');
assert(caching.stats.terrain_layouts>beforeRangeTerrain&&caching.stats.terrain_layouts<beforeRangeTerrain*2,
    'range motion only repaints boundary blocks, reusing interior terrain');
console.log('GRID_RANGE_CLIP_PASS exact convex fills; viewport-bounded panels; boundary-only range repaint');

// Exercise the production homography and polygon clip together. A rotated
// close camera puts two corners of a single terrain block behind its plane;
// its visible interior and every visible footprint cell must still be filled.
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_static_grid.js','utf8'),
    {GameUI:{CustomUIConfig:()=>shared},$:{CreatePanel:(_,host)=>panel(host)}});
let nearDistance=240,crossingPolygons=0;
function nearEngine(p) {
    const u=(p[0]-p[1])*Math.SQRT1_2,v=(p[0]+p[1])*Math.SQRT1_2,w=nearDistance+v;
    return w>1e-6?[800+600*u/w,450-600*v/w]:null;
}
const nearMask=panel({}),nearHost=panel({}),nearTerrain={},nearFoot={};
const nearGrid=shared.SurvivalStaticGrid.create({mask:nearMask,host:nearHost,
    viewport:()=>[1600,900],referenceWorld:()=>[0,0,384],project:nearEngine,
    setStyle:(p,k,v)=>{p.style[k]=v;},positionSegment(){}});
assert(nearGrid.configure({bounds:{min_x:-4096,max_x:4096,min_y:-4096,max_y:4096},height:384},64,
    {radius:1280,grid_z_offset:6}));
for(let i=0;i<12;i++)nearGrid.warm();
const nearState=api.create({terrainHost:nearTerrain,dynamicHost:{},footHost:nearFoot,
    range:()=>nearGrid.range(),visibleBounds:()=>nearGrid.drawBounds(),project:p=>nearGrid.project(p),
    projectPolygon:points=>{
        const visible=points.map(p=>!!nearGrid.project(p));
        if(visible.some(Boolean)&&visible.some(v=>!v))crossingPolygons++;
        return nearGrid.projectPolygon(points);
    },cameraKey:()=>nearGrid.cameraKey(),setStyle:(p,k,v)=>{p.style[k]=v;},
    cellSize:()=>64,zOffset:()=>6,viewport:()=>[1600,900]});
nearState.configure('3|64|-8|-8|8|8|384|'+'5'.repeat(32));
for(const distance of [240,400,512]) {
    nearDistance=distance;nearGrid.update([0,0,384]);
    const beforeCrossing=crossingPolygons;
    nearState.update([0,0,384],{grid_footprint_x:4,grid_footprint_y:4},null);
    assert(nearMask.visible,'the real grid projection survives close-camera horizon crossings');
    assert(crossingPolygons>beforeCrossing,'terrain corners actually cross the camera plane at distance '+distance);
    const reds=all.filter(p=>p.host===nearTerrain&&p.visible);
    assert.equal(reds.length,1,'the partly behind-camera terrain block retains its visible portion');
    const cells=all.filter(p=>p.host===nearFoot&&p.classes.has('FootprintTile')&&p.visible);
    assert.equal(cells.length,16,'all 4 by 4 footprint cells remain represented at distance '+distance);
    for(const p of reds.concat(cells)) {
        assert.equal(p.style.width,p.style.height);
        assert(parseFloat(p.style.width)<=1600,'near-plane clipping never allocates a giant color surface');
        assert(!/NaN|Infinity/.test(JSON.stringify(p.style)));
    }
    for(let sx=9;sx<1600;sx+=37)for(let sy=7;sy<900;sy+=29) {
        const world=nearGrid.worldAtScreen([sx,sy]);
        if(world&&Math.min(Math.abs(world[0]),Math.abs(world[1]),Math.abs(world[0]+512),Math.abs(world[1]+512))<0.001)continue;
        const expected=!!world&&world[0]>-512&&world[0]<0&&world[1]>-512&&world[1]<0;
        assert.equal(paintedAt(reds[0],sx,sy),expected,'near-plane red fill matches the inverse world projection');
    }
    cells.forEach((p,i)=>{
        const gx=Math.floor(i/4),gy=i%4;
        for(let u=0.1;u<1;u+=0.2)for(let v=0.1;v<1;v+=0.2) {
            const screen=nearGrid.project([-128+(gx+u)*64,-128+(gy+v)*64,390]);
            if(screen&&screen[0]>0&&screen[0]<1600&&screen[1]>0&&screen[1]<900)
                assert(paintedAt(p,screen[0],screen[1]),'every on-screen footprint interior remains filled');
        }
    });
}
console.log('GRID_NEAR_PLANE_PASS distances=240,400,512; visible red polygon; complete 4x4 footprint; bounded surfaces');

// Bounds are a coarse candidate filter, not part of the cached projected
// geometry. Expanding a buffered coverage window with a fixed camera must not
// reuse the small rectangle cut out when this terrain block first appeared.
let windowBounds=[-40,-40,40,40],windowKey=0;
const windowTerrain={},windowState=api.create({terrainHost:windowTerrain,dynamicHost:{},footHost:{},
    visibleBounds:()=>windowBounds,coverageKey:()=>String(windowKey),range:()=>({x:0,y:0,radius:1000}),
    project:p=>[p[0]+300,p[1]+300],cameraKey:()=> 'window-camera',
    setStyle:(p,k,v)=>{p.style[k]=v;},cellSize:()=>64,zOffset:()=>6,viewport:()=>[600,600]});
windowState.configure('3|64|-4|-4|8|8|384|'+'5'.repeat(32));windowState.warm();
windowBounds=[-256,-256,256,256];windowKey++;windowState.warm();
const windowFill=all.find(p=>p.host===windowTerrain&&p.visible);
assert(paintedAt(windowFill,80,80)&&paintedAt(windowFill,520,520),
    'expanding coverage never leaves the cached interior red rectangle cropped to its old bounds');

// Reusing panels across atlas shrink/grow, changing blocked spans, circle
// motion, and camera zoom must not leave old wedges or holes in the new fill.
function changingAtlas(x,y,w,h,phase) {
    const states=[];
    for(let gx=0;gx<w;gx++)for(let gy=0;gy<h;gy++)states.push((gx*7+gy*3+phase)%11<6?1:2);
    let packed='';for(let i=0;i<states.length;i+=2)packed+=(states[i]+4*(states[i+1]||0)).toString(16);
    return {x,y,w,h,states,source:'3|64|'+[x,y,w,h,384,packed].join('|')};
}
function expectedState(atlas,x,y) {
    const gx=Math.floor(x/64)-atlas.x,gy=Math.floor(y/64)-atlas.y;
    return gx>=0&&gy>=0&&gx<atlas.w&&gy<atlas.h?atlas.states[gx*atlas.h+gy]:0;
}
const changingTerrain={},changingDynamic={};
const changing=api.create({terrainHost:changingTerrain,dynamicHost:changingDynamic,footHost:{},
    range:()=>nearGrid.range(),visibleBounds:()=>nearGrid.drawBounds(),coverageKey:()=>nearGrid.coverageKey(),
    project:p=>nearGrid.project(p),projectPolygon:points=>nearGrid.projectPolygon(points),
    cameraKey:()=>nearGrid.cameraKey(),setStyle:(p,k,v)=>{p.style[k]=v;},
    cellSize:()=>64,zOffset:()=>6,viewport:()=>[1600,900]});
let comparedPixels=0;
for(let frame=0;frame<16;frame++) {
    nearDistance=[240,600,1600,4000][frame%4];
    const cursor=[[-768,-64],[512,512],[768,-256],[-128,0]][Math.floor(frame/4)];
    nearGrid.update([cursor[0],cursor[1],384]);
    const terrainAtlas=changingAtlas(-8,-8,frame%2?8:16,frame%3?16:8,frame);
    const dynamicAtlas=changingAtlas(-5+frame%4,-4,frame%2?12:4,frame%3?8:12,frame+3);
    changing.configure(terrainAtlas.source);changing.ingestDynamic(dynamicAtlas.source);
    for(let i=0;i<12;i++)changing.warm();
    const fills=all.filter(p=>(p.host===changingTerrain||p.host===changingDynamic)&&p.visible);
    for(let sx=13;sx<1600;sx+=43)for(let sy=17;sy<900;sy+=41) {
        const world=nearGrid.worldAtScreen([sx,sy]);
        if(!world)continue;
        const fx=((world[0]%64)+64)%64,fy=((world[1]%64)+64)%64;
        if(Math.min(fx,64-fx,fy,64-fy)<0.001)continue;
        const expected=inRangePolygon(world[0],world[1],nearGrid.range())&&
            (expectedState(terrainAtlas,world[0],world[1])===1||expectedState(dynamicAtlas,world[0],world[1])===1);
        assert.equal(fills.some(p=>paintedAt(p,sx,sy)),expected,
            'atlas/range/camera replacement preserves exact blocked coverage on frame '+frame);
        comparedPixels++;
    }
}
console.log('GRID_REUSE_COVERAGE_PASS moving bounds; shrinking atlases; '+comparedPixels+' screen samples');

// Native Panorama keeps the previous radial primitive when assigned "none".
// Reproduce its getter/setter behavior: a circle needs sixteen clip layers,
// while the later interior rectangle only needs two. The other fourteen must
// become full radial clips, otherwise their old edges punch holes in the quad.
let nativeRange={x:0,y:0,radius:220};
const nativeHost={},nativeState=api.create({terrainHost:nativeHost,dynamicHost:{},footHost:{},
    range:()=>nativeRange,project:p=>[p[0]+300,p[1]+300],cameraKey:()=> 'native-clip-reuse',
    setStyle:(p,k,v)=>{if(k!=='clip'||v!=='none')p.style[k]=v;},
    cellSize:()=>64,zOffset:()=>6,viewport:()=>[600,600]});
nativeState.configure('3|64|-4|-4|8|8|384|'+'5'.repeat(32));nativeState.warm();
const nativeFill=all.find(p=>p.host===nativeHost&&p.visible),nativeCount=all.length;
assert.equal(nativeFill.__clips.length,16);
assert(!paintedAt(nativeFill,60,60),'the first range correctly excludes the rectangle corners');
nativeRange={x:0,y:0,radius:1000};nativeState.warm();
assert.equal(all.length,nativeCount,'shrinking the clipping chain reuses its allocated nodes');
for(let x=51;x<555;x+=19)for(let y=53;y<555;y+=23)
    assert(paintedAt(nativeFill,x,y),'unused native radial clips must not cut holes in the newly enlarged red block');
nativeRange={x:0,y:0,radius:220};nativeState.warm();
assert.equal(all.length,nativeCount);
assert(!paintedAt(nativeFill,60,60)&&paintedAt(nativeFill,300,300),
    'the same layers resume exact circular clipping after their full-coverage reset');
console.log('GRID_NATIVE_CLIP_REUSE_PASS retained-radial engine semantics; 16 -> 2 -> 16 clips; no holes or allocations');
