'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const file=process.argv[2]||'panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js';
const baselineFile=process.argv[3]||'output/extreme_perf_20261008/hud_hotpaths_game_before/panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.js';
const source=fs.readFileSync(file,'utf8');
function between(s,first,last){const a=s.indexOf(first),b=s.indexOf(last,a+first.length);assert(a>=0&&b>a,first);return s.slice(a,b);}
function fixture(s){
 const counters={reads:0,writes:0,queries:0,classes:0},trace=[],env={generation:1,layoutRevision:0,now:1000};
 class Panel{
  constructor(id,parent=null){this.id=id;this.parent=parent;this.children=[];this.alive=true;this.visible=true;this.text='';this.styleWrites=[];this.unreadableKeys=[];this.style=new Proxy({}, {get:(o,k)=>{counters.reads++;if(this.unreadableKeys.includes(k))return null;const value=o[k];if(env.normalizeStyle&&typeof value==='string'){if(k==='position'&&/px/.test(value))return value.split(/\s+/).map(v=>Number.parseFloat(v).toFixed(1)+'px').join('  ');if(/^-?[\d.]+px$/.test(value))return Number.parseFloat(value).toFixed(1)+'px';if(k==='transform'&&value==='none')return 'scale3d(1.0, 1.0, 1.0)';}return value;},set:(o,k,v)=>{counters.writes++;trace.push([this.id,k,v]);this.styleWrites.push([k,v]);o[k]=v;return true;}});if(parent)parent.children.push(this);}
  IsValid(){return this.alive;}GetParent(){return this.parent;}
  GetChildCount(){return this.children.length;}GetChild(i){return this.children[i];}BHasClass(){return false;}
  SetParent(parent){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=parent;if(parent)parent.children.push(this);}
  FindChildTraverse(id){counters.queries++;function search(p){for(const c of p.children){if(c.id===id)return c;const v=search(c);if(v)return v;}return null;}return search(this);}
  SetHasClass(){counters.classes++;}SetImage(uri){this.image=uri;}
  GetPositionWithinWindow(){return {x:0,y:0};}AddClass(){}RemoveClass(){}
 }
 const root=new Panel('root'),ctx=new Panel('ctx',root);
 Object.assign(env,{root,ctx,Date:{now:()=>env.now},cfg:{},nodes:{},topButtons:{},assets:{key_plate:{file:'key.png'}},stats:[['attack','CombatAttackValue'],['armor','CombatArmorValue'],['attack_speed','CombatAttackSpeedValue'],['strength','CombatStrengthValue'],['agility','CombatAgilityValue'],['intelligence','CombatIntellectValue']],unit:7,selectedUnit:()=>env.unit,compact:String,
  text:(id,v)=>{if(env.nodes[id]&&env.nodes[id].text!==String(v))env.nodes[id].text=String(v);},
  statVisibility:()=>({combat:true,attributes:true}),buildingPresentation(){},available:id=>env.availability[id],availability:{vip:true,benefit:true,survival_shop:true},navWindowIds:{survival_shop:'survival_shop',treasure:'treasure',archive:'archive',lottery:'lottery',benefit:'benefit'},activeNavId:undefined,
  valid:p=>!!(p&&p.IsValid()),$: {Msg(){}}});
 vm.createContext(env);
 const cached=s.includes('    function findCached(')?between(s,'    function findCached(','    function style('):'function findCached(p,id){return p.FindChildTraverse(id);}';
 const levelPips=s.includes('    function styleAbilityLevelPips(')?between(s,'    function styleAbilityLevelPips(','    function child('):'';
 vm.runInContext(cached+between(s,'    function style(','    function create(')+levelPips+between(s,'    function child(','    function refreshInventoryPresentation(')+between(s,'    function markActiveNav(','    function topMetric(')+between(s,'    function mirror()','    function compact('),env);
 function reset(){for(const k of Object.keys(counters))counters[k]=0;trace.length=0;}
 return {env,counters,trace,Panel,reset};
}
const ids=['ButtonAndLevel','ButtonWithLevelUpTab','ButtonWell','ButtonSize','AbilityButton','AbilityImage','ItemImage','Cooldown','CooldownOverlay','HotkeyContainer','Hotkey','HotkeyText','AbilityBevel','ShineContainer','PassiveAbilityBorder'];
function squareCase(s){const f=fixture(s),slot=new f.Panel('Ability0',f.env.ctx),nodes={};for(const id of ids)nodes[id]=new f.Panel(id,slot);nodes.Cooldown.style.clip='engine-live-cooldown';f.env.square(slot);f.reset();for(let i=0;i<20;i++){f.env.now+=10;f.env.square(slot);}return {...f,slot,children:nodes,stable:{...f.counters}};}
const fixed=squareCase(source);
assert.equal(fixed.env.square.cacheStats,undefined,'diagnostics allocate no counters by default');
const diagnostic=squareCase(source);let captureToken=1;
diagnostic.env.cfg.SurvivalClientCallbackProbe={CaptureToken:()=>captureToken};diagnostic.env.normalizeStyle=true;
for(let i=0;i<3;i++)diagnostic.env.square(diagnostic.slot);
assert.equal(diagnostic.env.inspectSquareCache().square.calls,3);
assert.equal(diagnostic.env.inspectSquareCache().square.geometryChanged,0,'equivalent native normalized dimensions/position/identity do not invalidate geometry');
assert.equal(diagnostic.env.inspectSquareCache().square.hits,3);
assert.equal(diagnostic.env.inspectSquareCache().square.full,0);
const beforeNormalized='output/extreme_perf_20261008/square_normalized_game_before/panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.js';
if(fs.existsSync(beforeNormalized)){
 const old=squareCase(fs.readFileSync(beforeNormalized,'utf8'));old.env.cfg.SurvivalClientCallbackProbe={CaptureToken:()=>1};old.env.normalizeStyle=true;
 for(let i=0;i<3;i++)old.env.square(old.slot);
 assert.equal(old.env.inspectSquareCache().square.geometryChanged,3,'saved production source reproduces the observed native failure');
 assert.equal(old.env.inspectSquareCache().square.hits,0);
 assert(old.env.inspectSquareCache().square.samples.some(s=>s.expected==='116px'&&s.actual==='116.0px'));
}
for(const [actual,expected] of [['116.0px','116px'],[' 116.000px ','116px'],['0.0px  0.000px 0px','0px 0px 0px'],['scale3d(1.0, 1.0, 1.0)','none'],['matrix3d(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)','none']])assert.equal(diagnostic.env.sameGeometryValue(actual,expected),true,actual);
for(const [actual,expected] of [['72px','116px'],['116%','116px'],['auto','116px'],['undefined','116px'],['0px 1px 0px','0px 0px 0px'],['0px 0px','0px 0px 0px'],['scale3d(.5,1,1)','none'],['matrix3d(1,0,0,0,0,1,0,0,0,0,1,0,1,0,0,1)','none'],['matrix3d(1,,,0,0,1,0,0,0,0,1,0,0,0,0,1)','none']])assert.equal(diagnostic.env.sameGeometryValue(actual,expected),false,actual);
diagnostic.slot.style.width='72px';diagnostic.env.square(diagnostic.slot);assert.equal(diagnostic.slot.style.width,'116.0px','a real native resize still restores immediately');
assert.equal(diagnostic.env.inspectSquareCache().square.geometryChanged,1);
assert(diagnostic.env.inspectSquareCache().square.samples.some(s=>s.actual==='72.0px'));
captureToken=0;diagnostic.env.square(diagnostic.slot);assert.equal(diagnostic.env.inspectSquareCache().square.calls,4,'Stop disables new samples');
captureToken=2;diagnostic.env.square(diagnostic.slot);assert.equal(diagnostic.env.inspectSquareCache().square.calls,1,'next capture resets diagnostic counters');
assert.equal(fixed.children.Cooldown.style.clip,'engine-live-cooldown','native cooldown animation remains untouched');
assert.equal(fixed.slot.children.length,ids.length,'skin creates no native descendants');
if(fs.existsSync(baselineFile)){
 const old=squareCase(fs.readFileSync(baselineFile,'utf8'));
 assert(fixed.stable.queries<old.stable.queries/4,'stable native descendants avoid repeated traverse');
 assert(fixed.stable.reads<old.stable.reads/3,'stable slots avoid full cosmetic style reads');
 console.log('SQUARE_STABLE_COUNTS',JSON.stringify({before:old.stable,after:fixed.stable}));
}
// A newly created native image is styled on the very next refresh.
const previous=fixed.children.AbilityImage;fixed.slot.children=fixed.slot.children.filter(p=>p!==previous);previous.parent=null;
const replacement=new fixed.Panel('AbilityImage',fixed.slot);fixed.env.square(fixed.slot);
assert.equal(replacement.style.position,'6px 6px 0px');assert.equal(replacement.style.width,'104px');
// A whole valid subtree can move away; cached child references must not win.
const oldWell=fixed.children.ButtonWell,oldNested=new fixed.Panel('AbilityImage',oldWell);
fixed.slot.children=fixed.slot.children.filter(p=>p!==replacement);replacement.parent=null;
fixed.env.square(fixed.slot);assert.equal(oldNested.style.width,'104px');
fixed.slot.children=fixed.slot.children.filter(p=>p!==oldWell);oldWell.parent=new fixed.Panel('detached');
const newWell=new fixed.Panel('ButtonWell',fixed.slot),newNested=new fixed.Panel('AbilityImage',newWell);
fixed.env.square(fixed.slot);assert.equal(newNested.style.position,'6px 6px 0px');
// Geometry overrides recover immediately; cosmetic resets recover within 1s.
fixed.slot.style.width='72px';newNested.style.position='20px 20px 0px';fixed.env.square(fixed.slot);
assert.equal(fixed.slot.style.width,'116px');assert.equal(newNested.style.position,'6px 6px 0px');
newWell.style.border='1px solid red';fixed.env.now+=1001;fixed.env.square(fixed.slot);assert.equal(newWell.style.border,'0px');
newWell.style.border='2px solid red';fixed.env.square(fixed.slot,true);assert.equal(newWell.style.border,'0px','selection/native reflow forces full restore');
// Missing ability children are never held behind the optional retry interval.
const lateSlot=new fixed.Panel('Ability1',fixed.env.ctx);fixed.env.square(lateSlot);const late=new fixed.Panel('AbilityImage',lateSlot);fixed.env.square(lateSlot);assert.equal(late.style.width,'104px');
// A forced cosmetic repair uses final geometry once. In particular, a native
// button well must never cycle 0 ->116 ->0 minimums or116 ->10000 ->116 maximums.
fixed.reset();for(const p of [newWell,late])p.styleWrites.length=0;fixed.env.square(fixed.slot,true);
assert.equal(fixed.counters.writes,0,'stable forced square has no intermediate min/max/identity writes');
assert.equal(newWell.styleWrites.length,0);
const staggered=fixture(source),staggeredSlots=Array.from({length:12},(_,i)=>{
 const p=new staggered.Panel(i<6?'Ability'+i:'inventory_slot_'+(i-6),staggered.env.ctx);for(const id of ids)new staggered.Panel(id,p);staggered.env.square(p);return p;
});
staggered.env.cfg.SurvivalClientCallbackProbe={CaptureToken:()=>1};const repairBatches=[];let previousFull=0;
for(let tick=1;tick<=10;tick++){
 staggered.env.now=1000+tick*100;for(const p of staggeredSlots)staggered.env.square(p);
 const metrics=staggered.env.inspectSquareCache().square;repairBatches.push(metrics.full-previousFull);previousFull=metrics.full;
}
assert.equal(previousFull,12,'all native slots receive their first periodic repair within1s');
assert(Math.max(...repairBatches)<staggeredSlots.length/2,'periodic slot repairs are spread across ticks');
assert.equal(staggered.env.inspectSquareCache().square.periodic,12,'diagnostics report the real1s periodic repair');
for(const p of staggeredSlots)assert.equal(p.__handoffSquare.repairAt-p.__handoffSquare.checkedAt,1000,'each later periodic deadline stays at1s');
function mirrorCase(s){
 const f=fixture(s),e=f.env;
 for(const [target,origin] of [['HandoffName','SurvivalHeroName'],['HandoffLevel','SurvivalHeroLevel'],['Handoff_hp_value','SurvivalHeroHealthText'],['Handoff_mp_value','SurvivalHeroManaText']]){e.nodes[target]=new f.Panel(target,e.ctx);new f.Panel(origin,e.ctx).text=origin;}
 for(const type of ['hp','mp']){e.nodes['Handoff_'+type+'_fill']=new f.Panel('fill',e.ctx);new f.Panel('SurvivalHero'+(type==='hp'?'Health':'Mana')+'Fill',e.ctx).style.width='42%';}
 for(const [stat,origin] of e.stats){new f.Panel(origin,e.ctx).text='20';for(const prefix of ['HandoffStatIcon_','HandoffStatName_','HandoffStat_','HandoffStatBonus_','HandoffStatPercent_'])e.nodes[prefix+stat]=new f.Panel(prefix+stat,e.ctx);}
 e.nodes.HandoffLevelPlate=new f.Panel('levelPlate',e.ctx);e.nodes.HandoffLevelBounds=new f.Panel('levelBounds',e.ctx);
 for(const id of ['vip','benefit','survival_shop'])e.topButtons[id]=new f.Panel(id,e.ctx);
 e.nodes.HandoffNavIcon_vip=new f.Panel('vipIcon',e.ctx);
 const windows={};for(const id of ['CustomShopWindow','TreasureWindow','ArchiveWindow','LotteryWindow','DailyWindow','DailyEntry','PassEntry','HeroCombatDebugPanel']){windows[id]=new f.Panel(id,e.ctx);windows[id].visible=false;}
 e.snapshot={attack_max:100,display_attack_bonus:30,display_attack_pct:5};e.cfg.HandoffCombat={Snapshot:unit=>unit===e.unit?e.snapshot:null};
 e.mirror();f.reset();for(let i=0;i<20;i++)e.mirror();return {...f,windows,stable:{...f.counters}};
}
const mirrored=mirrorCase(source);
if(fs.existsSync(baselineFile)){
 const old=mirrorCase(fs.readFileSync(baselineFile,'utf8'));
 assert(mirrored.stable.queries<old.stable.queries/4,'stable mirror does not repeatedly traverse root or ctx');
 assert.equal(mirrored.stable.classes,0,'unchanged active entry does not repeatedly write all classes');
 console.log('MIRROR_STABLE_COUNTS',JSON.stringify({before:old.stable,after:mirrored.stable}));
}
mirrored.env.snapshot.attack_max=220;mirrored.env.snapshot.display_attack_bonus=70;mirrored.env.unit=19;mirrored.env.mirror();
assert.equal(mirrored.env.nodes.HandoffStat_attack.text,'150');assert.equal(mirrored.env.nodes.HandoffStatBonus_attack.text,'+70');
const heroName=mirrored.env.ctx.FindChildTraverse('SurvivalHeroName');heroName.text='new selected owner';mirrored.env.mirror();assert.equal(mirrored.env.nodes.HandoffName.text,'new selected owner');
heroName.alive=false;heroName.parent.children=heroName.parent.children.filter(p=>p!==heroName);new mirrored.Panel('SurvivalHeroName',mirrored.env.ctx).text='rebuilt source';mirrored.env.mirror();assert.equal(mirrored.env.nodes.HandoffName.text,'rebuilt source');
mirrored.windows.DailyWindow.visible=true;mirrored.env.syncActiveNav();assert.equal(mirrored.env.activeNavId,'benefit');
mirrored.windows.DailyWindow.visible=false;mirrored.env.syncActiveNav();assert.equal(mirrored.env.activeNavId,null);
// Optional-only negative caches expire; no poll/timer is introduced.
assert.equal(mirrored.env.findCached(mirrored.env.root,'LateOptional',true),null);const optional=new mirrored.Panel('LateOptional',mirrored.env.ctx);
assert.equal(mirrored.env.findCached(mirrored.env.root,'LateOptional',true),null);mirrored.env.now+=501;assert.strictEqual(mirrored.env.findCached(mirrored.env.root,'LateOptional',true),optional);
// Execute the complete real nativeLayout -> fitNativeSkills -> square chain.
// Switching the outer canvas/selected abilities does not change slot-local size.
function nativeReflowCase(s){
 const f=fixture(s),e=f.env,map={};
 function native(id,parent=e.root){return map[id]=new f.Panel(id,parent);}
 const lower=native('lower_hud'),outer=native('center_with_stats',lower),block=native('center_block',outer);
 const portrait=native('PortraitGroup',block);native('PortraitContainer',portrait);native('portraitHUD',portrait);
 const branch=native('AbilitiesAndStatBranch',block),list=native('abilities',branch),inv=native('inventory',block);
 native('minimap');native('inventory_composition_layer_container');native('buffs');native('debuffs');
 const skills=Array.from({length:6},(_,i)=>{const p=new f.Panel('Ability'+i,list);for(const id of ids)new f.Panel(id,p);return p;});
 const items=Array.from({length:6},(_,i)=>{const p=new f.Panel('inventory_slot_'+i,inv);for(const id of ids)new f.Panel(id,p);return p;});
 Object.assign(e,{native:id=>map[id]||null,missing:[],background:new f.Panel('background',e.ctx),currentEntries:[],skillPanels:[],layoutMinimap(){},runtimeCalls:0,completed:-1});
 e.ctx.actualuiscale_x=1;e.ctx.actualuiscale_y=1;e.normalizeStyle=true;
 e.cfg.HandoffCombat={NativeEntries:()=>e.currentEntries,ApplyRuntime:(p,a)=>{e.runtimeCalls++;p.style.opacity=a===e.completed?'0':'1';p.hittest=a!==e.completed;},IsCompleted:a=>a===e.completed};
 const wrappers=s.includes('    function nativeAbilityWrappers(')?between(s,'    function nativeAbilityWrappers(','    function findCached('):'';
 vm.runInContext(wrappers+between(s,'    function fitNativeSkills(','    // Called synchronously')+between(s,'    function nativeLayout(','    // Resolve navigation'),e);
 const g={width:1352,height:330,x:300,y:600,scale:0.5,portraitSize:264,heroWidth:493,centerWidth:1218,inventoryX:1951,minimapSize:220};
 function select(city){e.unit=city?19:7;e.currentEntries=Array.from({length:city?2:6},(_,i)=>({ability:(city?200:100)+i}));assert.equal(e.nativeLayout({...g,heroWidth:city?0:493,height:city?205:330,centerWidth:city?800:1218}),true);}
 select(false);e.cfg.SurvivalClientCallbackProbe={CaptureToken:()=>1};
 for(let i=0;i<20;i++){select(i%2===0);e.now+=10;}
 assert.equal(e.runtimeCalls,86,'each selected action still receives runtime refresh');
 assert.equal(e.skillPanels.length,6);for(const p of skills){assert.equal(p.style.width,'116.0px');assert.equal(p.__survivalWindowWidth,58);}
 for(const p of items)assert.equal(p.style.width,'116.0px');
 return {...f,e,map,select,g,skills,items,list,metrics:{...e.inspectSquareCache().square}};
}
const reflow=nativeReflowCase(source);
assert.equal(reflow.metrics.forced,0,'outer selection reflow no longer forces every existing slot');
assert(reflow.metrics.hits>reflow.metrics.full,'stable slots survive repeated builder/city reflow');
const forceBefore='output/extreme_perf_20261008/slot_force_game_before/panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.js';
if(fs.existsSync(forceBefore)){const old=nativeReflowCase(fs.readFileSync(forceBefore,'utf8'));assert(old.metrics.forced>0);assert(reflow.metrics.full<old.metrics.full/2);console.log('NATIVE_REFLOW_COUNTS',JSON.stringify({before:old.metrics.full,after:reflow.metrics.full,hits:reflow.metrics.hits}));}
reflow.e.completed=102;reflow.select(false);assert.equal(reflow.skills[2].style.width,'0.0px');assert.equal(reflow.skills[2].hittest,false);
reflow.e.completed=-1;reflow.select(false);assert.equal(reflow.skills[2].style.width,'116.0px');assert.equal(reflow.skills[2].hittest,true,'unfinished action regains input immediately');
const oldImage=reflow.skills[1].FindChildTraverse('AbilityImage');oldImage.SetParent(null);const lateImage=new reflow.Panel('AbilityImage',reflow.skills[1]);reflow.select(false);assert.equal(lateImage.style.width,'104.0px');
reflow.skills[0].alive=false;reflow.skills[0].SetParent(null);const newSlot=new reflow.Panel('Ability0',reflow.list);for(const id of ids)new reflow.Panel(id,newSlot);reflow.list.children=reflow.list.children.filter(p=>p!==newSlot);reflow.list.children.unshift(newSlot);reflow.select(false);assert.equal(newSlot.style.width,'116.0px','rebuilt native panel skins immediately');
const well=reflow.items[0].FindChildTraverse('ButtonWell');well.style.border='3px solid red';reflow.e.now+=1001;reflow.select(false);assert.equal(well.style.border,'0.0px','cosmetic reset still restores after bounded check');
// Execute the actual local1s repair, rather than only its scheduler stub below.
// It preserves custom HP/decor geometry, avoids re-binding runtime abilities and
// still restores genuinely overwritten/re-created native geometry.
reflow.reset();const beforeRuntime=reflow.e.runtimeCalls,beforeRevision=reflow.e.layoutRevision;
assert.equal(reflow.e.repairNativeLayout(reflow.g),true);assert.equal(reflow.counters.writes,0,'stable live-normalized native repair writes nothing '+JSON.stringify(reflow.trace));
assert.equal(reflow.e.runtimeCalls,beforeRuntime,'repair does not re-bind or square every skill');assert.equal(reflow.e.layoutRevision,beforeRevision);
const centerBlock=reflow.map.center_block;centerBlock.style.width='71px';reflow.map.buffs.style.position='0px 0px 0px';
centerBlock.unreadableKeys=['horizontalAlign'];reflow.reset();
assert.equal(reflow.e.repairNativeLayout(reflow.g),true);assert.equal(centerBlock.style.width,'1352.0px');assert.equal(reflow.map.buffs.style.position,'503.0px  -42.0px  0.0px');
assert(centerBlock.styleWrites.some(([k,v])=>k==='horizontalAlign'&&v==='left'),'unknown native getter remains a real setter');
centerBlock.unreadableKeys=[];
const portraitContainer=reflow.map.PortraitContainer;portraitContainer.style.opacity='0';reflow.e.repairNativeLayout(reflow.g);assert.equal(portraitContainer.style.opacity,'0','local repair preserves active multi-selection mask');
reflow.e.cfg.SurvivalProductionHUD={};reflow.map.buffs.style.position='503px -100px 0px';reflow.e.repairNativeLayout(reflow.g);
assert.equal(reflow.map.buffs.style.position,'503.0px  -100.0px  0.0px','repair preserves production HUD row offset owned by fast refresh');delete reflow.e.cfg.SurvivalProductionHUD;
const wrapper=new reflow.Panel('new_native_wrapper',reflow.map.AbilitiesAndStatBranch);reflow.list.SetParent(wrapper);
assert.equal(reflow.e.repairNativeLayout(reflow.g),false,'native wrapper replacement falls back to full structure reconstruction');
reflow.select(false);assert.equal(reflow.e.repairNativeLayout(reflow.g),true);assert.equal(wrapper.style.width,'1198.0px');
assert.equal(reflow.e.runtimeCalls,beforeRuntime+6,'full fallback synchronizes selected runtime once');
console.log('TOPNAV_HOTPATH_RECOVERY_PASS: live values/owner, valid detached subtree and replacements, immediate late ability children and geometry restoration, bounded cosmetic/optional retry, cooldown preservation');
console.log('TOPNAV_LOCAL_REPAIR_PASS: stable normalized native repair zero writes, one final min/max assignment, staggered1s slot repair, unknown getter setters, engine overrides and wrapper rebuild recover, multi-selection and production masks preserved');

