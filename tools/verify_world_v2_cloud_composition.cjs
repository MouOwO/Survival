const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert/strict');
const out=path.resolve(__dirname,'../output/survival_world_v2'),before=fs.readFileSync(path.join(out,'before_cloud_integration_v2/survival_world_v2.vmap'),'utf8'),after=fs.readFileSync(path.join(out,'survival_world_v2.vmap'),'utf8');
const checks=[];
for(const name of ['verticesHeight','verticesWater','gridnavFlags','cellsTileSet','cellsHidden']){
 const re=new RegExp('"'+name+'"\\s+"\\w+_array"\\s*\\[([^\\]]*)\\]');
 const a=before.match(re),b=after.match(re);assert(a&&b,'Missing grid array '+name);assert.equal(b[1],a[1],name+' changed');
 checks.push({name,unchanged:true,sha256:crypto.createHash('sha256').update(b[1]).digest('hex')});
}
const art=JSON.parse(fs.readFileSync(path.join(out,'cultivation_design.json')));
assert(art.outer.length<=24&&art.inner.length<=18);
for(const group of ['outer','inner'])for(const [i,c]of art[group].entries()){
 assert(c.projectedClearance>=180,'Gameplay visibility clearance failed');
 const name='cloud_bank_'+group+'_'+String(i).padStart(2,'0');
 const particle=fs.readFileSync(path.join(out,'source_particles',name+'.vpcf'),'utf8');
 assert(/m_nMaxParticles\s*=\s*1\b/.test(particle));assert(c.r<=3100,'Cloud magnified beyond authored outer limit');
 assert(after.includes('particles/survival_world_v2/'+name+'.vpcf'));
}
assert(!/morning_(billows|ribbon)/.test(after),'Old cloud textures referenced');
const result={grid:checks,outer:art.outer.length,inner:art.inner.length,textureVariants:[...new Set([...art.outer,...art.inner].map(c=>c.texture))],minimumProjectedClearance:Math.min(...[...art.outer,...art.inner].map(c=>c.projectedClearance)),backgroundOutsideGameplayGrid:art.background.innerHalfExtent>=16256,pass:true};
fs.writeFileSync(path.join(out,'cloud_composition_validation.json'),JSON.stringify(result,null,2));console.log(result);
