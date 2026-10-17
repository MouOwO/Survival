const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const directory = 'panorama/src/scripts/custom_game/';
const names = {20:'ability_building_blink',21:'ability_destroy_arrow_tower',30:'ability_wall_blink'};
const unitAbilities = {10:[20,21],11:[30],12:[]};
let selected = 11, cooldown = 0, now = 1, nativeAbility = -1, world = [129,191,384];
const panels = new Map(), scheduled = [], listeners = {}, sent = [], errors = [], keys = {}, mouse = {};
function panel(id) {
    const value = {style:{},visible:true,actualuiscale_x:1,actualuiscale_y:1,classes:new Set(),
        AddClass(name){this.classes.add(name);},RemoveClass(name){this.classes.delete(name);},
        SetHasClass(name,active){active?this.classes.add(name):this.classes.delete(name);},
        GetParent(){return null;},FindChildTraverse(name){return panels.get(name);}};
    panels.set(id,value);return value;
}
for (const id of ['GridPlacementRoot','GridPlacementCells','GridPlacementFootprint','GridPlacementTitle',
    'GridPlacementStatus','GridPlacementCursorIcon','SurvivalPointTargetHint']) panel(id);
const $ = id => panels.get(id.replace(/^#/,''));
$.CreatePanel = (_,parent,id) => panel(id); $.GetContextPanel = () => panels.get('GridPlacementRoot');
$.Msg = () => {}; $.Warning = () => {}; $.Schedule = (_,fn) => scheduled.push(fn);
const shared = {SurvivalSelectionResolver:{Resolve:()=>selected},
    SurvivalInputDispatcher:{RegisterKeyHandler:(id,fn)=>keys[id]=fn,
        RegisterMouseHandler:(id,fn)=>mouse[id]=fn},SurvivalPointTargetState:{active:false}};
const environment = {$,Date,GameUI:{CustomUIConfig:()=>shared,GetCursorPosition:()=>[500,500],
    GetScreenWorldPosition:()=>world},Game:{GetGameTime:()=>now,WorldToScreenX:x=>x+1000,
        WorldToScreenY:(_,y)=>y+1000},Entities:{GetUnitName:unit=>unit===11?'building_wall':'building_arrow_tower',
        GetAbility:(unit,slot)=>(unitAbilities[unit]||[])[slot]??-1},
    Abilities:{GetAbilityName:id=>names[id]||'',IsHidden:()=>false,
        GetCooldownTimeRemaining:()=>cooldown,GetLocalPlayerActiveAbility:()=>nativeAbility},
    GameEvents:{Subscribe:(name,fn)=>listeners[name]=fn,SendCustomGameEventToServer:(name,data)=>sent.push({name,data}),
        SendEventClientSide:(name,data)=>errors.push({name,data})},CustomNetTables:{GetTableValue:()=>null},
    Particles:{CreateParticle:()=>0,SetParticleControl:()=>{},DestroyParticleEffect:()=>{},ReleaseParticleIndex:()=>{}},
    ParticleAttachment_t:{PATTACH_WORLDORIGIN:6}};
vm.createContext(environment);
vm.runInContext(fs.readFileSync(directory+'survival_grid_placement.js','utf8'),environment);
vm.runInContext(fs.readFileSync(directory+'building_move.js','utf8'),environment);
const update = scheduled.find(fn=>fn.name==='updateLoop');
const lifecycle = scheduled.find(fn=>fn.name==='lifecycleTick');
const events = name => sent.filter(event=>event.name===name);
const commits = () => events('ui_grid_placement_commit');
const requests = () => events('ui_grid_placement_validate');
const towerProfile = {ability_name:names[20],building_id:'arrow_tower',placement_action:'relocate',
    grid_footprint_x:2,grid_footprint_y:2,preview_model:1};
const wallProfile = {ability_name:names[30],building_id:'wall',display_name:'城墙',placement_action:'relocate',
    grid_footprint_x:4,grid_footprint_y:4,preview_model:1};
const profiles = list => listeners.ui_grid_placement_profiles({cell_size:64,profiles:list});
const begins = [];
shared.SurvivalPointTargetInput = {
    Begin(ability,unit){begins.push({ability,unit});shared.SurvivalPointTargetState={active:true,
        name:names[ability],ability,unit};return true;},
    Cancel(){shared.SurvivalPointTargetState.active=false;}
};
profiles([towerProfile]);
const beforeCold = events('ui_grid_placement_profiles_request').length;
assert(keys.building_move('D',true),'wall D is available without the tower destroy ability');
assert.equal(events('ui_grid_placement_profiles_request').length,beforeCold+1,
    'a cached tower profile cannot satisfy a cold wall request');
assert(shared.SurvivalGridPlacement.IsRelocating(11));
assert.equal(begins.length,0,'wall never starts with the tower profile');
assert.equal(keys.building_move('G',true),false,'wall has no destroy shortcut');
assert.equal(shared.SurvivalArrowTowerTools.TriggerAbility(names[21],11),false,'wall has no destroy button');
keys.grid_placement('ESCAPE',true);
assert.equal(events('ui_grid_placement_preview_end').at(-1).data.ability_name,names[30],
    'cancelling a cold wall session names the wall ability');
assert(!shared.SurvivalGridPlacement.IsRelocating(11));

assert(shared.SurvivalArrowTowerTools.TriggerAbility(names[30],11));
mouse.grid_placement('pressed',0); world=[513,641,384];
profiles([towerProfile,wallProfile]);
assert.equal(commits().length,1,'first cold click resumes exactly once');
assert.deepEqual(begins.at(-1),{ability:30,unit:11});
const coldCommit=commits().at(-1).data;
assert.equal(coldCommit.ability_name,names[30]);
assert.deepEqual([coldCommit.x,coldCommit.y,coldCommit.z],[128,192,384]);
assert.equal(panels.get('GridPlacementTitle').text,'网格移动 · 城墙');
listeners.ui_grid_placement_commit_result({session_id:coldCommit.session_id,success:1});
lifecycle();assert(!shared.SurvivalGridPlacement.IsRelocating(11));

world=[128,192,384]; now++;
assert(keys.building_move('D',true));
const first=requests().at(-1).data;
assert(keys.building_move('D',true));
const second=requests().at(-1).data;
assert(Number(second.session_id)>Number(first.session_id),'wall D starts a fresh session');
assert.equal(second.ability_name,names[30]);
const cells=[];
for(const x of [32,96,160,224])for(const y of [96,160,224,288])cells.push({x,y,z:384,ok:1});
listeners.ui_grid_placement_validation({session_id:second.session_id,request_id:second.request_id,
    ability_name:names[30],success:1,request_anchor_x:2,request_anchor_y:3,anchor_x:2,anchor_y:3,
    world_x:128,world_y:192,world_z:384,cells,area:''});
update();
assert.equal(panels.get('GridPlacementCell0').__dividers.filter(p=>p.visible).length,6,
    'wall relocation displays its real 4 by 4 footprint');
assert(events('ui_grid_placement_pose').some(e=>e.data.ability_name===names[30]&&e.data.entindex===11),
    'model preview carries the wall ability and entity');
world=[257,321,384];mouse.grid_placement('pressed',0);
const landing=commits().at(-1).data;
assert.equal(landing.ability_name,names[30]);
assert.deepEqual([landing.x,landing.y],[256,320]);
listeners.ui_grid_placement_commit_result({session_id:landing.session_id,success:0,error:'build_cell_occupied'});
assert(shared.SurvivalGridPlacement.IsRelocating(11),'occupied landing keeps wall relocation usable');
world=[385,257,384];mouse.grid_placement('pressed',0);
assert(Number(commits().at(-1).data.session_id)>Number(landing.session_id));
assert.equal(commits().at(-1).data.ability_name,names[30]);
shared.SurvivalArrowTowerTools.Cancel();
assert(keys.building_move('D',true)); selected=10; lifecycle();
assert(!shared.SurvivalGridPlacement.IsRelocating(11),'selection change closes wall movement');
assert(keys.building_move('D',true));
assert.equal(requests().at(-1).data.ability_name,names[20],'tower still uses its original profile');
shared.SurvivalArrowTowerTools.Cancel(); selected=11;

cooldown=120;
const beforeCooldown={requests:requests().length,commits:commits().length};
assert(keys.building_move('D',true));
assert(shared.SurvivalArrowTowerTools.TriggerAbility(names[30],11));
assert.equal(shared.SurvivalGridPlacement.BeginRelocation(30,11),false);
shared.SurvivalPointTargetState={active:true,name:names[30],ability:30,unit:11};update();
nativeAbility=30;update();const errorCount=errors.length;
for(let i=0;i<4;i++)update();
assert.equal(errors.length,errorCount,'native wall cooldown polling does not spam');
assert.equal(requests().length,beforeCooldown.requests);
assert.equal(commits().length,beforeCooldown.commits);
assert(errors.every(e=>e.name==='dota_hud_error_message'&&e.data.message==='移动城墙CD中'));
nativeAbility=-1;cooldown=0;update();
assert(keys.building_move('D',true),'wall relocation recovers after cooldown');
shared.SurvivalArrowTowerTools.Cancel();
selected=12;assert.equal(keys.building_move('D',true),false,'unrelated units cannot move buildings');
assert.equal(shared.SurvivalGridPlacement.BeginRelocation(999,12),false);
console.log('WALL_MOVE_UI_PASS wall D/button, no G, cold profile/click/cancel, fresh sessions, 4x4 preview, snap/retry, selection, cooldown and tower parity');

const combat=fs.readFileSync(directory+'combat_stats.js','utf8');
function slice(start,end){return combat.slice(combat.indexOf(start),combat.indexOf(end));}
const combatShared={},delegated=[],combatErrors=[];
let combatCooldown=120;
const combatEnvironment={$:{Msg:()=>{}},GameUI:{CustomUIConfig:()=>combatShared},
    Abilities:{GetAbilityName:()=>names[30],GetCooldownTimeRemaining:()=>combatCooldown},
    unitOwnsAbility:(unit,ability)=>unit===11&&ability===30,casterForAbility:()=>11,
    abilityRuntime:()=>({ability_name:names[30],available:1}),isPassiveAbility:()=>false,
    pointTargetState:{active:false},cancelPointTarget:()=>{combatEnvironment.pointTargetState.active=false;},
    setPointTargetHint:()=>{},GameEvents:{SendEventClientSide:(name,data)=>combatErrors.push({name,data})}};
vm.createContext(combatEnvironment);
vm.runInContext(slice('    var utilityHotkeys =','    var builderHotkeysBySlotOrder ='),combatEnvironment);
vm.runInContext(slice('    function beginPointTarget(','    function pointTargetMouseHandler('),combatEnvironment);
vm.runInContext(slice('    function executeAbility(','    // ability_tooltip.js loads first'),combatEnvironment);
assert.equal(combatEnvironment.utilityHotkeys[names[30]],'D');
assert(combatEnvironment.utilityAbilityForKey.D.includes(names[30]));
assert.equal(combatEnvironment.utilityDisplayOrder[names[30]],combatEnvironment.utilityDisplayOrder[names[20]]);
assert.equal(combatEnvironment.beginPointTarget(30,11),false);
assert.equal(combatErrors.at(-1).data.message,'移动城墙CD中','point-input fallback gives wall-specific native error');
combatShared.SurvivalArrowTowerTools={RejectMoveCooldown:ability=>delegated.push({cooldown:ability}),
    TriggerAbility:(name,unit)=>{delegated.push({name,unit});return true;}};
assert.equal(combatEnvironment.beginPointTarget(30,11),false);
assert.deepEqual(delegated.at(-1),{cooldown:30});
assert(combatEnvironment.executeAbility(30));
assert.deepEqual(delegated.at(-1),{name:names[30],unit:11},'official wall button delegates to the grid adapter');
combatCooldown=0;assert(combatEnvironment.beginPointTarget(30,11));
assert.equal(combatEnvironment.pointTargetState.name,names[30]);
console.log('WALL_MOVE_COMBAT_INPUT_PASS D label/order, official button delegate, point-input cooldown and recovery');
