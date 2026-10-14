const test=require('node:test'),assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
function fixture(options={}){
 const h=createHarness(),Panel=h.root.constructor,stack=[],opened=[],closed=[];
 h.cfg.SurvivalUIRegistry={tokens:{},assets:{},pending:{},aliases:{},projectPaths:{}};
 h.load('common/ui_components.js'); // Real Lifecycle cancellation/generation behavior.
 h.cfg.SurvivalUILayers={Top:()=>stack.at(-1)||null,CloseTop(){closed.push(stack.pop());}};
 function view(id){return {Open(){opened.push(id);stack.push(id);},Close(){assert.equal(stack.at(-1),id);closed.push(stack.pop());},IsOpen:()=>stack.includes(id)};}
 h.cfg.SurvivalCollection=view('collection');h.cfg.SurvivalArchive=view('archive');h.cfg.SurvivalDaily=view('daily_rewards');h.cfg.SurvivalVIP=view('vip');
 h.load('common/purple_shell.js');
 function makeHUD(scale=1,x=8,y=6){
  const host=new Panel('Panel',h.root,'HandoffHUD'),top=new Panel('Panel',host,'HandoffTop'),entries={},parts={};
  const keys=['return','treasure','archive','lottery','benefit','shop','survival_shop','vip'];
  for(const key of keys){
   const entry=entries[key]=new Panel('Button',top,'HandoffNav_'+key);entry.AddClass('HandoffNav HandoffNavUnified');
   parts[key]={};
   for(const [part,type]of [['Glow','Panel'],['Icon','Image'],['CaptionHost','Panel'],['Caption','Label'],['Underline','Panel']])parts[key][part]=new Panel(type,part==='Caption'?parts[key].CaptionHost:entry,'HandoffNav'+part+'_'+key);
   parts[key].Caption.style.fontFamily='"Source Han Sans SC", "Noto Sans SC", "Microsoft YaHei", sans-serif';
   entry.SetPanelEvent('onactivate',()=>opened.push(key));
  }
  const effects=options.noEffects?null:new Panel('Button',top,'HandoffCombatEffects');
  if(effects)effects.SetPanelEvent('onactivate',()=>opened.push('effects'));
  function layout(value=scale,left=x,up=y){
   const screen=Number(top.actualuiscale_x)||1,px=v=>Math.round(v*value*screen)/screen;
   function box(node,bx,by,w,ht){node.style.position=`${px(bx)}px ${px(by)}px 0px`;node.style.width=px(w)+'px';node.style.height=px(ht)+'px';}
   top.style.width=630*value+'px';top.style.height=94*value+'px';top.style.position=`${left}px ${up}px 0px`;
   keys.forEach((key,index)=>{const width=key==='survival_shop'?96:key==='vip'?60:56;box(entries[key],key==='vip'?460:14+index*58,6,width,86);box(parts[key].Glow,(width-62)/2,0,62,62);box(parts[key].Icon,(width-44)/2,4,44,44);box(parts[key].CaptionHost,0,52,width,32);parts[key].Caption.style.fontSize=px(22)+'px';box(parts[key].Underline,(width-34)/2,84,34,2);});
   if(effects)box(effects,522,6,96,86);
  }
  layout();return {host,top,effects,entries,parts,layout};
 }
 const hud=makeHUD();h.load('collection_nav.js');
 return Object.assign(h,{stack,opened,closed,hud,makeHUD,entry:()=>h.nodes.HandoffNav_collection,refresh:()=>h.cfg.SurvivalCollectionNav.Refresh(),timers:()=>h.scheduled.filter(t=>!t.cancelled)});
}
test('collection opens through real menu routing and never bypasses a purchase modal',()=>{
 const h=fixture();
 h.click(h.entry());assert.deepEqual(h.stack,['collection']);assert.equal(h.entry().BHasClass('HandoffNavActive'),true);
 h.click(h.entry());assert.deepEqual(h.stack,[]);
 h.stack.push('archive','lottery_info');h.click(h.entry());assert.deepEqual(h.stack,['collection']);assert.deepEqual(h.closed,['collection','lottery_info','archive']);
 assert.equal(h.cfg.SurvivalPurpleShell.Navigate('daily_rewards'),true);assert.deepEqual(h.stack,['daily_rewards']);
 h.click(h.entry());assert.deepEqual(h.stack,['collection']);
 for(const modal of ['purchase_confirm','ucoin_checkout','setup','unknown_modal']){
  h.stack.push(modal);const opened=h.opened.length,closed=h.closed.length;
  h.click(h.entry());assert.equal(h.stack.at(-1),modal);assert.equal(h.opened.length,opened);assert.equal(h.closed.length,closed);
  assert.equal(h.cfg.SurvivalPurpleShell.Navigate('archive'),false);h.stack.pop();
 }
 h.cfg.SurvivalPurpleShell.Navigate('vip');assert.deepEqual(h.stack,['vip']);
 h.cfg.SurvivalCollectionNav.Dispose();assert.equal(h.timers().length,0);
});
test('new entry follows existing HUD geometry without changing Effects or rescanning a stable HUD',()=>{
 const h=fixture(),effectStyle={...h.hud.effects.style},event=h.hud.effects.events.onactivate;
 assert.equal(h.entry().GetParent(),h.hud.host);assert.equal(h.entry().style.position,'628px 12px 0px');assert.equal(h.entry().style.width,'56px');assert.equal(h.entry().style.height,'86px');
 assert.equal(h.nodes.HandoffCollectionCaption.text,'收藏');assert.equal(h.nodes.HandoffCollectionIcon.image,'file://{images}/custom_game/topnav_reference_v2/collection.svg');
 for(const cls of ['HandoffNav','HandoffNavUnified','HandoffCanvas'])assert(h.entry().BHasClass(cls));
 assert(h.nodes.HandoffCollectionGlow.BHasClass('HandoffNavGlow'));assert(h.nodes.HandoffCollectionCaption.BHasClass('HandoffNavCaption'));
 for(const [part,id]of [['Glow','Glow'],['Icon','Icon'],['CaptionHost','CaptionHost'],['Underline','Underline']])for(const key of ['position','width','height'])assert.equal(h.nodes['HandoffCollection'+id].style[key],h.hud.parts.archive[part].style[key]);
 const tree=h.counts.tree,writes=h.counts.style;
 for(let i=0;i<8;i++)h.flushFinite();
 assert.equal(h.counts.tree,tree,'steady refresh uses cached panels');assert.equal(h.counts.style,writes,'stable geometry does not rewrite styles');assert.equal(h.timers().length,1);
 assert.deepEqual({...h.hud.effects.style},effectStyle);assert.equal(h.hud.effects.events.onactivate,event);
 h.hud.layout(.5);const resizedEffects={...h.hud.effects.style};h.refresh();
 assert.equal(h.entry().style.position,'318px 9px 0px');assert.equal(h.entry().style.width,'28px');assert.equal(h.nodes.HandoffCollectionCaption.style.fontSize,'11px');
 assert.deepEqual({...h.hud.effects.style},resizedEffects);assert.equal(h.hud.effects.events.onactivate,event);
 h.hud.top.visible=false;h.refresh();assert.equal(h.entry().visible,false);
 h.hud.top.visible=true;h.refresh();assert.equal(h.entry().visible,true);
 h.cfg.SurvivalCollectionNav.Dispose();
});
test('module and HUD reload leave one button and one lifecycle timer; stale callbacks cannot recreate it',()=>{
 const h=fixture(),old=h.cfg.SurvivalCollectionNav,entry=h.entry(),stale=h.timers()[0].fn;
 h.load('collection_nav.js');assert.equal(old.IsAlive(),false);assert.equal(entry.IsValid(),false);assert.equal(h.timers().length,1);
 const fresh=h.entry();stale();assert.equal(h.entry(),fresh);assert.equal(h.timers().length,1);
 h.hud.host.DeleteAsync();h.cfg.HandoffGeneration++;h.hud=h.makeHUD(.75,12,4);h.refresh();
 assert.equal(h.entry().GetParent(),h.hud.host);assert.equal(h.entry().style.position,'478px 9px 0px');assert.equal(h.entry().style.width,'42px');
 assert.equal(h.hud.host.children.filter(p=>p.id==='HandoffNav_collection').length,1);
 const api=h.cfg.SurvivalCollectionNav,queued=h.timers()[0].fn;h.root.DeleteAsync();
 assert.doesNotThrow(()=>{h.flushFinite();queued();api.Dispose();api.Dispose();});assert.equal(api.IsAlive(),false);assert.equal(h.timers().length,0);
});
test('missing HUD waits locally and missing collection API cannot open a partial feature',()=>{
 const h=fixture();delete h.cfg.SurvivalCollection;h.refresh();assert.equal(h.entry().enabled,false);
 h.click(h.entry());assert.deepEqual(h.opened,[]);
 h.hud.top.DeleteAsync();h.cfg.HandoffGeneration++;h.refresh();assert.equal(h.entry().visible,false);
 h.hud.host.DeleteAsync();h.hud=h.makeHUD();
 h.cfg.SurvivalCollection={Open:()=>h.opened.push('collection'),Close(){}};
 for(let i=0;i<5;i++)h.flushFinite();
 assert.equal(h.entry().visible,true);assert.equal(h.entry().enabled,true);assert.equal(h.timers().length,1);
 h.cfg.SurvivalCollectionNav.Dispose();
});

