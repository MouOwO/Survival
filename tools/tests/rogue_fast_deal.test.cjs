'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {csv} = require('../shop_ui_12h/catalog.cjs');

// An alternate root also allows the same behavioral checks on a reviewed checkout.
const project = process.env.ROGUE_TEST_PROJECT || path.resolve(__dirname, '../..');
const resourceRoot = path.join(project, 'panorama/src');

// Runs the actual XML entry point and all its actual includes. Only the native
// Panel/input/network boundary is simulated; production lifecycle, art resolver,
// layer manager and animation code remain intact. CSS rasterization is outside
// this behavioral test and must also be checked in Panorama.
function createHarness(initial = {}, viewport = [1920, 1080]) {
    let time = 0, serial = 0, cursor = [960, 540];
    const nodes = {}, all = [], jobs = new Map(), events = new Map(), tables = new Map();
    const sent = [], mutations = [], sounds = [], loaded = [];
    class Panel {
        constructor(type, parent, id = '') {
            this.id = id; this.paneltype = type; this.parent = parent; this.children = [];
            this.classes = new Set(); this.events = {}; this.enabled = true; this._visible = true;
            this.actualuiscale_x = this.actualuiscale_y = 1;
            this.style = new Proxy({}, {set: (target, key, value) => {
                this.check(); mutations.push({time, panel: this, key, value}); target[key] = value; return true;
            }});
            if (parent) parent.children.push(this);
            if (id) nodes[id] = this;
            all.push(this);
        }
        check() { assert(!this.deleted, 'cancelled callbacks cannot touch a deleted panel: ' + this.id); }
        IsValid() { return !this.deleted; }
        AddClass(value) { this.check(); value.split(/\s+/).forEach(c => this.classes.add(c)); }
        RemoveClass(value) { this.check(); this.classes.delete(value); }
        BHasClass(value) { this.check(); return this.classes.has(value); }
        SetHasClass(value, enabled) { enabled ? this.AddClass(value) : this.RemoveClass(value); }
        GetParent() { this.check(); return this.parent; }
        Children() { this.check(); return this.children; }
        GetChildCount() { this.check(); return this.children.length; }
        GetChild(index) { this.check(); return this.children[index]; }
        FindChildTraverse(id) {
            this.check(); if (this.id === id) return this;
            for (const child of this.children) { const found = child.FindChildTraverse(id); if (found) return found; }
            return null;
        }
        SetPanelEvent(name, callback) { this.check(); this.events[name] = callback; }
        SetImage(uri) { this.check(); this.image = uri; }
        SetScaling(mode) { this.check(); this.scaling = mode; }
        SetFocus() { this.check(); }
        SetAcceptsFocus() { this.check(); }
        DeleteAsync() {
            this.check(); this.children.slice().forEach(child => child.DeleteAsync()); this.deleted = true;
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
            if (this.id && nodes[this.id] === this) delete nodes[this.id];
        }
        RemoveAndDeleteChildren() { this.check(); this.children.slice().forEach(child => child.DeleteAsync()); }
        GetPositionWithinWindow() {
            this.check(); let x = 0, y = 0;
            for (let p = this; p; p = p.parent) {
                const position = String(p.style.position || '0px 0px').split(' ');
                x += parseFloat(position[0]) || 0; y += parseFloat(position[1]) || 0;
            }
            return {x, y};
        }
        get actuallayoutwidth() { return parseFloat(this.style.width) || (this.parent && this.parent.actuallayoutwidth) || 290; }
        get actuallayoutheight() { return parseFloat(this.style.height) || (this.parent && this.parent.actuallayoutheight) || 672; }
        set visible(value) { this.check(); this._visible = value; mutations.push({time, panel: this, key: 'visible', value}); }
        get visible() { this.check(); return this._visible; }
        set text(value) { this.check(); this._text = String(value); }
        get text() { this.check(); return this._text || ''; }
    }
    const root = new Panel('Panel', null, 'Root');
    root.style.width = viewport[0] + 'px'; root.style.height = viewport[1] + 'px';
    const xml = fs.readFileSync(path.join(resourceRoot, 'layout/custom_game/rogue_reward_ui.xml'), 'utf8');
    const stack = [root];
    for (const tag of xml.match(/<\/?(?:Panel|Button|Label|Image|RadioButton|ToggleButton)\b[^>]*>/g) || []) {
        if (tag.startsWith('</')) { stack.pop(); continue; }
        const type = tag.match(/^<(\w+)/)[1], id = (tag.match(/\bid="([^"]*)"/) || [])[1] || '';
        const p = new Panel(type, stack.at(-1), id), cls = (tag.match(/\bclass="([^"]*)"/) || [])[1];
        if (cls) p.AddClass(cls);
        const text = (tag.match(/\btext="([^"]*)"/) || [])[1]; if (text !== undefined) p.text = text;
        if (!tag.endsWith('/>')) stack.push(p);
    }
    const $ = selector => nodes[String(selector).replace(/^#/, '')];
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.GetContextPanel = () => root;
    $.Schedule = (delay, callback) => {
        assert(Number.isFinite(delay) && delay >= 0, 'timers have a finite positive delay');
        const id = ++serial; jobs.set(id, {at: time + delay, callback}); return id;
    };
    $.CancelScheduled = id => jobs.delete(id);
    $.RegisterEventHandler = (name, p, callback) => { (p.handlers || (p.handlers = {}))[name] = callback; };
    $.DispatchEvent = $.Msg = () => {};
    const cfg = {};
    const env = {$, console, Date: class extends Date { static now() { return Math.round(time * 1000); } },
        GameUI: {CustomUIConfig: () => cfg, GetCursorPosition: () => cursor},
        Game: {GetLocalPlayerID: () => 0, EmitSound: sound => sounds.push(sound), AddCommand() {}},
        GameEvents: {
            Subscribe(name, callback) { const id = ++serial; events.set(id, {name, callback}); return id; },
            Unsubscribe(id) { events.delete(id); },
            SendCustomGameEventToServer(name, payload) { sent.push({name, payload}); }
        }, CustomNetTables: {
            GetTableValue: name => name === 'survival_rogue_reward' ? initial : null,
            SubscribeNetTableListener(name, callback) { const id = ++serial; tables.set(id, {name, callback}); return id; },
            UnsubscribeNetTableListener(id) { tables.delete(id); }
        }};
    const context = vm.createContext(env);
    const scriptBlock = (xml.match(/<scripts>([\s\S]*?)<\/scripts>/) || [])[1];
    assert(scriptBlock, 'live rogue layout declares its production scripts');
    for (const include of scriptBlock.matchAll(/src="file:\/\/\{resources\}\/([^"]+\.js)"/g)) {
        const relative = include[1]; loaded.push(relative);
        vm.runInContext(fs.readFileSync(path.join(resourceRoot, relative), 'utf8'), context, {filename: relative});
    }
    assert(loaded.includes('scripts/custom_game/rogue_remaining_5d5c1152eb.js'));
    assert(!loaded.includes('scripts/custom_game/rogue_reward_ui.js'), 'retired script must not replace the active UI in this test');
    function update(value, key = '0') {
        for (const listener of [...tables.values()]) if (listener.name === 'survival_rogue_reward') listener.callback(listener.name, key, value);
    }
    function emit(name, value) { for (const entry of [...events.values()]) if (entry.name === name) entry.callback(value); }
    function advance(seconds) {
        const end = time + seconds; let limit = 20000;
        while (limit--) {
            const next = [...jobs].filter(([, job]) => job.at <= end + 1e-10).sort((a, b) => a[1].at - b[1].at)[0];
            if (!next) break;
            jobs.delete(next[0]); time = next[1].at; next[1].callback();
        }
        assert(limit > 0, 'animation scheduling must converge'); time = end;
    }
    return {cfg, nodes, root, all, jobs, events, tables, sent, mutations, loaded, sounds, update, emit, advance,
        setCursor(x, y) { cursor = [x, y]; }, now: () => time,
        event(p, name) { assert(p.events[name], 'panel exposes ' + name); p.events[name](); }};
}

function descendants(p) { return p.Children().flatMap(child => [child, ...descendants(child)]); }
function tagged(p, cls) { return descendants(p).filter(child => child.BHasClass(cls)); }
function buttons(h) { return tagged(h.nodes.RogueRewardCards, 'RoguePick'); }
function offer(token = 'deal_1') {
    return {active: 1, token, rerolls_remaining: 1, cards: [
        {card_id: 'frozen_wall', display_name: '冻结之墙', description: '城墙护甲提高10点。'},
        {card_id: 'tower_growth', display_name: '箭塔成长', description: '箭塔攻击力提高15%。'},
        {card_id: 'recruit_training', display_name: '新兵训练', description: '守卫攻击力提高10%。'}]};
}
function assertNoFlip(h) {
    for (const p of h.all.filter(p => p.classes.has('RogueBack'))) {
        assert.equal(p._visible, false, 'no created card back can become visible');
        assert(!h.mutations.some(m => m.panel === p && m.key === 'visible' && m.value), 'the deal never flashes its card back');
    }
    for (const mutation of h.mutations.filter(m => m.key === 'transform')) {
        for (const match of String(mutation.value).matchAll(/rotate[XY]\(\s*([-\d.]+)deg\)/g)) {
            assert(Math.abs(Number(match[1])) < 45, 'no flip-through-edge rotation: ' + mutation.value);
        }
    }
}

function catalogCoverage() {
    const cards = csv(path.join(project, 'data/csv/肉鸽奖励系统/rogue_reward_cards.csv'));
    assert.equal(cards.length, 52, 'every configured boss and builder card participates in the art audit');
    assert.equal(new Set(cards.map(card => card.card_id)).size, cards.length);
    const h = createHarness(), ui = h.cfg.SurvivalRogueReward;
    ui.SetReducedMotion(true);
    for (const card of cards) {
        const resolved = h.cfg.SurvivalRogueArt.Resolve(card.card_id);
        assert(resolved, 'configured card has a matching illustration: ' + card.card_id);
        assert.match(resolved.uri, /^s2r:\/\/panorama\/images\/loadingscreens\/.+\.vtex$/,
            'illustration uses native large-format artwork: ' + card.card_id);
        assert.equal(resolved.abilityUri, 's2r://panorama/images/spellicons/' + card.icon_name + '_png.vtex',
            'small skill icon follows the authoritative card CSV: ' + card.card_id);
        h.update({active: 1, token: 'catalog_' + card.card_id, cards: [card]});
        const front = tagged(h.nodes.RogueRewardCards, 'RogueFront')[0];
        assert(front && front.visible && buttons(h)[0].enabled);
        assert.match(front.style.backgroundImage, /^url\("s2r:\/\/panorama\/images\/hud\/.+\.vtex"\)$/,
            'native HUD material supplies the card background');
        const artwork = tagged(front, 'RogueOptionIllustration');
        assert.equal(artwork.length, 1);
        assert.equal(artwork[0].style.backgroundImage, 'url("' + resolved.uri + '")');
        assert.equal(artwork[0].style.backgroundSize, 'cover');
        const icons = tagged(front, 'RogueAbilityIcon');
        assert.equal(icons.length, 1); assert.equal(icons[0].image, resolved.abilityUri);
        assert.equal(tagged(front, 'RogueCardName')[0].text, card.display_name, 'art refresh preserves the real card name');
        const description = tagged(front, 'RogueCardDescription')[0].text;
        assert.deepEqual(description.split(/[\n；;]/).map(line => line.trim()), card.description.split(/[\n；;]/).map(line => line.trim()),
            'all original effects and numeric values remain present: ' + card.card_id);
        assertNoFlip(h);
    }
    assert.equal(h.sent.length, 0, 'catalog artwork does not grant, select or reroll rewards');
    ui.Dispose(); assert.equal(h.jobs.size, 0);
}

function run() {
    const h = createHarness(), ui = h.cfg.SurvivalRogueReward, data = offer();
    h.update(data, '1'); assert(!ui.IsOpen(), 'another player cannot open our offer');
    h.update(data); assert(ui.IsOpen()); assert.equal(buttons(h).length, 3);
    assert.equal(h.cfg.SurvivalUILayers.Top(), 'rogue_choice');
    const first = buttons(h)[0]; h.event(first, 'onactivate');
    assert.equal(h.sent.length, 0, 'dealing cards cannot submit an accidental selection');
    for (let i = 0; i < 20; i++) {
        h.advance(.05); assertNoFlip(h);
        assert(tagged(h.nodes.RogueRewardCards, 'RogueFront').every(p => p.visible), 'all dealt artwork always faces the player');
    }
    assert(buttons(h).every(p => p.enabled), 'all choices are selectable within one second');
    assert(tagged(h.nodes.RogueRewardCards, 'RogueSlot').every(p => Number(p.style.opacity) === 1), 'all cards have arrived by one second');
    assert.equal(h.sent.length, 0, 'animation and input tracking do not send transactions');

    // Compare observed direction, without copying the production tilt formula.
    const transforms = () => tagged(h.nodes.RogueRewardCards, 'RogueTilt').map(p => String(p.style.transform || '')).join('|');
    assert.equal(tagged(h.nodes.RogueRewardCards, 'RogueTilt').length, 3, 'each face has its own pointer orientation surface');
    h.event(first, 'onmouseover'); h.setCursor(0, 0); h.advance(.2); const upperLeft = transforms();
    h.setCursor(1919, 1079); h.advance(.2); const lowerRight = transforms();
    assert.notEqual(lowerRight, upperLeft, 'moving the mouse changes the dealt card orientation');
    assertNoFlip(h);
    h.event(first, 'onmouseout'); h.advance(.2); const neutral = transforms();
    h.setCursor(0, 1079); h.advance(.2);
    assert.equal(transforms(), neutral, 'unhovered cards do not continue following the cursor');

    // Native rollover ordering may enter the next card before leaving the old.
    const picks = buttons(h), tiltSurfaces = tagged(h.nodes.RogueRewardCards, 'RogueTilt');
    h.event(picks[0], 'onmouseover');
    for (let i = 1; i <= 12; i++) {
        h.event(picks[i % 3], 'onmouseover'); h.event(picks[(i - 1) % 3], 'onmouseout');
    }
    h.advance(.1);
    const current = tiltSurfaces[0], historyStart = h.mutations.length;
    h.setCursor(1919, 1079); h.advance(.1);
    const moved = h.mutations.slice(historyStart).filter(m => tiltSurfaces.includes(m.panel) && m.key === 'transform');
    assert(moved.length > 0); assert(moved.every(m => m.panel === current), 'only the last hovered card follows subsequent cursor movement');
    assert(tiltSurfaces.slice(1).every(p => p.style.transform === 'none'), 'previous cards return to neutral');
    assert(h.jobs.size <= 2, 'rapid rollover leaves one cursor loop and one layout loop');
    h.event(picks[0], 'onmouseout'); h.advance(.1);

    h.event(buttons(h)[1], 'onactivate'); h.event(buttons(h)[1], 'onactivate');
    h.event(h.nodes.RogueRewardReroll, 'onactivate');
    assert.equal(h.sent.length, 1, 'selection and reroll are mutually locked while pending');
    assert.equal(h.sent[0].name, 'ui_rogue_reward_select');
    assert.equal(h.sent[0].payload.card_id, 'tower_growth');
    h.update({...data}); assert(buttons(h).every(p => !p.enabled), 'same-token snapshots cannot clear pending');
    h.emit('ui_rogue_reward_result', {token: 'stale', ok: 0}); assert(buttons(h).every(p => !p.enabled));
    ui.Close(); assert.equal(h.jobs.size, 0, 'close cancels animation, cursor and layout callbacks');
    ui.Open(); assert(buttons(h).every(p => !p.enabled), 'reopen preserves an in-flight request');
    h.emit('ui_rogue_reward_result', {token: data.token, ok: 0, error: 'retry'});
    assert(buttons(h).every(p => p.enabled), 'a matching failure permits a retry');
    h.event(h.nodes.RogueRewardReroll, 'onactivate'); h.event(h.nodes.RogueRewardReroll, 'onactivate');
    assert.equal(h.sent.length, 2); assert.equal(h.sent[1].name, 'ui_rogue_reward_reroll');

    const wish = {...offer('wish'), cards: [{card_id: 'divine_wish'}, {card_id: 'tower_growth'}, {card_id: 'fiscal_subsidy'}]};
    h.update(wish); h.advance(1); h.event(buttons(h)[0], 'onactivate');
    h.update({...wish, pending_card_id: 'divine_wish'});
    h.emit('ui_rogue_reward_result', {token: 'wish', ok: 0, error: 'builder_inventory_full'});
    assert.deepEqual(buttons(h).map(p => p.enabled), [true, false, false], 'partially applied wish only allows its own retry');
    assert.equal(h.nodes.RogueRewardReroll.enabled, false);
    const beforeWish = h.sent.length;
    h.event(buttons(h)[1], 'onactivate'); h.event(h.nodes.RogueRewardReroll, 'onactivate');
    assert.equal(h.sent.length, beforeWish);
    ui.Close(); ui.Open(); assert.deepEqual(buttons(h).map(p => p.enabled), [true, false, false]);
    h.event(buttons(h)[0], 'onactivate'); assert.equal(h.sent.length, beforeWish + 1);
    assert.equal(h.sent.at(-1).payload.card_id, 'divine_wish');

    // Interrupted dealing never leaves a hidden timer or an obsolete card alive.
    h.update(offer('interrupted')); h.advance(.1);
    const staleCallbacks = [...h.jobs.values()].map(job => job.callback);
    h.cfg.SurvivalUILayers.CloseTop(); assert.equal(h.jobs.size, 0);
    h.update(offer('interrupted')); assert(!ui.IsOpen(), 'same offer remains dismissed');
    h.event(h.nodes.RogueRewardResume, 'onactivate');
    assert(buttons(h).every(p => p.enabled), 'resuming immediately completes an interrupted deal');
    h.update(offer('replacement')); h.advance(1); assertNoFlip(h);
    for (const callback of staleCallbacks) assert.doesNotThrow(callback, 'cancelled generation cannot touch removed panels');
    h.update({active: 0}); assert.equal(h.jobs.size, 0); assert.equal(buttons(h).length, 0);
    h.advance(3); assert(!ui.IsOpen());
    h.update(offer('dispose')); h.advance(.1); ui.Dispose(); ui.Dispose();
    assert.equal(h.jobs.size, 0); assert.equal(h.events.size, 0); assert.equal(h.tables.size, 0);
    assert.equal(h.cfg.SurvivalUILayers.Top(), null); h.advance(3); assert(!ui.IsOpen());

    const motion = createHarness(); motion.cfg.SurvivalRogueReward.SetReducedMotion(true); motion.update(offer('motion'));
    assert(buttons(motion).every(p => p.enabled), 'reduced motion is immediately selectable');
    const motionTilts = tagged(motion.nodes.RogueRewardCards, 'RogueTilt');
    motion.event(buttons(motion)[0], 'onmouseover'); motion.setCursor(0, 0); motion.advance(.2);
    const reducedTransforms = motionTilts.map(p => p.style.transform);
    motion.setCursor(1919, 1079); motion.advance(.2);
    assert.deepEqual(motionTilts.map(p => p.style.transform), reducedTransforms, 'reduced motion never tilts cards in response to the cursor');
    assert(!motion.mutations.some(m => motionTilts.includes(m.panel) && m.key === 'transform' && /rotate[XY]\(/.test(m.value)));
    assertNoFlip(motion); motion.cfg.SurvivalRogueReward.Dispose(); assert.equal(motion.jobs.size, 0);
    catalogCoverage();
    console.log('ROGUE_FAST_DEAL_PASS: actual XML/includes, front-only deal within 1s, 52 CSV cards/native art/effects, cursor tilt and rapid rollover, pending/wish locks, cancellation, resume, reduced motion and disposal');
}

module.exports = {createHarness, offer, descendants, tagged, buttons, assertNoFlip, run};
if (require.main === module) run();
