'use strict';
// Separate Chrome proof of the production native-Label fallback. Native Dota
// image events remain unproven: this probe explicitly disables their DOM bridge.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {browser}=require('../archive_official_variants_20261019/browser.cjs');
const root=path.resolve(__dirname,'../..');
const arg=(n,d)=>{const i=process.argv.indexOf(n);return i<0?d:process.argv[i+1];};
const label=arg('--label','after_font_wallet');
if(!/^[a-z0-9_-]{1,40}$/.test(label))throw Error('Invalid label');
const folder=path.join(root,'output/ui_qa_20261025/browser',label),preview=path.join(folder,'preview/index.html');
const read=f=>fs.readFileSync(path.join(folder,f)),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const snapshot=JSON.parse(read('preview/snapshot.json'));
const report={schema:1,label,sourceDigest:snapshot.sourceDigest,at:new Date().toISOString(),
 scope:'Chrome actual production Label fallback with image callback bridge explicitly disabled; not native Dota',
 fixtureProvenance:{previewIndexSha256:sha(read('preview/index.html')),styleSha256:sha(read('preview/style.css')),nativeIconManifestSha256:sha(read('native_icons.json')),runnerSha256:sha(fs.readFileSync(__filename))},
 cases:[],publicNetworkAllowed:false,nativeGames:0,realAccounts:0,realOrders:0,passed:false};
const filename=path.join(folder,'font_fallback.json');
function save(){fs.writeFileSync(filename,JSON.stringify(report,null,2));}
function test(v,m){if(!v)throw Error(m);}
async function main(){
 const active=await browser({output:path.join(folder,'font_fallback_chrome')});
 try{
  await active.call('Network.enable');await active.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const [width,height]of [[1280,720],[1600,900],[1920,1080],[2560,1440]])for(const page of ['archive','collection']){
   const entry={width,height,page,passed:false};report.cases.push(entry);
   try{
    await active.viewport(width,height);await active.go(preview,'?page=archive&state=normal&font_fixture=fallback'+(page==='collection'?'&category=beast':''));
    entry.metrics=await active.run(`(()=>{
     syncLayout();
     const visible=e=>{const r=e.getBoundingClientRect();if(r.width<=0||r.height<=0||r.right<=0||r.bottom<=0||r.x>=innerWidth||r.y>=innerHeight)return false;for(let n=e;n;n=n.parentElement){const s=getComputedStyle(n);if(n.hidden||s.display==='none'||s.visibility==='hidden'||s.opacity==='0')return false;if(n!==e&&/(hidden|clip|scroll|auto)/.test(s.overflowX+' '+s.overflowY)){const p=n.getBoundingClientRect();if(r.right<=p.x||r.bottom<=p.y||r.x>=p.right||r.y>=p.bottom)return false;}}return true;};
     const win=nodes[${JSON.stringify(page==='archive'?'ArchiveWindow':'CollectionWindow')}],all=function walk(p){return [p,...p.Children().flatMap(walk)];}(root);
     const labels=all.filter(p=>p.type==='Label'&&p.__archiveFontOwner===cfg.SurvivalArchiveFontV36&&visible(p.el)&&p.text.trim()).map(p=>({text:p.text.slice(0,60),ink:p.style.color,computedColor:getComputedStyle(p.el).color,fontSize:getComputedStyle(p.el).fontSize,glyphVisible:p.Children().some(c=>c.id==='ArchiveFontV36Glyphs'&&c.visible)}));
     return {ready:previewReady,windowVisible:!!win&&visible(win.el),font:cfg.SurvivalArchiveFontV36.Inspect(),bridge:window.__uiqaFontBridge,forwardedEvents:window.__uiqaImageEvents.length,labels,errors:previewErrors,decodedAtlasImages:[...document.images].filter(e=>/font_regular_[01]/.test(e.src)).map(e=>({src:e.src,complete:e.complete,naturalWidth:e.naturalWidth}))};
    })()`);
    const m=entry.metrics;test(m.ready&&m.windowVisible,'production window unavailable');test(m.errors.length===0,'component error');
    test(m.bridge===false&&m.forwardedEvents===0,'fallback probe forwarded an image event');
    test(m.font.pages.every(s=>s==='loading'),'callback-free font readiness must remain unknown');
    test(m.labels.length>=3,'no visible production native Labels were inspected');
    test(m.labels.every(l=>!l.glyphVisible&&l.ink!=='#ffffff00'&&!/rgba\([^)]*,\s*0\)/.test(l.computedColor)),'fallback left transparent Label or unloaded glyph layer');
    entry.passed=true;
   }catch(error){entry.error=String(error.message||error);}
   const shot=path.join(folder,'screenshots',width+'x'+height+'_'+page+'_font_fallback.png');await active.shot(shot,{x:0,y:0,width,height});entry.screenshot=path.relative(root,shot).replaceAll('\\','/');
   entry.networkAttempts=active.events.filter(e=>e.method==='Network.requestWillBeSent'&&/^https?:|^wss?:/.test(e.params.request.url)).map(e=>e.params.request.url.split('?')[0]);
   if(entry.networkAttempts.length){entry.passed=false;entry.error='forbidden network attempt';}active.events.length=0;save();
   console.log(JSON.stringify({page,size:width+'x'+height,passed:entry.passed,labels:entry.metrics?.labels.length,error:entry.error||null}));
  }
  report.passed=report.cases.length===8&&report.cases.every(c=>c.passed);report.finishedAt=new Date().toISOString();save();if(!report.passed)process.exitCode=1;
 }finally{await active.close();}
}
main().catch(error=>{report.infrastructureError=String(error.message||error);save();console.error(report.infrastructureError);process.exitCode=1;});
