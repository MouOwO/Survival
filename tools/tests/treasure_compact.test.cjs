'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const project = path.resolve(__dirname, '../..');

// Actual XML, ModalShell, layer manager and controller; only native Panorama APIs are simulated.
function harness(beforeController) {
    const nodes = {}, listeners = new Map(), timers = new Map(), dispatched = [], sent = [];
    const counts = {created: 0, deleted: 0, tree: 0, style: 0, text: 0, image: 0};
    let serial = 0, now = 0, history = {history: []};
    class Panel {
        constructor(type, parent, id = '') {
            this.id = id; this.type = this.paneltype = type; this.parent = null;
            this.children = []; this.classes = new Set(); this.events = {}; this.handlers = {};
            this.visible = this.enabled = true;
            this.style = new Proxy({}, {set: (target, key, value) => {this.check(); counts.style++; target[key] = value; return true;}});
            counts.created++; this.SetParent(parent); if (id) nodes[id] = this;
        }
        check() { assert(!this.deleted, 'native operations must not use a deleted panel'); }
        IsValid() { return !this.deleted; }
        AddClass(c) { this.check(); c.split(/\s+/).filter(Boolean).forEach(x => this.classes.add(x)); }
        RemoveClass(c) { this.check(); this.classes.delete(c); }
        BHasClass(c) { this.check(); return this.classes.has(c); }
        SetHasClass(c, value) { value ? this.AddClass(c) : this.RemoveClass(c); }
        SetPanelEvent(name, fn) { this.check(); this.events[name] = fn; }
        Children() { this.check(); counts.tree++; return this.children.slice(); }
        GetChildCount() { this.check(); return this.children.length; }
        GetChild(i) { this.check(); return this.children[i]; }
        GetParent() { this.check(); return this.parent; }
        SetParent(parent) {
            this.check(); if (this.parent) this.parent.children = this.parent.children.filter(p => p !== this);
            this.parent = parent; if (parent) parent.children.push(this);
        }
        FindChildTraverse(id) {
            this.check(); counts.tree++; if (this.id === id) return this;
            for (const child of this.children) { const result = child.FindChildTraverse(id); if (result) return result; }
            return null;
        }
        FindChildrenWithClassTraverse(cls) {
            this.check(); return this.children.flatMap(p => (p.BHasClass(cls) ? [p] : []).concat(p.FindChildrenWithClassTraverse(cls)));
        }
        GetPositionWithinWindow() {
            this.check(); const position = String(this.style.position || '0px 0px').split(/\s+/);
            const parent = this.parent ? this.parent.GetPositionWithinWindow() : {x: 0, y: 0};
            return {x: parent.x + (parseFloat(position[0]) || 0) * this.actualuiscale_x,
                y: parent.y + (parseFloat(position[1]) || 0) * this.actualuiscale_y};
        }
        get actualuiscale_x() { return this.scale === undefined ? this.parent ? this.parent.actualuiscale_x : 1 : this.scale; }
        get actualuiscale_y() { return this.actualuiscale_x; }
        get actuallayoutwidth() { return this.layoutWidth === undefined ? this.style.width === '100%' && this.parent ? this.parent.actuallayoutwidth : (parseFloat(this.style.width) || 120) * this.actualuiscale_x : this.layoutWidth; }
        get actuallayoutheight() { return this.layoutHeight === undefined ? this.style.height === '100%' && this.parent ? this.parent.actuallayoutheight : (parseFloat(this.style.height) || 28) * this.actualuiscale_y : this.layoutHeight; }
        SetImage(value) { this.check(); this.image = value; counts.image++; }
        SetScaling(value) { this.check(); this.scaling = value; }
        SetAcceptsFocus(value) { this.check(); this.acceptsFocus = value; }
        SetFocus() { this.check(); this.focused = true; }
        ScrollToTop() { this.check(); }
        MoveChildBefore(child, before) { this.check(); this.children = this.children.filter(p => p !== child); this.children.splice(Math.max(0, this.children.indexOf(before)), 0, child); }
        RemoveAndDeleteChildren() { this.check(); this.children.slice().forEach(p => p.DeleteAsync()); }
        DeleteAsync() {
            this.check(); this.children.slice().forEach(p => p.DeleteAsync()); this.SetParent(null);
            this.deleted = true; counts.deleted++; if (nodes[this.id] === this) delete nodes[this.id];
        }
        set text(value) { this.check(); this._text = String(value); counts.text++; }
        get text() { this.check(); return this._text || ''; }
    }
    const hud = new Panel('Panel', null, 'HudRoot'); hud.layoutWidth = 1920; hud.layoutHeight = 1080;
    const navigation = new Panel('Panel', hud, 'OtherHudContext');
    const anchor = new Panel('Button', navigation, 'HandoffNav_treasure');
    anchor.style.position = '260px 30px 0px'; anchor.style.width = '64px'; anchor.style.height = '60px';
    const root = new Panel('Panel', hud, 'ArchiveContext');
    root.style.position = '40px 20px 0px'; root.layoutWidth = 1920; root.layoutHeight = 1080;
    const cfg = {};
    function $(id) { return nodes[id.slice(1)] || null; }
    $.GetContextPanel = () => root;
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.Schedule = (delay, fn) => { const id = ++serial; timers.set(id, {at: now + delay, fn}); return id; };
    $.CancelScheduled = id => timers.delete(id);
    $.RegisterEventHandler = (name, panel, fn) => { (panel.handlers[name] ||= []).push(fn); };
    $.DispatchEvent = (...args) => dispatched.push(args);
    $.Msg = () => {};
    const env = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg},
        Game: {GetLocalPlayerID: () => 0, IsInToolsMode: () => false},
        CustomNetTables: {
            GetTableValue: (table, key) => table === 'survival_rogue_reward' && String(key) === '0' ? history : null,
            SubscribeNetTableListener: (name, fn) => {const id = ++serial; listeners.set(id, {name, fn}); return id;},
            UnsubscribeNetTableListener: id => listeners.delete(id),
        },
        GameEvents: {Subscribe: () => ++serial, Unsubscribe() {}, SendCustomGameEventToServer: (...args) => sent.push(args)},
    });
    const xml = fs.readFileSync(path.join(project, 'panorama/src/layout/custom_game/archive.xml'), 'utf8'), stack = [root];
    for (const tag of xml.matchAll(/<(\/?)(Panel|Button|RadioButton|Label|Image)\b([^>]*)>/g)) {
        if (tag[1]) {stack.pop(); continue;}
        const attrs = Object.fromEntries([...tag[3].matchAll(/([\w-]+)="([^"]*)"/g)].map(x => [x[1], x[2]]));
        const panel = new Panel(tag[2], stack.at(-1), attrs.id);
        panel.AddClass(attrs.class || ''); if (attrs.text) panel.text = attrs.text;
        if (panel.BHasClass('ArchiveRoot')) {panel.style.width = '100%'; panel.style.height = '100%';}
        for (const key of ['visible', 'enabled', 'hittest', 'hittestchildren']) if (attrs[key]) panel[key] = attrs[key] !== 'false';
        if (attrs.onactivate) panel.events.onactivate = () => vm.runInContext(attrs.onactivate, env);
        if (!/\/\s*$/.test(tag[3])) stack.push(panel);
    }
    function load(name) { vm.runInContext(fs.readFileSync(path.join(project, 'panorama/src/scripts/custom_game', name), 'utf8'), env, {filename: name}); }
    for (const script of ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js', 'archive_v10_data.js', 'common/tooltip_dismiss.js', 'common/menu_v10.js']) load(script);
    const adopted = [], adopt = cfg.SurvivalUI.ModalShell.Adopt;
    cfg.SurvivalUI.ModalShell.Adopt = props => {adopted.push(props); return adopt(props);};
    function advance(seconds) {
        const end = now + seconds;
        for (let i = 0; i < 1000; i++) {
            const next = [...timers].filter(([, timer]) => timer.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
            if (!next) {now = end; return;}
            timers.delete(next[0]); now = next[1].at; next[1].fn();
        }
        throw new Error('timers failed to settle');
    }
    function net(key, value) {
        if (String(key) === '0') history = value;
        for (const listener of [...listeners.values()]) if (listener.name === 'survival_rogue_reward') listener.fn('survival_rogue_reward', key, value);
    }
    if (beforeController) beforeController({cfg, nodes, root, Panel});
    load('treasure_history.js');
    return {cfg, nodes, root, hud, anchor, counts, timers, listeners, dispatched, sent, adopted, load, advance, net};
}
function byClass(panel, cls) { return panel.FindChildrenWithClassTraverse(cls); }
function geometry(panel) {
    const [x, y] = String(panel.style.position || '').split(/\s+/).map(parseFloat);
    return {x, y, width: parseFloat(panel.style.width), height: parseFloat(panel.style.height)};
}
function treasure() {
    const h = harness(), {cfg, nodes} = h;
    let ui = cfg.SurvivalTreasure;
    const cards = () => nodes.TreasureCards.children;
    const occupied = () => cards().filter(p => !p.BHasClass('TreasureVacant'));
    const slotIcon = panel => byClass(panel, 'TreasureCompactIcon')[0];
    assert(ui, 'the actual controller is installed');
    assert.equal(cfg.SurvivalMenuV10.Entries().length, 0, 'treasure does not allocate a global V10 page');
    ui.Open();
    assert(ui.IsOpen()); assert.equal(cfg.SurvivalUILayers.Top(), 'treasure');
    assert.equal(h.adopted.length, 1); assert.equal(nodes.TreasureWindow.style.width, '292px'); assert.equal(nodes.TreasureWindow.style.height, '404px');
    assert.equal(cards().length, 20); assert(cards().every(p => p.BHasClass('TreasureVacant') && p.hittest === false));
    cards().forEach((card, i) => {
        const r = geometry(card); assert.equal(r.width, 60); assert.equal(r.height, 60);
        assert.equal(r.x, (i % 4) * 68); assert.equal(r.y, Math.floor(i / 4) * 68);
    });
    assert.equal(nodes.TreasureCount.text, '0 / 20');
    const start = geometry(nodes.TreasureWindow), anchorPosition = h.anchor.GetPositionWithinWindow(), parentPosition = nodes.TreasureWindow.parent.GetPositionWithinWindow();
    assert.equal(start.x, anchorPosition.x - parentPosition.x, 'popup left edge follows the navigation button across contexts');
    assert.equal(start.y, anchorPosition.y + h.anchor.actuallayoutheight - parentPosition.y + 4,
        'popup starts four pixels beneath the navigation button');
    h.anchor.style.position = '380px 40px 0px'; h.advance(.26);
    assert.equal(geometry(nodes.TreasureWindow).x, start.x + 120, 'the real ModalShell fitting tick follows a moved navigation anchor');
    h.hud.scale = .8; h.root.layoutWidth = 1536; h.root.layoutHeight = 864; ui.Fit();
    assert.equal(geometry(nodes.TreasureWindow).x, 340, 'native UI scaling is removed before applying popup-local coordinates');
    assert.equal(geometry(nodes.TreasureWindow).y, 84, 'the four-pixel lower-edge gap remains in UI coordinates');
    h.root.layoutWidth = 280; h.root.layoutHeight = 320; h.advance(.26);
    const compact = ui.Inspect(), shrunk = geometry(nodes.TreasureWindow);
    assert(compact.scale > 0 && compact.scale < 1);
    assert(shrunk.x >= 0 && shrunk.y >= 0 && shrunk.x + 292 * compact.scale <= h.root.actuallayoutwidth / .8 && shrunk.y + 404 * compact.scale <= h.root.actuallayoutheight / .8,
        'small viewport fitting and edge clamping keep the popup inside its parent');
    h.hud.scale = 1; h.root.layoutWidth = 1920; h.root.layoutHeight = 1080; h.advance(.26);
    assert.equal(ui.Inspect().scale, 1, 'a large viewport never enlarges the compact slots');

    ui.Close(); h.advance(1); const hidden = {...h.counts};
    const records = {};
    for (let i = 27; i >= 1; i--) records[i] = {name: '宝物' + i, description: '真实效果' + i,
        icon_name: i === 1 ? 'survival/native/frozen_wall' : i === 2 ? 'item_recipe' : 'lich_frost_shield',
        ...(i === 1 ? {quantity: 3} : i === 3 ? {qty: 0} : i === 4 ? {count: 8} : {})};
    for (let i = 0; i < 1000; i++) h.net('0', {history: records});
    assert.deepEqual(h.counts, hidden, 'hidden NetTable updates cache history without traversing or rewriting UI');
    ui.Open(); assert.equal(occupied().length, 20); assert.equal(nodes.TreasureCount.text, '20 / 20');
    assert(cards()[0].BHasClass('TreasureLatest'));
    const first = cards()[0], second = cards()[1];
    assert.equal(slotIcon(first).image, 'file://{images}/spellicons/survival/native/frozen_wall.png');
    assert.equal(slotIcon(second).type, 'DOTAItemImage'); assert.equal(slotIcon(second).itemname, 'item_recipe');
    assert.equal(slotIcon(cards()[2]).abilityname, 'lich_frost_shield');
    assert.equal(byClass(first, 'TreasureQuantity')[0].text, '3');
    assert.equal(byClass(second, 'TreasureQuantity').length, 0, 'records without authoritative quantity have no fabricated count');
    assert.equal(byClass(cards()[2], 'TreasureQuantity')[0].text, '0'); assert.equal(byClass(cards()[3], 'TreasureQuantity')[0].text, '8');
    cards()[19].events.onmouseover();
    const hover = h.dispatched.at(-1); assert.equal(hover[0], 'DOTAShowTextTooltip');
    assert(hover[2].includes('宝物20') && hover[2].includes('真实效果20'), 'numeric NetTable keys sort numerically before the 20-record cap');
    first.events.onmouseover(); assert(h.dispatched.at(-1)[2].includes('拥有数量：3'));
    h.net('1', {history: []}); assert.equal(occupied().length, 20, 'other player updates cannot replace local history');
    const oldHover = first.events.onmouseover;
    ui.Close(); assert.equal(h.dispatched.at(-1)[0], 'DOTAHideTextTooltip');
    const closeDispatches = h.dispatched.length; oldHover(); assert.equal(h.dispatched.length, closeDispatches, 'a hidden card cannot reopen its tooltip');
    ui.Open(); nodes.TreasureScrim.events.onactivate(); assert(!ui.IsOpen()); assert.equal(cfg.SurvivalUILayers.Top(), null);
    ui.Open(); assert(nodes.TreasureWindow.handlers.Cancelled.length > 0);
    nodes.TreasureWindow.handlers.Cancelled.forEach(fn => fn()); assert(!ui.IsOpen()); assert.equal(cfg.SurvivalUILayers.Top(), null);

    h.net('0', {history: [{name: '旧记录', description: '旧档真实效果'}]}); ui.Open();
    assert.equal(occupied().length, 1); assert.equal(cards().filter(p => p.BHasClass('TreasureVacant')).length, 19);
    assert(byClass(cards()[0], 'TreasureCompactGlyph').some(p => p.text === '旧'), 'records predating icon metadata retain their real name initial');
    const old = ui, retiredHover = cards()[0].events.onmouseover, retiredExit = cards()[0].events.onmouseout;
    h.load('treasure_history.js'); ui = cfg.SurvivalTreasure; ui.Open();
    assert.equal(cards().length, 20); assert.equal(occupied().length, 1); assert.equal(h.listeners.size, 1, 'reload keeps one local-history subscription');
    const beforeRetired = {...h.counts}, dispatchCount = h.dispatched.length;
    old.Open(); old.Close(); retiredHover(); retiredExit(); assert(!old.IsOpen()); assert(ui.IsOpen()); assert.deepEqual(h.counts, beforeRetired); assert.equal(h.dispatched.length, dispatchCount);
    assert.equal(byClass(nodes.TreasureWindow, 'UIModalInputShield').length, 1, 'reload does not accumulate modal input shields');
    const rewardSource = fs.readFileSync(path.join(project, 'scripts/vscripts/config/generated/rogue_reward_cards.lua'), 'utf8');
    const iconNames = [...new Set([...rewardSource.matchAll(/icon_name = "([^"]+)"/g)].map(match => match[1]))];
    assert(iconNames.length > 0, 'the icon check uses the actual reward catalog');
    for (const icon_name of iconNames) {
        h.net('0', {history: [{name: '真实奖励图标', icon_name}]});
        const art = slotIcon(cards()[0]);
        if (icon_name.includes('/')) {
            assert(fs.existsSync(path.join(project, 'panorama/src/images/spellicons', icon_name + '.png')), icon_name + ' has its real resource');
            assert.equal(art.image, 'file://{images}/spellicons/' + icon_name + '.png');
        } else if (icon_name.startsWith('item_')) assert.equal(art.itemname, icon_name);
        else assert.equal(art.abilityname, icon_name);
    }
    assert.equal(h.sent.length, 0, 'opening treasure never submits fabricated inventory changes');
    h.root.DeleteAsync();
    assert.doesNotThrow(() => {h.advance(1); ui.Close(); ui.Dispose(); ui.Dispose(); old.Dispose();});
    assert.equal(h.listeners.size, 0); assert.equal(h.timers.size, 0);

    const migrated = harness(({cfg, nodes, root, Panel}) => {
        // Reproduce the old controller's real V10 adoption and moved XML controls.
        const legacy = cfg.SurvivalMenuV10.Adopt({id: 'treasure', navId: 'treasure', root,
            panel: nodes.TreasureWindow, scrim: nodes.TreasureScrim, onClose: () => legacy.Close()});
        legacy.Move(nodes.TreasureCards, legacy.content); legacy.Move(nodes.TreasureCount, legacy.header);
        const empty = new Panel('Label', nodes.TreasureContent, 'TreasureEmpty'); empty.text = '尚未获得宝物';
        legacy.Move(empty, legacy.content); nodes.TreasureContent.style.visibility = 'collapse';
        nodes.TreasureWindow.AddClass('TreasureV10Page');
        cfg.SurvivalTreasure = {Dispose: () => legacy.Dispose()};
    });
    migrated.cfg.SurvivalTreasure.Open();
    assert.equal(migrated.cfg.SurvivalMenuV10.Entries().length, 0);
    assert.equal(migrated.nodes.TreasureContent.style.visibility, 'visible', 'legacy collapsed content becomes visible');
    assert.equal(migrated.nodes.TreasureCards.parent, migrated.nodes.TreasureContent, 'legacy V10 adoption restores original control parents');
    assert.equal(migrated.nodes.TreasureEmpty.visible, false, 'legacy empty-page label cannot cover the twenty reserved slots');
    assert.equal(migrated.nodes.TreasureCards.GetChildCount(), 20);
    assert.equal(byClass(migrated.nodes.TreasureWindow, 'UIModalInputShield').length, 1, 'legacy V10 input shield is retired before the new shell takes ownership');
    migrated.cfg.SurvivalTreasure.Dispose();
    assert.equal(migrated.timers.size, 0); assert.equal(migrated.listeners.size, 0);
    console.log('TREASURE_COMPACT_PASS: real XML/ModalShell/layers, 4x5 slots, 60px geometry, cross-context anchor, hidden caching, ordered local history, real art/quantities/tooltip, ESC/outside close, reload and disposal');
}
module.exports = {treasure, harness};
if (require.main === module) treasure();