test('missing, hidden, collapsed or removed Effects never hides collection and visible neighbors set its right edge',()=>{
 const h=fixture({noEffects:true});assert.equal(h.entry().visible,true);assert.equal(h.entry().style.position,'530px 12px 0px');
 h.hud.entries.vip.visible=false;h.refresh();assert.equal(h.entry().style.position,'468px 12px 0px');
 h.hud.entries.survival_shop.style.visibility='collapse';h.refresh();assert.equal(h.entry().style.position,'370px 12px 0px');
 const stableTree=h.counts.tree;for(let i=0;i<8;i++)h.flushFinite();assert.equal(h.counts.tree,stableTree,'Absent optional Effects is cached');h.cfg.SurvivalCollectionNav.Dispose();
 const other=fixture();other.hud.effects.visible=false;other.refresh();assert.equal(other.entry().visible,true);assert.equal(other.entry().style.position,'530px 12px 0px');
 other.hud.effects.visible=true;other.hud.effects.style.visibility='collapse';other.refresh();assert.equal(other.entry().visible,true);assert.equal(other.entry().style.position,'530px 12px 0px');
 other.hud.effects.DeleteAsync();other.refresh();assert.equal(other.entry().visible,true);assert.equal(other.entry().style.position,'530px 12px 0px');
 const scanned=other.counts.tree;other.refresh();assert.equal(other.counts.tree,scanned,'An invalidated optional anchor is reacquired once');other.cfg.SurvivalCollectionNav.Dispose();
});

