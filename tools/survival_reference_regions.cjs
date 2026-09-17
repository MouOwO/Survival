// Reference layout in minimap coordinates. X right, Y down, 64 Source units/pixel.
const blockedAreas=[],markers=[],mountainSamples=[];
M.lava='materials/blends/dire_lava.vmat';M.corrupt='materials/blends/dire_lava_green.vmat';
M.paving='materials/blends/stone_path009.vmat';
const P={tree:'models/props_foliage/tree_pine01.vmdl',rock:'models/props_debris/rock_debris001.vmdl',spike:'models/props_destruction/rockyspikes_dynamic.vmdl',statue:'models/props_garden/statue_garden001.vmdl',fence:'models/props_debris/spike_fence001a.vmdl'};
function mark(name,x,y,z=400,kind='land'){entity('info_target',name,[X(x),Y(y),z+24]);markers.push({name,x:X(x),y:Y(y),z,kind});}
function prop(type,x,y,z,scale=1,angle=0){entity('prop_static',type+'_'+node,[X(x),Y(y),z],{model:P[type],solid:'0'},`0 ${angle} 0`,scale);}
function inset(p,f=.9){const c=p.reduce((a,v)=>[a[0]+v[0]/p.length,a[1]+v[1]/p.length],[0,0]);return p.map(v=>[c[0]+(v[0]-c[0])*f,c[1]+(v[1]-c[1])*f]);}
function edge(p,z,type='tree',spacing=200,scale=.7,gap=false){p=inset(p,.91);for(let i=0;i<p.length;i++){const a=p[i],b=p[(i+1)%p.length],n=Math.max(1,Math.floor(Math.hypot(b[0]-a[0],b[1]-a[1])/spacing));for(let j=0;j<n;j++){if(gap&&i===0)continue;const t=(j+.5)/n;prop(type,(a[0]+(b[0]-a[0])*t)/64+170,95-(a[1]+(b[1]-a[1])*t)/64,z,scale,(i*51+j*37)%360);}}}
function paving(p,z,mat=M.paving){prism(inset(p,.9),z+2,z-8,mat,M.rock,'215 220 215 255');}
function room(name,x,y,w=13,h=10){const p=rect(x,y,x+w,y+h,1);platform(name,p,384,M.grass,true);paving(p,384);for(const q of [rect(x+.4,y+.4,x+w-.4,y+1,.2),rect(x+.4,y+h-1,x+w-.4,y+h-.4,.2),rect(x+.4,y+1,x+1,y+h-1,.2),rect(x+w-1,y+1,x+w-.4,y+h-1,.2)]){prism(q,500,380,M.grass);blockedAreas.push(q);}prism(ellipse(x+w/2,y+h/2,1.6,1.2,12),389,380,M.grass,M.rock,'115 160 90 255');mark(name+'_center',x+w/2,y+h/2,389);}
function bossRoom(name,x,y,w,h,style='tree'){const p=rect(x,y,x+w,y+h,1);platform(name,p,384,style==='lava'?M.lava:M.grass);if(style!=='lava')paving(p,384,style==='tree'?M.paving:M.stone);edge(p,384,style==='tree'?'tree':style==='lava'?'spike':'rock',style==='tree'?150:145,style==='lava'?.7:style==='rock'?1.25:.5);mark(name+'_boss_spawn',x+w/2,y+h*.45,384);if(style==='monument')prop('statue',x+w/2,y+1.8,385,.6);}

water('central_sea',101,24,218,128);water('western_channel',64,19,100,129);water('northeast_water',220,22,258,75);water('eastern_water',220,75,259,127);water('southwest_water',66,152,150,190);
// N1-10: eight different soft-cornered camps around a square lake.
platform('n01_10_island',ellipse(158,79,43,37,64),384,M.grass);
const camps=[[158,51,0],[183,59,1],[191,79,2],[181,101,3],[157,106,4],[133,99,5],[124,79,6],[135,57,7]];
for(const [cx,cy,i] of camps){const angle=i*Math.PI/4;let pts=[[-9,-6],[5,-7],[9,-3],[8,5],[0,7],[-8,4]].map(([x,y])=>[cx+x*Math.cos(angle)-y*Math.sin(angle),cy+x*Math.sin(angle)+y*Math.cos(angle)]);const p=polygon(pts);platform('n01_10_camp_'+i,p,416,i%2?M.grass:M.stone);edge(p,416,'tree',260,.58,true);mark('n01_10_player_'+i,cx,cy,416);}
const lake=rect(149,70,167,88,2);waters.push({name:'central_square_lake',polygon:lake,z:390});prism(lake,390,368,M.water,M.rock,'255 255 255 255');blockedAreas.push(lake);
mark('n01_10_monster_spawn',158,94,384);

