const fs=require('fs'),p=require('path'),vm=require('vm'),assert=require('assert');
const here=__dirname,build=JSON.parse(fs.readFileSync(p.join(here,'build.json')));
const entries=JSON.parse(fs.readFileSync(p.join(here,'archive_icon_manifest.json')));
const sharedBoss=entries.filter(e=>['boss','map_level'].includes(e.category_id));
assert.equal(sharedBoss.length,68);assert.equal(new Set(sharedBoss.map(e=>e.icon_path)).size,1,'Boss and map level share one original head icon');
const clears=entries.filter(e=>e.category_id==='clear');
assert.equal(new Set(clears.map(e=>e.icon_path)).size,1);assert.equal(new Set(clears.map(e=>e.tone_color)).size,5,'Five completion-count colors share the same source');
const qualityTones={n:'#aebbc1',r:'#76be91',sr:'#79adf0',ssr:'#b68ae2',ur:'#e5b758'};
for(const e of entries.filter(e=>e.category_id==='points'))assert.equal(e.tone_color,qualityTones[e.quality.toLowerCase()],'UI quality colors follow configuration');
const socialHeads=entries.filter(e=>['friend','ex'].includes(e.category_id));
assert.equal(socialHeads.length,80);
assert.equal(new Set(socialHeads.map(e=>e.icon_path)).size,80,'Each character keeps its own head-only artwork');
for(const e of socialHeads){assert(e.icon_path.startsWith('custom_game/archive_heads_v2/'));assert(!e.portrait,'A head-only source must display whole, without the old full-body crop');assert(e.runtime_uri.includes('/head_v2_'),'New texture identity prevents stale full-body cache');}
const work=entries.filter(e=>e.category_id==='work');
assert.equal(work.length,34);assert.equal(new Set(work.map(e=>e.icon_path)).size,3);
assert.equal(new Set(work.map(e=>e.tone_color)).size,17);
for(const e of work)assert(e.tint_icon&&e.icon_path.includes('/work_head_'),'Work heads use tinted simple art');
assert.equal(build.textureInputs.filter(p=>p.includes('/archive_gpu_')).length,new Set(entries.flatMap(e=>[e.runtime_uri,e.small_runtime_uri])).size,'Both unique archive engine texture sizes must be explicitly compiled; shared art reuses its GPU texture');
for(const entry of entries){
 assert(entry.runtime_uri&&entry.small_runtime_uri,'Artwork must have regular and small texture URIs');
 for(const uri of [entry.runtime_uri,entry.small_runtime_uri]){
  const path=uri.replace('s2r://panorama/','');assert(build.textureInputs.includes(path));
  const source=fs.readFileSync(p.join(here,'candidate/panorama',path),'utf8');
  assert(source.includes('"m_outputFormat" "string" "BGRA8888"'),'Panorama requires the tested native color format');
 }
}
const read=f=>fs.readFileSync(p.join(here,'candidate/panorama',f),'utf8');
const compileManifest=read(build.inputs.find(f=>f.endsWith('_assets.xml')));
for(const row of entries){
 assert(!compileManifest.includes('file://{images}/'+row.icon_path),'Masters must not become full-size runtime textures');
 assert(compileManifest.includes(row.small_runtime_uri)&&compileManifest.includes(row.runtime_uri));
}
class Panel {
 constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id;this.children=[];this.style={};this.events={};this.classes=[];if(parent)parent.children.push(this);}
 AddClass(c){this.classes.push(c);} SetImage(s){this.image=s;} SetScaling(s){this.scaling=s;}
 SetHasClass(c,on){this.classes=this.classes.filter(x=>x!==c);if(on)this.classes.push(c);}
 SetPanelEvent(e,f){this.events[e]=f;}
 RemoveAndDeleteChildren(){this.children=[];}
 Children(){return this.children;}
 FindChildTraverse(id){if(this.id===id)return this;for(const child of this.children){const found=child.FindChildTraverse(id);if(found)return found;}return null;}
}
const root=new Panel('Panel',null,'root'),content=new Panel('Panel',root,'ArchiveContent');
let fallback=0;const view={Icon:()=>fallback++,Init(){},Hide(){},Observe(data){this.snapshot=data;},Progress:item=>item.count+' / '+item.target};
const cfg={ArchiveHandoff:view};
vm.runInNewContext(fs.readFileSync(p.join(here,'../archive_polish_v1/nine_slice.js'),'utf8'),{GameUI:{CustomUIConfig:()=>cfg},$:{CreatePanel:(...a)=>new Panel(...a)}});
vm.runInNewContext(read(build.inputs.find(f=>f.includes('/icons_remaining_'))),{GameUI:{CustomUIConfig:()=>cfg},$:{CreatePanel:(...a)=>new Panel(...a),GetContextPanel:()=>root},GameEvents:{SendCustomGameEventToServer(){throw Error('Art preview must never change rewards');}}});
for(let i=0;i<entries.length;i++){
 const row=entries[i],card=new Panel('Panel',root,'card'+i),item=Object.freeze({id:row.item_id,count:i+1,target:430});
 view.Icon(card,item,row.category_id,{});
 assert.equal(card.children[0].children[0].image,row.runtime_uri||'file://{images}/'+row.icon_path,'Native card uses regular texture, never undersampled 64px art');
 assert.equal(card.children[0].children[0].scaling,'stretch-to-fit-preserve-aspect');
 assert.equal(card.children[1].text,(i+1)+' / 430','Actual owned count must survive icon override');
 if(row.portrait){const art=card.children[0],im=art.children[0];assert(art.classes.includes('ArchivePortraitViewport'));assert.equal(parseFloat(im.style.width),parseFloat(im.style.height),'Portrait keeps the master aspect ratio');assert.equal(parseFloat(im.style.width),row.display_width/row.portrait[2]);}
 if(row.tint_icon)assert.equal(card.children[0].children[0].style.washColor,row.tone_color);
 const corner=card.children.find(c=>c.classes.includes('ArchiveHoverCorner'));
 assert(corner&&!corner.hittest&&!corner.hittestchildren,'Every mapped category has a non-interactive foreground star');
 assert.equal(corner.children.length,3,'Foreground uses the same three-row grid as the frame');
 corner.children.forEach((r,y)=>r.children.forEach((t,x)=>assert.equal(t.style.opacity,x===0&&y===0?undefined:'0','Only the original upper-left tile is painted')));
}
view.Icon(root,{id:'shadow_01'},'friend',{});view.Icon(root,{id:'unmapped_test_item'},'shadow',{});assert.equal(fallback,2);
view.Init();view.Observe({category_id:'shadow'});
const button=root.FindChildTraverse('ArchiveArtTrialToggle'),trial=root.FindChildTraverse('ArchiveArtTrial');
assert.equal(trial.visible,false);button.events.onactivate();assert.equal(trial.visible,true);
assert.equal(root.FindChildTraverse('ArchiveArtTrialGrid').children.length,Math.min(8,entries.filter(e=>e.category_id==='shadow').length));
assert.equal(root.FindChildTraverse('ArchiveArtPreviousPage').enabled,false,'Previous page disabled at start');
const categoryCount=new Set(entries.map(e=>e.category_id)).size;
for(let n=0;n<categoryCount;n++){
 root.FindChildTraverse('ArchiveArtNextCategory').events.onactivate();
 assert(root.FindChildTraverse('ArchiveArtTrialGrid').children.length<=8,'Preview must never preload every category');
 root.FindChildTraverse('ArchiveArtNextPage').events.onactivate();
 assert(root.FindChildTraverse('ArchiveArtTrialGrid').children.length<=8);
 root.FindChildTraverse('ArchiveArtPreviousPage').events.onactivate();
}
view.Observe({category_id:'shadow'});assert.equal(trial.visible,true);
view.Observe({category_id:'clear'});assert.equal(trial.visible,false,'Switching category restores real archive');
const labeledHud=read(build.inputs.find(f=>f.includes('/topnav_remaining_')));
assert(labeledHud.includes('caption.text=a[1]')&&labeledHud.includes('place(caption,0,62,64,24)'),'Independent captions below unchanged icons');
const hud=labeledHud.replace(/b\.style\.height="88px";var caption=.*?caption\.style\.textShadow="[^"]*";/,'').replace('place(social,474,94,192,130);','place(social,474,70,192,130);').replace('f&&f.Compact?f.Compact(v):f&&f.Format?f.Format(v):String(v===undefined?"—":v)','f&&f.Compact?f.Compact(v):String(v===undefined?"—":v)');
const baseline=fs.readFileSync(p.join(here,'baseline/content/scripts/custom_game/handoff_hud.js'),'utf8').replace(/\r\n/g,'\n');
assert.equal(hud,require('../../../../tools/patch_hud_refresh.cjs')(baseline).replace('tooltip(b,a[1]);','/* Top navigation tooltips temporarily disabled. */').replace('width:w+"px",height:h+"px"','width:w+"px",height:h+"px",minWidth:w+"px",minHeight:h+"px",maxWidth:"10000px",maxHeight:"10000px"'),'Only navigation binding, tested event/overflow fix and pre-scale clipping constraints change');
let stock=0;cfg.SurvivalRewardPresentation={CreateIcon(){stock++;return 'stock';}};
const sharedScript=read(build.inputs.find(f=>f.includes('/item_art_remaining_')));
const sandbox={GameUI:{CustomUIConfig:()=>cfg},$:{CreatePanel:(...a)=>new Panel(...a)}};
vm.runInNewContext(sharedScript,sandbox);vm.runInNewContext(sharedScript,sandbox);
for(const row of entries){
 const item=Object.freeze({id:row.item_id,count:5,quality:'sr',price:188,enabled:true});
 const icon=cfg.SurvivalRewardPresentation.CreateIcon(root,item,'TestIcon');
 assert.equal(icon.image,row.runtime_uri||'file://{images}/'+row.icon_path);
 assert.equal(icon.scaling,'stretch-to-fit-preserve-aspect');
 if(row.content_id)assert.equal(cfg.SurvivalItemArt.Lookup({content_id:row.content_id}).item_id,row.item_id);
}
assert.equal(cfg.SurvivalRewardPresentation.CreateIcon(root,{id:'unknown'},'TestIcon'),'stock');assert.equal(stock,1,'Reload must not recursively wrap presentation');
for(const [kind,fn,cls] of [['shop','createEntryIcon','className'],['shop_tooltip','createIcon','"ShopTooltipMainIcon"']]){
 const baselineShop=fs.readFileSync(p.join(here,'baseline/content/scripts/custom_game',kind==='shop'?'shop_ui.js':'shop_tooltip.js'),'utf8').replace(/\r\n/g,'\n');
 const anchor=fn==='createEntryIcon'?'function createEntryIcon(parent, entry, className) {':'function createIcon(parent, entry) {';
 const patch='\n        var art=GameUI.CustomUIConfig().SurvivalItemArt; if(art&&art.Create(parent,entry,'+cls+'))return;';
 let candidate=read(build.inputs.find(f=>f.includes('/'+kind+'_remaining_')));
 if(kind==='shop_tooltip'){
  const start='    function placeBesideSource(',end='    function createIcon(';
  candidate=candidate.slice(0,candidate.indexOf(start))+baselineShop.slice(baselineShop.indexOf(start),baselineShop.indexOf(end))+candidate.slice(candidate.indexOf(end));
  candidate=candidate.replace('\n        var owner=byId("CustomShopWindow");tooltip.style.zIndex=String(Math.max(100000,Number(owner&&owner.style.zIndex)||0)+1);','');
 }
 assert.equal(candidate,baselineShop.replace(anchor,anchor+patch),'Preserve '+kind+' business content outside icon/position/layer changes');
}
console.log('ARCHIVE_ICONS_PASS: '+entries.length+' ID mappings, aspect ratio, real counts, category isolation, lazy read-only preview, shared shop/reward art, safe reload, business code unchanged');
