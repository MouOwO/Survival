const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const bootstrap=fs.readFileSync('panorama/src/scripts/custom_game/ui_bootstrap.js','utf8');
const source=bootstrap.slice(bootstrap.indexOf('    // BEGIN shared box-selection filter'),bootstrap.indexOf('    // END shared box-selection filter'));
const mouseCode=bootstrap.slice(bootstrap.indexOf('    GameUI.SetMouseCallback('),bootstrap.indexOf('    if (Game.AddCommand',bootstrap.indexOf('    GameUI.SetMouseCallback(')));
function harness(){
 let now=1000,selection=[1],point=[100,100],mode=0,shift=false,consumed=false,mouse,world=true,mouseDown=false;
 const cfg={SurvivalInputLifecycleGeneration:1,HandoffWorldOcclusion:[]},jobs=[],events={},calls=[],keys={};
 const units=new Map([[1,'npc_dota_hero_doom_bringer'],[2,'building_main_city'],[3,'npc_survival_lumberjack'],[4,'asset_proxy_tower_lina'],[5,'enemy_tree'],[6,'npc_survival_builder_proxy'],[7,'npc_dota_unit_ultimate_tower'],[8,'native_building'],[9,'npc_dota_hero_axe'],[10,'npc_survival_wave_monster']]);
 cfg.SurvivalInputDispatcher={generation:1,RegisterKeyHandler:(id,fn)=>keys[id]=fn};
 cfg.SurvivalSelectionResolver={BuilderEntity:()=>6,SetDisplayIdentityMode:()=>{}};
 const env={Date:{now:()=>now},CLICK_BEHAVIORS:{DOTA_CLICK_BEHAVIOR_NONE:0},
  $:{GetContextPanel:()=>({IsValid:()=>true}),Schedule:(delay,fn)=>jobs.push({at:now+delay*1000,fn}),Warning:()=>{}},
  Game:{GetLocalPlayerID:()=>0},Players:{GetSelectedEntities:()=>selection,GetPlayerHeroEntityIndex:()=>1},
  Entities:{IsValidEntity:id=>units.has(id),GetUnitName:id=>units.get(id),IsBuilding:id=>id===8},
  GameUI:{CustomUIConfig:()=>cfg,GetCursorPosition:()=>point,GetClickBehaviors:()=>mode,GetScreenWorldPosition:()=>world?[0,0,0]:null,IsShiftDown:()=>shift,
   IsMouseDown:()=>mouseDown,SetMouseCallback:fn=>mouse=fn,SelectUnit:(id,add)=>{calls.push([id,add]);selection=add?selection.concat(id):[id];(events.dota_player_update_selected_unit||[]).forEach(fn=>fn({}));}},
  GameEvents:{Subscribe:(name,fn)=>{(events[name]||(events[name]=[])).push(fn);}},
  inputConfig:cfg,mouseHandlers:{},mouseHandlerOrder:[],dispatch:()=>consumed};
 vm.createContext(env);vm.runInContext(source,env);vm.runInContext(mouseCode,env);
 function advance(ms=250){const target=now+ms;let count=0;while(jobs.some(j=>j.at<=target)){jobs.sort((a,b)=>a.at-b.at);const job=jobs.shift();now=job.at;job.fn();assert(++count<100,'no callback loop');}now=target;}
 function native(ids){selection=ids;(events.dota_player_update_selected_unit||[]).forEach(fn=>fn({}));}
 return {cfg,calls,units,advance,native,get:()=>Array.from(selection),set:(v)=>{selection=v;},mode:v=>mode=v,shift:v=>shift=v,consume:v=>consumed=v,world:v=>world=v,
  press:(x=100,y=100,event='pressed',button=0)=>{point=[x,y];if(button===0)mouseDown=true;return mouse(event,button);},release:(x=200,y=200)=>{point=[x,y];mouseDown=false;return mouse('released',0);},silentRelease:(x=200,y=200)=>{point=[x,y];mouseDown=false;},key:k=>keys.box_selection_cancel(k,true),reload:()=>{cfg.SurvivalInputLifecycleGeneration++;}};
}
let tests=0;function test(name,fn){fn();tests++;console.log('PASS '+name);}
test('mixed drag keeps heroes/workers and excludes every building proxy/tree',()=>{const h=harness();h.press();h.release();h.native([1,2,3,4,5,7,8,9]);h.advance();assert.deepEqual(h.get(),[1,3,9]);assert.deepEqual(h.calls,[[1,false],[3,true],[9,true]]);});
test('single click including slight hand jitter still selects building',()=>{const h=harness();h.press();h.release(104,103);h.native([2]);h.advance();assert.deepEqual(h.get(),[2]);assert.equal(h.calls.length,0);});
test('building-only drag restores previous selection',()=>{const h=harness();h.set([1,3]);h.press();h.release();h.native([2,4]);h.advance();assert.deepEqual(h.get(),[1,3]);});
test('one building in rectangle is allowed',()=>{for(const id of [2,4,7,8]){const h=harness();h.press();h.release();h.native([id]);h.advance();assert.deepEqual(h.get(),[id]);}});
test('first selection can fall back to builder',()=>{const h=harness();h.set([]);h.press();h.release();h.native([2,4]);h.advance();assert.deepEqual(h.get(),[6]);});
test('Shift preserves manually selected buildings but excludes newly boxed ones',()=>{const h=harness();h.set([2]);h.shift(true);h.press();h.release();h.native([2,1,4]);h.advance();assert.deepEqual(h.get(),[2,1]);});
test('ability targeting and consumed placement input bypass filter',()=>{for(const type of ['target','placement']){const h=harness();if(type==='target')h.mode(3);else h.consume(true);h.press();h.mode(0);h.consume(false);h.release();h.native([2]);h.advance();assert.deepEqual(h.get(),[2]);}});
test('HUD/minimap drags and modal clicks bypass filter',()=>{for(const block of ['hud','modal','outside']){const h=harness();if(block==='hud')h.cfg.HandoffWorldOcclusion=[{x:0,y:0,width:300,height:300}];if(block==='modal')h.cfg.SurvivalUILayers={Top:()=>({})};if(block==='outside')h.world(false);h.press();h.release();h.native([2]);h.advance();assert.deepEqual(h.get(),[2]);}});
test('right click and double click are unchanged',()=>{for(const pair of [['pressed',1],['doublepressed',0]]){const h=harness();h.press(100,100,...pair);h.release();h.native([2]);h.advance();assert.deepEqual(h.get(),[2]);}});
test('native selection delayed one frame is filtered',()=>{const h=harness();h.press();h.release();h.advance(10);h.native([1,2]);h.advance();assert.deepEqual(h.get(),[1]);});
test('later deliberate click/control-group key cancels pending correction',()=>{for(const action of ['mouse','key']){const h=harness();h.press();h.release();if(action==='mouse')h.press(250,250);else h.key('1');h.native([2]);h.advance();assert.deepEqual(h.get(),[2]);}});
test('reload invalidates old scheduled selection writes',()=>{const h=harness();h.press();h.release();h.native([1,2]);h.reload();h.advance();assert.deepEqual(h.get(),[1,2]);assert.equal(h.calls.length,0);});
test('stale entity and sparse native selection are handled',()=>{const h=harness();h.press();h.release();h.native({'0':1,'1':2,'2':999});h.advance();assert.deepEqual(h.get(),[1]);});
test('empty drag and ordinary mobile group do not rewrite selection',()=>{for(const ids of [[],[1,3,9]]){const h=harness();h.press();h.release();h.native(ids);h.advance();assert.deepEqual(h.get(),ids);assert.equal(h.calls.length,0);}});
test('native rectangle can reintroduce buildings after the first correction',()=>{const h=harness();h.press();h.release();h.native([1,2,3]);h.advance(40);assert.deepEqual(h.get(),[1,3]);h.native([1,2,3,4]);h.advance(80);assert.deepEqual(h.get(),[1,3]);});
test('a delayed final rectangle update is filtered without affecting later deliberate selection',()=>{const h=harness();h.press();h.release();h.advance(300);h.native([1,2]);h.advance(100);assert.deepEqual(h.get(),[1]);h.advance(400);h.native([1,2]);h.advance();assert.deepEqual(h.get(),[1,2]);});
test('actual engine path: press-only callback still filters after native mouse release',()=>{const h=harness();h.press();h.advance(50);h.native([1,2,3,4]);h.silentRelease();h.advance();assert.deepEqual(h.get(),[1,3]);assert.equal(h.cfg.SurvivalBoxSelectionFilter.Inspect().lastFilter.source,'mouse_state');});
test('press-only single click retains intentional building selection',()=>{const h=harness();h.press();h.native([2]);h.silentRelease(103,102);h.advance();assert.deepEqual(h.get(),[2]);});
test('building-only drag does not repeatedly reselect an already selected building',()=>{const h=harness();h.set([2]);h.press();h.silentRelease();h.native([2]);h.advance();assert.deepEqual(h.get(),[2]);assert.equal(h.calls.length,0);});
console.log('BOX_SELECTION_FILTER_PASS '+tests+' scenarios');

test('Shift adds one boxed building to existing group',()=>{const h=harness();h.set([1,3]);h.shift(true);h.press();h.release();h.native([1,3,2]);h.advance();assert.deepEqual(h.get(),[1,3,2]);});
test('one resource tree is still excluded',()=>{const h=harness();h.press();h.release();h.native([5]);h.advance();assert.deepEqual(h.get(),[1]);});
