// Four dry elevated courts, one wet spawn basin, exactly four bidirectional routes.
const R=1152,D=2880,Z=640,br=1280,stairsStart=1024,stairsEnd=2048,half=256;
const themes=['peach','snow','pine','sand'],placed=[],audit=[];
const smooth=x=>{x=Math.max(0,Math.min(1,x));return x*x*(3-2*x);};
const noise=(x,y)=>.5+.24*Math.sin(x*.003+y*.0015)+.16*Math.cos(y*.004-x*.002)+.07*Math.sin(x*.011+y*.009);
const rotate=(u,v,q)=>{const a=q*Math.PI/2;return[u*Math.cos(a)-v*Math.sin(a),u*Math.sin(a)+v*Math.cos(a)];};
const local=(x,y,q)=>rotate(x,y,-q);
const mat=(t,s='')=>'materials/basin_review/'+t+s+'.vmat';
const stone=mat('peach','_stone'),rock=mat('pine','_rock');
function prop(model,x,y,z=Z,angle=0,scale=1,color='255 255 255'){
 entity('prop_static','basin_'+model+'_'+placed.length,[x,y,z],{model:'models/xianxia_kit/'+model+'.vmdl',solid:'0',rendercolor:color},'0 '+angle+' 0',scale);placed.push({model,x,y,z,scale});
}
function native(model,x,y,z,angle=0,scale=1,color='255 255 255',skin='0',tree=false){entity(tree?'ent_dota_tree':'prop_static','basin_native_'+placed.length,[x,y,z],{model,solid:'0',rendercolor:color,skin,body:'1'},'0 '+angle+' 0',scale);placed.push({model,x,y,z,scale});}
function box(x,y,w,d,z,bottom,top,side=rock,q=0){prism([[-w/2,-d/2],[w/2,-d/2],[w/2,d/2],[-w/2,d/2]].map(p=>{const t=rotate(...p,q);return[x+t[0],y+t[1]];}),z,bottom,top,side,'255 255 255 255');}
function patch(name,bounds,field,height,paint,top,side,bottom){
 const verts=[],faces=[],ids=new Map(),edges=new Map(),step=64;
 const vertex=p=>{const key=p.map(v=>Math.round(v*1000)/1000).join(',');if(!ids.has(key)){ids.set(key,verts.length);verts.push(p);}return ids.get(key);};
 function tri(v){const a=verts[v[0]],b=verts[v[1]],c=verts[v[2]];if(Math.abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]))<.001)return;faces.push({v,m:0});for(let i=0;i<3;i++){const a=v[i],b=v[(i+1)%3],rev=b+','+a;if(edges.has(rev))edges.delete(rev);else edges.set(a+','+b,[a,b]);}}
 function clip(t){let p=[];for(let i=0;i<3;i++){const a=t[i],b=t[(i+1)%3];if(a.d>=0)p.push(a);if((a.d>=0)!==(b.d>=0)){const w=a.d/(a.d-b.d);p.push({x:a.x+(b.x-a.x)*w,y:a.y+(b.y-a.y)*w});}}const v=p.map(a=>vertex([a.x,a.y,height(a.x,a.y)]));for(let i=1;i+1<v.length;i++)if(new Set([v[0],v[i],v[i+1]]).size===3)tri([v[0],v[i],v[i+1]]);}
 const sample=(x,y)=>({x,y,d:field(x,y)});
 for(let y=bounds[1];y<bounds[3];y+=step)for(let x=bounds[0];x<bounds[2];x+=step){const a=sample(x,y),b=sample(x+step,y),c=sample(x+step,y+step),d=sample(x,y+step);clip([a,b,c]);clip([a,c,d]);}
 const count=verts.length,n=faces.length,cx=(bounds[0]+bounds[2])/2,cy=(bounds[1]+bounds[3])/2,isCourt=name.startsWith('court_');
 for(let i=0;i<count;i++){const p=verts[i];verts.push([cx+(p[0]-cx)*(isCourt?.88:1),cy+(p[1]-cy)*(isCourt?.88:1),bottom]);}
 for(let i=0;i<n;i++)faces.push({v:faces[i].v.slice().reverse().map(v=>v+count),m:1});
 const mid=new Map();
 function middle(i){if(!mid.has(i)){const p=verts[i],s=1.018+.02*noise(p[0],p[1]);mid.set(i,verts.length);verts.push([cx+(p[0]-cx)*s,cy+(p[1]-cy)*s,p[2]-90-28*Math.sin(p[0]*.02+p[1]*.015)]);}return mid.get(i);}
 for(const[a,b]of edges.values())if(isCourt){const ma=middle(a),mb=middle(b);faces.push({v:[b,a,ma,mb],m:1},{v:[mb,ma,a+count,b+count],m:1});}else faces.push({v:[b,a,a+count,b+count],m:1});
 paintNormal=v=>{const dx=(height(v[0]+8,v[1])-height(v[0]-8,v[1]))/16,dy=(height(v[0],v[1]+8)-height(v[0],v[1]-8))/16,l=Math.hypot(dx,dy,1);return[-dx/l,-dy/l,1/l];};
 floorUV=name==='court_snow'&&fs.existsSync(path.join(OUT,'snow_material/bake_report.json'))?v=>[(v[0]+1280)/2560,-(v[1]-1600)/2560]:null;
 paintVertex=paint;mesh(verts,faces,[top,side],'255 255 255 255');
 children[children.length-1]=children[children.length-1].replace('"CMapMesh"\n{','"CMapMesh"\n{'+val('name','string','AI_Floor_'+name));
 paintVertex=null;paintNormal=null;floorUV=null;audit.push({name,closed:true,topFaces:n});
}
function basinHeight(x,y){const r=Math.hypot(x,y),a=Math.atan2(y,x),rim=smooth((r-960)/300),opening=1-smooth((Math.min(Math.abs(x),Math.abs(y))-270)/220);return 64+64*smooth((r-440)/240)+rim*(1-opening)*(160+30*Math.sin(a*5));}
patch('basin',[-1344,-1344,1344,1344],(x,y)=>br+30*Math.sin(Math.atan2(y,x)*8)-Math.hypot(x,y),basinHeight,v=>{const[x,y]=v,r=Math.hypot(x,y),n=noise(x,y);return[.76*smooth((r-650)/440),.2+.27*n,.5*Math.exp(-Math.pow((r-690)/210,2)),0];},mat('pine'),rock,-128);
// Water boundary follows the shallow bed: 16 units deep at the center.
const puddle=Array.from({length:80},(_,i)=>{const a=i/80*Math.PI*2,r=490+9*Math.sin(a*5);return[r*Math.cos(a),r*Math.sin(a)];});
prism(puddle,80,78,'materials/survival_world_v2/shallow_water.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
for(let q=0;q<4;q++){
 const theme=themes[q],c=rotate(D,0,q),bb=[Math.floor((c[0]-R)/64)*64,Math.floor((c[1]-R)/64)*64,Math.ceil((c[0]+R)/64)*64,Math.ceil((c[1]+R)/64)*64];
 // Boolean notch extends into the disc; the top cannot cover the staircase.
 patch('court_'+theme,bb,(x,y)=>{const[u,v]=local(x,y,q),circle=R-Math.hypot(u-D,v),notch=Math.max(u-stairsEnd,Math.abs(v)-half);return Math.min(circle,notch);},()=>Z,v=>{
  const[u,w]=local(v[0],v[1],q),x=u-D,y=w,r=Math.hypot(x,y),n=noise(x+q*330,y-q*270),a=Math.atan2(y,x);
  const wornRing=Math.exp(-Math.pow((r-610-65*Math.sin(a*3))/120,2));
  const approach=Math.exp(-Math.pow(y/210,2))*smooth((-x+200)/800);
  const green={peach:.65,snow:.97,pine:.99,sand:.80}[theme]*(.70+.30*n)*(1-.46*approach);
  const bare=.05+.17*smooth((n-.48)*2.5);
  const paving=Math.max(0,Math.min(.90,(theme==='peach'?.55:0)+.25*wornRing+.48*approach-.18*n));
  if(theme==='snow'&&fs.existsSync(path.join(OUT,'snow_material/bake_report.json'))){const edge=smooth((r-740)/360),drift=smooth((Math.sin(a*3+.6)+.4*Math.sin(a*7)-.1)*.7),entrance=1-.75*approach;return[(.08+.66*edge+.28*drift)*entrance,0,0,0];}
  return[green,bare,paving,0];
 },theme==='snow'&&fs.existsSync(path.join(OUT,'snow_material/bake_report.json'))?mat('snow_authored'):mat(theme),mat(theme,'_rock'),Z-320);
 // 32 visible steps, a single 512-unit wide route, symmetric in all directions.
 for(let i=0;i<32;i++){const u=stairsStart+i*32+16,p=rotate(u,0,q);box(...p,32,512,128+(i+1)*16,-128,mat(theme,'_stone'),mat(theme,'_rock'),q);}
 // Stair cheeks are below the tread edge and cannot hide step risers.
 for(const sign of[-1,1])for(let i=0;i<16;i++){const p=rotate(stairsStart+i*64+32,sign*288,q);box(...p,64,56,128+(i+1)*32+30,-128,mat(theme,'_stone'),mat(theme,'_rock'),q);}
 // Low curved masonry perimeter, broken only at the inward-facing entrance.
 function arc(r0,r1,a0,a1,z,bottom,m){const p=[],n=Math.max(4,Math.ceil((a1-a0)*18));for(let i=0;i<=n;i++){const a=a0+(a1-a0)*i/n;p.push(rotate(D+r1*Math.cos(a),r1*Math.sin(a),q));}for(let i=n;i>=0;i--){const a=a0+(a1-a0)*i/n;p.push(rotate(D+r0*Math.cos(a),r0*Math.sin(a),q));}prism(p,z,bottom,m,mat(theme,'_rock'),'255 255 255 255');}
 const gap=.265,segments=42,start=-Math.PI+gap,end=Math.PI-gap,delta=(end-start)/segments;
 for(let i=0;i<segments;i++){
  const a=start+i*delta,b=a+delta-.002;
  arc(1058,1144,a,b,Z+64,Z-8,mat(theme,'_stone'));
  arc(1050,1152,a-.001,b+.001,Z+86,Z+64,mat(theme,'_stone'));
 }
 // Sparse flush circular inlay, not a raised obstacle or a full paving overlay.
 if(theme!=='snow')for(let j=0;j<3;j++){const a=j*Math.PI*2/3+.09,b=a+Math.PI*2/3-.18;arc(424,436,a,b,Z+.6,Z-.5,mat(theme,'_stone'));arc(477,483,a,b,Z+.6,Z-.5,mat(theme,'_stone'));}
 // Clear opening flanked by two built stone terminals; wall slot remains empty.
 for(const sign of[-1,1]){const p=rotate(2110,sign*320,q);prop('t06_rail_post',...p,Z,q*90,.95);}
 // Theme details are concentrated in five asymmetrical edge groups.
 const clusters=[[-2.15,895],[-.98,912],[.12,900],[1.02,895],[2.03,900]];
 for(let k=0;k<clusters.length;k++){
  const[a,r]=clusters[k],u=D+r*Math.cos(a),v=r*Math.sin(a),p=rotate(u,v,q);
  native('models/props_nature/river_rocks00'+(k%3+1)+'.vmdl',...p,Z-10,k*67,1.1+(k%2)*.3,theme==='sand'?'222 204 175':theme==='snow'?'224 234 240':'220 233 225');
  const p2=rotate(u+65*Math.cos(a+.8),v+65*Math.sin(a+.8),q);
  if(theme==='peach')native('models/props_tree/tree_oak_01.vmdl',...p2,Z,k*51,1.60+(k%2)*.25,'255 255 255','6',true);
  else if(theme==='snow')native('models/props_tree/tree_pine_01_heavysnow.vmdl',...p2,Z,k*51,1.25+(k%2)*.1,'255 255 255','0',true);
  else if(theme==='pine')native('maps/journey_assets/props/trees/journey_armandpine/journey_armandpine_01.vmdl',...p2,Z,k*51,1.65+(k%2)*.15,'241 248 236','0',true);
  if(theme==='sand')for(let j=0;j<3;j++){const p3=rotate(u-50+j*35,v+80,q);prop('v03_grass',...p3,Z,j*81,.9,'211 178 108');}
  else for(let j=0;j<2;j++){const p3=rotate(u-55+j*70,v-60,q);native(theme==='snow'?'models/props_nature/chipped_rocks002.vmdl':'models/props_nature/fern002.vmdl',...p3,Z,j*81,.7,theme==='snow'?'228 238 241':'236 240 222');}
 }
 // The continuous foundation mesh supplies the rock shoulder; no embedded pebble row.
 entity('info_target','build_court_'+theme,[...c,Z]);
 const gate=rotate(2112,0,q);entity('info_target','wall_slot_'+theme,[...gate,Z]);
}
// Basin rim rock groups leave all four exits and the interior unobstructed.
for(let i=0;i<12;i++){const a=(i+.5)/12*Math.PI*2,x=1160*Math.cos(a),y=1160*Math.sin(a);if(Math.min(Math.abs(x),Math.abs(y))<380)continue;native('models/props_nature/river_rocks00'+(i%3+1)+'.vmdl',x,y,basinHeight(x,y)-12,i*43,1.4);}
// A distant colored backdrop avoids exposing black void; no ocean is added.
box(0,0,24000,24000,-640,-680,'materials/survival_world_v2/cloud_horizon.vmat','materials/tools/toolsnodraw.vmat');
const walkable=(x,y)=>{
 if(Math.hypot(x,y)<1010)return true;
 for(let q=0;q<4;q++){const[u,v]=local(x,y,q);if(u>=900&&u<=2176&&Math.abs(v)<208)return true;if(Math.hypot(u-D,v)<1008&&(u>=2048||Math.abs(v)>320))return true;}
 return false;
};
entity('world_bounds','basin_bounds',[0,0,0],{min:'-4608 -4608 0',max:'4608 4608 0'});
for(const cls of['info_player_start_goodguys','info_player_start','info_player_start_badguys'])entity(cls,'basin_'+cls,[0,0,88]);
entity('info_target','basin_monster_spawn',[0,0,80]);entity('info_target','basin_builder_spawn',[96,0,80]);
entity('ent_dota_game_events','basin_events',[0,0,0]);
entity('env_global_light','basin_morning',[0,0,2000],{color:'255 243 220 255',lightscale:'1.35',ambientcolor1:'184 208 225 255',ambientscale1:'1.35',ambientcolor2:'181 195 198 255',ambientscale2:'.8',ambientcolor3:'133 147 147 255',groundscale:'.65',enableshadows:'1',StartDisabled:'0'},'55 315 0');
entity('env_tonemap_controller','basin_tonemap',[0,0,0],{UseCustomAutoExposureMin:'1',UseCustomAutoExposureMax:'1',AutoExposureMin:'.85',AutoExposureMax:'.95'});
let template=fs.readFileSync(path.resolve(__dirname,'../output/zombie_island_v1/source_template.vmap'),'utf8');template=template.slice(template.indexOf('"CMapRootElement"'));
function close(s,start,op,cl){let d=0,quoted=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')quoted=!quoted;if(!quoted){if(s[i]===op)d++;if(s[i]===cl&&--d===0)return i;}}throw Error('Unbalanced template');}
const wa=template.indexOf('"world" "CMapWorld"'),wb=template.indexOf('{',wa),we=close(template,wb,'{','}');let w=template.slice(wa,we+1);const cb=w.indexOf('[',w.indexOf('"children" "element_array"')),ce=close(w,cb,'[',']');
let grid=w.slice(cb+1,ce).trim();grid=grid.replace('"-8192 -8192 128"','"-8192 -8192 0"');
grid=grid.replace(/"([^"]+)" "(int|bool|float|vector2|vector3|vector4|color)_array"\s*\[([^\]]*)\]/g,(all,k,t,body)=>{
 const a=[...body.matchAll(/"([^"]*)"/g)].map(m=>m[1]);let fill=null;
 if(k==='cellsHidden')fill='1';else if(k==='verticesHeight'||k==='verticesWater'||k==='edgesPath'||k==='edgesDestruction'||k.startsWith('objects'))fill=k==='objectsVariationId'?'255':'0';
 else if(k==='blendOpacity')fill='0 255 0 128';else if(k==='blendColor')fill='255 255 255 0';else if(k==='grassOpacity'||k==='fogOpacity')fill='0';
 if(fill!==null)a.fill(fill);
 if(k==='gridnavFlags'){if(a.length!==65536)throw Error('Unexpected nav size '+a.length);for(let y=0;y<256;y++)for(let x=0;x<256;x++)a[y*256+x]=walkable(-8192+x*64+32,-8192+y*64+32)?'0':'1';}
 return arr(k,t,a);
});
function group(name,nodes,locked=false){return raw('CMapGroup',val('name','string',name)+val('nodeID','int',node++)+val('referenceID','uint64','0x0')+ea('children',nodes)+val('origin','vector3','0 0 0')+val('angles','qangle','0 0 0')+val('scales','vector3','1 1 1')+val('transformLocked','bool',locked?1:0)+val('force_hidden','bool',0)+val('editorOnly','bool',0)+val('deformationMode','int',1));}
const terrain=children.filter(s=>s.startsWith('"CMapMesh"')),props=children.filter(s=>/"classname" "string" "(prop_static|ent_dota_tree)"/.test(s)),other=children.filter(s=>!terrain.includes(s)&&!props.includes(s));
const grouped=[group('AI_01_TERRAIN',terrain,true),group('AI_02_BASE_PROPS',props),group('AI_03_LIGHT_AND_MARKERS',other),group('USER_90_DETAILS',[])];
w=w.slice(0,cb+1)+grid+',\n'+grouped.join(',\n')+w.slice(ce);template=template.slice(0,wa)+w+template.slice(we+1);
fs.writeFileSync(path.join(OUT,'survival_basin_review.vmap'),'<!-- dmx encoding keyvalues2 4 format vmap 40 -->\n'+template);
fs.writeFileSync(path.join(OUT,'design.json'),JSON.stringify({map:'survival_basin_review',center:[0,0],basinRadius:br,puddleRadius:490,puddleDepth:16,courtRadius:R,courtOffset:D,courtHeight:Z,stairWidth:512,stairRise:512,stairRun:1024,wallGapWidth:512,themes,patches:audit,props:placed},null,2));
console.log('Basin review built:',children.length,'nodes,',placed.length,'props.');
