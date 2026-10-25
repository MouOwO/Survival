'use strict';
// Assemble real components into a task-owned, immutable browser fixture.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),base=path.join(root,'output/ui_qa_20261025/browser');
const arg=(name,fallback)=>{const i=process.argv.indexOf(name);return i<0?fallback:process.argv[i+1];};
const label=arg('--label','baseline');
if(!/^[a-z0-9_-]{1,40}$/.test(label))throw Error('Invalid snapshot label');
const out=path.join(base,label,'preview');
if(fs.existsSync(out))throw Error('Snapshot already exists; use a new label');
fs.mkdirSync(path.dirname(out),{recursive:true});
const built=cp.spawnSync(process.execPath,['tools/purple_ui_10h/preview.cjs','--out',out],{cwd:root,encoding:'utf8',windowsHide:true});
if(built.status!==0)throw Error('Production assembly failed: '+built.stderr);
let html=fs.readFileSync(path.join(out,'index.html'),'utf8');
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const helpers={};
for(const name of ['adapter.js','state.js']){
 const source=path.join(root,'tools/purple_ui_10h',name),target=path.join(out,name),raw=fs.readFileSync(source);
 fs.writeFileSync(target,raw,{flag:'wx'});helpers[name]={source:path.relative(root,source).replaceAll('\\','/'),sha256:sha(raw)};
 html=html.replace(pathToFileURL(source).href,pathToFileURL(target).href);
}
fs.writeFileSync(path.join(out,'index.html'),html);
// Explicit cash UI fixture opt-in happens before production scripts initialize.
// Normal snapshots retain the distributed noncommercial capability setting.
const stateMarker='<script src="'+pathToFileURL(path.join(out,'state.js')).href+'"></script>';
if(!html.includes(stateMarker))throw Error('State bootstrap marker missing');
function fontImageBridge(){
 window.__uiqaImageEvents=[];
 window.__uiqaFontBridge=new URLSearchParams(location.search).get('font_fixture')!=='fallback';
 if(!window.__uiqaFontBridge)return;
 var original=$.RegisterEventHandler;
 $.RegisterEventHandler=function(name,panel,callback){
  var event=name==='ImageLoaded'?'load':name==='ImageFailedLoad'?'error':null;
  if(event&&panel&&panel.el instanceof HTMLImageElement){
   var handler=function(){
    if(panel.deleted)return;
    window.__uiqaImageEvents.push({name:name,domEvent:event,src:panel.el.src,naturalWidth:panel.el.naturalWidth,nativeEvent:false});
    callback();
   };
   panel.el.addEventListener(event,handler);return handler;
  }
  return original.apply(this,arguments);
 };
}
html=html.replace(stateMarker,'<script>('+fontImageBridge.toString()+')();</script>'+stateMarker);
html=html.replace(stateMarker,'<script>cfg.SurvivalDevelopmentPayments=new URLSearchParams(location.search).get("cash_fixture")==="1";if(new URLSearchParams(location.search).get("tooltip_fixture")==="long"){PREVIEW_FIXTURE.lottery.items.forEach(function(item){item.description=Array.from({length:50},function(_,i){return "第"+(i+1)+"行：同一实际奖励的明确长正文滚动样例。";}).join("\\n");});}window.__uiqaNativeEvents=[];GameEvents.SendEventClientSide=function(name,payload){__uiqaNativeEvents.push({name:name,payload:payload});};window.__uiqaCursor=[0,0];document.addEventListener("mousemove",function(event){window.__uiqaCursor=[event.clientX,event.clientY];},true);GameUI.GetCursorPosition=function(){return window.__uiqaCursor.slice();};var uiqaTextDescriptor=Object.getOwnPropertyDescriptor(Panel.prototype,"text");Object.defineProperty(Panel.prototype,"text",{get:uiqaTextDescriptor.get,set:function(value){var children=this.children.filter(function(child){return !child.deleted;});uiqaTextDescriptor.set.call(this,value);children.forEach(function(child){if(child.parent===this&&!child.deleted&&!this.el.contains(child.el))this.el.append(child.el);},this);}});var uiqaOriginalCssValue=cssValue;cssValue=function(value){var mapped=uiqaOriginalCssValue(value);return typeof mapped==="string"?mapped.replace(/(?:s2r:\\/\\/panorama\\/images\\/|file:\\/\\/\\/)[^"\x27)\\s]+/g,function(uri){return PREVIEW_ASSET_PATHS[uri]||uri;}):mapped;};</script>'+stateMarker);
fs.writeFileSync(path.join(out,'index.html'),html);
const sourceAliases=JSON.parse(html.match(/window\.PREVIEW_ASSET_PATHS=(\{[\s\S]*?\});window\.PREVIEW_BASELINE=/)[1]);
let css=fs.readFileSync(path.join(out,'style.css'),'utf8');
for(const [uri,target]of Object.entries(sourceAliases))if(uri.startsWith('s2r://'))css=css.replaceAll(uri,target);
fs.writeFileSync(path.join(out,'style.css'),css);
const assembly=JSON.parse(fs.readFileSync(path.join(out,'assembly.json'),'utf8'));
const sourceDigest=sha(JSON.stringify(assembly.sourceGraph));
const metadata={schema:1,label,at:new Date().toISOString(),kind:'production_components_synthetic_browser_snapshot',sourceDigest,helpers,
 sourceAssembly:assembly,network:'isolated Chrome; http/https/ws/wss blocked by runner',
 explicitFixtureExtensions:['cash_fixture=1 opts only the synthetic browser into cash UI before component initialization','tooltip_fixture=long explicitly expands description only on actual lottery items before their first snapshot','Native SendEventClientSide is captured locally; no native event is sent','GetCursorPosition reads actual CDP-driven DOM mousemove coordinates instead of the older adapter constant [0,0]','CSS s2r references resolve through the existing exact asset aliases; no placeholder background is introduced','Updating Label.text preserves child Panels, matching the native panel tree; the old adapter textContent setter detached reusable atlas glyph children','Real DOM img load/error events bridge font image callbacks in Chrome only; no Dota native event or GPU readiness is simulated. font_fixture=fallback disables this bridge for a separate native-Label fallback probe.'],
 limitations:['Chrome Panorama adapter is not the native renderer; native masks, font metrics and compositing still need native review','All accounts, balances, orders and rewards are explicit synthetic fixtures','No game, gateway or public service is contacted']};
fs.writeFileSync(path.join(out,'snapshot.json'),JSON.stringify(metadata,null,2));
console.log(JSON.stringify({status:'SNAPSHOT_CREATED',label,out,sourceDigest,sources:assembly.sourceGraph.length}));
