// Cloud placement is authored from the same active-area polygons as the map.
// No collision, no depth-test bypass, and no cloud over the central island/cross.
const cloudArt={theme:'修仙云海',timeOfDay:.3,outer:[],inner:[],pavilions:[],pines:[],clearance:360};
const playable=land.filter(a=>!a.nativeReuse);
function activeDistance(x,y){
 if(nativePreserved(x,y))return 0;
 let d=Infinity;
 for(const a of playable){if(inside(x,y,a.polygon))return 0;d=Math.min(d,edgeDistance(x,y,a.polygon));}
 return d;
}
function cloudSafe(x,y,r){
 // Test the projected footprint too: high clouds lean toward the camera at
 // the normal Dota pitch. Internal bands have only a small elevation offset.
 return activeDistance(x,y)>r+180&&activeDistance(x,y-180)>r+180;
}
function cloudEffect(x,y,z,type,index){entity('info_particle_system','cultivation_'+type+'_'+index,[x,y,z],{effect_name:'particles/survival_world_v2/'+type+'.vpcf',start_active:'1'});}
function outerCloud(x,y,angle,index){
 const r=1680;
 if(!cloudSafe(x,y,r))return;
 const z=650+260*(1+Math.sin(index*2.73));
 // The Blender cores remain editable source assets. In-engine the opaque
 // surface looked plastic, so use overlapping cloud cards at real 3D depths.
 cloudEffect(x,y,z+280,'cloud_outer',index*2);
 cloudEffect(x,y,z-280,'cloud_outer',index*2+1);
 cloudArt.outer.push({x,y,z,r,angle,projectedClearance:activeDistance(x,y)-r});
}
// Three irregular, overlapping shelves avoid a row of identical cloud objects.
let outerIndex=0;
for(let layer=0;layer<3;layer++)for(let side=0;side<4;side++)for(let t=-19000;t<=19000;t+=1250){
 const edge=16200+layer*1500+460*Math.sin(t*.0013+side*2.7+layer),offset=layer*470+210*Math.sin(t*.003);
 let x=side===0?edge:side===1?-edge:t+offset,y=side===2?edge:side===3?-edge:t+offset;
 if(!cloudSafe(x,y,1680)){if(side<2)x=Math.sign(x)*18500;else y=Math.sign(y)*18500;}
 outerCloud(x,y,side<2?90:0,outerIndex++);
}
// Broad ridges get overlapping low banks; narrow separators get thin wisps.
for(let gy=-15600;gy<=15600;gy+=440)for(let gx=-15600;gx<=15600;gx+=440){
 const x=gx+95*Math.sin(gy*.004),y=gy+75*Math.sin(gx*.003);
 if(nativePreserved(x,y)||at(x,y)||!cloudSafe(x,y,350))continue;
 const d=activeDistance(x,y),wide=cloudSafe(x,y,770),r=wide?770:350;
 // Leave the open sea clear, and use only ridge tops/land separators.
 if(waters.some(a=>inside(x,y,a.polygon)))continue;
 if(cloudArt.inner.some(p=>Math.hypot(p.x-x,p.y-y)<(wide?600:410)))continue;
 const z=terrainHeight(x,y)+130;cloudEffect(x,y,z,wide?'cloud_middle':'cloud_inner',cloudArt.inner.length);cloudArt.inner.push({x,y,z,r,projectedClearance:d-r});
}
// Open teal-roof pavilions sit in decorative margins, away from all spawn marks.
function pavilion(x,y,scale=1.15){
 if(markers.some(m=>Math.hypot(x-m.x,y-m.y)<950)||cloudArt.pavilions.some(p=>Math.hypot(p.x-x,p.y-y)<1600))return;
 const z=surface(x,y);entity('prop_static','cultivation_pavilion_'+cloudArt.pavilions.length,[x,y,z],{model:'models/survival_world_v2/cultivation_pavilion.vmdl',solid:'0',rendercolor:'255 255 255'},`0 ${cloudArt.pavilions.length%2*45} 0`,scale);cloudArt.pavilions.push({x,y,z,scale});
}
for(const p of [[-11800,15100],[-6200,15200],[1000,15100],[9200,14700],[-14900,7100],[-14900,1500],[-14600,-4400],[-14200,-14000],[-5500,-14000],[5200,-13500],[13200,-12500],[13700,-7100],[9700,-1200],[5000,-8100],[-4700,-8600]])pavilion(...p);
// Island landmarks only at the far ornamental corners, never at the gate/stairs.
for(let q=0;q<4;q++){const p=originalIsland.transform(768,1152,q);pavilion(...p,.8);}
const pineModel='maps/journey_assets/props/trees/journey_armandpine/journey_armandpine_01.vmdl';
for(const p of cloudArt.pavilions)for(let i=0;i<3;i++){
 const a=i*2.1+.5,x=p.x+Math.cos(a)*450,y=p.y+Math.sin(a)*450;
 if(markers.some(m=>Math.hypot(x-m.x,y-m.y)<550))continue;
 entity('prop_static','cultivation_pine_'+cloudArt.pines.length,[x,y,surface(x,y)],{model:pineModel,solid:'0',rendercolor:'214 232 213'},`0 ${i*113} 0`,.8+(i%2)*.15);cloudArt.pines.push({x,y});
}
fs.writeFileSync(path.join(OUT,'cultivation_design.json'),JSON.stringify(cloudArt,null,2));
