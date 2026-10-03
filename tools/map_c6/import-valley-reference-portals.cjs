'use strict';
// Exact resource-only import for the local art preview; never executes Workshop Lua.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs');
const root=path.resolve(__dirname,'../..');
const pack=process.argv[2]||'D:/SteamLibrary/steamapps/workshop/content/570/3164617180/3164617180.vpk';
const p=new L.Vpk(pack),prefix='particles/imagine_assets/environments_fx/portal_fx/';
const names=['act2_portal','act2_portal_warp','act2_portal_warp_bottom','act2_portal_top','act2_portal_bottom','act2_portal_embers'];
const records=[];
for(const name of names){
 const resource=prefix+name+'.vpcf_c',bytes=p.read(resource),dest=path.join(root,resource);
 if(fs.existsSync(dest)&&!fs.readFileSync(dest).equals(bytes))throw Error('Refusing to overwrite differing resource: '+resource);
 fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,bytes);
 records.push({resource,bytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
}
const dest=path.join(root,'output/valley_path_identify');fs.mkdirSync(dest,{recursive:true});
fs.writeFileSync(path.join(dest,'portal_import.json'),JSON.stringify({workshop_id:'3164617180',pack,records,usage:'local valley_decor_review only; reference spawn binding is not independently verified'},null,2));
console.log({imported:records.length});
