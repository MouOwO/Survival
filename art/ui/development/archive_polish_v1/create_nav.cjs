const fs=require('fs'),p=require('path');
const root=p.resolve(__dirname,'../../../..'),dir=p.join(root,'panorama/src/images/custom_game/archive_polish_v1/nav');fs.mkdirSync(dir,{recursive:true});
const shapes={
 clear:'<path d="M21 10h22v14c0 12-22 12-22 0zM21 15H12v7c0 9 8 11 14 11M43 15h9v7c0 9-8 11-14 11M32 35v13M21 53h22M25 48h14"/><path d="m32 14 2 5 6 .3-4.5 3.6 1.5 5.5-5-3-5 3 1.5-5.5-4.5-3.6 6-.3z"/>',
 endless:'<path d="M32 32C16 10 7 19 7 32s9 22 25 0 25-13 25 0-9 22-25 0z"/><path d="m25 13 7-6 7 6M25 51l7 6 7-6"/>',
 map_level:'<path d="m8 15 15-5 18 5 15-5v39l-15 5-18-5-15 5zM23 10v39M41 15v39M13 37l12-15 9 12 8-8 9 12"/>',
 work:'<rect x="8" y="20" width="48" height="32" rx="4"/><path d="M23 20v-8h18v8M8 30l20 7h8l20-7M27 32h10v10H27z"/>',
 fishing:'<path d="M12 32c12-19 27-17 37 0-10 17-25 19-37 0zM49 32l10-12v24zM19 24l-8-9M19 40l-8 9"/><circle cx="25" cy="29" r="2" fill="#e8c98a"/><path d="M34 12V6"/>',
 building:'<path d="M10 55V26l22-16 22 16v29zM7 26h50M24 55V38h16v17M16 30h4M44 30h4M28 6h8M32 10V6"/>',
 boss:'<path d="m14 25-6-15 15 11M50 25l6-15-15 11M16 22l16-9 16 9 4 15-10 18H22L12 37zM20 32l8 4M44 32l-8 4M25 46h14M28 47v6M36 47v6"/>'
};
const names={clear:'通关存档',endless:'无尽存档',map_level:'地图等级',work:'上班福利',fishing:'钓鱼存档',building:'存档建筑',boss:'BOSS存档'};
let csv='category_id,display_name,image_path,normal_color,selected_color,design_size\n';
for(const [id,body]of Object.entries(shapes)){fs.writeFileSync(p.join(dir,id+'.svg'),'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="none" stroke="#e8c98a" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">'+body+'</g></svg>');csv+=[id,names[id],'custom_game/archive_polish_v1/nav/'+id+'.svg','#e8c98a','#000000',31].join(',')+'\n';}
fs.writeFileSync(p.join(root,'data/csv/存档系统/archive_navigation_icons.csv'),csv);
// Panorama's native SVG importer needs explicit paint on each primitive.
require('./flatten_nav.cjs');
console.log('7 distinct native vector navigation icons (explicit native paint)');
