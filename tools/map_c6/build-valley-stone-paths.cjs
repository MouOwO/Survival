'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs'),M=require('./mesh.cjs');
const out=path.resolve(__dirname,'../../output/valley_stone_paths'),before=fs.readFileSync(path.join(out,'before.vmap'),'utf8');
let node=Math.max(...[...before.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
const clamp=x=>Math.max(0,Math.min(1,x)),smooth=x=>{x=clamp(x);return x*x*(3-2*x);};
const meshes=[];let faces=0;
for(let lane=0;lane<4;lane++){
 const rot=(x,y)=>[[x,y],[y,-x],[-x,-y],[-y,x]][lane];
 const quads=[];
 for(let r=864;r<2816;r+=32)for(let s=-352;s<352;s+=32){
  const q=[[s,r],[s+32,r],[s+32,r+32],[s,r+32]].map(([x,y])=>{const p=rot(x,y);return [p[0]-1024,p[1]+4096,129.5];});quads.push(q);
 }
 let m=M.mesh(quads,'maps/ti10_assets/blends/mod_radiant_ti10_angled_000.vmat',node++,(wx,wy)=>{
  const x=wx+1024,y=wy-4096,r=Math.max(Math.abs(x),Math.abs(y)),s=Math.abs(x)>Math.abs(y)?y:x;
  const width=265+25*Math.exp(-Math.pow((r-1120)/230,2))+18*Math.sin(r*.014+lane)+12*Math.sin(r*.033+lane*2);
  const w=smooth((width+55-Math.abs(s-10*Math.sin(r*.009+lane*1.7)))/92)*smooth((r-864)/96)*smooth((2816-r)/128);
  return {blend:[0,1-w,w,.5],tint:[1,1,1,0]};
 });
 m=L.setValue(m,'physicsType','none');meshes.push(m);faces+=quads.length;
}
const world=before.indexOf('"CMapWorld"'),start=before.indexOf('[',before.indexOf('"children" "element_array"',world)),end=L.endOf(before,start,'[',']')-1;
const result=before.slice(0,end)+',\n'+meshes.join(',\n')+'\n'+before.slice(end);
for(const type of ['CMapEntity','CMapMesh']){const after=new Map(L.blocks(result,type).map(b=>[L.value(b.text,'nodeID'),b.text]));for(const b of L.blocks(before,type))if(after.get(L.value(b.text,'nodeID'))!==b.text)throw Error('Existing object changed');}
if(L.blocks(result,'CMapDotaTileGrid')[0].text!==L.blocks(before,'CMapDotaTileGrid')[0].text)throw Error('Terrain changed');
fs.writeFileSync(path.join(out,'stone_paths.vmap'),result);
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({implementation:'four editable non-colliding vertex-blended paving meshes',meshes:4,quads:faces,baseline_sha256:crypto.createHash('sha256').update(before).digest('hex'),existing_geometry_entities_terrain_navigation_preserved:true,material:'maps/ti10_assets/blends/mod_radiant_ti10_angled_000.vmat',stone_texture:'materials/stone/stone_path001_angled_color_psd_150d1d7b.vtex'},null,2));
console.log({meshes:4,quads:faces});
