const test=require('node:test'),assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
function fixture(){
 const h=createHarness(),Panel=h.root.constructor,stack=[],opened=[],closed=[];
 h.cfg.SurvivalUIRegistry={tokens:{},assets:{},pending:{},aliases:{},projectPaths:{}};
 h.load('common/ui_components.js'); // Real Lifecycle cancellation/generation behavior.
 h.cfg.SurvivalUILayers={Top:()=>stack.at(-1)||null,CloseTop(){closed.push(stack.pop());}};
 function view(id){return {Open(){opened.push(id);stack.push(id);},Close(){assert.equal(stack.at(-1),id);closed.push(stack.pop());},IsOpen:()=>stack.includes(id)};}
 h.cfg.SurvivalCollection=view('collection');h.cfg.SurvivalArchive=view('archive');h.cfg.SurvivalDaily=view('daily_rewards');h.cfg.SurvivalVIP=view('vip');
 h.load('common/purple_shell.js');
 function makeHUD(scale=1,x=8,y=6){
  const host=new Panel('Panel',h.root,'HandoffHUD'),top=new Panel('Panel',host,'HandoffTop'),effects=new Panel('Button',top,'HandoffCombatEffects');
  top.style.width=630*scale+'px';top.style.height=94*scale+'px';top.style.position=`${x}px ${y}px 0px`;
  effects.style.position=`${522*scale}px ${6*scale}px 0px`;effects.style.width=96*scale+'px';effects.style.height=86*scale+'px';
  effects.SetPanelEvent('onactivate',()=>opened.push('effects'));
  return {host,top,effects};
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
 assert.equal(h.entry().GetParent(),h.hud.host);assert.equal(h.entry().style.position,'634px 12px 0px');assert.equal(h.entry().style.width,'96px');
 assert.equal(h.nodes.HandoffCollectionCaption.text,'收藏');assert.equal(h.nodes.HandoffCollectionIcon.image,'file://{images}/custom_game/collection_gw2_v1/collection_icon.png');
 const tree=h.counts.tree,writes=h.counts.style;
 for(let i=0;i<8;i++)h.flushFinite();
 assert.equal(h.counts.tree,tree,'steady refresh uses cached panels');assert.equal(h.counts.style,writes,'stable geometry does not rewrite styles');assert.equal(h.timers().length,1);
 h.hud.top.style.width='315px';h.refresh();
 assert.equal(h.entry().style.position,'321px 9px 0px');assert.equal(h.entry().style.width,'48px');assert.equal(h.nodes.HandoffCollectionCaption.style.fontSize,'11px');
 assert.deepEqual({...h.hud.effects.style},effectStyle);assert.equal(h.hud.effects.events.onactivate,event);
 h.hud.top.visible=false;h.refresh();assert.equal(h.entry().visible,false);
 h.hud.top.visible=true;h.refresh();assert.equal(h.entry().visible,true);
 h.cfg.SurvivalCollectionNav.Dispose();
});
test('module and HUD reload leave one button and one lifecycle timer; stale callbacks cannot recreate it',()=>{
 const h=fixture(),old=h.cfg.SurvivalCollectionNav,entry=h.entry(),stale=h.timers()[0].fn;
 h.load('collection_nav.js');assert.equal(old.IsAlive(),false);assert.equal(entry.IsValid(),false);assert.equal(h.timers().length,1);
 const fresh=h.entry();stale();assert.equal(h.entry(),fresh);assert.equal(h.timers().length,1);
 h.hud.host.DeleteAsync();h.cfg.HandoffGeneration++;h.hud=h.makeHUD(.75,12,4);h.refresh();
 assert.equal(h.entry().GetParent(),h.hud.host);assert.equal(h.entry().style.position,'482px 9px 0px');assert.equal(h.entry().style.width,'72px');
 assert.equal(h.hud.host.children.filter(p=>p.id==='HandoffNav_collection').length,1);
 const api=h.cfg.SurvivalCollectionNav,queued=h.timers()[0].fn;h.root.DeleteAsync();
 assert.doesNotThrow(()=>{h.flushFinite();queued();api.Dispose();api.Dispose();});assert.equal(api.IsAlive(),false);assert.equal(h.timers().length,0);
});
test('missing HUD waits locally and missing collection API cannot open a partial feature',()=>{
 const h=fixture();delete h.cfg.SurvivalCollection;h.refresh();assert.equal(h.entry().enabled,false);
 h.click(h.entry());assert.deepEqual(h.opened,[]);
 h.hud.top.DeleteAsync();h.cfg.HandoffGeneration++;h.refresh();assert.equal(h.entry().visible,false);
 const Panel=h.root.constructor,top=new Panel('Panel',h.hud.host,'HandoffTop');top.style.width='630px';top.style.position='8px 6px 0px';new Panel('Button',top,'HandoffCombatEffects');
 h.cfg.SurvivalCollection={Open:()=>h.opened.push('collection'),Close(){}};
 for(let i=0;i<5;i++)h.flushFinite();
 assert.equal(h.entry().visible,true);assert.equal(h.entry().enabled,true);assert.equal(h.timers().length,1);
 h.cfg.SurvivalCollectionNav.Dispose();
});
