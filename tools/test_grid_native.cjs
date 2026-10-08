const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const shared={},calls=[],panels=[];
let clock=0;
function panel(){const p={visible:false,style:{},AddClass(){},RemoveClass(){}};panels.push(p);return p;}
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_static_grid.js','utf8'),{
    GameUI:{CustomUIConfig:()=>shared},$:{CreatePanel:panel},Date:{now:()=>clock}
});
let serial=0;
const particles={CreateParticle(path,attach,owner){calls.push(['create',path,attach,owner]);return serial++;},
    SetParticleControl(id,cp,p){calls.push(['control',id,cp,...p]);},
    DestroyParticleEffect(id,instant){calls.push(['destroy',id,instant]);},
    ReleaseParticleIndex(id){calls.push(['release',id]);}};
const api=shared.SurvivalStaticGrid,native=api.createNativeGrid(particles,6);
assert(native.update([0,0,384],64,390,1280));
assert.equal(native.stats.creates,1);
assert.equal(calls[0][1],'particles/survival_grid/reference_grid_0.vpcf');
assert.deepEqual(calls.at(-1),['control',0,0,0,0,390],'particle zero is a valid index');
const before=calls.length;
for(let i=0;i<120;i++)assert(native.update([0,0,384],64,390,1280));
assert.equal(calls.length,before,'stationary and camera-only updates never cross the particle API bridge');
for(const [world,phase] of [[[32,0,384],1],[[0,32,384],2],[[32,32,384],3],[[-32,-32,384],3],[[-64,0,384],0]]){
    assert(native.update(world,64,390,1280));
    assert.equal(native.stats.phase,phase,'odd footprint phase remains world aligned at negative coordinates');
}
const creates=native.stats.creates;
native.update([-128,64,384],64,390,1280);
assert.equal(native.stats.creates,creates,'whole-cell cursor movement retains the same particle');
native.hide();native.hide();
assert.equal(calls.filter(c=>c[0]==='destroy').length,creates);
assert.equal(calls.filter(c=>c[0]==='release').length,creates);
assert(!native.update([0,0,384],128,390,1280),'unsupported grid sizes keep the UI fallback');
assert(!native.update([0,0,384],64,390,640),'unsupported radii keep the UI fallback');
assert(!native.update([10,0,384],64,390,1280),'off-grid positions cannot shift the texture away from world cells');

let distance=1200,styleWrites=0,segments=0;
const mask=panel(),host=panel(),outline=panel();
const grid=api.create({mask,host,outline,nativeGrid:native,viewport:()=>[1600,900],referenceWorld:()=>[0,0],
    project:p=>{const w=distance+0.4*p[1];return w>0?[800+900*p[0]/w,450-550*p[1]/w]:null;},
    setStyle(p,k,v){p.style[k]=v;styleWrites++;},positionSegment(){segments++;}});
grid.configure({bounds:{min_x:-16384,max_x:16384,min_y:-16384,max_y:16384},height:384},64,{radius:1280,grid_z_offset:6});
for(let i=0;i<80;i++)grid.prewarm();
assert.equal(grid.stats.line_panels,0);assert.equal(grid.stats.mark_panels,0);
grid.setPlaneRange(true);
grid.update([0,0,384]);
assert(!outline.visible,'native grid and circle share one world sprite, with no UI ring');
const zoomStart={nodes:panels.length,controls:native.stats.control_updates,creates:native.stats.creates,styles:styleWrites};
for(const d of [2400,1800,1200,800,600,520,512,400,240,600,1200,2400]){
    distance=d;grid.update([0,0,384]);assert(mask.visible&&grid.stats.native_active);
}
assert.equal(native.stats.control_updates,zoomStart.controls);
assert.equal(native.stats.creates,zoomStart.creates);
assert.equal(styleWrites,zoomStart.styles,'camera zoom never rewrites white-grid panel styles');
assert.equal(panels.length,zoomStart.nodes);assert.equal(segments,0);assert.equal(grid.stats.layout_writes,0);
grid.hide();assert(!native.stats.active&&!mask.visible);
grid.update([0,0,384]);assert(native.stats.active&&mask.visible);
grid.update([16000,0,384]);
assert(!native.stats.active&&!grid.stats.native_active,'finite outer map bounds use the clipped UI fallback');
grid.update([0,0,384]);assert(native.stats.active&&mask.visible);
grid.configure(null,64,{});assert(!native.stats.active&&!grid.stats.native_active);

const failed=api.createNativeGrid({...particles,CreateParticle(){return -1;}},6);
assert.equal(failed.update([0,0,384],64,390,1280),false);
assert.equal(failed.stats.active,false);
const throws=api.createNativeGrid({...particles,
    SetParticleControl(id,cp){if(cp===0)throw new Error('renderer rejected control');},
    DestroyParticleEffect(){throw new Error('renderer already disposed');}},6);
const releases=calls.filter(c=>c[0]==='release').length;
assert.equal(throws.update([0,0,384],64,390,1280),false,'control failure selects the fallback');
assert.equal(throws.stats.active,false);
assert.equal(calls.filter(c=>c[0]==='release').length,releases+1,'release is still attempted after destruction throws');
assert(!native.update([NaN,0,384],64,390,1280));
assert(!native.update(null,64,390,1280));
let reject=true;
const recoverable=api.createNativeGrid({...particles,CreateParticle(...args){return reject?-1:particles.CreateParticle(...args);}},6);
const recoveryMask=panel(),recoveryHost=panel();
const recovery=api.create({mask:recoveryMask,host:recoveryHost,nativeGrid:recoverable,
    viewport:()=>[1600,900],project:p=>[800+p[0],450-p[1]],
    setStyle(p,k,v){p.style[k]=v;},positionSegment(){}});
const recoveryLayout={bounds:{min_x:-4096,max_x:4096,min_y:-4096,max_y:4096},height:384};
recovery.configure(recoveryLayout,64,{radius:1280,grid_z_offset:6});
for(let i=0;i<12;i++)recovery.update([0,0,384]);
assert(recoveryMask.visible&&!recovery.stats.native_active&&recovery.stats.visible_lines>0,
    'renderer failure actually displays the projected UI fallback');
reject=false;clock=1001;recovery.update([0,0,384]);
assert(recovery.stats.native_active&&recoveryMask.visible,'renderer recovers after the retry interval');
assert(recoveryHost!==host);
recovery.configure({...recoveryLayout,height:512},64,{radius:1280,grid_z_offset:6});
recovery.update([0,0,512]);
assert.deepEqual(calls.at(-1).slice(2),[0,0,0,518],'new map height reaches the native plane without a stale particle');
recovery.configure(recoveryLayout,128,{radius:1280,grid_z_offset:6});
for(let i=0;i<12;i++)recovery.prewarm();
assert.equal(recovery.stats.line_panels,128);assert.equal(recovery.stats.mark_panels,160,
    'unsupported configurations retain UI prewarming');
console.log('GRID_NATIVE_PASS one sprite; four footprint phases; zero white layouts or particle controls during zoom; cleanup and fallback');
