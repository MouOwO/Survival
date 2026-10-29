'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),cp=require('child_process');
const L=require('../map_c6/lib.cjs');
const input=process.argv[2];assert(input,'Pass current text DMX snapshot');
const out=path.resolve('output/scourge_highland_20261029');fs.mkdirSync(out,{recursive:true});
const text=fs.readFileSync(input,'utf8'),grid=L.blocks(text,'CDmeDotaTileGrid')[0].text;
const heights=L.array(grid,'verticesHeight').map(Number),nav=L.array(grid,'gridnavFlags').map(Number);
assert.equal(heights.length,129*129);assert.equal(nav.length,512*512);
assert(heights.every(n=>Number.isInteger(n)&&n>=0&&n<=9),'Fixture encoding requires single-digit height layers');
const row=JSON.parse(fs.readFileSync('art/maps/mode_spawns/layout.json','utf8')).modes.scourge;
const sample=(x,y)=>{const gx=(x+16384)/256,gy=(y+16384)/256,i=Math.floor(gx),j=Math.floor(gy),u=gx-i,v=gy-j;
 return 128+128*((1-u)*(1-v)*heights[j*129+i]+u*(1-v)*heights[j*129+i+1]+(1-u)*v*heights[(j+1)*129+i]+u*v*heights[(j+1)*129+i+1]);};
const entities=L.blocks(text,'CMapEntity'),markers={};
for(const kind of ['player','monster'])for(let id=0;id<4;id++){
 const name=`mode_scourge_${kind}_${id}_spawn`,blocks=entities.filter(b=>L.value(b.text,'targetname')===name);assert.equal(blocks.length,1);
 const p=L.value(blocks[0].text,'origin').split(' ').map(Number),expected=row[kind==='player'?'players':'monsters'][id];
 assert.deepEqual(p,[expected[0],expected[1],expected[2]+16]);assert.equal(sample(p[0],p[1]),expected[2]);markers[name]=p;
}
markers.scourge_start=row.center;
// Source-grid route check only. Native collision/pathing still needs a new game.
const routes=[];
for(let id=0;id<4;id++){
 const start=row.monsters[id],goal=row.players[id],cell=p=>Math.floor((p[1]+16384)/64)*512+Math.floor((p[0]+16384)/64);
 const first=cell(start),last=cell(goal),seen=new Set([first]),queue=[first];let head=0;
 while(head<queue.length&&!seen.has(last)){
  const k=queue[head++],x=k%512,y=Math.floor(k/512),wx=-16352+x*64,wy=-16352+y*64;
  for(const [dx,dy] of [[1,0],[-1,0],[0,1],[0,-1]]){
   const nx=x+dx,ny=y+dy,n=ny*512+nx,px=wx+dx*64,py=wy+dy*64;
   if(px<row.bounds[0]||px>row.bounds[2]||py<row.bounds[1]||py>row.bounds[3]||seen.has(n)||nav[n]!==0)continue;
   if(Math.abs(sample(wx,wy)-sample(px,py))>64)continue;
   seen.add(n);queue.push(n);
  }
 }
 assert(seen.has(last),'No source-grid lowland to plateau route for '+id);routes.push({id,source_grid_route:true,visited_cells:seen.size});
}
const lua='return {height='+JSON.stringify(heights.join(''))+',nav='+JSON.stringify(nav.map(n=>n===0?'0':'1').join(''))+',markers={'+Object.entries(markers).map(([key,p])=>'["'+key+'"]={'+p.join(',')+'}').join(',')+'}}';
const fixture=path.join(out,'terrain_fixture.lua');fs.writeFileSync(fixture,lua);
const result=cp.spawnSync(process.env.LUA||'C:/Program Files/lua/bin/lua5.1.exe',['tools/test_scourge_highland.lua',fixture],{encoding:'utf8',windowsHide:true});
assert.equal(result.status,0,result.stdout+result.stderr);
fs.writeFileSync(path.join(out,'terrain_validation.json'),JSON.stringify({source:input,source_grid_routes:routes,lua:result.stdout,native_pathing_verified:false},null,2)+'\n');
console.log(result.stdout.trim());console.log('SCOURGE_TERRAIN_PASS: eight map markers and four source-grid lowland-to-plateau paths');
