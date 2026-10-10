'use strict';
// Import existing source counterparts of the shipped textures; never infer obsolete assets.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const repo=process.cwd(),content=path.resolve(repo,'../../../content/dota_addons/Survival');
const runtime='panorama/images/custom_game/reward_art_v5',destination='art/ui/sources/custom_game/reward_art_v5',records=[];
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
fs.mkdirSync(destination,{recursive:true});
for(const file of fs.readdirSync(runtime).filter(x=>x.endsWith('.vtex_c'))){
 const definition=path.join(content,'panorama/images/custom_game/reward_art_v5',file.replace(/\.vtex_c$/,'.vtex'));
 const text=fs.readFileSync(definition,'utf8'),input=text.match(/"m_fileName"\s+"string"\s+"([^"]+)"/);
 if(!input)throw Error('No source texture input '+file);
 const source=path.resolve(content,input[1]);if(!source.startsWith(content+path.sep))throw Error('Source escaped addon content');
 for(const [src,dest]of [[definition,destination+'/'+path.basename(definition)],[source,destination+'/'+path.basename(source)]]){
  const bytes=fs.readFileSync(src),normalized=dest.endsWith('.vtex')?Buffer.from(bytes.toString('utf8').replaceAll('\r\n','\n')):bytes;
  if(fs.existsSync(dest)&&!fs.readFileSync(dest).equals(normalized)){
   if(!dest.endsWith('.vtex')||fs.readFileSync(dest,'utf8').replaceAll('\r\n','\n')!==normalized.toString('utf8'))throw Error('Existing project artwork differs '+dest);
  }
  fs.writeFileSync(dest,normalized);
  records.push({source:dest,sha256:hash(dest),originalSha256:hash(src),runtime:runtime+'/'+file,origin:'Existing Workshop source; PNG bytes preserved, texture definitions use repository LF endings'});
 }
}
fs.writeFileSync('design_refs/ui_20h/Delivery/recovered_sources.json',JSON.stringify({at:new Date().toISOString(),records},null,2));
console.log('UI20H_GAME_ASSET_SOURCES_RECOVERED',records.length,'source files for',records.length/2,'textures');
