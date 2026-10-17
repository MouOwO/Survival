'use strict';
// Isolated assembly of the actual loading XML/JS/CSS. No menu, account, game or network fixture.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{pathToFileURL}=require('url');
const base='design_refs/dawnward_loading_20261015',baseline=process.argv.includes('--baseline');
const option=process.argv.indexOf('--out'),out=option>=0?process.argv[option+1]:base+'/'+(baseline?'baseline/preview':'final/preview');
fs.mkdirSync(out,{recursive:true});
const sourceRoot=baseline?base+'/baseline/sources/panorama/src':'panorama/src';
const file=rel=>path.join(sourceRoot,rel),read=rel=>fs.readFileSync(file(rel),'utf8').replace(/^\uFEFF/,'');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex'),uri=f=>pathToFileURL(path.resolve(f)).href;
const manifest=fs.readFileSync('panorama/src/layout/custom_game/custom_ui_manifest.xml','utf8');
if(!/<CustomUIElement\b[^>]*type="Hud"[^>]*layoutfile="file:\/\/\{resources\}\/layout\/custom_game\/startup_loading.xml"/.test(manifest))throw Error('Loading HUD is not registered');
const rel='layout/custom_game/startup_loading.xml',xml=read(rel),section=name=>(xml.match(new RegExp('<'+name+'>([\\s\\S]*?)</'+name+'>'))||[])[1]||'';
const includes=name=>[...section(name).matchAll(/src="file:\/\/\{resources\}\/([^\"]+)"/g)].map(m=>m[1]);
const layout={rel,xml,styles:includes('styles'),scripts:includes('scripts')};
const sources=Object.fromEntries([rel,...layout.styles,...layout.scripts].map(name=>[name,read(name)]));
const alternate=read('layout/custom_game/custom_loading_screen.xml');
if(alternate.replace(' StartupNativeLoadingContext','')!==xml)throw Error('Loading entrypoints may differ only by their native-context marker');
const assets={},assetEvidence=[];
function imageUri(value){const image=value.replace(/^file:\/\/\{images\}\//,''),frozen=file('images/'+image),live='panorama/src/images/'+image,source=fs.existsSync(frozen)?frozen:live;if(!fs.existsSync(source))throw Error('Missing actual loading asset: '+image);const target=uri(source);assets[image]=target;assets['file://{images}/'+image]=target;if(!assetEvidence.some(x=>x.path===source))assetEvidence.push({path:source,sha256:sha(fs.readFileSync(source))});return target;}
for(const source of Object.values(sources))for(const match of source.matchAll(/file:\/\/\{images\}\/([^"')\s]+)/g))imageUri('file://{images}/'+match[1]);
// Reuse the existing converter's actual function definitions without running its
// all-menu build or touching its fixtures, adapter, output or production sources.
const converterSource=fs.readFileSync('tools/menus_v10/preview.cjs','utf8');
const converterBody=converterSource.slice(converterSource.indexOf('function gradient('),converterSource.indexOf('\nconst content=csv('));
if(!converterBody.includes('function convertCss('))throw Error('Shared converter boundary changed');
const convertCss=new Function('imageUri',converterBody+';return convertCss;')(imageUri);
const css=layout.styles.map(name=>'/* '+name+' */\n'+convertCss(sources[name])).join('\n');
fs.writeFileSync(path.join(out,'style.css'),css);
const props={'visibility':'visible','fit-width':'0','fit-height':'0','halign':'left','valign':'top','flow':'none','ignore-flow':'false','position':'normal','brightness':'1','saturation':'1'};
const customProperties=Object.entries(props).map(([name,value])=>'@property --pano-'+name+'{syntax:"*";inherits:false;initial-value:'+value+'}').join('\n');
const scriptJson=value=>JSON.stringify(value).replaceAll('</script','<\\/script');
fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>孤城逐晓 · 实际加载组件离线预览</title><style>
${customProperties}
@font-face{font-family:"Source Han Serif SC";src:url("${uri('panorama/fonts/Radiance-Survival-SourceHanSerifSC-Bold.otf')}");font-weight:700}@font-face{font-family:Radiance;src:url("${uri('panorama/fonts/Radiance-Survival-SourceHanSansSC-Regular.otf')}");font-weight:400}@font-face{font-family:Radiance;src:url("${uri('panorama/fonts/Radiance-Survival-SourceHanSansSC-Medium.otf')}");font-weight:700}
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#070d12}body{font-family:Radiance,"Microsoft YaHei",sans-serif}.panel{position:absolute;flex-shrink:0;transform-origin:0 0;align-content:flex-start;align-items:flex-start}.panel[hidden]{display:none!important}.label{display:block;pointer-events:none;line-height:1.25;white-space:nowrap}.button{cursor:pointer}.PreviewContext .button{pointer-events:auto}.PreviewContext .UIDisabled{pointer-events:none}img{object-fit:contain}#PreviewRoot{left:0;top:0;overflow:visible}.PreviewContext{left:0;top:0;width:100%;height:100%}.StartupLoadingHidden{display:none!important}
</style><link rel="stylesheet" href="style.css"><div id="PreviewRoot"></div>
<script>window.PREVIEW_LAYOUTS=${scriptJson([layout])};window.PREVIEW_SOURCES=${scriptJson(sources)};window.PREVIEW_FIXTURE={nativeBitmaps:[],archiveIcons:[]};window.PREVIEW_ASSET_PATHS=${scriptJson(assets)};window.PREVIEW_SOURCE_ROOT=${scriptJson(uri(sourceRoot)+'/')};window.IMAGE_ROOT=${scriptJson(uri(sourceRoot+'/images')+'/')};window.IMAGE_FALLBACK_ROOT=window.IMAGE_ROOT;</script><script src="${uri('tools/archive_v10/adapter.js')}"></script><script src="state.js"></script></html>`);
const state=String.raw`'use strict';
// Local emulation of native ImageLoaded and startup nettable state. Production
// render(), progress, readiness, validation and click handlers execute unchanged.
const imageListeners=new WeakMap();
$.RegisterEventHandler=(name,panel,fn)=>{const event=name==='ImageLoaded'?'load':name==='ImageFailedLoad'?'error':null;if(event){const handler=()=>{try{fn();syncLayout()}catch(error){previewErrors.push({scope:name,message:String(error),stack:error.stack})}};panel.el.addEventListener(event,handler);const list=imageListeners.get(panel)||[];list.push({event,handler});imageListeners.set(panel,list);}return 1};
$.UnregisterEventHandler=(name,panel,fn)=>{for(const row of imageListeners.get(panel)||[])panel.el.removeEventListener(row.event,row.handler)};
CustomNetTables.UnsubscribeNetTableListener=()=>{};
const realSetImage=Panel.prototype.SetImage;
Panel.prototype.SetImage=function(value){if(this.BHasClass('StartupLoadingBackground'))this.el.style.objectFit='cover';return realSetImage.call(this,value)};
const originalSync=syncLayout;
window.syncLayout=function(){originalSync();for(const well of document.querySelectorAll('.StartupLoadingProgressWell')){const child=well.querySelector('.StartupLoadingProgressEmpty'),style=getComputedStyle(well);if(child){const left=parseFloat(style.paddingLeft)||0,right=parseFloat(style.paddingRight)||0,top=parseFloat(style.paddingTop)||0,bottom=parseFloat(style.paddingBottom)||0;Object.assign(child.style,{left:left+'px',top:top+'px',width:Math.max(0,well.clientWidth-left-right)+'px',height:Math.max(0,well.clientHeight-top-bottom)+'px'});}}for(const image of document.querySelectorAll('.StartupLoadingProgressFrame img'))image.style.objectFit='fill';const canvas=document.createElement('canvas'),ctx=canvas.getContext('2d');for(const element of document.querySelectorAll('.SurvivalStartupLoading .label')){const style=getComputedStyle(element);if(style.getPropertyValue('--pano-shrink').trim()!=='1'||element.hidden||!element.getClientRects().length)continue;const nominal=+(element.dataset.startupNominalSize||(element.dataset.startupNominalSize=parseFloat(style.fontSize)));element.style.fontSize=nominal+'px';if(['normal','pre-wrap'].includes(style.whiteSpace)){const limit=parseFloat(style.maxHeight);if(Number.isFinite(limit)){let size=nominal;while(element.scrollHeight>limit+1&&size>8){size-=.5;element.style.fontSize=size+'px';}}}else{ctx.font=style.fontWeight+' '+nominal+'px '+style.fontFamily;const width=ctx.measureText(element.textContent).width+(parseFloat(style.letterSpacing)||0)*Math.max(0,element.textContent.length-1);if(width>0&&element.clientWidth>0)element.style.fontSize=Math.min(nominal,nominal*element.clientWidth/width)+'px';}}};
const params=new URLSearchParams(location.search),chosen=params.get('state')||'resources';
const names=['逐晓守望者','极长玩家名称用于检验四人横排与裁切边界LongNickname','새벽의수호자','Dawnward Citadel 玩家四'];
function player(i,status,ready){return {player_id:i,player_name:names[i],status,authenticated:ready?1:0,client_ready:ready?1:0,ready:ready?1:0}}
const states={
 resources:{session_id:'offline_loading_resources',phase:'loading',admission_complete:0,all_ready:0,selector_player_id:0,assets:{progress:62.5,complete:0,failed:0},players:[{...player(0,'loading',false),authenticated:1,client_ready:1},player(1,'loading',false),player(2,'loading',false),player(3,'loading',false)]},
 team_setup:{session_id:'offline_native_team_setup',phase:'team_setup',native_team_setup:1,admission_complete:0,all_ready:0,selector_player_id:0,assets:{progress:0,complete:0,failed:0},players:[0,1,2,3].map(i=>player(i,'team_setup',false))},
 error:{session_id:'offline_loading_error',phase:'error',error:'backend_connection_pending',admission_complete:0,all_ready:0,selector_player_id:0,assets:{progress:83,complete:0,failed:0},players:[{...player(0,'auth_error',false),client_ready:1},player(1,'loading',false),player(2,'disconnected',false),player(3,'loading',false)]},
 waiting:{session_id:'offline_loading_waiting',phase:'loading',admission_complete:0,all_ready:0,selector_player_id:0,assets:{progress:100,complete:1,failed:0},players:[player(0,'ready',true),player(1,'ready',true),player(2,'ready',true),{...player(3,'connecting_backend',false),authenticated:1}]}
};
if(!states[chosen])throw Error('Unknown loading fixture');
window.loadingFixture={state:chosen,packet:JSON.parse(JSON.stringify(states[chosen])),expectedPercent:chosen==='resources'?77:chosen==='team_setup'?0:chosen==='error'?69:100,expectedFill:chosen==='resources'?77.5:chosen==='team_setup'?0:chosen==='error'?69.8:100,scope:'explicit offline loading nettable; no account or native game'};
netData.survival_loading={state:loadingFixture.packet};
window.loadingReady=previewLoad().then(async()=>{await document.fonts.ready;await Promise.all([...document.images].map(image=>image.decode().catch(()=>false)));await new Promise(resolve=>setTimeout(resolve,120));syncLayout();return !previewErrors.length}).catch(error=>{previewErrors.push({scope:'loading fixture',message:String(error),stack:error.stack});return false});
`;
fs.writeFileSync(path.join(out,'state.js'),state);
const records=[...Object.keys(sources),'layout/custom_game/custom_loading_screen.xml'].map(name=>({path:'panorama/src/'+name,read_from:file(name),sha256:sha(fs.readFileSync(file(name)))}));
fs.writeFileSync(path.join(out,'assembly.json'),JSON.stringify({kind:'production_loading_component_browser_preview',baseline,layouts:[{rel,styles:layout.styles,scripts:layout.scripts}],sources:records,assets:assetEvidence,fixtures:['resources','team_setup','error','waiting'],harness:['tools/dawnward_loading_20261015/preview.cjs','tools/archive_v10/adapter.js','tools/menus_v10/preview.cjs'].map(name=>({path:name,sha256:sha(fs.readFileSync(name))})),adapter_corrections:['Native ImageLoaded/Failed mapped to actual DOM image load events','Image scaling=stretch-to-cover-preserve-aspect maps to object-fit:cover','Warcraft frame Image scaling=stretch-to-fit maps to object-fit:fill in this preview only','Source Han Serif SC uses the project actual bundled bold font','ProgressWell 100% child fills native parent padding content area; CSS absolute percent normally includes the padding box','Authored native text-overflow:shrink measured locally for startup labels only','Native hittest=false/hittestchildren=true preserves descendant button hit targets'],scope:'Browser executes exact frozen production XML/JS/CSS with explicit local nettable samples. No actual game, account, backend, gateway, login, asset compile or production network verification.'},null,2));
console.log('DAWNWARD_LOADING_PREVIEW '+out);
module.exports={out};
