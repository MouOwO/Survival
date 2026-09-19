const fs=require('fs'),path=require('path'),{open}=require('./vpk_inspect.cjs');
const native=open('D:/steam/steamapps/common/dota 2 beta/game/dota/pak01_dir.vpk');
const names=new Set(native.entries.map(e=>e.path));
const usage=JSON.parse(fs.readFileSync('output/reference_asset_study/asset_usage.json','utf8'));
const models=Object.entries(usage).filter(([p])=>p.endsWith('.vmdl')).map(([p,count])=>({path:p,count,native:names.has(p+'_c')})).sort((a,b)=>b.count-a.count);
fs.writeFileSync('output/reference_asset_study/native_resource_audit.json',JSON.stringify(models,null,2));
console.log(JSON.stringify({uniqueModels:models.length,nativeModels:models.filter(a=>a.native).length,mostUsed:models.slice(0,15)},null,2));
