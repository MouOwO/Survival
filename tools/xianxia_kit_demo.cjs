// Isolated Source 2 review scene using the project's proven VMAP serializer.
const fs=require('fs'),path=require('path');
let src=fs.readFileSync(path.join(__dirname,'build_zombie_abyss_map.cjs'),'utf8');
let prefix=src.slice(0,src.indexOf("water('central_sea'"));
prefix=prefix.replace('../output/zombie_island_v1','../output/xianxia_kit').replace('zombie-abyss-v1-','xianxia-kit-review-');
const demo=`
const stone='materials/xianxia_kit/xx_stone.vmat',rock='materials/xianxia_kit/xx_rock.vmat';
function box(x,y,w,d,z,bottom,mat){prism([[x-w/2,y-d/2],[x+w/2,y-d/2],[x+w/2,y+d/2],[x-w/2,y+d/2]],z,bottom,mat,rock,'255 255 255 255');}
const placed=[];
function prop(name,x,y,z=256,angle=0,scale=1){entity('prop_static',name+'_'+placed.length,[x,y,z],{model:'models/xianxia_kit/'+name+'.vmdl',solid:'0',rendercolor:'255 255 255'},'0 '+angle+' 0',scale);placed.push({name,x,y,z,angle,scale});}
box(0,0,2048,1024,254,8,stone);
for(const x of [-768,-256,256,768]){prop('t01_shore_straight',x,-512);prop('t01_shore_straight',x,512,256,180);}
for(const y of [-224,224])for(const [x,angle]of [[-960,-90],[960,90]]){prop('t01_shore_straight',x,y,256,angle);children[children.length-1]=children[children.length-1].replace('"1 1 1"','"0.875 1 1"');}
prop('t04_stairs',0,-704);prop('a02_gateway',0,-450,256,0,.85);prop('a01_pavilion',-640,220,256,0,.8);
prop('v01_pine_0',800,340);prop('v02_peach_0',-870,360,256,25,.8);prop('v02_peach_1',850,-370,256,-20,.8);
for(const x of [-768,-512,512,768])prop('t06_rail_straight',x,-550);
for(const p of [[-900,-360],[870,460],[940,80]]){prop('v03_rock_1',...p);prop('v03_fern',p[0]+50,p[1]);}
prop('a03_stone_lamp',520,400,256,0,.8);prop('a03_censer',-500,220,300,0,.7);
// Individual component inspection pads, in addition to the assembled island.
const assets=JSON.parse(fs.readFileSync(path.join(OUT,'asset_manifest.json')));
for(let i=0;i<assets.length;i++){const x=-2500+(i%7)*850,y=1800+Math.floor(i/7)*1000;box(x,y,720,720,0,-80,stone);prop(assets[i].name,x,y,assets[i].category==='terrain'?250:0);}
box(0,1800,9000,7200,-210,-400,'materials/xianxia_kit/xx_waterbed.vmat');
box(0,1800,9000,7200,-120,-128,'materials/xianxia_kit/xx_water.vmat');
for(const [name,x,y,z]of [['c01_cloud_sea',-2400,-900,-180],['c02_cliff_cloud',2200,-400,-40],['c03_cloud_band',-2100,100,-80],['c04_thin_mist',2000,-1300,0]])entity('info_particle_system',name,[x,y,z],{effect_name:'particles/xianxia_kit/'+name+'.vpcf',start_active:'1'});
entity('world_bounds','kit_bounds',[0,0,0],{min:'-4608 -2048 0',max:'4608 6144 0'});
entity('info_player_start_goodguys','kit_start',[0,0,300]);entity('info_player_start','kit_editor_start',[0,0,300]);entity('info_player_start_badguys','kit_bad_start',[1800,0,0]);
entity('ent_dota_game_events','kit_events',[0,0,0]);
entity('env_global_light','kit_morning',[0,0,2000],{color:'255 245 225 255',lightscale:'1.6',ambientcolor1:'186 211 225 255',ambientscale1:'1.3',ambientcolor2:'182 192 200 255',ambientscale2:'.7',ambientcolor3:'120 135 138 255',groundscale:'.6',enableshadows:'1',StartDisabled:'0'},'55 315 0');
entity('env_tonemap_controller','kit_tonemap',[0,0,0],{UseCustomAutoExposureMin:'1',UseCustomAutoExposureMax:'1',AutoExposureMin:'.85',AutoExposureMax:'1'});
let template=fs.readFileSync(path.resolve(__dirname,'../output/zombie_island_v1/source_template.vmap'),'utf8');template=template.slice(template.indexOf('"CMapRootElement"'));
function close(s,start,op,cl){let d=0,q=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\\\')q=!q;if(!q){if(s[i]===op)d++;if(s[i]===cl&&--d===0)return i;}}throw Error('Unbalanced template');}
const wa=template.indexOf('"world" "CMapWorld"'),wb=template.indexOf('{',wa),we=close(template,wb,'{','}');let w=template.slice(wa,we+1);const cb=w.indexOf('[',w.indexOf('"children" "element_array"')),ce=close(w,cb,'[',']');
let grid=w.slice(cb+1,ce).trim();grid=grid.replace(/("cellsHidden" "bool_array"\\s*\\[)[^\\]]*/g,(a,b)=>b+a.slice(b.length).replaceAll('"0"','"1"'));
w=w.slice(0,cb+1)+grid+',\\n'+children.join(',\\n')+w.slice(ce);template=template.slice(0,wa)+w+template.slice(we+1);
fs.writeFileSync(path.join(OUT,'xianxia_kit_review.vmap'),'<!-- dmx encoding keyvalues2 4 format vmap 40 -->\\n'+template);fs.writeFileSync(path.join(OUT,'demo_placements.json'),JSON.stringify(placed,null,2));console.log('Review map:',placed.length,'model instances');
`;
new Function('require','__dirname',prefix+demo)(require,__dirname);
