// Cloud composition is isolated from the accepted architecture and terrain.
const cloudArt=require("./world_v2_cloud_composition.cjs")({fs,path,OUT,land,nativePreserved,inside,edgeDistance,terrainHeight,hotSpring,entity,prism});
// Open teal-roof pavilions sit in decorative margins, away from all spawn marks.
function pavilion(x,y,scale=1.15){
 if(markers.some(m=>Math.hypot(x-m.x,y-m.y)<950)||cloudArt.pavilions.some(p=>Math.hypot(p.x-x,p.y-y)<1600))return;
 const z=surface(x,y);entity('prop_static','cultivation_pavilion_'+cloudArt.pavilions.length,[x,y,z],{model:'models/xianxia_kit/a01_pavilion_detail.vmdl',solid:'0',rendercolor:'255 255 255'},`0 ${cloudArt.pavilions.length%2*45} 0`,scale*.92);cloudArt.pavilions.push({x,y,z,scale:scale*.92,model:'a01_pavilion_detail'});
}
for(const p of [[-11800,15100],[-14900,1500],[5200,-13500],[13700,-7100]])pavilion(...p);
// Island landmarks only at the far ornamental corners, never at the gate/stairs.
for(let q=0;q<4;q++){const p=originalIsland.transform(768,1152,q);pavilion(...p,.8);}
for(const p of cloudArt.pavilions)for(let i=0;i<3;i++){
 const a=i*2.1+.5,x=p.x+Math.cos(a)*450,y=p.y+Math.sin(a)*450;
 if(markers.some(m=>Math.hypot(x-m.x,y-m.y)<550))continue;
 const pineModel='models/xianxia_kit/v01_pine_rooted_'+(i%2)+'.vmdl';
 entity('prop_static','cultivation_pine_'+cloudArt.pines.length,[x,y,surface(x,y)],{model:pineModel,solid:'0',rendercolor:'145 169 147'},`0 ${i*113} 0`,.8+(i%2)*.15);cloudArt.pines.push({x,y,model:pineModel});
}
fs.writeFileSync(path.join(OUT,'cultivation_design.json'),JSON.stringify(cloudArt,null,2));
