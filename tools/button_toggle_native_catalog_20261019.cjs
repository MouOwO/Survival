'use strict';
// Decode selected installed Valve controls without changing production resources.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const {open}=require('./vpk_inspect.cjs');
const repo=path.resolve(__dirname,'..'),base=path.join(repo,'design_refs/button_toggle_catalog_20261019'),out=path.join(base,'native');
const viewer=path.join(repo,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
const vpkFile=path.resolve(repo,'../../dota/pak01_dir.vpk'),vpk=open(vpkFile),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const usage=new Map();
function scan(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){const file=path.join(dir,entry.name);if(entry.isDirectory())scan(file);else if(/\.(js|css|xml)$/.test(file)){const source=fs.readFileSync(file,'utf8'),regex=/(?:s2r:\/\/|file:\/\/\{images\}\/)[^\s'";)]+/g;let m;while((m=regex.exec(source))){const uri=m[0];if(!usage.has(uri))usage.set(uri,[]);const evidence={file:path.relative(repo,file).replaceAll('\\','/'),line:source.slice(0,m.index).split('\n').length};if(!usage.get(uri).some(x=>x.file===evidence.file&&x.line===evidence.line))usage.get(uri).push(evidence);}}}}
scan(path.join(repo,'panorama/src'));
const crownfall=vpk.entries.filter(e=>e.path.startsWith('panorama/images/events/crownfall/buttons/')&&!e.path.includes('/emblem_')).map(e=>e.path);
const names=['arrow_dropdown_png','arrow_dropdown_up_png','arrow_dropdown_disabled_png','arrow_left_png','arrow_right_png','check_png','check_gradient_png','check_shadow_png','checkbox_check_psd','close_png','plus_png','plus_gradient_png','plus_thin_png','icon_search_png','icon_search_shadow_psd','x_close_png','x_close_white_psd'];
const resources=[...crownfall,...['background_play_button_2x_png','background_play_button_large_2x_png'].map(n=>'panorama/images/backgrounds/'+n+'.vtex_c'),...names.map(n=>'panorama/images/control_icons/'+n+'.vtex_c'),'panorama/images/control_icons/24px/plus.vsvg_c','panorama/images/spellicons/skeleton_king_reincarnation_png.vtex_c','panorama/images/spellicons/tinker_rearm_png.vtex_c'];
fs.mkdirSync(out,{recursive:true});
const records=[];
for(const resource of resources){
 const entry=vpk.entries.find(e=>e.path===resource);if(!entry)throw Error('Missing selected native asset: '+resource);
 const vector=resource.endsWith('.vsvg_c'),bytes=vpk.read(entry),stem=resource.replace(/^panorama\/images\//,'').replace(/\.(vtex|vsvg)_c$/,'').replaceAll('/','__');
 const input=path.join(out,stem+(vector?'.vsvg_c':'.vtex_c')),preview=path.join(out,stem+(vector?'.svg':'.png'));
 fs.writeFileSync(input,bytes);cp.execFileSync(viewer,['-i',input,'-o',preview,'-d'],{windowsHide:true,stdio:'pipe'});
 if(!fs.existsSync(preview))throw Error('Native decode did not produce '+path.basename(preview));
 const decoded=fs.readFileSync(preview),relative=resource.replace(/^panorama\/images\//,'').replace(/_png\.vtex_c$/,'.png').replace(/_psd\.vtex_c$/,'.psd').replace(/\.vsvg_c$/,'.svg');
 const aliases=vector?['file://{images}/'+relative,'s2r://panorama/images/'+relative.replace(/\.svg$/,'.vsvg')]:['s2r://'+resource.slice(0,-2),'file://{images}/'+relative,'s2r://panorama/images/'+relative];
 const references=aliases.flatMap(uri=>(usage.get(uri)||[]).map(e=>({uri,...e})));
 const width=vector?Number((decoded.toString().match(/\bwidth="([\d.]+)/)||[])[1]||24):decoded.readUInt32BE(16),height=vector?Number((decoded.toString().match(/\bheight="([\d.]+)/)||[])[1]||24):decoded.readUInt32BE(20);
 records.push({id:'N'+String(records.length+1).padStart(2,'0'),uri:references[0]?.uri||aliases[0],aliases,vpk_entry:resource,png_local:vector?null:path.relative(repo,preview).replaceAll('\\','/'),svg_local:vector?path.relative(repo,preview).replaceAll('\\','/'):null,dimensions:{width,height},sourceSHA:sha(bytes),previewSHA:sha(decoded),status:references.length?'used_in_project':'native_available',usage:references.length?'项目源码已有静态引用':'本机官方同目录备选，当前项目未引用',evidence:references,method:vector?'Source2Viewer exact vector decompile; no visual edits':'Source2Viewer exact texture decode; no resizing, redrawing, or visual edits'});
}
const manifest={kind:'selected_installed_dota_controls',productionFilesChanged:false,sourceArchive:vpkFile,selection:'Static project references plus nearby official Crownfall button and basic control alternatives. Not a complete inventory of every Dota resource.',records};
fs.writeFileSync(path.join(base,'native_manifest.json'),JSON.stringify(manifest,null,2));
console.log(JSON.stringify({status:'PASS',count:records.length,used:records.filter(r=>r.status==='used_in_project').map(r=>({id:r.id,uri:r.uri,dimensions:r.dimensions})),manifest:'design_refs/button_toggle_catalog_20261019/native_manifest.json'}));