// N11-20: central stone square with four trapezoid arms.
platform('n11_20_center',rect(92,165,123,180,1),384,M.paving);
const trapezoids=[[[96,165],[119,165],[113,155],[102,155]],[[123,165],[123,180],[142,176],[142,170]],[[96,180],[119,180],[114,190],[102,190]],[[92,165],[92,180],[73,176],[73,170]]];
trapezoids.forEach((p,i)=>{platform('n11_20_camp_'+i,polygon(p),400,M.dirt);const c=p.reduce((a,v)=>[a[0]+v[0]/4,a[1]+v[1]/4],[0,0]);mark('n11_20_player_'+i,...c,400);});mark('n11_20_monster_spawn',107.5,172.5,384);paving(ellipse(107.5,172.5,3,3,4),384,M.stone);

// N21-30: four raised grass quadrants inside a spiked cage.
platform('n21_30_courtyard',rect(2,29,59,67,1.8),384,M.paving);
for(const [x,y,i]of [[4,31,0],[4,51,1],[34,51,2],[34,31,3]]){const p=rect(x,y,x+23,y+13,1);platform('n21_30_camp_'+i,p,432,M.grass);edge(p,432,'tree',240,.62,true);mark('n21_30_player_'+i,x+11.5,y+6.5,432);}
edge(rect(2,29,59,67,1),390,'fence',190,1);mark('n21_30_monster_spawn',30.5,48.5,384);paving(rect(27,45,34,52,.5),384,M.stone);

// N31-40: right/left/right/left from north to south.
platform('n31_40_corridor',rect(2,120,59,186,1.5),384,M.paving);
for(let i=0;i<4;i++){const right=i%2===0,x=right?29:4,y=122+i*16;const p=rect(x,y,x+26,y+12,1.5);platform('n31_40_camp_'+i,p,416,right?M.paving:M.dirt);edge(p,416,'tree',260,.55,true);mark('n31_40_player_'+i,x+13,y+6,416);const sx=right?13:47;mark('n31_40_monster_'+i,sx,y+6,384);paving(rect(Math.min(sx,x+13),y+4,Math.max(sx,x+13)+.5,y+8,.6),384,M.stone);}

// N41-50: four identical grassy clearings down the western edge of snowfield.
platform('n41_50_snowfield',rect(263,4,338,77,2),512,M.snow);
for(let i=0;i<4;i++){const y=8+i*17,p=rect(265,y,293,y+12,1);platform('n41_50_camp_'+i,p,560,M.grass);edge(p,560,'tree',180,.66,true);mark('n41_50_player_'+i,279,y+6,560);mark('n41_50_monster_'+i,308,y+6,512);}

// N51-60: one large camp with corrupt approach and a single broad spawn clearing.
platform('n51_60_corruption',rect(263,104,338,141,2),384,M.corrupt);
const shared=rect(302,106,337,137,2);platform('n51_60_shared_camp',shared,432,M.grass);edge(shared,432,'tree',225,.72,true);mark('n51_60_player_shared',322,122,432);
paving(ellipse(279,123,9,11,24),384,M.dirt);mark('n51_60_monster_spawn',279,123,384);

// 1-10 rebirth bosses: western vertical strip, identical tree islands.
for(let i=0;i<10;i++)bossRoom('rebirth_'+String(i+1).padStart(2,'0'),67,24+i*9.9,11,8.2,'tree');
bossRoom('flame_troll',83,25,13,10,'lava');bossRoom('ice_elegy',83,38,13,10,'rock');bossRoom('synthesis_gem',83,51,13,10,'rock');
// Ten Commandments: 3 x 4 arenas, final two bottom-right remain empty.
for(let r=0;r<4;r++)for(let c=0;c<3;c++){const i=r*3+c;const name=i<10?'commandment_'+String(i+1).padStart(2,'0'):'commandment_empty_'+i;bossRoom(name,223+c*11.5,82+r*10.6,10,9,'monument');if(i>=10){markers.pop();}}
bossRoom('polar_crystal_mobs',222,67,16,11,'rock');paving(rect(222,67,238,78,1),384,M.snow);
bossRoom('molten_core_mobs',241,67,16,11,'lava');bossRoom('seven_sins',241,25,15,15,'lava');

// Four identical player groups, each with wood/gold/attributes/greater attributes.
const groups=[[70,5],[176,5],[70,132],[176,132]],types=['wood','gold','attributes','greater_attributes'];
groups.forEach(([x,y],player)=>types.forEach((type,i)=>room('training_p'+player+'_'+type,x+i*16,y,13,10)));
for(let i=0;i<4;i++)room('endless_p'+i,162+i*36,155,17,11);

// Original challenge reserve: a ring of ancient monuments, open central arena.
const original=ellipse(29,94,23,16,40);platform('original_challenge_reserve',original,384,M.grass);paving(ellipse(29,94,12,9,8),384,M.paving);edge(original,384,'tree',280,.85);
for(let i=0;i<6;i++){const t=i*Math.PI/3;prop('statue',29+15*Math.cos(t),94+11*Math.sin(t),384,.85,i*60);}mark('original_challenge_center',29,94,384);

