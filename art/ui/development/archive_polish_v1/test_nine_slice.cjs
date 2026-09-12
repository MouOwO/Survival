const fs=require('fs'),vm=require('vm'),assert=require('assert');
class Panel{constructor(parent){this.parent=parent;this.children=[];this.style={};this.classes=[];if(parent)parent.children.push(this)}AddClass(c){this.classes.push(c)}}
const cfg={},root=new Panel();vm.runInNewContext(fs.readFileSync(__dirname+'/nine_slice.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg},$:{CreatePanel:(type,parent)=>new Panel(parent)}});
for(const spec of [[304,64,35,23],[209,54,31,18],[143,138,29,33],[88,29,12,10]]){
 const [w,h,l,t]=spec,n=cfg.SurvivalNineSlice.Create(root,'file://test',w,h,[l,t,l,t],'Test');
 assert.equal(n.children.length,3);assert.equal(n.hittest,false);assert.equal(n.hittestchildren,false);
 const regions=[];
 n.children.forEach((row,y)=>{assert.equal(row.children.length,3);assert.equal(row.style.height,y===1?'fill-parent-flow(1)':t+'px');row.children.forEach((tile,x)=>{assert.equal(tile.style.width,x===1?'fill-parent-flow(1)':l+'px');assert.equal(tile.hittestchildren,false);const [sx,sy]=tile.style.backgroundSize.split(' ').map(parseFloat);assert(Number.isFinite(sx)&&Number.isFinite(sy));const cw=w*100/sx,ch=h*100/sy;regions.push(cw*ch);});});
 assert(Math.abs(regions.reduce((a,b)=>a+b,0)-w*h)<.001,'UV regions must cover the source exactly once');
 for(const [W,H]of [[w,h],[w*2,h],[w,h*2],[w*2,h*2]]){const midW=W-2*l,midH=H-2*t;assert(midW>0&&midH>0);assert.equal(2*l+midW,W);assert.equal(2*t+midH,H);}
}
const asymmetric=cfg.SurvivalNineSlice.Create(root,'file://test',143,138,[29,33,12,12]);
const center=asymmetric.children[1].children[1],pos=center.style.backgroundPosition.split(' ').map(parseFloat);
assert(Math.abs(pos[0]/100*(29+12)-29)<.00001,'Center UV must start after the left corner');
assert(Math.abs(pos[1]/100*(33+12)-33)<.00001,'Center UV must start below the top corner');
console.log('NINE_SLICE_PASS: fixed corners, independent edge axes, complete UV coverage including asymmetric margins, four profiles at four target sizes, no hit interception');
// Source resolution is independent of the final button width. Fixed regions
// must preserve identical X/Y sampling scales even on compact archive controls.
for(const [w,h,b,targetH] of [[156,64,[24,22,24,22],64],[156,64,[24,22,24,22],29],[156,64,[24,22,24,22],31],[256,76,[38,25,38,25],31],[112,32,[12,10,12,10],42]]){
 const scale=targetH/h,n=cfg.SurvivalNineSlice.AtHeight(root,'file://test',w,h,b,targetH);
 const top=n.children[0],corner=top.children[0];
 assert(Math.abs(parseFloat(corner.style.width)/b[0]-scale)<1e-9);
 assert(Math.abs(parseFloat(top.style.height)/b[1]-scale)<1e-9);
 const [sx,sy]=corner.style.backgroundSize.split(' ').map(parseFloat);
 assert(Math.abs(w*100/sx-b[0])<1e-9);
 assert(Math.abs(h*100/sy-b[1])<1e-9);
}
console.log('NINE_SLICE_SOURCE_SCALE_PASS: 156x64 buttons, 256x76 selected filters and 112x32 pass badges preserve original corner proportions');
