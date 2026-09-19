// Entity-only pass: safe for a manually saved Hammer map. Does not regenerate
// meshes, paint, navigation, gameplay markers or editor metadata.
const fs=require('fs'),path=require('path'),L=require('./lib.cjs');
const old={min:[-80.6833,-87.9808,-17.859253],max:[84.8251,69.1202,8.859245]};
const variants=[
 {name:'classical_ivy002',min:[-43.46686,-84.8801,-7.562992],max:[43.46686,79.709305,33.675],triangles:136},
 {name:'classical_ivy004',min:[-47.684597,-95.899155,-22.554504],max:[47.3822,96.37715,35.1895],triangles:128}
];
function property(t,key,val){
 if(L.value(t,key)!==undefined)return L.setValue(t,key,val);
 const p=t.indexOf('"entity_properties"'),a=t.indexOf('{',p),e=L.endOf(t,a)-1;
 return t.slice(0,e)+'\n"'+key+'" "string" "'+val+'"\n'+t.slice(e);
}
// Source QAngle: yaw around Z, pitch around Y, roll around X.
function rotate(v,angles){
 const [p,y,r]=angles.map(a=>a*Math.PI/180),[x0,y0,z0]=v;
 const y1=y0*Math.cos(r)-z0*Math.sin(r),z1=y0*Math.sin(r)+z0*Math.cos(r);
 const x2=x0*Math.cos(p)+z1*Math.sin(p),z2=-x0*Math.sin(p)+z1*Math.cos(p);
 return [x2*Math.cos(y)-y1*Math.sin(y),x2*Math.sin(y)+y1*Math.cos(y),z2];
}
function optimize(text){
 const stats={ivyReplaced:0,ivyTrianglesBefore:0,ivyTrianglesAfter:0,smallPlantShadowsDisabled:0,previewActorsEditorOnly:0};
 const edits=[];
 for(const b of L.blocks(text,'CMapEntity')){
  let t=b.text;const cls=L.value(t,'classname'),model=L.value(t,'model')||'';
  if(cls==='prop_static'&&model==='models/props_nature/ivy_128a.vmdl'){
   const next=variants[stats.ivyReplaced%variants.length];
   const origin=L.value(t,'origin').split(/\s+/).map(Number),angles=L.value(t,'angles').split(/\s+/).map(Number);
   const scale=L.value(t,'scales').split(/\s+/).map(Number);
   const ns=scale.map((s,i)=>s*(old.max[i]-old.min[i])/(next.max[i]-next.min[i]));
   const delta=rotate(scale.map((s,i)=>s*old.min[i]-ns[i]*next.min[i]),angles);
   t=L.setValue(t,'origin',origin.map((v,i)=>(v+delta[i]).toFixed(8)).join(' '));
   t=L.setValue(t,'scales',ns.map(v=>v.toFixed(8)).join(' '));
   t=L.setValue(t,'model','models/props_nature/'+next.name+'.vmdl');
   stats.ivyReplaced++;stats.ivyTrianglesBefore+=2084;stats.ivyTrianglesAfter+=next.triangles;
  }
  if(cls==='prop_static'&&/^models\/props_nature\/(?:bush|fern|grass_clump|flowers|petals|leaf_pile|ivy_|classical_ivy|plant\d|mushroom)/.test(model)){
   if(L.value(t,'disableshadows')!=='1'){t=property(t,'disableshadows','1');stats.smallPlantShadowsDisabled++;}
  }
  // These unnamed, non-solid figures are generated room scale references,
  // not NPC spawners. Retain them in Hammer, exclude them from the game build.
  if(cls==='prop_dynamic'&&!L.value(t,'targetname')&&L.value(t,'solid')==='0'&&
   /^(?:models\/heroes\/axe\/axe|models\/creeps\/neutral_creeps\/n_creep_golem_a\/neutral_creep_golem_a)\.vmdl$/.test(model)&&
   L.value(t,'editorOnly')!=='1'){
   t=L.setValue(t,'editorOnly','1');stats.previewActorsEditorOnly++;
  }
  if(t!==b.text)edits.push({...b,replacement:t});
 }
 const parts=[];let cursor=0;
 for(const e of edits){parts.push(text.slice(cursor,e.start),e.replacement);cursor=e.end;}
 parts.push(text.slice(cursor));text=parts.join('');
 return {text,stats};
}
if(require.main===module){
 const [input,output]=process.argv.slice(2);if(!input||!output)throw Error('Usage: node optimize-scene.cjs input_text.vmap output_text.vmap');
 if(path.resolve(input)===path.resolve(output))throw Error('Keep the input as a backup; output must differ');
 const result=optimize(fs.readFileSync(input,'utf8'));
 fs.writeFileSync(output,result.text);fs.writeFileSync(output+'.optimization.json',JSON.stringify(result.stats,null,2));
 console.log(JSON.stringify(result.stats));
}
module.exports={optimize,rotate,variants};
