// Latest saved map -> five native, paintable challenge islands. No full regeneration.
'use strict';
const fs=require('fs'),crypto=require('crypto'),L=require('./lib.cjs');
const out='output/challenge_native',source=fs.readFileSync(out+'/before_text.vmap','utf8');
const old=require('../../output/challenge_art_unify/manifest.json');
const defs=old.defs.map(d=>({...d,center:d.id==='08'?[-5248,6656]:d.center,playableSize:[1049,1049],nativeNavSize:[1024,1024],set:d.theme==='snow'?1:d.theme==='volcanic'?2:3}));
const assert=(v,m)=>{if(!v)throw Error(m);};
const sha=s=>crypto.createHash('sha256').update(s).digest('hex');
const inside=(x,y,d,r)=>Math.abs(x-d.center[0])<=r&&Math.abs(y-d.center[1])<=r;
const entities=L.blocks(source,'CMapEntity'),meshes=L.blocks(source,'CMapMesh'),grid=L.blocks(source,'CMapDotaTileGrid')[0],g=L.blocks(grid.text,'CDmeDotaTileGrid')[0];
function arrays(t,min){const a={};for(const m of t.matchAll(/"(\w+)" "(int|uint8|bool|color|string)_array"\s*\[([^\]]*)\]/g)){const v=[...m[3].matchAll(/"([^"\r\n]*)"/g)].map(m=>m[1]);if(v.length>=min)a[m[1]]=/Configuration/.test(m[1])?L.records(v):v;}return a;}
const a=arrays(g.text,16384),original=JSON.parse(JSON.stringify(a));
assert(!a.cellsTileSet.includes('3'),'Fourth tile slot is used; cannot replace it safely');
const seed=fs.readFileSync('output/map_layout_v4/seed.vmap','utf8'),sa=arrays(L.blocks(seed,'CDmeDotaTileGrid')[0].text,4096),variants=new Map();
for(let y=0;y<64;y++)for(let x=0;x<64;x++){const i=y*64+x,vs=[y*65+x,y*65+x+1,(y+1)*65+x,(y+1)*65+x+1];if(sa.cellsTileSet[i]!=='2'||vs.some(v=>sa.verticesHeight[v]!=='0'))continue;const k=vs.map(v=>sa.verticesWater[v]).join('');if(!variants.has(k))variants.set(k,[]);variants.get(k).push(i);}
const changedCells=[];
for(let y=0;y<129;y++)for(let x=0;x<129;x++){const wx=-16384+x*256,wy=-16384+y*256,d=defs.find(d=>inside(wx,wy,d,1280));if(!d)continue;const dx=wx-d.center[0],dy=wy-d.center[1],land=(dx/840)**4+(dy/860)**4<=1;a.verticesWater[y*129+x]=land?'0':'1';a.verticesHeight[y*129+x]='0';}
// Round unsupported tiny concave cuts into the island rather than inserting
// a green Radiant fallback tile into the winter shoreline.
for(let pass=0;pass<20;pass++){let changed=0;for(let y=0;y<128;y++)for(let x=0;x<128;x++){
 if(!defs.some(d=>inside(-16256+x*256,-16256+y*256,d,1152)))continue;
 const vs=[y*129+x,y*129+x+1,(y+1)*129+x,(y+1)*129+x+1],mask=vs.map(v=>a.verticesWater[v]).join('');
 if(mask!=='1111'&&!variants.has(mask))for(const v of vs)if(a.verticesWater[v]==='1'){a.verticesWater[v]='0';changed++;}
}if(!changed)break;}
for(let y=0;y<128;y++)for(let x=0;x<128;x++){
 const wx=-16256+x*256,wy=-16256+y*256,d=defs.find(d=>inside(wx,wy,d,1152));if(!d)continue;
 const i=y*128+x,vs=[y*129+x,y*129+x+1,(y+1)*129+x,(y+1)*129+x+1],mask=vs.map(v=>a.verticesWater[v]).join('');
 if(mask==='1111')continue;const opts=variants.get(mask);assert(opts,'No official winter shoreline for mask '+mask);
 const si=opts[(x*7+y*13)%opts.length];
 for(const k of ['cellsHidden','cellsOrientation','cellsCustomPathType','cellsVariationId','cellConfiguration','cellConfigurationByName'])a[k][i]=sa[k][si];
 a.cellsTileSet[i]='3';a.cellsMaterialSet[i]=String(d.set);changedCells.push(i);
}
const clamp=v=>Math.max(0,Math.min(1,v)),smooth=(a,b,v)=>{const t=clamp((v-a)/(b-a));return t*t*(3-2*t);};
const n=(x,y)=>.5+.22*Math.sin(x/190+y/117)+.17*Math.cos(y/87-x/250)+.07*Math.sin(x/53-y/61),byte=v=>Math.round(clamp(v)*255);
for(let y=0;y<1025;y++)for(let x=0;x<1025;x++){
 const wx=-16384+x*32,wy=-16384+y*32,d=defs.find(d=>inside(wx,wy,d,1136));if(!d)continue;const dx=wx-d.center[0],dy=wy-d.center[1],i=y*1025+x,t=n(dx,dy),edge=smooth(500,800,Math.max(Math.abs(dx),Math.abs(dy)));
 let r,g,b;
 if(d.theme==='snow'){r=.84+.13*t;g=(1-edge)*smooth(.52,.8,n(dx+70,dy-110))*.5;b=edge*.25;}
 else if(d.theme==='volcanic'){r=.78+.18*t;g=smooth(.44,.72,t)*.45;b=edge*smooth(.60,.80,t)*.72;}
 else{r=(1-smooth(-230,200,dx+100*Math.sin(dy/140)))*.65;g=r*.4;b=smooth(-10,300,dx)*smooth(.57,.8,t)*(.3+.6*edge);}
 a.blendOpacity[i]=[byte(r),byte(g),byte(b),128].join(' ');a.blendColor[i]='255 255 255 0';a.blendTransitionAndPath[i]='0 0 0 0';a.grassOpacity[i]='0';a.blendHeight[i]=String(Math.round(128+edge*9*(t-.5)));a.flowMap[i]='10 20 0 0';
}
for(let y=0;y<512;y++)for(let x=0;x<512;x++){
 const wx=-16352+x*64,wy=-16352+y*64,d=defs.find(d=>inside(wx,wy,d,1136));if(!d)continue;
 // GridNav is 64-unit quantized. Only cells FULLY inside the 1049 box open.
 // This yields a 1024-unit navigable square, never an expanded 1088 square.
 a.gridnavFlags[y*512+x]=(Math.abs(wx-d.center[0])+32<=524.5&&Math.abs(wy-d.center[1])+32<=524.5)?'0':'1';
}
// No automatic camp/grass/prop tile placements in the native test islands.
for(let y=0;y<513;y++)for(let x=0;x<513;x++)if(defs.some(d=>inside(-16384+x*64,-16384+y*64,d,1088))){const i=y*513+x;for(const k of Object.keys(a).filter(k=>k.startsWith('object')&&a[k].length===263169))a[k][i]=/Configuration/.test(k)?[]:k==='objectsVariationId'?'255':'0';}
let updated=g.text.replace(/"(\w+)" "(int|uint8|bool|color|string)_array"\s*\[[^\]]*\]/g,(all,k,type)=>{if(!a[k])return all;const v=/Configuration/.test(k)?a[k].flatMap(r=>[String(r.length),...r]):a[k];return `"${k}" "${type}_array" [`+v.map(v=>'"'+v+'"').join(',')+']';});
let terrain=grid.text.slice(0,g.start)+updated+grid.text.slice(g.end);
terrain=terrain.replaceAll('maps/tilesets/radiant_coloseum_basic.vmap','maps/tilesets/survival_challenge_native.vmap');
const removedSet=new Set(old.newNodes),edits=[{...grid,text:terrain}],removed=[];
const isTarget=t=>/^challenge_(05|06|07|08|09)_/.test(L.value(t,'targetname')||'');
const markers=[];
for(const b of [...entities,...meshes]){
 const id=+L.value(b.text,'nodeID');if(removedSet.has(id)&&!isTarget(b.text)){edits.push({...b,text:''});removed.push(id);continue;}
 if(!isTarget(b.text))continue;const name=L.value(b.text,'targetname'),d=defs.find(d=>name.startsWith('challenge_'+d.id+'_'));
 const was=old.defs.find(q=>q.id===d.id),p=L.value(b.text,'origin').split(' ').map(Number);p[0]+=d.center[0]-was.center[0];p[1]+=d.center[1]-was.center[1];p[2]=148;edits.push({...b,text:L.setValue(b.text,'origin',p.join(' '))});markers.push({name,origin:p});
}
let result=source,cursor=0,parts=[];for(const e of edits.sort((a,b)=>a.start-b.start)){assert(e.start>=cursor,'Overlapping edit');let before=source.slice(cursor,e.start);if(!e.text){const comma=source.slice(e.end).match(/^\s*,/);if(comma){parts.push(before);cursor=e.end+comma[0].length;continue;}before=before.replace(/,\s*$/,'');}parts.push(before,e.text);cursor=e.end;}parts.push(source.slice(cursor));result=parts.join('');
result=result.replace('"maps/tilesets/radiant_coloseum_basic.vmap"','"maps/tilesets/survival_challenge_native.vmap"');
// Add exact design-limit markers; these are not an oversized physical platform.
let next=Math.max(...[...source.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
const adds=[];for(const d of defs)for(const [label,sign] of [['min',-1],['max',1]])adds.push(`"CMapEntity" { "id" "elementid" "${crypto.randomUUID()}" "nodeID" "int" "${next++}" "children" "element_array" [] "entity_properties" "EditGameClassProps" { "id" "elementid" "${crypto.randomUUID()}" "classname" "string" "info_target" "targetname" "string" "challenge_${d.id}_playable_${label}" } "origin" "vector3" "${d.center[0]+sign*524.5} ${d.center[1]+sign*524.5} 128" "angles" "qangle" "0 0 0" "scales" "vector3" "1 1 1" }`);
const world=result.indexOf('"world" "CMapWorld"'),cs=result.indexOf('[',result.indexOf('"children" "element_array"',world)),ce=L.endOf(result,cs,'[',']')-1;result=result.slice(0,ce).replace(/,\s*$/,'')+',\n'+adds.join(',')+'\n'+result.slice(ce);
const after=new Map([...L.blocks(result,'CMapEntity'),...L.blocks(result,'CMapMesh')].map(b=>[L.value(b.text,'nodeID'),b.text]));let preserved=0;
for(const b of [...entities,...meshes])if(!removedSet.has(+L.value(b.text,'nodeID'))&&!isTarget(b.text)){assert(after.get(L.value(b.text,'nodeID'))===b.text,'Changed unrelated object');preserved++;}
fs.writeFileSync(out+'/native.vmap',result);fs.writeFileSync(out+'/manifest.json',JSON.stringify({sourceSHA256:sha(fs.readFileSync(out+'/before.vmap')),defs,markers,removed,preserved,changedNativeCells:changedCells.length,tileSet:'maps/tilesets/survival_challenge_native.vmap',navigation:'1049 design boundary; engine 64-unit nav grid conservatively opens 1024, never enlarges movement',water:'Same official water_flow as ocean; no winter opaque ice sheet against liquid water'},null,2));console.log(JSON.stringify({nativeCells:changedCells.length,preserved,removed:removed.length,output:out+'/native.vmap'}));