// Mountains occupy only the reference's non-playable black gaps, never sea or camps.
function buildMountains(){
 const step=4,nx=85,ny=48,verts=[],faces=[];
 function protectedPoint(x,y){return land.some(a=>inside(X(x),Y(y),a.polygon))||waters.some(a=>inside(X(x),Y(y),a.polygon));}
 function height(x,y){
   if(protectedPoint(x,y))return -240;
   let margin=20;for(let r=2;r<=16;r+=2){let near=false;for(let a=0;a<8;a++){const t=a*Math.PI/4;if(protectedPoint(x+r*Math.cos(t),y+r*Math.sin(t)))near=true;}if(near){margin=r;break;}}
   const noise=(Math.sin(x*.47+y*.28)+Math.cos(x*.23-y*.53)+2)/4;
   return -180+Math.min(1,margin/10)*(650+noise*1300);
 }
 for(let y=0;y<=ny;y++)for(let x=0;x<=nx;x++){let z=height(x*step,y*step);verts.push([X(x*step),Y(y*step),z]);if(z>700&&x%8===0&&y%6===0)mountainSamples.push({name:'mountain_'+x+'_'+y,x:X(x*step),y:Y(y*step),z});}
 const size=verts.length;for(const v of verts.slice())verts.push([v[0],v[1],-1700]);
 for(let y=0;y<ny;y++)for(let x=0;x<nx;x++){const a=y*(nx+1)+x,b=a+1,c=a+nx+1,d=c+1;const snowy=verts[a][2]>1200&&verts[d][2]>1100;faces.push({v:[a,c,b],m:snowy?1:0},{v:[b,c,d],m:snowy?1:0},{v:[a+size,b+size,c+size],m:0},{v:[b+size,d+size,c+size],m:0});}
 const perimeter=[];for(let x=0;x<=nx;x++)perimeter.push(x);for(let y=1;y<=ny;y++)perimeter.push(y*(nx+1)+nx);for(let x=nx-1;x>=0;x--)perimeter.push(ny*(nx+1)+x);for(let y=ny-1;y>0;y--)perimeter.push(y*(nx+1));
 for(let i=0;i<perimeter.length;i++){const a=perimeter[i],b=perimeter[(i+1)%perimeter.length];faces.push({v:[a,b,b+size,a+size],m:0});}
 mesh(verts,faces,[M.rock,M.snow],'178 193 203 255');
}
function writePreviewFiles(report){
 const tests=markers.filter(m=>!m.name.includes('empty')).map(m=>({name:m.name,x:m.x,y:m.y,z:m.z,walk:true}));
 for(const m of mountainSamples.slice(0,12))tests.push({...m,walk:false});
 tests.push({name:'central_square_lake',x:X(158),y:Y(79),z:390,walk:false});
 const lua=`if GetMapName() ~= 'survival_reference_v2' then error('Load survival_reference_v2') end\nlocal tests={\n${tests.map(t=>`{name='${t.name}',x=${t.x},y=${t.y},z=${t.z},walk=${t.walk}}`).join(',\n')}\n}\nlocal failures=0\nfor _,t in ipairs(tests) do local v=Vector(t.x,t.y,t.z); local walk=GridNav:IsTraversable(v) and not GridNav:IsBlocked(v); local ok=walk==t.walk; if not ok then failures=failures+1 end; print('[REFERENCE_MAP]',t.name,ok and 'PASS' or 'FAIL',walk,GetGroundHeight(v,nil)) end\nprint('[REFERENCE_MAP] TOTAL',#tests,'FAILURES',failures)\n`;
 fs.writeFileSync(path.resolve(__dirname,'../scripts/vscripts/maps/survival_reference_v2_verify.lua'),lua);
 let svg='<svg xmlns="http://www.w3.org/2000/svg" width="1700" height="960" viewBox="0 0 340 192"><rect width="340" height="192" fill="#53636e"/>';
 const poly=(p,color)=>`<polygon points="${p.map(v=>(v[0]/64+170)+','+(95-v[1]/64)).join(' ')}" fill="${color}" stroke="#a3b3a0" stroke-width=".2"/>`;
 waters.forEach(a=>svg+=poly(a.polygon,'#23617c'));land.forEach(a=>svg+=poly(a.polygon,a.name.includes('snow')?'#e1eff4':a.name.includes('corruption')?'#35483a':a.name.includes('camp')?'#86a267':a.room?'#a3a394':'#657e51'));
 svg+=poly(rect(149,70,167,88,2),'#23617c');
 for(const m of markers)svg+=`<circle cx="${m.x/64+170}" cy="${95-m.y/64}" r=".6" fill="#f7d58a"><title>${m.name}</title></circle>`;
 const labels=[[158,45,'N1–10'],[107,163,'N11–20'],[30,28,'N21–30'],[30,119,'N31–40'],[313,43,'N41–50'],[317,103,'N51–60'],[29,92,'ORIGINAL'],[238,81,'10 BOSSES']];
 for(const [x,y,s] of labels)svg+=`<text x="${x}" y="${y}" fill="white" text-anchor="middle" font-family="sans-serif" font-size="3">${s}</text>`;
 fs.writeFileSync(path.join(OUT,'layout.svg'),svg+'</svg>');
}
