'use strict';
// Preview-only exact VPK exports for native backgrounds used by the current baseline.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto'),{pathToFileURL}=require('node:url');
const {open}=require('../vpk_inspect.cjs');
const out='output/archive_user_skin_20261019',dest=out+'/native',report=JSON.parse(fs.readFileSync(out+'/report.json','utf8'));
const viewer=path.resolve('output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'),vpk=open(path.resolve('../../dota/pak01_dir.vpk'));
assertFile(viewer);fs.mkdirSync(dest,{recursive:true});
const prior=fs.existsSync(dest+'/manifest.json')?JSON.parse(fs.readFileSync(dest+'/manifest.json','utf8')):{aliases:{},records:[]},aliases=prior.aliases,records=prior.records;
const required=new Set();
for(const row of [...report.failureState.images,...report.failureState.backgrounds])if(!row.decoded){const match=decodeURIComponent(row.src).match(/\/(?:art\/ui\/sources|panorama\/src\/images)\/(.+\.png)$/);if(match)required.add(match[1]);}
for(const relative of required){
 if(!/^[A-Za-z0-9_/-]+\.png$/.test(relative)||relative.includes('..'))throw Error('Unexpected native URI '+relative);
 const stem=relative.slice(0,-4),resources=['panorama/images/'+stem+'_png.vtex_c','panorama/images/'+stem+'.vtex_c'],entry=vpk.entries.find(row=>resources.includes(row.path));
 if(!entry)throw Error('Missing native VPK asset: '+relative);
 const bytes=vpk.read(entry),input=path.resolve(dest,stem.replaceAll('/','_')+'.vtex_c'),png=input.replace(/\.vtex_c$/,'.png');fs.writeFileSync(input,bytes);
 if(!fs.existsSync(png))cp.execFileSync(viewer,['-i',input,'-o',png,'-d'],{windowsHide:true,stdio:'pipe'});assertFile(png);
 const local=pathToFileURL(png).href;for(const key of [relative,'file://{images}/'+relative,'s2r://'+entry.path.replace(/\.vtex_c$/,'.vtex')])aliases[key]=local;
 const data=fs.readFileSync(png),record={relative,resource:entry.path,resourceSha256:sha(bytes),previewPng:path.relative(process.cwd(),png).replaceAll('\\','/'),pngSha256:sha(data),width:data.readUInt32BE(16),height:data.readUInt32BE(20)};
 const index=records.findIndex(row=>row.relative===relative);if(index<0)records.push(record);else records[index]=record;
}
fs.writeFileSync(dest+'/manifest.json',JSON.stringify({kind:'exact_installed_dota_native_background_exports_preview_only',notProductionChange:true,aliases,records},null,2));
console.log('ARCHIVE_USER_SKIN_NATIVE_EXPORTED '+records.length);
function sha(bytes){return crypto.createHash('sha256').update(bytes).digest('hex');}
function assertFile(file){if(!fs.existsSync(file))throw Error('Required file unavailable: '+file);}
