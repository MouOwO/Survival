'use strict';
// Check real compile results and identity preservation, not synthetic color samples.
const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto'),path=require('path');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/shop_icon_quality_20261017');
const read=f=>JSON.parse(fs.readFileSync(path.join(root,f),'utf8').replace(/^\uFEFF/,'')),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const table=read('data/ui/item_resources.json'),rows=new Map(table.items.map(r=>[r.id,r]));
const first=read('output/shop_icon_quality_20261017/resource_changes.json').changed,second=read('output/shop_icon_quality_20261017/market_resource_changes.json').changes,last=read('output/shop_icon_quality_20261017/recharge_resource_change.json');
const all=[...first,...second,{id:last.id,before:last.before,after:last.after}],allowed=new Set(['kind','uri','source_size','native_type','native_name']);
for(const c of all){assert.deepEqual(rows.get(c.id),c.after,'Final exact selected row '+c.id);const before=Object.fromEntries(Object.entries(c.before).filter(([k])=>!allowed.has(k))),after=Object.fromEntries(Object.entries(c.after).filter(([k])=>!allowed.has(k)));assert.deepEqual(before,after,'Identity, aliases and unrelated metadata preserved: '+c.id);}
const plan=read('output/shop_icon_quality_20261017/texture_plan.json'),compiled=read('output/shop_icon_quality_20261017/native_compiled/manifest.json');
for(const p of plan.textures){assert.equal(sha(fs.readFileSync(path.join(root,p.sourcePng))),p.sourcePngSha256,'Original source pixels untouched '+p.id);assert.equal(sha(fs.readFileSync(path.join(root,p.recipe))),p.recipeSha256,'Reviewed recipe unchanged '+p.id);const c=compiled.records.find(r=>r.id===p.id);assert(c);assert(Math.min(c.width,c.height)>=p.expectedMinimumDimension);assert.equal(c.format,28);assert.equal(c.mipLevels,1);assert.equal(c.noLod,true);}
const audit=read('output/shop_icon_quality_20261017/audit.json');assert.equal(audit.status,'PASS');assert.equal(audit.counts.listedSourceUnder128,0);assert.equal(audit.registryHash,sha(fs.readFileSync(path.join(root,'data/ui/item_resources.json'))));
const js=fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/common/item_resources.js'),'utf8');assert(js.includes(audit.registryHash),'Generated JS and maintained table match');
const result={status:'PASS',registryHash:audit.registryHash,changedArtworkRows:all.length,identitiesAndAliasesRetained:true,unmodifiedOriginalSourcePNGs:plan.textures.length,actualCompiledTextureDimensions:compiled.records.map(r=>({id:r.id,width:r.width,height:r.height,format:r.format,mips:r.mipLevels,noLod:r.noLod})),marketplaceListed:audit.counts.marketplaceListed,listedSourceUnder128:0,coveredShopChallengeAndResearchRows:audit.rows.filter(r=>r.listed).length};
fs.writeFileSync(path.join(out,'resource_validation.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));
