// Rounded closed heightfields use one continuous meadow/soil/stone paint field.
const roundIsland=originalIsland.round,roundAudit=[];
prism([[preserved[0],preserved[1]],[preserved[2],preserved[1]],[preserved[2],preserved[3]],[preserved[0],preserved[3]]],254,-512,'materials/survival_world_v2/transition_forest.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
function roundPatch(name,bounds,insideField,heightField,paint,topMaterial,bottom,holes=false){
 const verts=[],faces=[],ids=new Map(),edges=new Map(),step=64;
 const vertex=(p)=>{const key=p.map(v=>Math.round(v*1000)/1000).join(',');if(!ids.has(key)){ids.set(key,verts.length);verts.push(p);}return ids.get(key);};
 const tri=v=>{faces.push({v,m:0});for(let i=0;i<3;i++){const a=v[i],b=v[(i+1)%3],reverse=b+','+a;if(edges.has(reverse))edges.delete(reverse);else edges.set(a+','+b,[a,b]);}};
 function clip(t){
  const p=[];for(let i=0;i<3;i++){const a=t[i],b=t[(i+1)%3];if(a.d>=0)p.push(a);if((a.d>=0)!==(b.d>=0)){const w=a.d/(a.d-b.d);p.push({x:a.x+(b.x-a.x)*w,y:a.y+(b.y-a.y)*w,d:0});}}
  const v=p.map(a=>vertex([a.x,a.y,heightField(a.x,a.y)]));for(let i=1;i+1<v.length;i++)if(new Set([v[0],v[i],v[i+1]]).size===3)tri([v[0],v[i],v[i+1]]);
 }
 const sample=(x,y)=>({x,y,d:insideField(x,y)});
 for(let y=bounds[1];y<bounds[3];y+=step)for(let x=bounds[0];x<bounds[2];x+=step){
  if(holes&&roundIsland.stairHole(x+32,y+32))continue;
  const a=sample(x,y),b=sample(x+step,y),c=sample(x+step,y+step),d=sample(x,y+step);clip([a,b,c]);clip([a,c,d]);
 }
 const count=verts.length,topFaces=faces.length;for(let i=0;i<count;i++)verts.push([verts[i][0],verts[i][1],bottom]);
 for(let i=0;i<topFaces;i++)faces.push({v:faces[i].v.slice().reverse().map(v=>v+count),m:9});
 for(const [a,b]of edges.values())faces.push({v:[b,a,a+count,b+count],m:9});
 paintBlendSoftness=['ocean','shallow'].includes(name)?[1,1,1,0]:[.22,.24,.20,0];
 paintVertex=paint;normalVertex=(v)=>{const dx=(heightField(v[0]+16,v[1])-heightField(v[0]-16,v[1]))/32,dy=(heightField(v[0],v[1]+16)-heightField(v[0],v[1]-16))/32,l=Math.hypot(dx,dy,1);return[-dx/l,-dy/l,1/l];};
 mesh(verts,faces,[topMaterial,...Array(8).fill('materials/tools/toolsnodraw.vmat'),['ocean','shallow'].includes(name)?'materials/tools/toolsnodraw.vmat':'materials/survival_world_v2/island_natural_rock.vmat'],'255 255 255 255');paintVertex=null;normalVertex=null;paintBlendSoftness=[.22,.24,.20,0];
 roundAudit.push({name,vertices:verts.length,topFaces,closed:true});
}
for(let q=0;q<4;q++){
 const c=roundIsland.world(roundIsland.islandOffset,0,q),r=roundIsland.radius;
 const bb=[Math.floor((c[0]-r)/64)*64,Math.floor((c[1]-r)/64)*64,Math.ceil((c[0]+r)/64)*64,Math.ceil((c[1]+r)/64)*64];
 roundPatch('island_'+q,bb,(x,y)=>r-Math.hypot(x-c[0],y-c[1]),roundIsland.height,roundIsland.paint,'materials/survival_world_v2/island_meadow.vmat',240,true);
}
roundPatch('ocean',preserved,(x,y)=>roundIsland.lakeDistance(x,y),()=>400,(v,m)=>{
 if(m!==0)return[0,0,0,0];const d=roundIsland.islandDistance(v[0],v[1]),n=roundIsland.noise(v[0]*.6,v[1]*.6),shore=Math.exp(-Math.abs(d)/180);
 const gap=smooth(roundIsland.lakeDistance(v[0],v[1])/300);
 return [.11*shore*smooth((n-.45)*3)*gap,.025*shore*gap,(.06+.08*n)*gap,0];
},'materials/survival_world_v2/island_ocean_waves.vmat',398);
roundPatch('shallow',preserved,(x,y)=>-roundIsland.lakeDistance(x,y),()=>400,(v,m)=>m===0?[0,0,.82*smooth(-roundIsland.lakeDistance(v[0],v[1])/480),0]:[0,0,0,0],'materials/survival_world_v2/island_shallow_blend.vmat',398);
fs.writeFileSync(path.join(OUT,'round_island_design.json'),JSON.stringify({center:roundIsland.center,radius:roundIsland.radius,islandOffset:roundIsland.islandOffset,lakeRadius:roundIsland.lakeRadius,shoreSlopeWidth:160,paint:'continuous vertex-painted meadow, soil, rock and sparse stone',patches:roundAudit},null,2));
fs.writeFileSync(path.join(OUT,'island_foundation_design.json'),JSON.stringify({method:'four closed rounded natural terrain bodies',closed:true,tiers:[{top:640},{top:768}],copingThickness:0,entrances:'main and side stairs excluded from terrain surface'},null,2));
