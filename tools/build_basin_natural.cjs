// Art sample derived from the user's saved native terrain, never writes its source.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {worldChildren,name}=require('./basin_handoff_merge.cjs');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/basin_natural'),matdir=path.join(out,'materials');fs.mkdirSync(matdir,{recursive:true});
const source=fs.readFileSync(path.join(root,'output/basin_single/user_platform_text.vmap'),'utf8'),w=worldChildren(source);
let grid=w.nodes.find(n=>n.startsWith('"CMapDotaTileGrid"'));
function read(k){return [...grid.match(new RegExp('"'+k+'" "\\w+_array"\\s*\\[([^\\]]*)\\]'))[1].matchAll(/"([^"]*)"/g)].map(m=>m[1]);}
const h=read('verticesHeight').map(Number),hidden=read('cellsHidden').map(Number),flat=new Set();
for(let y=0;y<64;y++)for(let x=0;x<64;x++)if(!hidden[y*64+x]&&[h[y*65+x],h[y*65+x+1],h[(y+1)*65+x],h[(y+1)*65+x+1]].every(v=>v<=1)&&!(x>=30&&x<=35&&y>=30&&y<=33))hidden[y*64+x]=1;
for(let y=0;y<64;y++)for(let x=0;x<64;x++)if(!hidden[y*64+x]&&[h[y*65+x],h[y*65+x+1],h[(y+1)*65+x],h[(y+1)*65+x+1]].every(v=>v===4))flat.add(y*64+x);
const smooth=x=>{x=Math.max(0,Math.min(1,x));return x*x*(3-2*x);};
const noise=(x,y)=>.5+.25*Math.sin(x*.003+y*.0017)+.15*Math.cos(y*.006-x*.0023)+.1*Math.sin(x*.018+y*.012);
const ci=(x,y)=>Math.floor((y+8192)/256)*64+Math.floor((x+8192)/256);
function inFlat(x,y){return flat.has(ci(x,y));}
const borders=[];
for(const i of flat){const x=-8192+i%64*256,y=-8192+Math.floor(i/64)*256;for(const[other,seg]of [[i-1,[x,y,x,y+256]],[i+1,[x+256,y,x+256,y+256]],[i-64,[x,y,x+256,y]],[i+64,[x,y+256,x+256,y+256]]])if(!flat.has(other))borders.push(seg);}
function borderDistance(x,y){let d=Infinity;for(const[a,b,c,e]of borders){let t=Math.max(0,Math.min(1,((x-a)*(c-a)+(y-b)*(e-b))/((c-a)**2+(e-b)**2)));d=Math.min(d,Math.hypot(x-a-t*(c-a),y-b-t*(e-b)));}return inFlat(x,y)?d:-d;}
function wet(x,y){
 const ellipse=(cx,cy,rx,ry)=>(1-Math.hypot((x-cx)/rx,(y-cy)/ry))*Math.min(rx,ry);
 const a=ellipse(4310,570,380,780),b=ellipse(3750,1320,660,340),c=ellipse(2370,950,315,260);
 let f=Math.max(a,b,c)+12*Math.sin(x*.024+y*.018)+8*Math.cos(y*.037-x*.009);
 // Keep water 96 units clear of any original cliff / staircase tile.
 return Math.min(f,borderDistance(x,y)-180);
}
const height=(x,y)=>512-90*smooth((wet(x,y)+60)/240)+2*(noise(x,y)-.5);
const paint=(x,y)=>{const f=wet(x,y),d=borderDistance(x,y),n=noise(x,y);return[Math.max(.03,.7*smooth((f+100)/180)),Math.min(.85,.68*Math.exp(-Math.pow((f+75)/150,2))+.6*(1-smooth(d/240))*(.6+.4*n)),0,0];};
const nativeHeight=(x,y)=>{const u=(x+8192)/256,v=(y+8192)/256,ix=Math.floor(u),iy=Math.floor(v),a=u-ix,b=v-iy;return 128*((h[iy*65+ix]*(1-a)+h[iy*65+ix+1]*a)*(1-b)+(h[(iy+1)*65+ix]*(1-a)+h[(iy+1)*65+ix+1]*a)*b);};
const groundHeight=(x,y)=>inFlat(x,y)?height(x,y):nativeHeight(x,y);
// Use precisely the native footprint for the editable sculpted floor replacement.
let prefix=fs.readFileSync(path.join(__dirname,'build_zombie_abyss_map.cjs'),'utf8').split("water('central_sea'")[0];
prefix=prefix.replace('../output/zombie_island_v1','../output/basin_natural').replaceAll('zombie-abyss-v1-','basin-natural-');
prefix=prefix.replace("stream('normal','vector3',edges.map(e=>normals[e.face]),1)","stream('normal','vector3',edges.map(e=>paintNormal&&faces[e.face].m===0?paintNormal(verts[e.b]):normals[e.face]),1),stream('VertexPaintBlendParams','vector4',edges.map(e=>paintVertex&&faces[e.face].m===0?paintVertex(verts[e.b]):[0,0,0,0]),1),stream('VertexPaintBlendParams1','vector4',edges.map(()=>[.5,.5,.5,0]),1),stream('VertexPaintTintColor','vector4',edges.map(()=>[1,1,1,0]),1)");
const build=new Function('require','__dirname','cfg','let paintVertex=null,paintNormal=null;\n'+prefix+`
const {flat,height,paint,wet,groundHeight}=cfg,top='materials/basin_natural/ground.vmat',rock='materials/basin_natural/rock.vmat';
const verts=[],faces=[],ids=new Map(),edges=new Map();
function vertex(x,y,z){const k=x+','+y+','+z;if(!ids.has(k)){ids.set(k,verts.length);verts.push([x,y,z]);}return ids.get(k);}
function tri(v){faces.push({v,m:0});for(let i=0;i<3;i++){let a=v[i],b=v[(i+1)%3];if(edges.has(b+','+a))edges.delete(b+','+a);else edges.set(a+','+b,[a,b]);}}
for(const cell of flat){let x0=-8192+cell%64*256,y0=-8192+Math.floor(cell/64)*256;for(let y=y0;y<y0+256;y+=32)for(let x=x0;x<x0+256;x+=32){const p=[[x,y],[x+32,y],[x+32,y+32],[x,y+32]].map(([a,b])=>vertex(a,b,height(a,b)));tri([p[0],p[1],p[2]]);tri([p[0],p[2],p[3]]);}}
const count=verts.length,n=faces.length;for(let i=0;i<count;i++)verts.push([verts[i][0],verts[i][1],352]);for(let i=0;i<n;i++)faces.push({v:faces[i].v.slice().reverse().map(v=>v+count),m:1});
for(const[a,b]of edges.values())faces.push({v:[b,a,a+count,b+count],m:1});
paintVertex=v=>paint(v[0],v[1]);paintNormal=v=>{const dx=(height(v[0]+4,v[1])-height(v[0]-4,v[1]))/8,dy=(height(v[0],v[1]+4)-height(v[0],v[1]-4))/8,l=Math.hypot(dx,dy,1);return[-dx/l,-dy/l,1/l];};
mesh(verts,faces,[top,rock]);paintVertex=null;paintNormal=null;
children[0]=children[0].replace('"CMapMesh"\\n{','"CMapMesh"\\n{'+val('name','string','ART_Editable_Slate_And_Shore'));
// One submerged water plane per pool. Ground intersection shapes the visible shoreline.
for(const[cx,cy,rx,ry]of [[4310,570,445,880],[3750,1320,760,410],[2370,950,385,330]]){
 const p=Array.from({length:64},(_,i)=>{const a=i*Math.PI/32;return[cx+rx*Math.cos(a),cy+ry*Math.sin(a)];});
 prism(p,498,496,'materials/basin_natural/water.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
}
let pi=0;const prop=(model,x,y,z,angle,scale,color='235 243 248')=>entity(model.includes('props_tree')?'ent_dota_tree':'prop_static','natural_edge_'+pi++,[x,y,groundHeight(x,y)-12],{model,solid:'0',rendercolor:color,body:'1'},'0 '+angle+' 0',scale);
// Sparse asymmetric groups; the foreground and west gate stay unobstructed.
const groups=[[1900,1350,1],[2800,1870,1],[3520,1660,1],[4670,1250,1],[5000,420,1],[4450,-1480,0],[2820,-1480,0],[1660,-870,0]];
for(let i=0;i<groups.length;i++){const[x,y,pine]=groups[i];for(let j=0;j<3;j++)prop('models/props_nature/river_rocks00'+(1+(i+j)%3)+'.vmdl',x+j*76-80,y+Math.sin(i+j)*90,495,43*i+81*j,1.25+j*.38);if(pine)prop('models/props_tree/tree_pine_01_heavysnow.vmdl',x+45,y+55,500,i*53,1.6+(i%3)*.22,'231 244 236');}
for(const[x,y]of [[2210,1530],[3120,1740],[3990,1420],[4840,850]])if(wet(x,y)<-65)prop('models/props_tree/tree_pine_01.vmdl',x,y,500,x%360,1.55,'222 240 227');
for(const[x,y]of [[2100,850],[2590,1140],[4100,1240],[4400,-200],[3610,1630]])prop('models/props_nature/river_rocks002.vmdl',x,y,480,x%360,.48,'205 221 220');
entity('info_player_start_goodguys','natural_start',[3030,0,530]);entity('info_player_start','natural_editor_start',[3030,0,530]);
for(let i=0;i<4;i++)entity('info_target','player_'+i+'_builder_spawn',[3000+i*80,0,530]);
entity('env_global_light','natural_morning_light',[3000,0,2400],{color:'230 242 249 255',lightscale:'1.45',ambientcolor1:'138 177 200 255',ambientscale1:'1.25',ambientcolor2:'126 151 166 255',ambientscale2:'.75',ambientcolor3:'83 114 133 255',groundscale:'.5',specularcolor:'169 219 246 255',specularpower:'22',enableshadows:'1',StartDisabled:'0',fow_darkness:'1'},'55 315 0');
entity('env_fog_controller','natural_distance_fog',[0,0,-1000],{fogenable:'1',fogcolor:'89 154 175',fogstart:'6500',fogend:'19000',fogmaxdensity:'.75',spawnflags:'1'});
entity('env_tonemap_controller','natural_tonemap',[0,0,0],{UseCustomAutoExposureMin:'1',UseCustomAutoExposureMax:'1',AutoExposureMin:'.9',AutoExposureMax:'1.05'});
entity('ent_dota_game_events','natural_game_events',[0,0,0]);entity('water_lod_control','natural_water_lod',[0,0,0],{cheapwaterstartdistance:'30000',cheapwaterenddistance:'40000'});
entity('world_bounds','natural_bounds',[0,0,0],{min:'-1500 -4000 0',max:'6500 4000 0'});
// Low distant blue water gives depth below the existing natural cliffs.
prism([[-16000,-16000],[18000,-16000],[18000,16000],[-16000,16000]],-390,-410,'materials/basin_natural/distant.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
prism([[-16000,-16000],[18000,-16000],[18000,16000],[-16000,16000]],-850,-870,'materials/basin_natural/backdrop.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
return {nodes:children,flatTriangles:n,props:pi};`);
const result=build(require,__dirname,{flat,height,paint,wet,groundHeight});
const replaceArray=(k,t,a)=>{const actual=grid.match(new RegExp('"'+k+'" "(\\w+)_array"'))?.[1];if(!actual)throw Error('Missing grid array '+k);const re=new RegExp('"'+k+'" "'+actual+'_array"\\s*\\[[^\\]]*\\]');grid=grid.replace(re,'"'+k+'" "'+actual+'_array"\n['+a.map(v=>'"'+v+'"').join(',\n')+']');};
for(const k of ['cellConfiguration','cellConfigurationByName','objectConfiguration','objectConfigurationByName'])grid=grid.replace(new RegExp('"'+k+'" "(\\w+)_array"\\s*\\[[^\\]]*\\]'),(_,t)=>'"'+k+'" "'+t+'_array" []');
replaceArray('cellsHidden','int',hidden.map((v,i)=>flat.has(i)?1:v));
replaceArray('gridnavFlags','int',Array.from({length:65536},(_,i)=>hidden[Math.floor(i/256/4)*64+Math.floor(i%256/4)]?1:0));
for(const k of ['objectsPropType','objectsPlantType','objectsTreeType'])replaceArray(k,'int',read(k).map(()=>0));
// Repaint all remaining native tile surfaces using the same cool layered palette.
for(const k of ['blendOpacity','blendColor','blendTransitionAndPath','grassOpacity']){
 const a=read(k),t=grid.match(new RegExp('"'+k+'" "(\\w+)_array"'))[1];
 for(let i=0;i<a.length;i++){const x=-8192+i%513*32,y=-8192+Math.floor(i/513)*32;if(k==='blendOpacity')a[i]='0 0 0 128';if(k==='blendColor')a[i]='255 255 255 0';if(k==='blendTransitionAndPath')a[i]='0 255 0 0';if(k==='grassOpacity')a[i]=0;}
 replaceArray(k,t,a);
}
// Original brush-painted trees are retained. Drop isolated accidental tiles only.
grid=grid.replaceAll('maps/tilesets/radiant_basic.vmap','maps/tilesets/survival_natural_slate.vmap');
let finalNodes=[grid,...result.nodes],s=source.slice(0,w.a+1)+'\n'+finalNodes.join(',\n')+'\n'+source.slice(w.b);let nodeId=1;s=s.replace(/("nodeID"\s+"int"\s+")\d+/g,(_,p)=>p+nodeId++);
fs.writeFileSync(path.join(out,'survival_basin_natural.vmap'),s);
let tiles=fs.readFileSync(path.join(root,'output/basin_single/radiant_basic_text.vmap'),'utf8');
tiles=tiles.replace(/materials\/blends\/mod_radiant[^"\r\n]*\.vmat/g,'materials/basin_natural/ground_native.vmat');
tiles=tiles.replaceAll('materials/water/water_generic_000.vmat','materials/basin_natural/water.vmat');
tiles=tiles.replace(/("name" "string" "VertexPaintTintColor:0"[\s\S]*?"data" "vector4_array"\s*\[)([^\]]*)(\])/g,(_,a,b,c)=>a+b.replace(/"[^"]*"/g,'"1 1 1 0"')+c);
fs.writeFileSync(path.join(out,'survival_natural_slate.vmap'),tiles);
const set=(s,k,v)=>{const r=new RegExp('"'+k+'"\\s*"[^"\\n]*"');return r.test(s)?s.replace(r,'"'+k+'" "'+v+'"'):s.replace(/\n\{/,'\n{\n "'+k+'" "'+v+'"');};
let mat='"Layer0"\n{\n "shader" "multiblend.vfx"\n "F_WORLDSPACE_UVS" "1"\n "F_NORMAL_MAP" "1"\n "F_SPECULAR" "1"\n "g_flBumpStrength" ".9"\n "g_flSpecularIntensity" ".55"\n "g_flSpecularBloom" "0"\n';
for(let i=0;i<4;i++)mat+=` "TextureColor${i}" "materials/${i===3?'survival_world_v2/cliff_wall002_color.png':'basin_natural/slate_color.png'}"\n "TextureNormal${i}" "materials/${i===3?'survival_world_v2/cliff_wall001_normal.png':'basin_natural/slate_normal.png'}"\n "TextureReflectance${i}" "[${i===1?'.15 .15 .15':'.06 .06 .06'} 1]"\n "TextureRevealMask${i}" "[.5 .5 .5 0]"\n "TextureSelfIllumMask${i}" "[0 0 0 0]"\n "TextureBloom${i}" "[0 0 0 0]"\n "g_vColorTint${i}" "[${['1 1 1','.57 .76 .80','.65 .78 .71','.68 .79 .82'][i]} 0]"\n "g_flTexCoordScale${i}" "${i===3?4:1}"\n`;
mat=mat.replace(/("g_flTexCoordScale[012]"\s+")1"/g,'$1'+'8"');
mat+=' "Attributes" { "dota.nav.walkable" "1" }\n}\n';
let nativeMat=set(set(mat,'g_vColorTint1','[1 1 1 0]'),'g_vColorTint2','[1 1 1 0]');fs.writeFileSync(path.join(matdir,'ground_native.vmat'),nativeMat);
mat=set(mat,'TextureColor2','materials/survival_world_v2/sand_path009_color.png');mat=set(mat,'TextureNormal2','materials/survival_world_v2/sand_path001_normal.png');mat=set(mat,'g_flTexCoordScale2','3');mat=set(mat,'g_vColorTint2','[.60 .65 .62 0]');mat=set(mat,'TextureRevealMask2','materials/survival_world_v2/sand_cracked001_1017aede_blend.png');
fs.writeFileSync(path.join(matdir,'ground.vmat'),mat);
fs.writeFileSync(path.join(matdir,'rock.vmat'),'"Layer0" { "shader" "global_lit_simple.vfx" "F_NORMAL_MAP" "1" "TextureColor" "materials/survival_world_v2/cliff_wall002_color.png" "TextureNormal" "materials/survival_world_v2/cliff_wall001_normal.png" "g_vColorTint" "[.68 .79 .82 0]" }');
let water=fs.readFileSync(path.join(root,'output/survival_world_v2/source_materials/shallow_water.vmat'),'utf8');
for(const[k,v]of Object.entries({g_flWaterDepth:'65',g_flBumpStrength:'.8',g_flReflectionAmount:'.26',g_flReflectionPower:'2.4',g_flRefractionAmount:'.035',g_flFlowTimeScale:'.4',g_flBaseBloom:'.01',g_flNormalUvScale:'300',g_vWaterFogColor:'[.05 .40 .44 1]',g_vRefractionTint:'[.42 .82 .86 0]',g_vReflectionColor:'[.48 .69 .76 0]'}))water=set(water,k,v);
fs.copyFileSync(path.join(root,'output/basin_single/decoded/materials/water/water_river_normal_sharp_temp_normal.png'),path.join(matdir,'water_sharp_normal.png'));
for(const[k,v]of Object.entries({TextureNormal:'materials/basin_natural/water_sharp_normal.png',g_flBumpStrength:'.32',g_flReflectionPower:'7',g_flReflectionAmount:'.17',g_flNormalUvScale:'500',g_vReflectionColor:'[.20 .34 .40 0]'}))water=set(water,k,v);
fs.writeFileSync(path.join(matdir,'water.vmat'),water);fs.writeFileSync(path.join(matdir,'distant.vmat'),set(set(set(water,'g_flWaterDepth','1500'),'g_vWaterFogColor','[.025 .19 .25 1]'),'g_flBumpStrength','.13'));
fs.writeFileSync(path.join(matdir,'backdrop.vmat'),'"Layer0" { "shader" "global_lit_simple.vfx" "F_FULLBRIGHT" "1" "F_DO_NOT_CAST_SHADOWS" "1" "TextureColor" "[.14 .33 .39 1]" "Attributes" { "mapbuilder.nonsolid" "1" } }');
fs.writeFileSync(path.join(out,'design.json'),JSON.stringify({map:'survival_basin_natural',sourceMap:'survival_basin_native',sourceHash:crypto.createHash('sha256').update(source).digest('hex'),nativeFlatCells:flat.size,editableMeshTriangles:result.flatTriangles,props:result.props,originalMapUnchanged:true,center:[3328,0,512],waterLevel:498,waterMaxDepth:76,material:'independently baked periodic slate + layered dampness',notes:'Native perimeter and west staircase retained; internal floor is a Shift+V paintable Hammer mesh.'},null,2));
console.log('Natural sample written',flat.size,'native flat cells replaced with editable sculpted mesh;',result.flatTriangles,'top triangles');
