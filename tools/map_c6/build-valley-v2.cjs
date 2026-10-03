// Art-only revision, built from the current map snapshot, never the old layout generator.
'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs'),Mesh=require('./mesh.cjs');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/valley_decor_v2');
const assets=path.join(root,'art/maps/c6/valley_v2/materials/survival_valley');
fs.mkdirSync(assets,{recursive:true});
const guid=()=>crypto.randomUUID();
function material(source,name,params){
 let text=fs.readFileSync(source,'utf8').replace(/\s*"Compiled Textures"\s*\{[^}]*\}/,'');
 text=text.replace(/("Texture\w+"\s*")([^"\r\n]+\.png)"/g,(_,key,file)=>{
  const basename=path.basename(file),local=path.join(path.dirname(source),basename);
  if(!fs.existsSync(local))throw Error('Missing source texture '+local);
  fs.copyFileSync(local,path.join(assets,basename));
  return key+'materials/survival_valley/'+basename+'"';
 });
 for(const [key,value] of Object.entries(params)){
  const re=new RegExp('("'+key+'"\\s*")[^"]*"');
  if(!re.test(text))throw Error('Missing material parameter '+key);
  text=text.replace(re,(_,head)=>head+value+'"');
 }
 fs.writeFileSync(path.join(assets,name+'.vmat'),text);
}
material(path.join(root,'output/reference_asset_study/art_decompiled/maps/ti10_assets/blends/mod_radiant_ti10_000.vmat'),'meadow_soft',{
 g_flSpecularIntensity:'.15',g_flBumpStrength:'.38',g_flTexCoordScale1:'4',g_flTexCoordScale2:'4',
 g_vColorTint0:'[.42 .55 .32 1]',g_vColorTintB0:'[.40 .48 .33 0]',
 g_vColorTint1:'[.40 .54 .34 1]',g_vColorTintB1:'[.34 .48 .31 0]',
 g_vColorTint2:'[.47 .61 .40 1]',g_vColorTintB2:'[.43 .57 .36 1]',
 g_vColorTint3:'[.59 .62 .61 1]',g_vColorTintB3:'[.65 .65 .60 1]'
});
for(const [name,tint,w,h] of [['flowers_red','[.86 .22 .18 1]',30,20],['flowers_ivory','[.9 .85 .66 1]',26,18],['flowers_mauve','[.62 .42 .70 1]',28,20]])
 material(path.join(out,'decompiled/flowers.vmat'),name,{g_vColorTint:tint,g_vColorTint2:'[.37 .51 .29 0]',g_flGrassWidth:w,g_flGrassHeightMin:h-5,g_flGrassHeightMax:h,g_flSpecularIntensity:'.1'});
material(path.join(out,'decompiled/aegis.vmat'),'stone_aegis',{g_vColorTint2:'[.78 .83 .82 0]',g_flSpecularIntensity:'.35',g_flSpecularBloom:'0'});
// Editable flower cards supplement engine grass where its generated coverage is sparse.
let groundFlowers=fs.readFileSync(path.join(assets,'flowers_red.vmat'),'utf8')
 .replace('grasstile_preview.vfx','global_lit_simple.vfx').replace(/\s*"g_flGrass\w+"\s*"[^"]*"/g,'')
 .replace('"F_SPECULAR"\t"1"','"F_SPECULAR"\t"0"')
 .replace('{','{\n "F_TRANSLUCENT" "1"\n "F_ALPHA_TEST" "1"\n "g_flAlphaTestReference" ".3"');
