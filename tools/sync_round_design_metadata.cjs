// Keep design records consistent with the already-authored 400 water surface.
const fs=require('fs'),path=require('path');const root=path.resolve(__dirname,'..'),out=path.join(root,'output/survival_world_v2');
const replacements={
 'tools/world_v2_original_island.cjs':[['const levels={water:416','const levels={water:400']],
 'tools/build_survival_world_v2.cjs':[["polygon:cross,z:416,shallow:true","polygon:cross,z:400,shallow:true"]],
 'tools/survival_world_v2_surface.cjs':[["mainIsland:'four rotated original U islands'","mainIsland:'four rounded meadow islands around a small circular shallow lake'"],['waterZ:416,transitionWidth:760','waterZ:400,transitionWidth:1080']]
};
for(const [file,edits]of Object.entries(replacements)){const p=path.join(root,file);let s=fs.readFileSync(p,'utf8');for(const [a,b]of edits)s=s.replace(a,b);fs.writeFileSync(p,s);}
for(const [file,edit]of Object.entries({
 'island_levels_design.json':o=>{o.water=400;},
 'surface_design.json':o=>{o.mainIsland='four rounded meadow islands around a small circular shallow lake';o.waterZ=400;o.transitionWidth=1080;},
 'layout.json':o=>{for(const w of o.waters||[])if(w.name==='central_cross_shallows')w.z=400;}
})){const p=path.join(out,file),o=JSON.parse(fs.readFileSync(p,'utf8'));edit(o);fs.writeFileSync(p,JSON.stringify(o,null,2));}
console.log('Round island metadata synchronized; no geometry changed.');