test('neighbor movement and pixel scale changes stay aligned without a fixed-size minimum or original-event changes',()=>{
 const h=fixture(),events=Object.fromEntries(Object.entries(h.hud.entries).map(([key,panel])=>[key,panel.events.onactivate]));
 h.hud.effects.style.position='574px 6px 0px';h.hud.effects.style.width='106px';h.refresh();assert.equal(h.entry().style.position,'690px 12px 0px');
 h.hud.parts.archive.Caption.style.fontSize='21px';h.refresh();assert.equal(h.nodes.HandoffCollectionCaption.style.fontSize,'21px');
 for(const [width,height,pixelScale]of [[960,720,1],[1280,720,1],[1920,1080,1],[2560,1440,1.25],[3440,1440,1]]){
  h.hud.top.actualuiscale_x=pixelScale;const scale=Math.min((width-16)/1672,height/941);h.hud.layout(scale);const styles=Object.fromEntries(Object.entries(h.hud.entries).map(([key,panel])=>[key,{...panel.style}]));h.refresh();
  assert.equal(h.entry().style.width,h.hud.entries.archive.style.width);assert.equal(h.entry().style.height,h.hud.entries.archive.style.height);
  assert.equal(h.nodes.HandoffCollectionIcon.style.width,h.hud.parts.archive.Icon.style.width);assert.equal(h.nodes.HandoffCollectionCaption.style.fontSize,h.hud.parts.archive.Caption.style.fontSize);
  const [x]=h.entry().style.position.split(' ').map(parseFloat),right=x+parseFloat(h.entry().style.width),statusScale=Math.min(width/1672,height/941),statusLeft=(width-1672*statusScale)/2+722*statusScale;
  assert(right<statusLeft,'The added regular entry stays before the existing status row');assert(right<width,'The entry remains within the viewport');
  for(const [key,panel]of Object.entries(h.hud.entries)){assert.deepEqual({...panel.style},styles[key]);assert.equal(panel.events.onactivate,events[key]);}
 }
 h.cfg.SurvivalCollectionNav.Dispose();
});

test('zero-layout boot waits safely and reference replacement recovers without generation changes',()=>{
 const h=fixture(),entry=h.entry(),archive=h.hud.entries.archive;
 h.hud.top.style.width='0px';h.refresh();assert.equal(entry.visible,false);h.click(entry);assert.equal(h.opened.length,0);
 h.hud.layout();archive.style.width='0px';h.refresh();assert.equal(entry.visible,false);
 h.hud.layout();h.refresh();assert.equal(entry.visible,true);
 // Native panels need not expose a JS paneltype field for geometry reuse.
 archive.paneltype=0;h.refresh();assert.equal(entry.visible,true);
 archive.DeleteAsync();h.refresh();assert.equal(entry.visible,true);assert.equal(entry.style.width,h.hud.entries.treasure.style.width);
 h.hud.top.style.visibility='collapse';h.refresh();assert.equal(entry.visible,false);h.hud.top.style.visibility='visible';h.refresh();assert.equal(entry.visible,true);
 for(const panel of Object.values(h.hud.entries))if(panel.IsValid())panel.DeleteAsync();h.refresh();assert.equal(entry.visible,false,'Effects alone is not a regular navigation reference');
 h.cfg.SurvivalCollectionNav.Dispose();
});
