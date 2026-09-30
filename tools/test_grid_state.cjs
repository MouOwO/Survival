const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const shared={},all=[];
function panel(host) {
    const p={host,visible:false,style:{},classes:new Set(),AddClass(c){this.classes.add(c);},
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