// Execute the real layout and mirror scheduling with live panel doubles. The
// native setter with an unreadable getter is deliberately NEVER memoized.
function stableLayoutCase(s) {
 const f=fixture(s),e=f.env,map={};
 const nativeIds=['abilities','inventory','PortraitGroup','minimap_container','minimap'];
 for(const id of nativeIds) map[id]=new f.Panel(id,e.root);
 const unreadable={values:{},styleWrites:0};
 unreadable.style=new Proxy({}, {get:()=>null,set:(o,k,v)=>{unreadable.values[k]=v;unreadable.styleWrites++;return true;}});
 unreadable.IsValid=()=>true;
 Object.assign(e,{ready:false,geometry:null,lastSignature:'',layoutRevision:0,layoutRepairAt:0,layoutPanels:[],
  natives:map,missing:[],native:id=>map[id]||null,currentEntries:[],slotFrames:[],
  nativeLayoutCalls:0,repairCalls:0,navigationCalls:0,statsCalls:0,
  top:new f.Panel('top',e.ctx),topStatus:new f.Panel('topStatus',e.ctx),topBackdrop:new f.Panel('topBackdrop',e.ctx),enemyCounter:new f.Panel('enemy',e.ctx),
  bottom:new f.Panel('bottom',e.ctx),background:new f.Panel('background',e.ctx),center:new f.Panel('center',e.ctx),inventory:new f.Panel('decorInventory',e.ctx),
  create:(type,parent,id)=>{const p=new f.Panel(id,parent);e.nodes[id]=p;return p;},
  art:(parent,id)=>{const p=new f.Panel(id,parent);e.nodes[id]=p;return p;},
  centered:(parent,id,x,y,w,h)=>e.place(e.nodes[id+'Bounds']||e.nodes[id],x,y,w,h),
  nine:(parent,id,key,x,y,w,h)=>e.place(parent,x,y,w,h),
  layoutNavigation:()=>e.navigationCalls++,layoutStats:()=>e.statsCalls++,
  canvas:(p,g)=>e.place(p,g.x,g.y,g.width,g.height),
  nativeLayout:g=>{e.nativeLayoutCalls++;e.style(unreadable,{width:'116px',height:'116px'});return true;},
  repairNativeLayout:g=>{e.repairCalls++;e.style(unreadable,{width:'116px',height:'116px'});return true;},
  abilityCount:()=>{e.currentEntries=e.abilityList;return e.currentEntries.length;},
  abilityList:[{ability:100,name:'ability_tower_class_1'},{ability:101,name:'ability_tower_class_2'}]});
 e.ctx.actuallayoutwidth=1672;e.ctx.actuallayoutheight=941;e.ctx.actualuiscale_x=1;e.ctx.actualuiscale_y=1;
 e.cfg.HandoffGeometry=()=>({x:300,y:600,width:1200,height:330,heroWidth:493,centerWidth:700,
  scale:.5,portraitSize:264,attributeX:300,attributeWidth:190,inventoryX:1193,minimapSize:220,barWidth:680});
 for(const kind of ['hp','mp'])for(const suffix of ['_track','_fill','_value']) e.nodes['Handoff_'+kind+suffix]=new f.Panel('Handoff_'+kind+suffix,e.center);
 vm.runInContext(between(s,'    function layout() {','    function revealWhenStable()'),e);
 e.layout();const warmCalls=e.nativeLayoutCalls,warmUnreadable=unreadable.styleWrites;f.reset();
 for(let i=0;i<9;i++){e.now+=100;e.layout();}
 assert.equal(e.nativeLayoutCalls,warmCalls,'stable 0.1s refreshes skip complete native layout');
 assert.equal(f.counters.writes,0,'stable layout produces no redundant style writes');
 assert.equal(f.counters.reads,0,'stable layout does not read decorative/native style getters');
 assert.equal(unreadable.styleWrites,warmUnreadable,'unreadable getters do not cause 10Hz writes');
 e.now+=100;e.layout();
 assert.equal(e.nativeLayoutCalls,warmCalls,'one-second repair does not rebuild the complete custom layout');
 assert.equal(e.repairCalls,1,'one-second local native repair remains active');
 assert.equal(unreadable.styleWrites,warmUnreadable+2,'unreadable getters still get their real setters on repair');
 e.unit=19;e.layout();assert.equal(e.nativeLayoutCalls,warmCalls+1,'selection change updates geometry immediately');
 e.ctx.actuallayoutwidth=1920;e.layout();assert.equal(e.nativeLayoutCalls,warmCalls+2,'viewport resize updates immediately');
 e.abilityList=[{ability:200,name:'ability_tower_class_3'}];e.layout();assert.equal(e.nativeLayoutCalls,warmCalls+3,'ability replacement updates immediately');
 map.abilities=new f.Panel('abilities',e.root);e.layout();assert.equal(e.nativeLayoutCalls,warmCalls+4,'valid native scope replacement updates immediately');
 e.ctx.actualuiscale_x=1.25;e.layout();assert.equal(e.nativeLayoutCalls,warmCalls+5,'UI scale changes update immediately');
 const repairCount=e.nativeLayoutCalls;e.now+=999;e.layout();assert.equal(e.nativeLayoutCalls,repairCount);
 e.now+=1;e.layout();assert.equal(e.nativeLayoutCalls,repairCount,'stable repair leaves custom geometry intact');assert.equal(e.repairCalls,2,'native repair deadline is no later than 1s');
 return {f,e,unreadable};
}
const layoutCase=stableLayoutCase(source);
console.log('TOPNAV_LAYOUT_SPLIT_PASS: stable 10Hz zero structural style reads/writes, 1s real repair including null getters, immediate selection/resize/ability/native scope/UI scale changes');
// Existing mirror fixture executes production mirror(). HP/mana and stat values
// still update between repairs, while stable visibility and clipping do not.
const fastMirror=mirrorCase(source),fastEnv=fastMirror.env;
fastMirror.reset();for(let index=0;index<9;index++){fastEnv.now+=100;fastEnv.mirror();}
assert.equal(fastMirror.counters.writes,0,'stable fast mirror has no redundant style writes');
fastEnv.ctx.FindChildTraverse('SurvivalHeroHealthText').text='123 / 456';
fastEnv.ctx.FindChildTraverse('SurvivalHeroManaText').text='77 / 88';
fastEnv.ctx.FindChildTraverse('SurvivalHeroHealthFill').style.width='27%';
fastEnv.ctx.FindChildTraverse('CombatAttackValue').text='99';fastEnv.snapshot.attack_max=240;fastEnv.snapshot.display_attack_bonus=80;
fastEnv.mirror();assert.equal(fastEnv.nodes.Handoff_hp_value.text,'123 / 456');
assert.equal(fastEnv.nodes.Handoff_mp_value.text,'77 / 88');assert.equal(fastEnv.nodes.Handoff_hp_fill.style.clip,'rect(0%, 27%, 100%, 0%)');
assert.equal(fastEnv.nodes.HandoffStat_attack.text,'160');assert.equal(fastEnv.nodes.HandoffStatBonus_attack.text,'+80');
fastEnv.nodes.HandoffStat_attack.style.visibility='collapse';fastEnv.now+=1000;fastEnv.mirror();
assert.equal(fastEnv.nodes.HandoffStat_attack.style.visibility,'visible','engine visibility overwrite repairs within 1s');
console.log('TOPNAV_FAST_MIRROR_PASS: live HP/mana/fill/stat deltas between structural repairs, stable zero style writes, bounded visibility repair');
