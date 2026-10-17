'use strict';
// Read-only audit of installed native resources and the maintained item table.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {open}=require('../vpk_inspect.cjs');
const root=path.resolve(__dirname,'../..');process.chdir(root);
const out='output/daily_native_icons_20261017';
const bytes=fs.readFileSync('data/ui/item_resources.json'),data=JSON.parse(bytes),daily=data.items.filter(row=>row.id.startsWith('daily_'));
const vpk=open(path.resolve('../../dota/pak01_dir.vpk')),entries=new Map(vpk.entries.map(entry=>[entry.path,entry]));
assert.equal(daily.length,12);
const native=JSON.parse(fs.readFileSync(out+'/manifest.json','utf8'));
const records=daily.map(row=>{
 assert.equal(row.native_type,'item');assert.equal(row.fit,'contain');
 assert.equal(row.uri,'file://{images}/items/'+row.native_name+'.png');
 const resource='panorama/images/items/'+row.native_name+'_png.vtex_c',entry=entries.get(resource);
 assert(entry,'Installed Dota resource exists: '+resource);
 const sourceSha256=crypto.createHash('sha256').update(vpk.read(entry)).digest('hex');
 const exported=native.records.find(asset=>asset.uri===row.uri);
 assert(exported,'Reviewed original PNG exists: '+row.id);
 assert.equal(sourceSha256,exported.source_sha256);assert.deepEqual(row.source_size,[exported.width,exported.height]);
 assert.equal(crypto.createHash('sha256').update(fs.readFileSync(exported.png)).digest('hex'),exported.png_sha256);
 return {id:row.id,name:row.name,uri:row.uri,resource,sourceSize:row.source_size,sourceSha256,fit:row.fit};
});
const beforeFile=out+'/registry_before.json';let scope;
if(fs.existsSync(beforeFile)){
 const before=JSON.parse(fs.readFileSync(beforeFile,'utf8'));
 assert.deepEqual(data.items.filter(row=>!row.id.startsWith('daily_')),before.items.filter(row=>!row.id.startsWith('daily_')));
 const stable=['id','name','kind','aliases','quality','category_id'];
 for(const row of daily){const old=before.items.find(item=>item.id===row.id);for(const key of stable)assert.deepEqual(row[key],old[key],row.id+': '+key);}
 scope={otherResourcesUnchanged:data.items.length-daily.length,rewardNamesAndIdentitiesUnchanged:true};
}
const report={status:'PASS_DAILY_NATIVE_RESOURCES',registrySha256:crypto.createHash('sha256').update(bytes).digest('hex'),items:data.items.length,...scope,records};
fs.mkdirSync(out,{recursive:true});fs.writeFileSync(out+'/resource_audit.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({status:report.status,verifiedNativeResources:records.length,...scope}));
