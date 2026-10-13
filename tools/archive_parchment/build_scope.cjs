'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const repo=path.resolve(__dirname,'../..'),manifest=JSON.parse(fs.readFileSync(path.join(__dirname,'asset_manifest.json'),'utf8'));
const sources=['scripts/custom_game/archive_v10.js','scripts/custom_game/archive_v10_semantics.js','scripts/custom_game/archive_parchment_data.js','styles/custom_game/archive_v10.css','layout/custom_game/archive.xml','layout/custom_game/archive_parchment_assets.xml'];
const images=Object.entries(manifest.assets).map(([key,asset])=>{
 if(!/^art\/ui\/sources\/custom_game\/archive_parchment_v1\/[a-z0-9_]+\.png$/.test(asset.file))throw Error('Unexpected manifest asset path: '+key);
 const data=fs.readFileSync(path.join(repo,asset.file)),digest=crypto.createHash('sha256').update(data).digest('hex');
 if(digest.toLowerCase()!==String(asset.sha256).toLowerCase())throw Error('Manifest hash mismatch: '+key);
 if(data.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'||data.readUInt32BE(16)!==asset.size[0]||data.readUInt32BE(20)!==asset.size[1])throw Error('Manifest PNG size mismatch: '+key);
 return 'images/'+asset.file.slice('art/ui/sources/'.length);
});
if(!images.length||new Set(images).size!==images.length)throw Error('Manifest must list unique PNG assets.');
fs.writeFileSync(path.join(__dirname,'compile_scope.json'),JSON.stringify([...sources,...images.sort()],null,2)+'\n');
console.log('ARCHIVE_PARCHMENT_SCOPE_BUILT sources='+sources.length+' pngs='+images.length);
