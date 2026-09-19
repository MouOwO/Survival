// Coordinates are native 256-unit Dota terrain tiles, viewed from above.
// North is +Y. This is the editable authority for the approved C6 layout.
const sanctuary=require('./sanctuary.cjs');
const areaScale={central:(sanctuary.radius/(22*256))**2,ordinary:.7,smallSoutheast:.3};
const centralScale=Math.sqrt(areaScale.central);
const size = 128, tile = 256, center = {x:60,y:85,r:sanctuary.radius/256};
const centralPoint=(x,y)=>[center.x+(x-center.x)*centralScale,center.y+(y-center.y)*centralScale];
const centralOriginal=(x,y)=>[center.x+(x-center.x)/centralScale,center.y+(y-center.y)/centralScale];
const localPoint=(x,y)=>[center.x+x/tile,center.y+y/tile];
const halfPool=sanctuary.poolSide/2;
const poolCorners=[[halfPool,-halfPool],[halfPool,halfPool],[-halfPool,halfPool],[-halfPool,-halfPool]].map(([x,y])=>localPoint(x,y));
const players=[0,1,2,3].map(id=>{
 const point=(x,y)=>localPoint(...sanctuary.rotate(x,y,id));
 const [x,y]=point(1420,1116),[ex,ey]=point(2100,0),[ax,ay]=point(600,0);
 return {id,x,y,ex,ey,ax,ay,z:sanctuary.landHeight+16,entranceZ:sanctuary.laneHeight+16,spawnZ:16};
});
const resourceTree=localPoint(1670,1366);
const rooms=[];
const add=(id,group,x,y,w,h,season)=>{
  const ratio=group==='small_southeast'?areaScale.smallSoutheast:areaScale.ordinary,s=Math.sqrt(ratio);
  rooms.push({id,group,x:x+w*(1-s)/2,y:y+h*(1-s)/2,w:w*s,h:h*s,season,areaScale:ratio,original:{x,y,w,h}});
};
for(let i=0;i<10;i++)add(`west_${i+1}`,'west_main',23,52+i*6,7,5,i%4);
for(let i=0;i<3;i++)add(`west_inner_${i+1}`,'west_inner',34,94+i*7,6,6,i);
for(const [group,x,y] of [['northwest',28,119],['northeast',67,119],['southwest',28,40],['southeast',67,40]])
  for(let i=0;i<4;i++)add(`${group}_${i+1}`,group,x+i*7,y,6,6,i%4);
for(let i=0;i<4;i++)add(`east_${i+1}`,'east',87,64+i*12,9,10,i);
for(let j=0;j<2;j++)for(let i=0;i<5;i++)add(`small_${j*5+i+1}`,'small_southeast',70+i*9,10+j*16,8,8,(i+j)%4);
// Additional individual courts visible in approved C6, outside the 10-room group.
add('star_west','individual',34,18,7,7,1);
add('star_east','individual',45,18,7,7,3);
add('far_east','individual',118,51,7,8,2);
add('southern','individual',58,7,7,7,0);
const inside=(x,y,r,margin=0)=>x>=r.x-margin&&x<=r.x+r.w+margin&&y>=r.y-margin&&y<=r.y+r.h+margin;
function region(x,y) {
  const room=rooms.find(r=>inside(x,y,r));
  if(room)return {land:true,height:0,season:room.season,room:room.id};
  const dx=x-center.x,dy=y-center.y;
  if(dx*dx+dy*dy<=center.r*center.r) {
    if(Math.abs(dx*tile)<=halfPool&&Math.abs(dy*tile)<=halfPool)return {land:false,height:0,season:0,centralWater:true};
    const season=Math.abs(dx)>Math.abs(dy)?(dx>0?1:0):2;
    return {land:true,height:0,season,central:true};
  }
  // Spacious left meadows, with low ridges and clear basin floors.
  if((x>=3&&x<=19&&y>=95&&y<=112)||(x>=2&&x<=19&&y>=6&&y<=49))
    return {land:true,height:0,season:y>80?0:1,plain:true};
  // Four wooded upper-right ledges, as explicitly retained in C6.
  for(let i=0;i<4;i++)if(x>=102&&x<=112&&y>=88+i*9&&y<=94+i*9)
    return {land:true,height:0,season:2,ledge:true};
  // Star-shaped southwest island. Flat ground remains around its two courts.
  const sx=Math.abs(x-43),sy=Math.abs(y-22);
  if((sx<4&&sy<13)||(sy<4&&sx<13)||(sx+sy<12))return {land:true,height:0,season:2,star:true};
  // Red boss platform and retained distant decorative sacred cliffs.
  if((x-62)**2+(y-31)**2<16)return {land:true,height:0,season:1,boss:true};
  if([[5,62],[12,72],[4,84],[14,57]].some(([cx,cy])=>(x-cx)**2+(y-cy)**2<4))return {land:true,height:1,season:2,scenery:true};
  if(x>117&&y>84)return {land:true,height:1,season:3,scenery:true};
  if([[121,28],[124,18],[121,5]].some(([cx,cy])=>(x-cx)**2+(y-cy)**2<4))return {land:true,height:1,season:3,scenery:true};
  return {land:false,height:0,season:0};
}
function world(x,y,z=144){return [(x-size/2)*tile,(y-size/2)*tile,z];}
module.exports={size,tile,center,rooms,inside,region,world,areaScale,centralScale,centralPoint,centralOriginal,poolCorners,players,resourceTree,sanctuary,localPoint};
