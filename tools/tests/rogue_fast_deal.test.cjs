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
    let time = 0, serial = 0, cursor = [960, 540], cursorReads = 0;
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
        GameUI: {CustomUIConfig: () => cfg, GetCursorPosition: () => { cursorReads++; return cursor; }},
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
        setCursor(x, y) { cursor = [x, y]; }, cursorReads: () => cursorReads, now: () => time,
        event(p, name) { assert(p.events[name], 'panel exposes ' + name); p.events[name](); }};
}

function descendants(p) { return p.Children().flatMap(child => [child, ...descendants(child)]); }
function tagged(p, cls) { return descendants(p).filter(child => child.BHasClass(cls)); }
function buttons(h) { return tagged(h.nodes.RogueRewardCards, 'RoguePick'); }
function assertInputBoundary(h) {
    for (const slot of tagged(h.nodes.RogueRewardCards, 'RogueSlot')) {
        assert.equal(slot.hittest, false, 'transparent card margins cannot intercept a neighbour');
        assert.equal(slot.hittestchildren, true, 'the visible face and its actual button remain interactive');
        const pick = tagged(slot, 'RoguePick')[0], tilt = tagged(slot, 'RogueTilt')[0];
        assert(pick && tilt); assert.equal(pick.GetParent(), slot); assert.equal(tilt.GetParent(), slot);
        assert.equal(tilt.hittest, false, 'the paint container cannot intercept input itself');
        assert.equal(tilt.hittestchildren, true);
    }
}
function activateDescription(h, index) {
    const front = tagged(h.nodes.RogueRewardCards, 'RogueFront')[index];
    const description = tagged(front, 'RogueCardDescription')[0];
    assert.equal(description.hittest, true, 'description keeps native scrolling and pointer input');
    let receiver = description;
    while (receiver && !receiver.events.onactivate) receiver = receiver.GetParent();
    assert.equal(receiver, front, 'description activation bubbles to its own front, never a neighbouring slot');
    h.event(receiver, 'onactivate');
}
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
        h.update({active: 1, token: 'catalog_' + card.card_id, cards: [card]});
        const front = tagged(h.nodes.RogueRewardCards, 'RogueFront')[0];
        assert(front && front.visible && buttons(h)[0].enabled);
        assertInputBoundary(h);
        // The gray-white native panel can use a solid or gradient material.
        // Panorama visual review checks its color without pinning the old dark texture.
        const artwork = tagged(front, 'RogueOptionIllustration');
        assert.equal(artwork.length, 1);
        assert.equal(artwork[0].style.backgroundImage, 'url("' + resolved.uri + '")');
        assert.equal(artwork[0].style.backgroundSize, 'cover');
        const icons = tagged(front, 'RogueAbilityIcon');
        assert.equal(icons.length, 0, 'the compact title has no upper-left skill icon: ' + card.card_id);
        assert.equal(tagged(front, 'RogueCardName')[0].text, card.display_name, 'art refresh preserves the real card name');
        const description = tagged(front, 'RogueCardDescription')[0].text;
        assert.deepEqual(description.split(/[\n；;]/).map(line => line.trim()), card.description.split(/[\n；;]/).map(line => line.trim()),
            'all original effects and numeric values remain present: ' + card.card_id);
        assertNoFlip(h);
    }
    assert.equal(h.sent.length, 0, 'catalog artwork does not grant, select or reroll rewards');
    ui.Dispose(); assert.equal(h.jobs.size, 0);
}

function motionStates(h) {
    return tagged(h.nodes.RogueRewardCards, 'RogueSlot').map(slot => {
        const surfaces = [slot, ...descendants(slot)];
        const hovered = surfaces.some(p => p.BHasClass('RogueHovered'));
        return {running: !hovered && surfaces.some(p => p.BHasClass('RogueWobble')), hovered};
    });
}
function assertAllWobbling(h, message) {
    assert.deepEqual(motionStates(h), Array.from({length: 3}, () => ({running: true, hovered: false})), message);
}
function assertMotionStopped(h, message) {
    assert(motionStates(h).every(state => !state.running), message);
}

