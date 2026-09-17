// Native Oriental lanterns and a restrained ghost-light procession.
const nightArt={theme:'百鬼夜行',timeOfDay:0,lanterns:[],wisps:[]};
const lanternModel='maps/journey_assets/props/lanterns/lantern_jrny_radiant_1.vmdl';
const lampLightTemplate=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../output/reference_asset_study/lighting.json'),'utf8')).ent_dota_lightinfo;
function nightLantern(x,y,scale=1){
 if(markers.some(m=>Math.hypot(x-m.x,y-m.y)<350))return;
 const z=surface(x,y),i=nightArt.lanterns.length;
 entity('prop_static','yokai_lantern_'+i,[x,y,z],{model:lanternModel,solid:'0',skin:'0',rendercolor:'245 208 190',renderamt:'255'},`0 ${i*67%360} 0`,scale);
 const light={...lampLightTemplate,inner_radius:'110',outer_radius:'560',farz_override:'45000'};
 for(const k of Object.keys(light))if(k.endsWith('map_texture')||k==='height_fog_textureopacity')delete light[k];
 for(const time of ['day','night'])Object.assign(light,{['color_'+time]:'235 154 86 255',['light_scale_'+time]:'2.2',['ambient_color_'+time]:'154 112 92 255',['ambient_scale_'+time]:'.85',['fog_start_'+time]:'20000',['fog_end_'+time]:'40000',['fog_height_'+time]:'0',['fow_darkess_'+time]:'1',['light_direction_'+time]:'66 330 0'});
 entity('ent_dota_lightinfo','yokai_lantern_light_'+i,[x,y,z],light,'66 330 0');
 entity('info_particle_system','yokai_lantern_flame_'+i,[x,y,z+175*scale],{effect_name:'particles/survival_world_v2/yokai_lantern_glow.vpcf',start_active:'1'});
 nightArt.lanterns.push({x,y,z,model:lanternModel});
}
function ghostLight(x,y){const z=surface(x,y)+65;entity('info_particle_system','yokai_wisp_'+nightArt.wisps.length,[x,y,z],{effect_name:'particles/survival_world_v2/yokai_wisps.vpcf',start_active:'1'});nightArt.wisps.push({x,y,z});}
for(let q=0;q<4;q++){
 for(const side of [-1,1])nightLantern(...originalIsland.worldPoint(1920,side*832,q),.9);
 nightLantern(...originalIsland.worldPoint(784,784,q),.8);
 for(const p of [[-2304,768],[-2304,-512],[-1024,1024],[-1024,-768],[768,768],[768,-512],[-512,528],[-512,-272]])nightLantern(...originalIsland.transform(...p,q),1.05);
 for(const p of [[-2100,1150],[-1600,-1050]])ghostLight(...originalIsland.transform(...p,q));
}
for(const a of land){
 if(a.nativeReuse||!(a.combatArt||a.name.includes('camp')))continue;
 const p=a.polygon,c=p.reduce((s,v)=>[s[0]+v[0]/p.length,s[1]+v[1]/p.length],[0,0]);
 const v=p[0],x=c[0]+(v[0]-c[0])*.77,y=c[1]+(v[1]-c[1])*.77;nightLantern(x,y,a.combatArt?.7:.9);
}
for(let i=0;i<6;i++){const a=i*Math.PI/3;nightLantern(hotSpring.x+Math.cos(a)*1300,hotSpring.y+Math.sin(a)*880,.9);if(i%2===0)ghostLight(hotSpring.x+Math.cos(a)*1700,hotSpring.y+Math.sin(a)*1150);}
fs.writeFileSync(path.join(OUT,'yokai_design.json'),JSON.stringify(nightArt,null,2));
