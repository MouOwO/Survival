const fs = require('fs'), vm = require('vm'), assert = require('assert');
const panels = {}, listeners = {}, handlers = {}, stack = [];
class Panel {
    constructor(type, parent, id) {
        this.type = type; this.parent = parent; this.id = id;
        this.children = []; this.classes = new Set(); this.events = {}; this.style = {};
        if (parent) parent.children.push(this);
        if (id) panels[id] = this;
    }
    SetImage(value) { this.image = value; }
    AddClass(name) { this.classes.add(name); }
    RemoveClass(name) { this.classes.delete(name); }
    SetPanelEvent(name, callback) { this.events[name] = callback; }
    SetFocus() { this.focused = true; }
    RemoveAndDeleteChildren() { this.children = []; }
}
const root = new Panel('Panel', null, 'Root');
for (const match of fs.readFileSync('panorama/src/layout/custom_game/archive.xml', 'utf8').matchAll(/id="([^"]+)"/g)) {
    new Panel('Panel', root, match[1]);
}
const $ = selector => panels[selector.slice(1)];
$.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
$.RegisterEventHandler = (event, panel, callback) => handlers[event] = callback;
let snapshot = {};
const config = { SurvivalUILayers: {
    Open(id, panel, close, input) { stack.push({id, panel, close, input}); },
    Close(id) { const index = stack.findIndex(item => item.id === id); if (index >= 0) stack.splice(index, 1); }
}};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/treasure_history.js', 'utf8'), {
    $, Game: { GetLocalPlayerID: () => 0 }, GameUI: { CustomUIConfig: () => config },
    CustomNetTables: {
        SubscribeNetTableListener: (name, callback) => listeners[name] = callback,
        GetTableValue: () => snapshot
    }
});
const ui = config.SurvivalTreasure, cards = () => panels.TreasureCards.children;
const names = () => cards().map(card => card.children.find(child => child.classes.has('TreasureName')).text);
ui.Toggle();
assert.equal(cards().length, 20, 'empty state retains all twenty slots');
assert(cards().every(card => card.classes.has('TreasureVacant')));
assert.equal(stack[0].input.scrim, panels.TreasureScrim, 'outside click uses the modal input layer');
assert(panels.TreasureWindow.focused);
ui.Close();
assert.equal(stack.length, 0);
assert(panels.TreasureWindow.classes.has('ArchiveHidden'));
const history = {};
for (let i = 25; i >= 1; i--) history[i] = {name: '宝物' + i, description: '效果' + i, icon_name: i === 1 ? 'item_recipe' : 'tinker_rearm'};
snapshot = {history};
ui.Toggle();
assert.equal(cards().length, 20);
assert.equal(names()[0], '宝物1');
assert.equal(names()[19], '宝物20', 'numeric NetTable keys are ordered and capped');
assert(cards()[0].classes.has('TreasureLatest'));
assert.equal(cards()[0].children[1].children[0].type, 'DOTAItemImage');
assert.equal(cards()[1].children[1].children[0].type, 'DOTAAbilityImage');
cards()[19].events.onmouseover();
assert.equal(panels.TreasureTooltipName.text, '宝物20');
assert.equal(panels.TreasureTooltipEffect.text, '效果20');
assert(!panels.TreasureTooltip.classes.has('ArchiveHidden'));
cards()[19].events.onmouseout();
assert(panels.TreasureTooltip.classes.has('ArchiveHidden'));
listeners.survival_rogue_reward('', '1', {history: []});
assert.equal(names()[0], '宝物1', 'other players cannot replace local treasure history');
listeners.survival_rogue_reward('', '0', {history: [{name: '旧记录'}]});
assert.equal(names()[0], '旧记录');
assert.equal(cards()[0].children[1].children[0].text, '旧', 'older snapshots without icons still render');
assert.equal(cards().filter(card => card.classes.has('TreasureVacant')).length, 19);
handlers.Cancelled();
assert.equal(stack.length, 0, 'Escape releases the modal layer');
assert(panels.TreasureScrim.classes.has('ArchiveHidden'));
console.log('TREASURE_HISTORY_UI_PASS: twenty slots, NetTable ordering, real icons, player isolation, hover detail, modal close');

ui.Toggle();
const iconPaths=[...fs.readFileSync('scripts/vscripts/config/generated/rogue_reward_cards.lua','utf8').matchAll(/icon_name = "([^"]+)"/g)].map(m=>m[1]);
for(const icon_name of iconPaths){
 assert(fs.existsSync('panorama/src/images/spellicons/'+icon_name+'.png'),icon_name);
 listeners.survival_rogue_reward('', '0', {history:[{name:'reward',icon_name}]});
 const icon=cards()[0].children[1].children[0];
 assert.equal(icon.type,'Image');assert.equal(icon.image,'file://{images}/spellicons/'+icon_name+'.png');
}
console.log('TREASURE_ALL_TEXTURES_PASS: '+iconPaths.length+' reward thumbnails');