function assertAxisAlignedCardMotion() {
    const xml = fs.readFileSync(path.join(resourceRoot, 'layout/custom_game/rogue_reward_ui.xml'), 'utf8');
    const styles = (xml.match(/<styles>([\s\S]*?)<\/styles>/) || [])[1] || '';
    const includes = [...styles.matchAll(/src="file:\/\/\{resources\}\/([^"]+\.css)"/g)].map(match => match[1]);
    const active = 'styles/custom_game/rogue_readability_v1.css';
    assert.equal(includes.at(-1), active, 'axis-aligned face styles must be the final live XML override');
    const css = fs.readFileSync(path.join(resourceRoot, active), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    function blocks(source) {
        const result = []; let start = 0, depth = 0, header = '', bodyStart = 0;
        for (let i = 0; i < source.length; i++) {
            if (source[i] === '{') {
                if (depth++ === 0) { header = source.slice(start, i).trim(); bodyStart = i + 1; }
            } else if (source[i] === '}' && --depth === 0) {
                result.push({header, body: source.slice(bodyStart, i)}); start = i + 1;
            }
            assert(depth >= 0, 'balanced card CSS blocks');
        }
        assert.equal(depth, 0, 'complete card CSS blocks'); return result;
    }
    function declarations(body, name) {
        return [...body.matchAll(new RegExp('(?:^|;)\\s*' + name + '\\s*:\\s*([^;{}]+)', 'g'))].map(match => match[1].trim());
    }
    function planarTransform(value, context, keyframe) {
        if (value === 'none') return;
        let functions = 0;
        const remainder = value.replace(/([a-zA-Z][a-zA-Z0-9]*)\(\s*([^()]*)\)/g, (_, name, args) => {
            functions++;
            if (/^(?:translate(?:3d|X|Y|Z)?|scale(?:3d|X|Y|Z)?)$/i.test(name)) return '';
            // A neutral legacy reset is safe outside keyframes. Animated faces
            // may only translate/scale: even a one-degree tilt stair-steps a
            // high-contrast native Panel border.
            const zeroRotation = /^(?:rotate(?:X|Y|Z)?|skew(?:X|Y)?)$/i.test(name)
                && args.split(',').every(arg => /^[-+]?0+(?:\.0+)?(?:deg|rad|turn)?$/.test(arg.trim()));
            assert(!keyframe && zeroRotation, context + ' must keep the card face axis aligned: ' + value);
            return '';
        });
        assert(functions && !remainder.trim(), context + ' uses explicit planar transforms: ' + value);
    }
    const rules = blocks(css), animations = new Set(); let checkedTransforms = 0;
    for (const rule of rules.filter(rule => !rule.header.startsWith('@')
        && /\.Rogue(?:Tilt|Pick|Slot|Front)\b/.test(rule.header))) {
        for (const value of declarations(rule.body, 'transform')) {
            planarTransform(value, rule.header, false); checkedTransforms++;
        }
        for (const value of declarations(rule.body, 'animation-name')) {
            for (const name of value.split(',').map(name => name.trim().replace(/^['"]|['"]$/g, ''))) {
                if (name !== 'none') animations.add(name);
            }
        }
    }
    assert(checkedTransforms > 0, 'inspect the actual idle and hover card transforms');
    assert(animations.size > 0, 'idle feedback remains an active native CSS animation');
    for (const name of animations) {
        const frame = rules.find(rule => /^@keyframes\s+/.test(rule.header)
            && rule.header.replace(/^@keyframes\s+/, '').replace(/^['"]|['"]$/g, '') === name);
        assert(frame, 'live card animation has actual keyframes: ' + name);
        const steps = blocks(frame.body); let animatedTransforms = 0;
        for (const step of steps) for (const value of declarations(step.body, 'transform')) {
            planarTransform(value, name + ' ' + step.header, true); animatedTransforms++;
        }
        assert(animatedTransforms > 0, 'inspect every active card animation without fixing its name or amplitude');
    }
}

function run() {
    assertAxisAlignedCardMotion();
    const h = createHarness(), ui = h.cfg.SurvivalRogueReward, data = offer();
    h.update(data, '1'); assert(!ui.IsOpen(), 'another player cannot open our offer');
    h.update(data); assert(ui.IsOpen()); assert.equal(buttons(h).length, 3);
    assertInputBoundary(h); assertMotionStopped(h, 'dealing faces wait until they have arrived before native animation begins');
    assert.equal(h.cfg.SurvivalUILayers.Top(), 'rogue_choice');
    const first = buttons(h)[0]; h.event(first, 'onactivate'); activateDescription(h, 0);
    assert.equal(h.sent.length, 0, 'dealing cards cannot submit an accidental selection');
    for (let i = 0; i < 20; i++) {
        h.advance(.05); assertNoFlip(h);
        assert(tagged(h.nodes.RogueRewardCards, 'RogueFront').every(p => p.visible), 'all dealt artwork always faces the player');
    }
    assert(buttons(h).every(p => p.enabled), 'all choices are selectable within one second');
    assert(tagged(h.nodes.RogueRewardCards, 'RogueSlot').every(p => Number(p.style.opacity) === 1), 'all cards have arrived by one second');
    assert.equal(h.sent.length, 0, 'animation never sends transactions');

    // The verified reference animates its cards in CSS. Check user-visible
    // activation/hover relationships, without mirroring keyframe math or timing.
    assertAllWobbling(h, 'all ready cards run the native idle motion without hover or cursor movement');
    assert.equal(h.jobs.size, 1, 'native idle motion requires only the existing fit timer');
    h.setCursor(0, 0); h.advance(.2); h.setCursor(1919, 1079); h.advance(.2);
    assertAllWobbling(h, 'pointer position does not replace reference idle motion');
    assert.equal(h.cursorReads(), 0, 'the verified CSS reference never polls cursor position');
    assert.equal(h.jobs.size, 1, 'moving the cursor cannot create a direction timer');
    h.event(first, 'onmouseover');
    assert.deepEqual(motionStates(h), [{running: false, hovered: true}, {running: true, hovered: false}, {running: true, hovered: false}],
        'hover pauses only its own card while the other two continue');
    h.advance(.2); assert.equal(h.jobs.size, 1);
    h.event(first, 'onmouseout'); assertAllWobbling(h, 'leaving restores native idle motion');

    // Native rollover ordering may enter the next card before leaving the old.
    const picks = buttons(h); h.event(picks[0], 'onmouseover');
    for (let i = 1; i <= 12; i++) {
        h.event(picks[i % 3], 'onmouseover'); h.event(picks[(i - 1) % 3], 'onmouseout');
    }
    assert.deepEqual(motionStates(h), [{running: false, hovered: true}, {running: true, hovered: false}, {running: true, hovered: false}],
        'stale mouseout never clears the newly hovered card or pauses its neighbours');
    h.advance(.1); assert.equal(h.jobs.size, 1, 'rapid hover changes never spawn JavaScript animation loops');
    h.event(picks[0], 'onmouseout'); assertAllWobbling(h, 'all three resume after rapid hover leaves');

    activateDescription(h, 1);
    h.event(buttons(h)[1], 'onactivate'); h.event(buttons(h)[1], 'onactivate'); activateDescription(h, 2);
    h.event(h.nodes.RogueRewardReroll, 'onactivate');
    assert.equal(h.sent.length, 1, 'selection and reroll are mutually locked while pending');
    assert.equal(h.sent[0].name, 'ui_rogue_reward_select'); assert.equal(h.sent[0].payload.card_id, 'tower_growth');
    assertMotionStopped(h, 'pending selection stops native motion on every card');
    h.update({...data}); assert(buttons(h).every(p => !p.enabled), 'same-token snapshots cannot clear pending');
    h.emit('ui_rogue_reward_result', {token: 'stale', ok: 0}); assert(buttons(h).every(p => !p.enabled));
    ui.Close(); assert.equal(h.jobs.size, 0, 'close cancels dealing and fitting callbacks');
    assertMotionStopped(h, 'closing also disables native CSS motion');
    ui.Open(); assert(buttons(h).every(p => !p.enabled), 'reopen preserves an in-flight request');
    assertMotionStopped(h, 'reopen cannot restart motion while its request remains pending');
    h.emit('ui_rogue_reward_result', {token: data.token, ok: 0, error: 'retry'});
    assert(buttons(h).every(p => p.enabled), 'a matching failure permits a retry');
    assertAllWobbling(h, 'matching selection failure restores native motion, including after close/reopen');
    assert.equal(h.jobs.size, 1, 'retry recovery retains only layout fitting');
    h.event(h.nodes.RogueRewardReroll, 'onactivate'); h.event(h.nodes.RogueRewardReroll, 'onactivate');
    assert.equal(h.sent.length, 2); assert.equal(h.sent[1].name, 'ui_rogue_reward_reroll');
    assertMotionStopped(h, 'pending reroll stops native card motion');
    h.advance(.1); assert.equal(h.jobs.size, 1);
    h.emit('ui_rogue_reward_result', {token: data.token, ok: 0, error: 'reroll_retry'});
    assertAllWobbling(h, 'matching reroll failure restores all three native animations');
    assert.equal(h.jobs.size, 1);

    const wish = {...offer('wish'), cards: [{card_id: 'divine_wish'}, {card_id: 'tower_growth'}, {card_id: 'fiscal_subsidy'}]};
    h.update(wish); h.advance(1); h.event(buttons(h)[0], 'onactivate');
    h.update({...wish, pending_card_id: 'divine_wish'});
    h.emit('ui_rogue_reward_result', {token: 'wish', ok: 0, error: 'builder_inventory_full'});
    assert.deepEqual(buttons(h).map(p => p.enabled), [true, false, false], 'partially applied wish only allows its own retry');
    assert.equal(h.nodes.RogueRewardReroll.enabled, false);
    const beforeWish = h.sent.length;
    h.event(buttons(h)[1], 'onactivate'); h.event(h.nodes.RogueRewardReroll, 'onactivate'); activateDescription(h, 2);
    assert.equal(h.sent.length, beforeWish);
    ui.Close(); ui.Open(); assert.deepEqual(buttons(h).map(p => p.enabled), [true, false, false]);
    h.event(buttons(h)[0], 'onactivate'); assert.equal(h.sent.length, beforeWish + 1);
    assert.equal(h.sent.at(-1).payload.card_id, 'divine_wish');

    // Interrupted dealing never leaves a hidden timer or an obsolete card alive.
    h.update(offer('interrupted')); h.advance(.1);
    const staleCallbacks = [...h.jobs.values()].map(job => job.callback);
    h.cfg.SurvivalUILayers.CloseTop(); assert.equal(h.jobs.size, 0);
    assertMotionStopped(h, 'interrupted hidden choices cannot keep native card motion active');
    h.update(offer('interrupted')); assert(!ui.IsOpen(), 'same offer remains dismissed');
    h.event(h.nodes.RogueRewardResume, 'onactivate');
    assert(buttons(h).every(p => p.enabled), 'resuming immediately completes an interrupted deal');
    assertAllWobbling(h, 'resuming an interrupted deal starts all three reference animations');
    h.update(offer('replacement')); h.advance(1); assertNoFlip(h);
    for (const callback of staleCallbacks) assert.doesNotThrow(callback, 'cancelled generation cannot touch removed panels');
    h.update({active: 0}); assert.equal(h.jobs.size, 0); assert.equal(buttons(h).length, 0);
    h.advance(3); assert(!ui.IsOpen());
    h.update(offer('dispose')); h.advance(.1); ui.Dispose(); ui.Dispose();
    assert.equal(h.jobs.size, 0); assert.equal(h.events.size, 0); assert.equal(h.tables.size, 0);
    assertMotionStopped(h, 'disposal disables the retained native animation classes');
    assert.equal(h.cfg.SurvivalUILayers.Top(), null); h.advance(3); assert(!ui.IsOpen());

    const motion = createHarness(), motionUI = motion.cfg.SurvivalRogueReward;
    motionUI.SetReducedMotion(true); motion.update(offer('motion'));
    assert(buttons(motion).every(p => p.enabled), 'reduced motion is immediately selectable');
    assertMotionStopped(motion, 'reduced motion suppresses native idle animation');
    motion.setCursor(0, 0); motion.advance(.2); motion.event(buttons(motion)[0], 'onmouseover');
    motion.setCursor(1919, 1079); motion.advance(.2); assertMotionStopped(motion, 'hover cannot restart native idle animation under reduced motion');
    assert.equal(motion.jobs.size, 1); assert.equal(motion.cursorReads(), 0);
    assertNoFlip(motion); motionUI.Dispose(); assert.equal(motion.jobs.size, 0);
    const changedMotion = createHarness(), changedUI = changedMotion.cfg.SurvivalRogueReward;
    changedMotion.update(offer('change_motion')); changedMotion.advance(1.1); assertAllWobbling(changedMotion);
    changedUI.SetReducedMotion(true); assertMotionStopped(changedMotion, 'live reduced-motion setting stops all CSS animation');
    assert.equal(changedMotion.jobs.size, 1);
    for (let i = 0; i < 4; i++) { changedUI.SetReducedMotion(false); changedUI.SetReducedMotion(true); }
    changedUI.SetReducedMotion(false); assertAllWobbling(changedMotion, 'disabling reduced motion restores all three native animations');
    changedMotion.advance(.1); assert.equal(changedMotion.jobs.size, 1, 'rapid motion toggles never create a JavaScript direction loop');
    changedUI.Dispose(); assert.equal(changedMotion.jobs.size, 0);
    catalogCoverage();
    console.log('ROGUE_FAST_DEAL_PASS: actual XML/includes, front-only deal within 1s, 52 CSV cards/native art/effects/no title icons, axis-aligned native CSS idle/hover motion without cursor polling, input and pending/wish guards, lifecycle, retry and reduced motion');
}

module.exports = {createHarness, offer, descendants, tagged, buttons, assertNoFlip, motionStates, run};
if (require.main === module) run();
