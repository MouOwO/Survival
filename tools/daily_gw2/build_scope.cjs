'use strict';
// Scope only this presentation's production sources and every manifest PNG.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const repo=path.resolve(__dirname,'../..');
const sources=['scripts/custom_game/daily_remaining_5d5c1152eb.js','scripts/custom_game/daily_gw2_data.js','styles/custom_game/daily_gw2.css','layout/custom_game/archive.xml','layout/custom_game/daily_gw2_assets.xml'];
function build(){
 const manifest=JSON.parse(fs.readFileSync(path.join(__dirname,'asset_manifest.json'),'utf8'));
 const images=Object.entries(manifest.assets).map(([key,asset])=>{
  if(!/^art\/ui\/sources\/custom_game\/daily_gw2_v1\/[a-z0-9_]+\.png$/.test(asset.file))throw Error('Unexpected manifest asset path: '+key);
  const data=fs.readFileSync(path.join(repo,asset.file));
  if(crypto.createHash('sha256').update(data).digest('hex')!==String(asset.sha256).toLowerCase())throw Error('Manifest hash mismatch: '+key);
  if(data.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'||data.readUInt32BE(16)!==asset.size[0]||data.readUInt32BE(20)!==asset.size[1])throw Error('Manifest PNG size mismatch: '+key);
  return 'images/'+asset.file.slice('art/ui/sources/'.length);
 });
 if(!images.length||new Set(images).size!==images.length)throw Error('Manifest must contain unique PNG assets.');
 const scope=[...sources,...images.sort()];
 fs.writeFileSync(path.join(__dirname,'compile_scope.json'),JSON.stringify(scope,null,2)+'\n');
 console.log('DAILY_GW2_SCOPE_BUILT sources='+sources.length+' pngs='+images.length);
 return scope;
}
if(require.main===module)build();
module.exports={sources,build};