fs.writeFileSync(path.join(assets,'flowers_ground_red.vmat'),groundFlowers);
let tiles=fs.readFileSync(path.join(out,'tileset_before.vmap'),'utf8');
tiles=tiles.replaceAll('maps/ti10_assets/blends/mod_radiant_ti10_000.vmat','materials/survival_valley/meadow_soft.vmat');
for(let i=0;i<3;i++)tiles=tiles.replaceAll('maps/ti10_assets/cards/card_flowers_ti10_00'+(i+1)+'.vmat','materials/survival_valley/'+['flowers_red','flowers_ivory','flowers_mauve'][i]+'.vmat');
for(const [slotIndex,slot] of L.blocks(tiles,'CGrassMaterialSlot').entries()){
 if(slotIndex>2)continue;
 let replacement=slot.text;
 for(const layer of L.blocks(slot.text,'CPerLayerGrassData')){
  const enabled=['layerData1','layerData2'].includes(L.value(layer.text,'name'));
  let next=L.setValue(layer.text,'enabled',enabled?'1':'0');
  next=L.setValue(next,'weight',[.18,.045,.035][slotIndex]);
  next=L.setValue(next,'blendMin','.18');next=L.setValue(next,'blendMax','1');
  replacement=replacement.replace(layer.text,next);
 }
 tiles=tiles.replace(slot.text,replacement);
}
fs.writeFileSync(path.join(out,'survival_valley_ti10.vmap'),tiles);
const before=fs.readFileSync(path.join(out,'before.vmap'),'utf8');
let node=Math.max(...[...before.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
const additions=[],manifest=[],groups={};
function add(group,text){additions.push(text);(groups[group]??=[]).push(text);}
function entity(group,name,origin,model,scale=1,yaw=0,color='255 255 255',extra={}){
 const cls=model?'prop_static':'info_particle_system';
 const props={classname:cls,targetname:name,...(model?{model,solid:'0',rendercolor:color,skin:'0',grass_exclusion_radius:'0',disablemerging:'0'}:{}),...extra};
 const text=`"CMapEntity" { "id" "elementid" "${guid()}" "nodeID" "int" "${node++}" "children" "element_array" [] "entity_properties" "EditGameClassProps" { "id" "elementid" "${guid()}" ${Object.entries(props).map(([k,v])=>`"${k}" "string" "${v}"`).join(' ')} } "origin" "vector3" "${origin.join(' ')}" "angles" "qangle" "0 ${yaw} 0" "scales" "vector3" "${scale} ${scale} ${scale}" "force_hidden" "bool" "0" "editorOnly" "bool" "0" }`;
 add(group,text);manifest.push({group,name,origin,model,scale,yaw,...extra});
}
const rot=(x,y,k)=>[[x,y],[y,-x],[-x,-y],[-y,x]][k];
const world=(x,y,k,z=384)=>{let p=rot(x,y,k);return[p[0]-1024,p[1]+4096,z];};
let seed=1978;const rnd=()=>((seed=(Math.imul(seed,1664525)+1013904223)>>>0)/4294967296);
// Wall pockets rather than isolated, repeating tropical fern clumps.
for(let k=0;k<4;k++){
 const pockets=[[645,1230],[690,2040],[1320,2330],[2090,1680],[1680,600],[1120,610]];
 for(let j=0;j<pockets.length;j++){
  const [x,y]=pockets[j],group='valley_v2_border_'+k+'_'+j;
  entity(group,group+'_shrub',world(x,y,k),'models/props_nature/bush_spring_01.vmdl',.36+rnd()*.12,rnd()*360,'175 208 169');
  for(let m=0;m<2;m++)entity(group,group+'_flowers_'+m,world(x+20+rnd()*45,y-55+rnd()*90,k), 'maps/ti10_assets/flowers/flowers_ti10_01.vmdl',.16+rnd()*.08,rnd()*360,'218 170 179');
 }
 // Deliberately uneven, low broken paving; no new blocking geometry.
 for(let j=0;j<4;j++){
  let x=700+rnd()*130,y=1050+rnd()*1100;
  entity('valley_v2_stones_'+k,`valley_v2_buried_slab_${k}_${j}`,world(x,y,k,381),`models/props_stone/colosseum_wall/colosseum_slab0${1+j%3}.vmdl`,.5+rnd()*.3,rnd()*360,'192 207 201');
 }
 const quads=[];
 for(let j=0;j<170;j++){
  let x=780+rnd()*1460,y=770+rnd()*1500;
  if(Math.hypot(x,y)>2660||Math.hypot(x-1550,y-1170)<310){j--;continue;}
  // Keep the existing paved southwest court clear.
  if(k===2&&x>950&&y>950)continue;
  const a=rnd()*Math.PI*2,w=18+rnd()*16,h=w*.55;
  quads.push([[-w/2,-h/2,385],[w/2,-h/2,385],[w/2,h/2,391],[-w/2,h/2,391]].map(([u,v,z])=>world(x+u*Math.cos(a)-v*Math.sin(a),y+u*Math.sin(a)+v*Math.cos(a),k,z)));
 }
 let flowers=Mesh.mesh(quads,'materials/survival_valley/flowers_ground_red.vmat',node++);
 flowers=L.setValue(flowers,'physicsType','none');flowers=L.setValue(flowers,'disableShadows','1');
 const uv=quads.flatMap(()=>['0 0','0 1','1 1','1 0','1 0','1 1','0 1','0 0']);
 for(const st of L.blocks(flowers,'CDmePolygonMeshDataStream'))if(L.value(st.text,'semanticName')==='texcoord')flowers=flowers.replace(st.text,L.setArray(st.text,'data',uv));
 add('valley_v2_red_flower_scatter_'+k,flowers);
 const group='valley_v2_spawn_'+(k+1),p=world(1112,0,k,128);
 entity(group,group+'_stone_arch',p,'models/architecture/crypt/crypt_door_01_frame.vmdl',.58,90-k*90,'214 225 219');
 for(const sign of [-1,1]){
  entity(group,group+'_candles_'+sign,world(1160,sign*176,k,132),'models/props_debris/candles001.vmdl',.82,k*90);
  entity(group,group+'_base_'+sign,world(1112,sign*165,k,122),'models/props_stone/colosseum_wall/colosseum_slab01.vmdl',1.4,k*90,'211 218 215');
  entity(group,group+'_flowers_'+sign,world(1185,sign*202,k,129),'maps/ti10_assets/flowers/flowers_ti10_01.vmdl',.20,k*90);
 }
 entity(group,'valley_decor_v1_fx_monsterborn_player'+(k+1),[...p.slice(0,2),132],null,1,0,'255 255 255',{effect_name:'particles/survival_environment/valley_spawn.vpcf',start_active:'1'});
}
// The reference's carved ground motif is an overlay, not a model-browser prop.
const donor=fs.readFileSync(path.join(out,'aegis_overlay.txt'),'utf8');
for(let k=0;k<4;k++){
 let text=donor.replace(/"elementid" "[^"]+"/g,()=>`"elementid" "${guid()}"`).replace(/"referenceID" "uint64" "[^"]*"/g,'"referenceID" "uint64" "0x0"');
 text=L.setValue(text,'nodeID',node++);text=L.setValue(text,'origin',world(1550,1170,k,384).join(' '));text=L.setValue(text,'angles',`0 ${12-k*90} 0`);
 text=L.setValue(text,'tintColor','218 225 220 255');text=L.setValue(text,'projectionFar','16');
 text=text.replaceAll('maps/ti10_assets/overlays/aegis_ti10_radiant_01.vmat','materials/survival_valley/stone_aegis.vmat');
 for(const stream of L.blocks(text,'CDmePolygonMeshDataStream'))if(L.value(stream.text,'semanticName')==='position'){
  let positions=L.array(stream.text,'data').map(s=>s.split(' ').map(Number));
  const cx=positions.reduce((s,p)=>s+p[0],0)/4,cy=positions.reduce((s,p)=>s+p[1],0)/4;
  text=text.replace(stream.text,L.setArray(stream.text,'data',positions.map(p=>`${(p[0]-cx)*.42} ${(p[1]-cy)*.42} 3`)));
 }
 add('valley_v2_ground_emblem_'+k,text);
}
const g=L.blocks(before,'CDmeDotaTileGrid')[0];let grid=g.text;
const opacity=L.array(grid,'blendOpacity'),color=L.array(grid,'blendColor'),grass=L.array(grid,'grassOpacity');
const clamp=(v,a=0,b=1)=>Math.max(a,Math.min(b,v));let painted=0;
for(let j=0;j<1025;j++)for(let i=0;i<1025;i++){
 const x=i*32-16384+1024,y=j*32-16384-4096,r=Math.hypot(x,y);
 if(r<840||r>2740)continue;
 const idx=j*1025+i,old=opacity[idx].split(' ').map(Number);if(old[1]<190||old[2]>30)continue;
 const n=clamp(.5+.23*Math.sin(x*.004+y*.002)+.17*Math.sin(y*.007-x*.003)+.1*Math.sin(x*.017+y*.009));
 const minor=Math.min(Math.abs(x),Math.abs(y)),major=Math.max(Math.abs(x),Math.abs(y));
 const lane=minor<160?clamp(1-minor/160):0;
 // Soft irregular islands of exposed stone, not uniformly scattered rock props.
 const stone=clamp((Math.sin(x*.009+Math.sin(y*.003)*2)*Math.cos(y*.011-x*.003)-.35)*1.7);
 const border=clamp(1-Math.abs(minor-630)/170);
 opacity[idx]=`${Math.round(22+n*32)} ${Math.round(215+n*35-lane*75)} ${Math.round(clamp(stone*1.35)*250+lane*5)} ${old[3]}`;
 color[idx]=`250 253 247 12`;
 grass[idx]=String(Math.round((105+n*110+border*25)*(1-lane*.94)*(1-stone*.6)));
 painted++;
}
grid=L.setArray(grid,'blendOpacity',opacity);grid=L.setArray(grid,'blendColor',color);grid=L.setArray(grid,'grassOpacity',grass);
let result=before.slice(0,g.start)+grid+before.slice(g.end);
result=result.replaceAll('maps/tilesets/survival_radiant_ti10_basic.vmap','maps/tilesets/survival_valley_ti10.vmap');
const worldStart=result.indexOf('"CMapWorld"'),start=result.indexOf('[',result.indexOf('"children" "element_array"',worldStart)),end=L.endOf(result,start,'[',']')-1;
function group(name,children){return `"CMapGroup" { "id" "elementid" "${guid()}" "nodeID" "int" "${node++}" "name" "string" "${name}" "children" "element_array" [${children.join(',\n')}] "origin" "vector3" "0 0 0" "angles" "qangle" "0 0 0" "scales" "vector3" "1 1 1" }`;}
const grouped=Object.entries(groups).map(([name,children])=>group(name,children));
result=result.slice(0,end)+',\n'+grouped.join(',\n')+'\n'+result.slice(end);
for(const type of ['CMapEntity','CMapMesh']){
 const after=new Map(L.blocks(result,type).map(e=>[L.value(e.text,'nodeID'),e.text]));
 for(const e of L.blocks(before,type))if(after.get(L.value(e.text,'nodeID'))!==e.text)throw Error('Existing '+type+' changed.');
}
for(const key of ['verticesHeight','verticesWater','gridnavFlags','cellConfiguration','objectsTreeType'])if(JSON.stringify(L.array(g.text,key))!==JSON.stringify(L.array(grid,key)))throw Error('Gameplay array changed '+key);
fs.writeFileSync(path.join(out,'valley_decor_review.vmap'),result);
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({revision:2,painted_samples:painted,existing_geometry_and_markers_preserved:true,navigation_and_height_preserved:true,props:manifest.length,overlays:4,groups:Object.keys(groups),additions:manifest},null,2));
// Standalone editable art palette; all group names match the review map's search names.
const palette=`<!-- dmx encoding keyvalues2 1 format vmap 29 -->\n"CMapRootElement" { "id" "elementid" "${guid()}" "mapVersion" "int" "1" "world" "CMapWorld" { "id" "elementid" "${guid()}" "nodeID" "int" "1" "children" "element_array" [${grouped.filter((_,i)=>i<1||['valley_v2_spawn_1','valley_v2_ground_emblem_0','valley_v2_red_flower_scatter_0','valley_v2_stones_0'].includes(Object.keys(groups)[i])).join(',\n')}] "entity_properties" "EditGameClassProps" { "id" "elementid" "${guid()}" "classname" "string" "worldspawn" } } }`;
fs.writeFileSync(path.join(out,'valley_detail_palette.vmap'),palette);
console.log(JSON.stringify({painted,props:manifest.length,overlays:4,groups:grouped.length,assets:fs.readdirSync(assets).length}));
