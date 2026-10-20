'use strict';
// Offline assembly only. Real XML/JS/CSS and repository CSV, no game/account IO.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process'),{pathToFileURL}=require('node:url');
const repo=path.resolve(__dirname,'../..'),arg=process.argv.indexOf('--out'),out=path.resolve(repo,arg<0?'output/lottery_fullscreen_20261018/preview':process.argv[arg+1]);
if(!out.startsWith(path.join(repo,'output/lottery_fullscreen_20261018')+path.sep))throw Error('Lottery preview output must stay in its task output folder.');
process.chdir(repo);
const child=spawnSync(process.execPath,['tools/menus_v10/preview.cjs','--out',out],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);if(child.stderr)process.stderr.write(child.stderr);if(child.status!==0)throw Error('Active production assembly failed.');
const entry=path.join(out,'index.html');let html=fs.readFileSync(entry,'utf8');
// The shared legacy converter drops the wrong token for color-first native
// text shadows. Rebuild only those declarations from each frozen stylesheet;
// all authored offsets, blur, colors and shadow layers remain unchanged.
const styleFile=path.join(out,'style.css');let previewCSS=fs.readFileSync(styleFile,'utf8');
previewCSS=previewCSS.replace(/(\/\* (styles\/[^\n]+\.css) \*\/\n)([\s\S]*?)(?=\/\* styles\/|$)/g,(_,marker,rel,body)=>{
 const native=fs.readFileSync(path.join(repo,'panorama/src',rel),'utf8'),shadows=[...native.matchAll(/text-shadow:\s*([^;]+)/g)].map(match=>match[1]);let index=0;
 body=body.replace(/text-shadow:\s*([^;]+)/g,()=>{const value=shadows[index++];if(value===undefined)throw Error('Text shadow declaration count mismatch '+rel);return 'text-shadow:'+value.split(',').flatMap(part=>{const strength=part.match(/(-?[\d.]+px\s+-?[\d.]+px\s+[\d.]+px)\s+([\d.]+)(?=\s|$)/),converted=part.trim().replace(/(-?[\d.]+px\s+-?[\d.]+px\s+[\d.]+px)\s+[\d.]+(?=\s|$)/,'$1');return Array.from({length:strength?Math.max(1,Math.ceil(Number(strength[2]))):1},()=>converted);}).join(',');});
 if(index!==shadows.length)throw Error('Missing text shadow declaration '+rel);return marker+body;
});fs.writeFileSync(styleFile,previewCSS);
function replaceObject(prefix,suffix,fn){const start=html.indexOf(prefix)+prefix.length,end=html.indexOf(suffix,start);if(start<prefix.length||end<start)throw Error('Missing snapshot marker '+prefix);const original=JSON.parse(html.slice(start,end));html=html.slice(0,start)+JSON.stringify(fn(original)).replaceAll('</script','<\\/script')+html.slice(end);}
const allow=new Set(['common/item_resources','ui_snapshot_cache','common/ui_typography','common/ui_registry','common/ui_components','common/reward_feedback','common/tooltip_dismiss','ui_layers','archive_v10_data','common/menu_v10','common/purple_shell','reward_presentation','native_ui_icons','item_art_remaining_5d5c1152eb','reference_windows','remaining_5d5c1152eb','lottery_scene_transition','lottery_handoff_bb9968eef7','lottery_cinematic_v1','lottery_ui_remaining_5d5c1152eb','lottery_gw2_data','lottery_gw2'].map(x=>'scripts/custom_game/'+x+'.js'));
// The actual lottery tooltip reuses the market's shared frame renderer.
['black_lion_market_model','black_lion_market'].forEach(name=>allow.add('scripts/custom_game/'+name+'.js'));
let activeScripts=[],excluded=[];
replaceObject('window.PREVIEW_LAYOUTS=',';window.PREVIEW_SOURCES=',layouts=>{const hud=layouts.find(x=>x.rel==='layout/custom_game/survival_hud.xml');if(!hud)throw Error('Active lottery HUD absent');excluded=hud.scripts.filter(x=>!allow.has(x));hud.scripts=hud.scripts.filter(x=>allow.has(x));activeScripts=hud.scripts;for(const name of ['lottery_gw2.js','lottery_ui_remaining_5d5c1152eb.js'])if(!hud.scripts.some(x=>x.endsWith('/'+name)))throw Error('Missing active production '+name);return [hud];});
replaceObject('window.PREVIEW_SOURCES=',';window.PREVIEW_FIXTURE=',sources=>{for(const key of Object.keys(sources))if(key.endsWith('.js')&&!allow.has(key))delete sources[key];return sources;});
const nativeManifestPath=path.join(repo,'output/lottery_light_controls_20261018/native_preview/manifest.json');
if(!fs.existsSync(nativeManifestPath))throw Error('Export the installed lottery native preview resources before building this preview.');
const nativeManifestBytes=fs.readFileSync(nativeManifestPath),nativeManifest=JSON.parse(nativeManifestBytes);
for(const record of nativeManifest.records){const bytes=fs.readFileSync(path.join(repo,record.previewPath));if(crypto.createHash('sha256').update(bytes).digest('hex')!==record.previewSha256)throw Error('Native preview bytes drifted: '+record.resource);}
replaceObject('window.PREVIEW_ASSET_PATHS=',';window.PREVIEW_BASELINE=',assets=>Object.assign(assets,nativeManifest.aliases));
// The generic adapter resolves file-image aliases. Its CSS transport also needs
// these exact registered s2r backgrounds; the production scripts stay intact.
const adapterTag='<script src="'+pathToFileURL(path.join(repo,'tools/archive_v10/adapter.js')).href+'"></script>';
if(!html.includes(adapterTag))throw Error('Reusable browser adapter entry unavailable');
html=html.replace(adapterTag,adapterTag+'<script>const lotteryNativeCSSValue=cssValue;cssValue=function(value){return lotteryNativeCSSValue(typeof value==="string"?value.replace(/s2r:\\/\\/panorama\\/images\\/[^"\')\\s]+/g,uri=>PREVIEW_ASSET_PATHS[uri]||uri):value);};</script>');
const stateUrl=pathToFileURL(path.join(repo,'tools/menus_v10/state.js')).href,newState=pathToFileURL(path.join(repo,'tools/lottery_final_20261018/state.js')).href;
if(!html.includes('<script src="'+stateUrl+'"></script>'))throw Error('Reusable state entry unavailable');
html=html.replace('<script src="'+stateUrl+'"></script>','<script src="'+newState+'"></script>').replace(/<title>[^<]*<\/title>/,'<title>最终抽奖 · 生产组件离线预览</title>').replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1最终抽奖 · 实际 XML / JS / CSS · CSV 奖池 · 余额/资格为离线样例 · 无游戏或账户连接$2');
const movieTransport=fs.readFileSync(path.join(__dirname,'movie_transport.js'),'utf8').replace('__LOTTERY_MOVIE_PATHS__',JSON.stringify(Object.fromEntries(['map','cultivation','dragon_knight','summer'].map(id=>[id,pathToFileURL(path.join(repo,'panorama/videos/custom_game/lottery_cinematic_v1/'+id+'.webm')).href]))));
html=html.replace(adapterTag,adapterTag+'<script>'+movieTransport+'</script>');
const maskPath='art/ui/sources/custom_game/lottery_final_v1/scene_blend.svg',maskBytes=fs.existsSync(maskPath)?fs.readFileSync(maskPath):null;
// Chrome rejects external file: CSS masks as cross-origin. Embed the exact
// authored SVG bytes for this offline transport only; the mask is unchanged.
if(maskBytes)html=html.replace('window.PREVIEW_BASELINE=','window.LOTTERY_PREVIEW_MASK_URI='+JSON.stringify('data:image/svg+xml;base64,'+maskBytes.toString('base64'))+';window.PREVIEW_BASELINE=');
// The production font registry has both faces. Load the existing medium font in
// this browser adapter too; this does not alter the game's font configuration.
const medium=path.join(repo,'panorama/fonts/SourceHanSansSC-Medium.otf');
if(fs.existsSync(medium))html=html.replace('</style>','@font-face{font-family:"Source Han Sans SC";font-weight:500;src:url("'+pathToFileURL(medium).href+'")}\n</style>');
fs.writeFileSync(entry,html);
const file=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(file,'utf8'));
assembly.kind='lottery_fullscreen_production_component_browser_preview';assembly.gameVerified=false;assembly.activeScripts=activeScripts;assembly.excludedScripts=excluded;assembly.sourceGraph=assembly.sourceGraph.filter(x=>!x.path.endsWith('.js')||allow.has(x.path));
assembly.nativePreviewResources={manifest:path.relative(repo,nativeManifestPath).replaceAll('\\','/'),sha256:crypto.createHash('sha256').update(nativeManifestBytes).digest('hex'),...nativeManifest};
if(maskBytes)assembly.opacityMaskTransport={path:maskPath,sha256:crypto.createHash('sha256').update(maskBytes).digest('hex'),preserveAspectRatio:(maskBytes.toString('utf8').match(/preserveAspectRatio="([^"]+)"/)||[])[1]||'xMidYMid meet (default)',browserTransport:'Identical SVG bytes as a data URI to avoid file-protocol CORS rejection of CSS masks; production URI remains unchanged.'};
assembly.movieTransport={kind:'Browser-only Panel Movie methods render the exact installed local webm in a muted HTML video; all playback, skipping, cancellation and result logic remains the production code. Native sound, decoder and game rendering are not verified.',files:['map','cultivation','dragon_knight','summer'].map(id=>{const p='panorama/videos/custom_game/lottery_cinematic_v1/'+id+'.webm';return{path:p,sha256:crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex')}})};
assembly.previewHarness=['tools/menus_v10/preview.cjs','tools/archive_v10/adapter.js',...['preview.cjs','capture.cjs','movie_transport.js'].map(x=>'tools/lottery_fullscreen_20261018/'+x).concat(['tools/lottery_final_20261018/state.js','tools/lottery_final_20261018/browser.cjs'])].filter(x=>fs.existsSync(x)).map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}));
assembly.limitations.push('Only the actual lottery dependency scripts execute. Other HUD nodes are parsed from the actual XML and hidden by a preview-only fixture. Outbound events are captured in memory. No real game, account, payment, or reward mutation occurs.');
assembly.limitations.push('Panorama text-shadow intensity is approximated with repeated identical CSS shadows, including labels created by XML. These captures verify layout and authored shadow presence, not exact native alpha or font rasterization.');
fs.writeFileSync(file,JSON.stringify(assembly,null,2));console.log('LOTTERY_FULLSCREEN_PREVIEW_BUILT '+path.relative(repo,out));
