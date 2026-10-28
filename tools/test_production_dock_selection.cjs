const assert = require('assert'), fs = require('fs'), vm = require('vm');
const sourcePath = 'panorama/src/scripts/custom_game/production_progress.js';
const model = require('../' + sourcePath);
const options = Array.from({length: 8}, (_, i) => ({training_id: 'worker_' + (i + 1), level: i + 1, name: '伐木工', count: 0, max_count: 3, queued_count: 0, available: 1, cost_wood: 10, train_duration: 1}));
const nodes = {}, callbacks = {}, scheduled = [], sent = [], runtime = {}, dispatched = [];
let unit = 10, time = 10, modal = false, hitEntities = [{entityIndex: 10}], mouseHandler;
function panel(id, parent, type = 'Panel') {
    const p = {id, parent, type, style: {}, visible: true, classes: new Set(), children: [], handlers: {}, text: '',
        IsValid() { return true; }, SetImage(uri) { this.image = uri; }, FindChildTraverse(key) { return nodes[key] || null; },
        AddClass(c) { this.classes.add(c); }, SetHasClass(c, value) { value ? this.classes.add(c) : this.classes.delete(c); },
        RemoveAndDeleteChildren() { this.children = []; }, SetPanelEvent(event, handler) { this.handlers[event] = handler; }};
    if (parent) parent.children.push(p);
    if (id) nodes[id] = p;
    return p;
}
const ctx = panel('Context'); panel('SurvivalProductionPanel', ctx); panel('SurvivalResearchAutoMarkers', ctx);
const cfg = {SurvivalUILayers: {Top: () => modal}, SurvivalSelectionResolver: {ResolveDisplayUnit: () => unit},
    SurvivalInputDispatcher: {RegisterMouseHandler: (name, handler) => mouseHandler = handler}};
const env = {console, $, GameUI: {CustomUIConfig: () => cfg, GetScreenEntities: () => hitEntities, GetCursorPosition: () => [100, 100]},
    Game: {GetLocalPlayerID: () => 0, GetGameTime: () => time}, Players: {GetLocalPlayerPortraitUnit: () => unit},
    Entities: {GetUnitName: id => id === 10 || id === 11 ? 'building_main_city' : id === 20 ? 'building_research_lab' : id === 21 ? 'building_advanced_research_lab' : 'hero'},
    CustomNetTables: {GetTableValue: (name, key) => runtime[key]},
    GameEvents: {Subscribe: (name, callback) => {callbacks[name] = callback;}, SendCustomGameEventToServer: (name, payload) => sent.push({name, payload})}};
function $(id) { return nodes[id.slice(1)]; }
$.GetContextPanel = () => ctx; $.CreatePanel = (type, parent, id) => panel(id, parent, type);
$.DispatchEvent = (...args) => dispatched.push(args); $.Schedule = (delay, fn) => scheduled.push(fn);
vm.runInNewContext(fs.readFileSync(sourcePath, 'utf8'), env);
const hud = cfg.SurvivalProductionHUD, g = {x: 350, y: 700, scale: .5, height:330, minimapSize:220, heroWidth: 453, centerWidth: 498};
const freshOptions = () => options.map(v => ({...v, count: 0, queued_count: 0}));
function snapshot(training, extra = {}) { callbacks.ui_selected_unit_stats_snapshot({success: 1, player_id: 0, entindex: unit, training, ...extra}); }
function refresh(entries = []) { return hud.Refresh(g, unit, true, entries); }
const geometry = require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
const research={researching:1,display_name:'伐木效率',ability_name:'ability_research_worker_attack',
    target_level:2,started_at:10,finish_at:12,duration:2,auto_enabled:0,auto_research:{},queued:[],
    active_job:{job_id:'0:20:active',technology_group:'worker_attack'},
    abilities_by_name:{ability_research_worker_attack:{available:1,technology_group:'worker_attack'}}};

// Reproduce the guest layout with real snapshot/selection refreshes. A city
// queue can use the left dock while the next selected laboratory needs above.
// These are physical-to-logical conversion cases, not the guest's measured UI scale.
for(const [index,[physicalWidth,physicalHeight,uiScale]] of [
    [1280,720,1],[1366,768,1],[1920,1200,1],[1600,900,1],
    [1920,1080,1],[1920,1080,1.5],
    [2560,1440,1],[2560,1440,1.5],[2560,1440,1.75],[2560,1440,2]
].entries()) {
    ctx.actuallayoutwidth=physicalWidth;ctx.actuallayoutheight=physicalHeight;
    ctx.actualuiscale_x=ctx.actualuiscale_y=uiScale;
    const anchor=geometry(physicalWidth/uiScale,physicalHeight/uiScale,3,true,false,{production:true});
    const before=JSON.stringify(anchor);
    const city=model.PanelGeometry(anchor,true),lab=model.PanelGeometry(anchor,false);
    const expectPlacement=placement=>{
        assert.equal(nodes.SurvivalProductionPanel.style.position,`${placement.x}px ${placement.y}px 0px`);
        assert.equal(nodes.SurvivalProductionPanel.style.transform,`scale3d(${placement.scale},${placement.scale},1)`);
        assert(Math.abs(nodes.SurvivalProductionPanel.__survivalWindowWidth-placement.width*placement.scale*uiScale)<.000001,
            'physical occlusion width applies UI scale once');
        assert(Math.abs(nodes.SurvivalProductionPanel.__survivalWindowHeight-placement.height*placement.scale*uiScale)<.000001,
            'physical occlusion height applies UI scale once');
    };
    unit=10;hud.Refresh(anchor,unit,true,[]);
    snapshot({options:freshOptions(),queued:[]},{refresh_sequence:20000+index});
    expectPlacement(city);
    assert.equal(nodes.ProductionTitle.visible,false);assert.equal(nodes.ProductionTrainingSlot0.visible,true);
    const cityPosition=nodes.SurvivalProductionPanel.style.position;
    for(const labUnit of [20,21]) {
        unit=labUnit;hud.Refresh(anchor,unit,true,[]);
        snapshot(undefined,{research,refresh_sequence:21000+index});
        expectPlacement(lab);
        assert.equal(nodes.ProductionTitle.text,labUnit===20?'科技研究':'高级科技研究');
        assert.equal(nodes.ProductionTitle.visible,true);assert.equal(nodes.ProductionTrainingSlot0.visible,false);
    }
    unit=10;hud.Refresh(anchor,unit,true,[]);
    expectPlacement(city);
    assert.equal(nodes.SurvivalProductionPanel.style.position,cityPosition,'returning to city restores its own dock');
    assert.equal(nodes.ProductionTitle.visible,false);assert.equal(nodes.ProductionTrainingSlot0.visible,true);
    assert.deepEqual(Array.from(hud.Inspect().slots),['worker_1','worker_2','worker_3','worker_4']);
    assert.equal(JSON.stringify(anchor),before,'queue refresh leaves shared native/title/buff geometry unchanged');
}
ctx.actualuiscale_x=ctx.actualuiscale_y=1;
console.log('PRODUCTION_RESPONSIVE_SELECTION_PASS: 10 physical viewport/UI-scale cases, city/ordinary/advanced/city snapshots, own dock and physical occlusion bounds');
