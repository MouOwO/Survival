'use strict';
// Run both complete HUD scripts. Ability enumeration uses the real combat HUD
// helpers; only native Panorama/entity APIs and authoritative DTOs are mocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const current = 'panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js';
const baseline = 'output/ui_refresh_audit_20261013/topnav_refresh_context_v1_before_20261013/topnav_remaining_5d5c1152eb.js';
const source = fs.readFileSync(path.join(root, process.argv[2] || current), 'utf8');
const before = fs.readFileSync(path.join(root, process.argv[3] || baseline), 'utf8');
const combatSource = fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game/combat_stats.js'), 'utf8');
function section(text, start, end) {
    const a = text.indexOf(start), b = text.indexOf(end, a + start.length);
    assert(a >= 0 && b > a, start);
    return text.slice(a, b);
}
const combatHelpers = section(combatSource, '    function orderVisibleAbilities(', '    function refreshInventory()');
const geometry = require(path.join(root, 'panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js'));
function fixture(code) {
    const state = {unit: 7, now: 1000, snapshot: {}, runtime: {}, hidden: new Set(), completed: new Set(), names: {}, slots: {}, counts: {}, failReader: false};
    const counters = {enumerations: 0, getAbility: 0, getAbilityName: 0, isHidden: 0, runtime: 0, schedules: 0, production: 0};
    const warnings = [], listeners = {}, timers = [], sent = [], runtimeCalls = [];
    class Panel {
        constructor(type, id, parent = null) {
            this.paneltype = type; this.id = id; this.parent = null; this.children = [];
            this.alive = true; this.visible = true; this.hittest = true; this.hittestchildren = true;
            this.style = {}; this.text = ''; this.classes = new Set(); this.events = {};
            this.actuallayoutwidth = 1920; this.actuallayoutheight = 1080;
            this.actualuiscale_x = 1; this.actualuiscale_y = 1;
            if (parent) this.SetParent(parent);
        }
        IsValid() { return this.alive; }
        GetParent() { return this.parent; }
        SetParent(parent) { if (this.parent) this.parent.children = this.parent.children.filter(c => c !== this); this.parent = parent; if (parent) parent.children.push(this); }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
        Children() { return this.children.slice(); }
        FindChildTraverse(id) { for (const child of this.children) { if (child.id === id && child.alive) return child; const found = child.FindChildTraverse(id); if (found) return found; } return null; }
        AddClass(name) { this.classes.add(name); }
        RemoveClass(name) { this.classes.delete(name); }
        BHasClass(name) { return this.classes.has(name); }
        SetHasClass(name, active) { if (active) this.classes.add(name); else this.classes.delete(name); }
        SetPanelEvent(name, callback) { this.events[name] = callback; }
        SetImage(uri) { this.image = uri; }
        SetScaling(mode) { this.scaling = mode; }
        DeleteAsync() { this.alive = false; this.SetParent(null); }
        GetPositionWithinWindow() { return {x: 0, y: 0}; }
        GetAttributeString(name, fallback) { return this[name] || fallback; }
        SetAttributeString(name, value) { this[name] = value; }
    }
    const gameRoot = new Panel('Panel', 'root'), ctx = new Panel('Panel', 'context', gameRoot);
    new Panel('Panel', 'HandoffHUD', ctx);
    const map = {};
    function native(id, parent = gameRoot) { return map[id] = new Panel('Panel', id, parent); }
    const lower = native('lower_hud'), outer = native('center_with_stats', lower), block = native('center_block', outer);
    const portrait = native('PortraitGroup', block);
    for (const id of ['PortraitContainer', 'portraitHUD', 'portraitHUDOverlay']) native(id, portrait);
    const branch = native('AbilitiesAndStatBranch', block), abilities = native('abilities', branch), inventory = native('inventory', block);
    native('StatBranch', branch);
    const minimap = native('minimap_container'), minimapBlock = native('minimap_block', minimap); native('minimap', minimapBlock);
    for (const id of ['inventory_composition_layer_container', 'buffs', 'debuffs']) native(id);
    const slotChildren = ['ButtonAndLevel','ButtonWithLevelUpTab','ButtonWell','ButtonSize','AbilityButton','AbilityImage','Cooldown','CooldownOverlay','HotkeyContainer','Hotkey','HotkeyText','AbilityBevel','ShineContainer','PassiveAbilityBorder','AbilityLevelContainer'];
    function skill(id, parent = map.abilities) { const p = new Panel('Panel', id, parent); for (const child of slotChildren) new Panel('Panel', child, p); p.FindChildTraverse('Cooldown').style.clip = 'native-live-cooldown'; return p; }
    for (let i = 0; i < 8; i++) skill('Ability' + i, abilities);
    for (let i = 0; i < 9; i++) { const p = skill('inventory_slot_' + i, inventory); new Panel('Image', 'ItemImage', p); }
    const health = new Panel('Label', 'SurvivalHeroHealthText', ctx); health.text = '80 / 100';
    const mana = new Panel('Label', 'SurvivalHeroManaText', ctx); mana.text = '20 / 100';
    const hpFill = new Panel('Panel', 'SurvivalHeroHealthFill', ctx); hpFill.style.width = '80%';
    const mpFill = new Panel('Panel', 'SurvivalHeroManaFill', ctx); mpFill.style.width = '20%';
    for (const [id, text] of [['SurvivalHeroName','Axe'],['SurvivalHeroLevel','5'],['CombatAttackValue','20'],['CombatArmorValue','3'],['CombatAttackSpeedValue','100%'],['CombatStrengthValue','10'],['CombatAgilityValue','10'],['CombatIntellectValue','10']]) new Panel('Label', id, ctx).text = text;
    const cfg = {HandoffAssets: new Proxy({}, {get: (_, key) => ({file: String(key) + '.png'})}), HandoffGeometry: geometry,
        SurvivalSelectionResolver: {ResolveDisplayUnit: () => state.unit}, SurvivalNumberFormatter: {Compact: value => String(value ?? '—')},
        SurvivalProductionHUD: {Refresh() { counters.production++; return 0; }}};
    const initial = {sequence: 1, resources: {wood: 100, gold: 50, population: 1, max_population: 20}, wave: {alive: 0, alive_limit: 90, current_wave: 1, total_waves: 30, timer: 10, status: 'countdown', countdown_deadline: 100}};
    const env = vm.createContext({
        cfg, state, counters, runtimeCalls, utilityHotkeys: {}, utilityDisplayOrder: {},
        unitAbilityCount: unit => (counters.enumerations++, state.failReader ? (() => { throw Error('native reader unavailable'); })() : (state.counts[unit] || 0)),
        isPassiveAbility: ability => !!state.runtime[ability]?.passive,
        abilityRuntime: ability => ({...(state.runtime[ability] || {}), completed: state.completed.has(ability) ? 1 : 0}),
        Entities: {GetUnitName: unit => unit === 19 ? 'building_main_city' : 'npc_dota_hero_axe', IsHero: unit => unit !== 19, IsBuilding: unit => unit === 19,
            GetAbility(unit, slot) { counters.getAbility++; if(state.onGetAbility)state.onGetAbility(unit,slot); return state.slots[unit]?.[slot] ?? -1; }, GetItemInSlot: () => -1},
        Abilities: {GetAbilityName(ability) { counters.getAbilityName++; return state.names[ability] || ''; }, IsHidden(ability) { counters.isHidden++; return state.hidden.has(ability); }},
        GameUI: {CustomUIConfig: () => cfg}, Players: {GetLocalPlayerPortraitUnit: () => state.unit},
        Game: {GetLocalPlayerID: () => 0, GetGameTime: () => state.now / 1000, IsInToolsMode: () => false},
        CustomNetTables: {GetTableValue: table => table === 'survival_ui_state' ? initial : null},
        GameEvents: {Subscribe(name, cb) { (listeners[name] ||= []).push(cb); }, SendCustomGameEventToServer(name, payload) { sent.push({name, payload}); }},
        Date: {now: () => state.now}, $: {GetContextPanel: () => ctx, CreatePanel: (type, parent, id) => new Panel(type, id, parent),
            Schedule(delay, cb) { counters.schedules++; const item = {at: state.now + delay * 1000, cb}; timers.push(item); return item; },
            Msg() {}, Warning(message) { warnings.push(String(message)); }, DispatchEvent() {}, Localize: x => x}
    });
    vm.runInContext(combatHelpers, env, {filename: 'actual_combat_helpers.js'});
    cfg.HandoffCombat = {NativeEntries: env.nativeAbilityEntries, Entries: env.visibleAbilityEntries,
        IsCompleted: ability => state.completed.has(ability), Snapshot: () => state.snapshot, RefreshSelection() {},
        ApplyRuntime(panel, ability) { counters.runtime++; const runtime = state.runtime[ability] || {}; const completed = state.completed.has(ability); panel.style.opacity = completed ? '0' : '1'; panel.hittest = !completed; panel.SetHasClass('DOTADisabled', runtime.prerequisite_met === 0); runtimeCalls.push({unit: state.unit, ability, completed, level: runtime.level, prerequisite: runtime.prerequisite_met}); }};
    function setAbilities(unit, values) { state.slots[unit] = values; state.counts[unit] = values.length; values.forEach(a => { state.names[a] ||= 'ability_' + a; state.runtime[a] ||= {level: 1, prerequisite_met: 1}; }); }
    setAbilities(7, [101,102,103,104]); setAbilities(19, [201,202]);
    state.runtime[102].passive = true;
    const originals = {...cfg.HandoffCombat};
    function load() { vm.runInContext(code, env, {filename: 'complete_topnav.js'}); }
    function advance(ms) { const target = state.now + ms; let count = 0; while (true) { timers.sort((a,b) => a.at - b.at); const task = timers[0]; if (!task || task.at > target) break; assert(++count < 20000, 'scheduler bounded'); timers.shift(); state.now = task.at; task.cb(); } state.now = target; }
    function emit(name, payload) { (listeners[name] || []).slice().forEach(cb => cb(payload)); }
    function inspect() { return JSON.parse(JSON.stringify(cfg.SurvivalMainHUD.Inspect())); }
    function semantic() { return {hud: inspect(), slots: map.abilities.children.map(p => ({id:p.id,width:p.style.width,visible:p.style.visibility,opacity:p.style.opacity,hittest:p.hittest,clip:p.FindChildTraverse('Cooldown')?.style.clip})), runtime: runtimeCalls.slice(), production: counters.production}; }
    load();
    return {state,counters,cfg,map,ctx,Panel,skill,health,hpFill,mpFill,warnings,sent,originals,load,advance,emit,inspect,semantic,setAbilities};
}
function run(code) {
    const f = fixture(code); f.advance(2000);
    assert.deepEqual(f.warnings, []);
    const start = {...f.counters}; f.advance(5000);
    const stable = Object.fromEntries(Object.keys(start).map(k => [k, f.counters[k] - start[k]]));
    const stages = [f.semantic()];
    // Same unit and count, different handles; hidden and completed remain fresh.
    f.setAbilities(7,[301,302,303,304]); f.emit('dota_ability_changed',{PlayerID:0}); f.advance(100); stages.push(f.semantic());
    f.state.hidden.add(302); f.state.completed.add(303); f.advance(100); stages.push(f.semantic());
    f.state.hidden.delete(302); f.state.completed.delete(303); f.state.runtime[304].level=7; f.state.runtime[304].prerequisite_met=0;
    f.health.text='40 / 100'; f.hpFill.style.width='40%'; f.mpFill.style.width='75%';
    f.map.abilities.children[0].FindChildTraverse('Cooldown').style.clip='native-cooldown-progress-changed';
    f.advance(100); stages.push(f.semantic());
    f.state.unit=19; f.emit('dota_player_update_selected_unit',{PlayerID:0}); f.advance(100); stages.push(f.semantic());
    f.ctx.actuallayoutwidth=2560; f.ctx.actuallayoutheight=1440; f.ctx.actualuiscale_x=1.25; f.ctx.actualuiscale_y=1.25; f.advance(100); stages.push(f.semantic());
    const old=f.map.abilities; old.alive=false; old.SetParent(null); f.map.abilities=new f.Panel('Panel','abilities',f.map.AbilitiesAndStatBranch);
    for(let i=0;i<8;i++)f.skill('Ability'+i); f.advance(100); stages.push(f.semantic());
    f.state.failReader=true; f.advance(100); assert(f.warnings.length>0); f.state.failReader=false; f.warnings.length=0; f.advance(100); stages.push(f.semantic());
    const generation=f.cfg.HandoffGeneration; f.load(); assert.equal(f.cfg.HandoffGeneration,generation+1); f.advance(500); stages.push(f.semantic());
    assert.deepEqual(f.warnings, []);
    for(const key of ['NativeEntries','Entries','IsCompleted','ApplyRuntime','Snapshot','RefreshSelection'])assert.strictEqual(f.cfg.HandoffCombat[key],f.originals[key],key+' global contract untouched');
    return {f,stable,stages};
}
const old = run(before), updated = run(source);
assert.deepEqual(updated.stages,old.stages,'complete scripts preserve geometry/identity, native CD, runtime/level/prerequisite/completion, selection/viewport/panel failure recovery/reload');
assert.deepEqual(updated.stages[1].hud.abilities,['ability_301','ability_302','ability_303','ability_304']);
assert.deepEqual(updated.stages[2].hud.abilities,['ability_301','ability_304'],'hidden and newly completed abilities affect layout on the next normal tick');
assert.equal(updated.stages[3].hud.hp,'40 / 100','health updates between structural events');
assert.equal(updated.stages[3].slots[0].clip,'native-cooldown-progress-changed','native cooldown progress is never cached or overwritten');
assert(updated.stages[3].runtime.some(r=>r.ability===304&&r.level===7&&r.prerequisite===0),'level and prerequisite state remain fresh');
assert.equal(updated.stages[4].hud.unit,19);
assert(updated.stable.enumerations < old.stable.enumerations, 'saved old production script must reproduce duplicate native enumeration');
assert.equal(updated.stable.getAbility*old.stable.enumerations, old.stable.getAbility*updated.stable.enumerations);
assert.equal(updated.stable.getAbilityName*old.stable.enumerations, old.stable.getAbilityName*updated.stable.enumerations);
assert.equal(updated.stable.isHidden*old.stable.enumerations, old.stable.isHidden*updated.stable.enumerations);
assert.equal(updated.stable.runtime,old.stable.runtime,'runtime refresh cadence never reduced');
assert.equal(updated.stable.production,old.stable.production,'production refresh cadence never reduced');
// The global Entries API remains a fresh scan even outside HUD refreshes.
const snapshot=updated.f.counters.enumerations; updated.f.cfg.HandoffCombat.Entries(19); updated.f.cfg.HandoffCombat.Entries(19);
assert.equal(updated.f.counters.enumerations,snapshot+2);
// A re-entrant native read may change the unit, API owner, or reader. Sharing
// must be limited to the exact same synchronous read identity in that case.
function invalidationCase(code, reason) {
    const f=fixture(code); f.advance(500);
    const combat=f.cfg.HandoffCombat, original=combat.NativeEntries;
    let once=true;
    f.state.onGetAbility=function(){
        if(once){
            once=false;
            if(reason==='unit')f.state.unit=19;
            if(reason==='reader')combat.NativeEntries=function(nextUnit){return original(nextUnit);};
            if(reason==='owner')f.cfg.HandoffCombat={...combat,NativeEntries:function(nextUnit){return original(nextUnit);}};
        }
    };
    f.advance(100); assert.deepEqual(f.warnings,[]);
    return f.semantic();
}
for(const reason of ['unit','reader','owner'])assert.deepEqual(invalidationCase(source,reason),invalidationCase(before,reason),reason+' replacement must not reuse the old native enumeration');
function legacyCase(code, missing) {
    const f=fixture(code); f.advance(500); delete f.cfg.HandoffCombat[missing];
    f.state.completed.add(101); f.advance(100); assert.deepEqual(f.warnings,[]);
    return f.semantic();
}
for(const missing of ['NativeEntries','IsCompleted'])assert.deepEqual(legacyCase(source,missing),legacyCase(before,missing),'missing optional '+missing+' preserves original contract');
if(process.env.TOPNAV_REFRESH_EVIDENCE)fs.writeFileSync(process.env.TOPNAV_REFRESH_EVIDENCE,JSON.stringify({scope:'complete old/new HUD VM, real combat enumeration helpers; native mocks; counts not FPS',stable_seconds:5,before:old.stable,after:updated.stable,semantic_stages_equal:true},null,2)+'\n');
console.log('TOPNAV_REFRESH_CONTEXT_PASS '+JSON.stringify({before:old.stable,after:updated.stable})+'; fresh between ticks, hidden/completed/runtime, selection/viewport/panel/failure/reload, global API preserved');
