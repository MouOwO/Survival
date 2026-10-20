'use strict';
// Exact installed Valve resources, exported only for the offline browser.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process'),{pathToFileURL}=require('node:url');
const {open}=require('../vpk_inspect.cjs');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'output/lottery_light_controls_20261018/native_preview');
const viewer=path.join(repo,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
const vpk=open(path.resolve(repo,'../../dota/pak01_dir.vpk')),records=[],aliases={};
const rows=[
 {resource:'panorama/images/control_icons/24px/plus.vsvg_c',name:'plus',kind:'svg',aliases:['control_icons/24px/plus.svg','file://{images}/control_icons/24px/plus.svg']},
 {resource:'panorama/images/icon_ticket_png.vtex_c',name:'icon_ticket',kind:'png',aliases:['icon_ticket.png','file://{images}/icon_ticket.png','s2r://panorama/images/icon_ticket_png.vtex']}
];
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
fs.mkdirSync(out,{recursive:true});
for(const row of rows){
 const entry=vpk.entries.find(x=>x.path===row.resource);if(!entry)throw Error('Installed resource is missing: '+row.resource);
 const bytes=vpk.read(entry),input=path.join(out,row.name+path.extname(row.resource)),exported=path.join(out,row.name+'.'+row.kind);
 fs.writeFileSync(input,bytes);
 if(row.kind==='svg'){
  const start=bytes.indexOf('<svg'),end=bytes.indexOf('</svg>',start);if(start<0||end<start)throw Error('Compiled vector has no verbatim SVG payload');
  fs.writeFileSync(exported,bytes.subarray(start,end+6));
 }else{
  cp.execFileSync(viewer,['-i',input,'-o',exported,'-d'],{windowsHide:true,stdio:'pipe'});
 }
 if(!fs.existsSync(exported))throw Error('Native preview conversion failed: '+row.resource);
 const decoded=fs.readFileSync(exported),record={resource:row.resource,sourceSha256:sha(bytes),previewPath:path.relative(repo,exported).replaceAll('\\','/'),previewSha256:sha(decoded),method:row.kind==='svg'?'verbatim SVG payload from installed VSVG':'Source2Viewer texture decode; no edits or resampling'};
 if(row.kind==='png'){record.width=decoded.readUInt32BE(16);record.height=decoded.readUInt32BE(20);}
 records.push(record);for(const alias of row.aliases)aliases[alias]=pathToFileURL(exported).href;
}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({kind:'exact_installed_native_resources_for_offline_lottery_only',records,aliases},null,2)+'\n');
console.log('LOTTERY_NATIVE_PREVIEW_PASS '+records.length+' exact installed resources');
