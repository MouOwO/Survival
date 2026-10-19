'use strict';
// Restore only the exact Valve components used by this review package.
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..'),cache=path.join(root,'output/lottery_native_concepts_20261019/assets');
const rows=JSON.parse(fs.readFileSync(path.join(__dirname,'native_assets.json'),'utf8')).records;
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
let vpk,restored=0;
for(const row of rows){
 const target=path.resolve(root,row.path);
 if(!target.startsWith(cache+path.sep))throw Error('Asset must stay inside this concept cache');
 if(fs.existsSync(target)&&sha(fs.readFileSync(target))===row.pngSha256)continue;
 if(!vpk)vpk=require('../vpk_inspect.cjs').open(path.resolve(root,'../../dota/pak01_dir.vpk'));
 const entry=vpk.entries.find(e=>e.path===row.resource);if(!entry)throw Error('Missing installed Valve asset '+row.resource);
 const bytes=vpk.read(entry);if(sha(bytes)!==row.sha256)throw Error('Installed Valve asset changed; review before refreshing '+row.resource);
 fs.mkdirSync(path.dirname(target),{recursive:true});const compiled=target.replace(/\.png$/,'.vtex_c');fs.writeFileSync(compiled,bytes);
 const cli=process.env.SOURCE2VIEWER_CLI||path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
 if(!fs.existsSync(cli))throw Error('Set SOURCE2VIEWER_CLI to the local Source2Viewer CLI executable');
 cp.execFileSync(cli,['-i',compiled,'-o',target,'-d'],{windowsHide:true,stdio:'pipe'});
 if(sha(fs.readFileSync(target))!==row.pngSha256)throw Error('Decoded native image differs '+row.resource);restored++;
}
console.log('NATIVE_CONCEPT_ASSETS_PASS '+rows.length+' exact Valve components, '+restored+' restored');
