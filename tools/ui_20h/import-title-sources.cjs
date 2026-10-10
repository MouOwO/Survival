'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert');
const from=path.resolve('../../../content/dota_addons/Survival/panorama/images/custom_game/titles'),to='art/ui/sources/custom_game/titles',records=[];
fs.mkdirSync(to,{recursive:true});
for(const name of fs.readdirSync(from).filter(name=>/\.(png|svg)$/.test(name))){
 const original=fs.readFileSync(path.join(from,name)),file=to+'/'+name;
 if(fs.existsSync(file))assert(fs.readFileSync(file).equals(original),'Existing title asset differs: '+name);else fs.writeFileSync(file,original);
 const suffix=name.endsWith('.svg')?'.vsvg_c':'_png.vtex_c',runtime='panorama/images/custom_game/titles/'+name.replace(/\.(png|svg)$/,suffix),compiled=fs.existsSync(runtime)?runtime:null;
 records.push({source:file,original:path.join(from,name),compiled,sha256:crypto.createHash('sha256').update(original).digest('hex'),bytes:original.length,policy:'Merged content asset, copied only when missing; pixels unchanged'});
}
fs.writeFileSync('design_refs/ui_20h/work/feedback10/title_sources.json',JSON.stringify(records,null,2));console.log('TITLE_SOURCES_PRESERVED '+records.length+' original assets');
