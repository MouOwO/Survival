// Transplant the original editable Dota tile data, including paint and authored props.
// The four inward-facing U shapes meet along their diagonal shoulders.
const fs=require('fs'),path=require('path');
const source=fs.readFileSync(path.resolve(__dirname,'../output/reference_asset_study/project_template_text.vmap'),'utf8');
const arrays={};
for(const m of source.matchAll(/^\t{6}"(\w+)" "(\w+)_array"\s*\[([^\]]*)\]/gm)){
 if(/^(cells|vertices|edges|objects|blend|grass|flow|fog|gridnav)/.test(m[1]))arrays[m[1]]=[...m[3].matchAll(/"([^"]*)"/g)].map(v=>v[1]);
}
const center=[-1152,2688],pivot=[-2688,128];
function rotate(x,y,q){return q===0?[x,y]:q===1?[-y,x]:q===2?[-x,-y]:[y,-x];}
function quadrant(x,y){return Math.abs(x)>=Math.abs(y)?x>=0?0:2:y>=0?1:3;}
function locate(x,y){
 const dx=x-center[0],dy=y-center[1];if(Math.max(Math.abs(dx),Math.abs(dy))>4352)return null;
 const q=quadrant(dx,dy),v=rotate(dx,dy,(4-q)%4),sx=v[0]+pivot[0],sy=v[1]+pivot[1];
 return {q,x:sx,y:sy,valid:sx>=-3072&&sx<=1792&&sy>=-1664&&sy<=1920};
}
function scalar(key,x,y,step,vertex=true){const n=16384/step+(vertex?1:0),ix=Math.max(0,Math.min(n-1,Math.floor((x+8192)/step))),iy=Math.max(0,Math.min(n-1,Math.floor((y+8192)/step)));return arrays[key]?.[iy*n+ix];}
function shallow(x,y){const dx=Math.abs(x-center[0]),dy=Math.abs(y-center[1]);return Math.max(dx,dy)<=1792&&Math.min(dx,dy)<=320;}
function originalLand(p){return p?.valid&&scalar('verticesWater',p.x,p.y,256)==='0';}
// The source's 0-level courtyard and 1-level side arms are separate gameplay
// terraces. Previously the +3 offset put the courtyard BELOW our 416 water.
const levels={water:416,bed:396,attack:640,tower:768,stairStart:1792,stairEnd:2304,stairWidth:576};
function approach(x,y){const p=locate(x,y);if(!p)return false;const r=p.x-pivot[0],v=p.y-pivot[1];return r>=levels.stairStart&&r<=2688&&Math.abs(v)<=320;}
function replacedStairTile(x,y){const p=locate(x,y);return !!p&&Math.abs(p.x-pivot[0]-levels.stairEnd)<8&&Math.abs(p.y-pivot[1])<128;}
function height(x,y){const p=locate(x,y);if(!p)return null;if(shallow(x,y))return 3;if(!p.valid)return 3;
 // Keep the native foundation below the explicit entrance treads.
 if(approach(x,y)&&p.x-pivot[0]<levels.stairEnd)return 3;
 return originalLand(p)?Number(scalar('verticesHeight',p.x,p.y,256))+5:3;}
function edgeValue(key,x,y,vertical,p){
 // Each row has 65 vertical and 64 horizontal edges; the last row only horizontals.
 const a=rotate(x-center[0],y-center[1],(4-p.q)%4),b=rotate(x+(vertical?0:256)-center[0],y+(vertical?256:0)-center[1],(4-p.q)%4);
 const sx=Math.round((Math.min(a[0],b[0])+pivot[0]+8192)/256),sy=Math.round((Math.min(a[1],b[1])+pivot[1]+8192)/256),v=Math.abs(a[0]-b[0])<1;
 return arrays[key][sy<64?sy*129+sx*2+(v?0:1):64*129+sx]||'0';
}
function sample(key,x,y,original,edgeVertical=false){
 const p=locate(x,y);if(!p)return original;
 const isShallow=shallow(x,y),land=originalLand(p);
 if(key==='verticesHeight')return height(x,y);
 if(key==='verticesWater')return isShallow||land?'0':'1';
 if(key==='gridnavFlags')return isShallow||approach(x,y)||land?'0':'1';
 if(key==='cellsTileSet')return '0';
 if(!p.valid)return original;
 if(approach(x,y)&&/^objects(Prop|Plant|Tree)Type$/.test(key))return '0';
 if(key.startsWith('edges'))return edgeValue(key,x,y,edgeVertical,p);
 let value;
 if(key.startsWith('cells'))value=scalar(key,p.x,p.y,256,false);
 else if(key.startsWith('objects'))value=scalar(key,p.x,p.y,64);
 else if(/^(blend|grass|fog|flow)/.test(key))value=scalar(key,p.x,p.y,32);
 if(value===undefined)return original;
 if(key==='cellsOrientation')value=(Number(value)+p.q)%4;
 if(key==='objectsRotation')value=(Number(value)+p.q*64)%256;
 if(key==='objectsTileSet')value='0';
 if(key==='blendOpacity'&&isShallow)value='210 255 0 128';
 if(key==='grassOpacity'&&isShallow)value='0';
 return value;
}
function transform(sx,sy,q){const v=rotate(sx-pivot[0],sy-pivot[1],q);return [center[0]+v[0],center[1]+v[1]];}
module.exports={center,pivot,locate,shallow,height,sample,transform,arrays,originalLand,levels,approach,replacedStairTile};
