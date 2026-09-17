// V2 reuses the VMAP serializer verified by the first terrain prototype.
const fs=require('fs'),path=require('path');
let src=fs.readFileSync(path.join(__dirname,'build_zombie_abyss_map.cjs'),'utf8');
src=src.replaceAll('zombie-abyss-v1-','survival-reference-v2-').replaceAll('zombie_abyss_v1','survival_reference_v2').replace("../output/zombie_island_v1","../output/survival_reference_v2");
src=src.replace("path.join(OUT,'source_template.vmap')","path.resolve(__dirname,'../output/zombie_island_v1/source_template.vmap')");
// Use the native blue water material; ocean blend defaults to an opaque gray layer on meshes.
src=src.replace("AutoExposureMin:'.65',AutoExposureMax:'.85'","AutoExposureMin:'2',AutoExposureMax:'2'");
src=src.replace("material===M.snow?'195 207 215 255':'177 185 172 255'","material===M.snow?'245 250 255 255':material===M.grass?'125 170 93 255':'205 207 203 255'");
src=src.replace("const isLand=(x,y)=>land.some(a=>inside(x,y,a.polygon));","const isLand=(x,y)=>land.some(a=>inside(x,y,a.polygon))&&!blockedAreas.some(p=>inside(x,y,p));");
const start=src.indexOf("water('central_sea'");
const end=src.indexOf('// Clip all non-land',start);
src=src.slice(0,start)+fs.readFileSync(path.join(__dirname,'survival_reference_regions.cjs'),'utf8')+'\n'+src.slice(end);
src=src.replace("// Dark distant floor gives abyss depth. Control clips above prevent traversing it.\nprism(rect(0,0,340,192,.1),-1600,-1664,M.black,M.black,'255 255 255 255');","// Mountain mesh covers the old black void; nav blocking is independent.\nbuildMountains();");
src=src.replaceAll("[X(158),Y(81),420]","[X(158),Y(61),460]");
src=src.replace("[X(153+i*3),Y(82),420]","[X(153+i*3),Y(61),460]");
src=src.replace("lightscale:'2.2'","lightscale:'3.5'").replace("ambientscale1:'1.8'","ambientscale1:'2.4'").replace("fow_darkness:'1.2'","fow_darkness:'0.6'");
src=src.replace('land,waters,entities:node-10','land,waters,markers,blockedAreas,mountainSamples,entities:node-10');
src=src.replace("fs.writeFileSync(path.join(OUT,'layout.json'),JSON.stringify(report,null,2));","fs.writeFileSync(path.join(OUT,'layout.json'),JSON.stringify(report,null,2));\nwritePreviewFiles(report);");
new Function('require','__dirname',src)(require,__dirname);
