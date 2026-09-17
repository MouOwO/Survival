// Standalone main-island art map + editable prefab. Main gameplay map is untouched.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/main_island');
const layout=JSON.parse(fs.readFileSync(path.join(out,'island_layout.json'))),assets=JSON.parse(fs.readFileSync(path.join(out,'asset_manifest.json')));
const src=fs.readFileSync(path.join(__dirname,'build_zombie_abyss_map.cjs'),'utf8');
const prefix=src.slice(0,src.indexOf("water('central_sea'")).replace('../output/zombie_island_v1','../output/main_island').replace('zombie-abyss-v1-','main-island-review-');
const {children,entity,prism}=new Function('require','__dirname',prefix+'\nreturn {children,entity,prism};')(require,__dirname);
const matdir=path.join(out,'source/materials/main_island');
const support='materials/main_island/floor_support.vmat';
// Invisible collision/nav backing avoids depth fighting with pavers at the
// much higher overview camera used for a 10,000-unit island.
fs.writeFileSync(path.join(matdir,'floor_support.vmat'),fs.readFileSync(path.join(matdir,'mortar.vmat'),'utf8').replace(/}\s*$/,'"Attributes" { "dota.nav.walkable" "1" "mapbuilder.nodraw" "1" }\n}\n'));
// Use the established ocean shader, with our generated blue surface and normal maps.
let water=fs.readFileSync(path.join(root,'output/survival_world_v2/source_materials/ocean_water.vmat'),'utf8');
water=water.replaceAll('materials/survival_world_v2/water_river_oil_normal.png','materials/main_island/water_normal.png').replaceAll('materials/survival_world_v2/water_ocean_00_refl.png','materials/main_island/water_reflectance.png');
water=water.replace(/("TextureColor[0-3]"\s*)"[^"]+"/g,'$1"materials/main_island/water_color.png"');
water=water.replace(/("g_flTexCoordScale[0-3]"\s*)"[^"]+"/g,'$1"1.0"').replace('"g_flBumpStrength" ".18"','"g_flBumpStrength" ".28"');
fs.writeFileSync(path.join(matdir,'ocean_surface.vmat'),water);
function area(p){return p.reduce((s,a,i)=>{const b=p[(i+1)%p.length];return s+a[0]*b[1]-a[1]*b[0]},0);}
const ccw=p=>area(p)<0?p.slice().reverse():p;
for(const s of layout.supports)prism(ccw(s.polygon),s.top,s.bottom,support,'materials/main_island/mortar.vmat','255 255 255 255');
// The existing island uses a shallow traversable center for attack approaches.
// Keep this bed separate from the non-solid visual water surface.
const lake=[];
for(let q=0;q<4;q++)for(const [x,y]of [[-640,640],[-448,1792],[-320,2304],[320,2304],[448,1792],[640,640]]){
 const a=-q*Math.PI/2;const p=[Math.round(x*Math.cos(a)-y*Math.sin(a)),Math.round(x*Math.sin(a)+y*Math.cos(a))];
 if(!lake.length||lake.at(-1).some((v,i)=>v!==p[i]))lake.push(p);
}
if(lake[0].every((v,i)=>v===lake.at(-1)[i]))lake.pop();
prism(ccw(lake),396,300,support,'materials/main_island/rock_wet.vmat','255 255 255 255');
for(let i=0;i<layout.placements.length;i++){
 const p=layout.placements[i],a=assets.find(a=>a.name===p.name);
 entity('prop_static',`main_island_${String(i).padStart(4,'0')}_${path.basename(p.name,'.vmdl')}`,p.origin,
  {model:p.native?p.name:'models/main_island/'+p.name+'.vmdl',solid:a?.collision_hulls?'6':'0',rendercolor:'255 255 255',disableshadows:p.group==='06 Water'?'1':'0'},`0 ${p.yaw} 0`,1);
 children[children.length-1]=children.at(-1).replace('"scales" "vector3" "1 1 1"',`"scales" "vector3" "${p.scale.join(' ')}"`);
}
for(const m of layout.markers)entity('info_target',m.name,m.origin);
// The ocean is part of this independent prefab, placed in its own world mesh.
prism([[-8192,-8192],[8192,-8192],[8192,8192],[-8192,8192]],400,399,'materials/main_island/ocean_surface.vmat','materials/main_island/ocean_surface.vmat','255 255 255 255');
const prefab=children.slice();
entity('world_bounds','main_island_review_bounds',[0,0,0],{min:'-6144 -6144 0',max:'6144 6144 0'});
entity('info_player_start_goodguys','island_review_start',[0,3456,664]);
entity('info_player_start','island_editor_start',[0,3456,664]);
entity('info_player_start_badguys','island_enemy_start',[0,0,420]);
entity('ent_dota_game_events','island_events',[0,0,0]);
entity('env_global_light','island_sun',[0,0,6000],{color:'255 245 224 255',lightscale:'1.9',ambientcolor1:'187 207 220 255',ambientscale1:'1.0',ambientcolor2:'175 191 189 255',ambientscale2:'.7',ambientcolor3:'117 139 135 255',groundscale:'.6',enableshadows:'1',StartDisabled:'0'},'55 315 0');
entity('env_tonemap_controller','island_exposure',[0,0,0],{UseCustomAutoExposureMin:'1',UseCustomAutoExposureMax:'1',AutoExposureMin:'.85',AutoExposureMax:'1.0'});
entity('water_lod_control','island_water_lod',[0,0,0],{cheapwaterstartdistance:'30000',cheapwaterenddistance:'40000'});
let template=fs.readFileSync(path.join(root,'output/zombie_island_v1/source_template.vmap'),'utf8');template=template.slice(template.indexOf('"CMapRootElement"'));
function close(s,start,op,cl){let d=0,q=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')q=!q;if(!q){if(s[i]===op)d++;if(s[i]===cl&&--d===0)return i;}}throw Error('Unbalanced VMAP');}
const wa=template.indexOf('"world" "CMapWorld"'),wb=template.indexOf('{',wa),we=close(template,wb,'{','}'),world=template.slice(wa,we+1),cb=world.indexOf('[',world.indexOf('"children" "element_array"')),ce=close(world,cb,'[',']');
let grid=world.slice(cb+1,ce).trim();
function inside(x,y,p){let c=false;for(let i=0,j=p.length-1;i<p.length;j=i++){let a=p[i],b=p[j];if((a[1]>y)!=(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])c=!c;}return c;}
const walkable=(x,y)=>inside(x,y,lake)||layout.supports.some(s=>inside(x,y,s.polygon));let openCells=0;
grid=grid.replace(/^(\t{6})"([^"]+)" "(\w+)_array"\s*\[([^\]]*)\]/gm,(all,indent,k,type,body)=>{
 if(type==='element')return all;const old=[...body.matchAll(/"([^"]*)"/g)].map(m=>m[1]);
 if(/^(cell|object)Configuration/.test(k))return `${indent}"${k}" "${type}_array" []`;
 let fill=old[0]||'0';if(k==='cellsHidden')fill='1';
 else if(k==='verticesHeight'||k==='verticesWater'||k==='edgesPath'||k==='edgesDestruction'||k.startsWith('objects'))fill=k==='objectsVariationId'?'255':'0';
 else if(k==='blendOpacity')fill='0 255 0 128';else if(k==='blendColor')fill='255 255 255 0';else if(k==='grassOpacity'||k==='fogOpacity')fill='0';else if(k==='flowMap'||k==='fogFlowMap')fill='128 128 0 0';
 const values=Array(old.length).fill(fill);
 if(k==='gridnavFlags')for(let y=0;y<256;y++)for(let x=0;x<256;x++){let can=walkable(-8192+x*64+32,-8192+y*64+32);values[y*256+x]=can?'0':'1';if(can)openCells++;}
 return `${indent}"${k}" "${type}_array" [${values.map(v=>'"'+v+'"').join(',')} ]`;
});
fs.mkdirSync(path.join(out,'source/maps/prefabs'),{recursive:true});
function save(name,items){let w=world.slice(0,cb+1)+items.join(',\n')+world.slice(ce);fs.writeFileSync(path.join(out,'source/maps',name+'.vmap'),'<!-- dmx encoding keyvalues2 4 format vmap 40 -->\n'+template.slice(0,wa)+w+template.slice(we+1));}
save('main_island_review',[grid,...children]);save('prefabs/main_island',prefab);
fs.writeFileSync(path.join(out,'map_manifest.json'),JSON.stringify({map:'main_island_review',instances:layout.placements.length,models:assets.length,walkableCells:openCells,centralBed:lake,sourceCenter:[0,0],mainMapModified:false},null,2));
console.log('MAIN_ISLAND_MAP',layout.placements.length,'instances',openCells,'walkable grid cells');
