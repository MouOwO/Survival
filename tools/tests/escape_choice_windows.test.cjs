const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const workspace = path.resolve(__dirname, '../..');

function harness(script, initial, tableName, ids) {
    const nodes = new Map(), events = new Map(), tables = new Map(), timers = new Map(), sent = [];
    let sequence = 0, clock = 0, fitCount = 0;
    function create(type, parent, id = '') {
        const node = { id: id || `auto_${++sequence}`, paneltype: type, parent, style: {}, children: [],
            visible: true, enabled: true, classes: new Set(), handlers: {}, valid: true,
            AddClass(c) { this.classes.add(c); }, RemoveClass(c) { this.classes.delete(c); },
            SetHasClass(c, value) { value ? this.classes.add(c) : this.classes.delete(c); },
            BHasClass(c) { return this.classes.has(c); }, IsValid() { return this.valid; },
            GetParent() { return this.parent; }, Children() { return this.children; },
            SetPanelEvent(name, callback) { this.handlers[name] = callback; },
            DeleteAsync() { this.valid = false; if (this.parent) this.parent.children = this.parent.children.filter(n => n !== this); },
            RemoveAndDeleteChildren() { this.children.forEach(n => n.DeleteAsync()); this.children = []; }
        };
        nodes.set(node.id, node);
        if (parent) parent.children.push(node);
        return node;
    }
    const root = create('Panel', null, 'root');
    ids.forEach(id => create('Panel', root, id));
    const $ = selector => nodes.get(selector.replace(/^#/, ''));
    $.CreatePanel = create;
    $.GetContextPanel = () => root;
    $.Schedule = (delay, callback) => { const id = ++sequence; timers.set(id, { at: clock + delay, callback }); return id; };
    $.CancelScheduled = id => timers.delete(id);
    const GameEvents = {
        Subscribe(name, callback) { const id = ++sequence; events.set(id, { name, callback }); return id; },
        Unsubscribe(id) { events.delete(id); },
        SendCustomGameEventToServer(name, payload) { sent.push({ name, payload }); }
    };
    function lifecycle() {
        const ownedTimers = new Set(), ownedEvents = new Set();
        const life = {
            Later(delay, callback) { let id; id = $.Schedule(delay, () => { ownedTimers.delete(id); callback(); }); ownedTimers.add(id); return id; },
            Subscribe(name, callback) { const id = GameEvents.Subscribe(name, callback); ownedEvents.add(id); return id; },
            Cancel() { ownedTimers.forEach(id => $.CancelScheduled(id)); ownedTimers.clear(); },
            Dispose() { life.Cancel(); ownedEvents.forEach(id => GameEvents.Unsubscribe(id)); ownedEvents.clear(); }
        };
        return life;
    }
    const stack = [];
    const cfg = {
        SurvivalUI: { Lifecycle: lifecycle, Fit() { fitCount++; }, FullscreenShell: { Adopt() {} } },
        RemainingHandoff: { RogueSequence() {
            const life = lifecycle();
            return { Later: life.Later, Cancel: life.Cancel, Dispose: life.Dispose,
                Animate(card) { life.Later(.4, () => { card.slot.style.opacity = '1'; }); } };
        } },
        SurvivalRogueArt: { Apply() {} },
        SurvivalUILayers: {
            Open(id, panel, close) { this.Close(id); stack.push({ id, panel, close }); },
            Close(id) { const index = stack.findIndex(entry => entry.id === id); if (index >= 0) stack.splice(index, 1); },
            Top() { return stack.at(-1)?.id || null; },
            CloseTop() { stack.at(-1)?.close('escape'); }
        }
    };
    const context = {
        $, GameUI: { CustomUIConfig: () => cfg }, Game: { GetLocalPlayerID: () => 0, EmitSound() {} }, GameEvents,
        CustomNetTables: {
            GetTableValue: name => name === tableName ? initial : null,
            SubscribeNetTableListener(name, callback) { const id = ++sequence; tables.set(id, { name, callback }); return id; },
            UnsubscribeNetTableListener(id) { tables.delete(id); }
        }
    };
    vm.runInNewContext(fs.readFileSync(path.join(workspace, script), 'utf8'), context, { filename: script });
    return { cfg, nodes, timers, events, tables, sent, fitCount: () => fitCount,
        update(value) { for (const entry of tables.values()) if (entry.name === tableName) entry.callback(tableName, tableName === 'survival_rogue_reward' ? '0' : 'player_0', value); },
        event(name, value) { for (const entry of events.values()) if (entry.name === name) entry.callback(value); },
        runUntil(end) {
            let limit = 1000;
            while (limit--) {
                const next = [...timers].filter(([, timer]) => timer.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
                if (!next) break;
                timers.delete(next[0]); clock = next[1].at; next[1].callback();
            }
            assert(limit > 0, 'callbacks must not create an unbounded loop'); clock = end;
        }
    };
}

function rogueOffer(token, cardId = 'instant_wood') {
    return { active: 1, token, rerolls_remaining: 1, cards: [{ card_id: cardId, display_name: cardId, description: '强化' }] };
}
const rogue = harness('panorama/src/scripts/custom_game/rogue_remaining_5d5c1152eb.js', rogueOffer('rogue_1'), 'survival_rogue_reward',
    ['RogueRewardBackdrop', 'RogueRewardSurface', 'RogueRewardCards', 'RogueRewardReroll', 'RogueRewardRerollText', 'RogueRewardStatus']);
const rogueUI = rogue.cfg.SurvivalRogueReward;
const rogueResume = rogue.nodes.get('RogueRewardResume');
assert(rogueUI.IsOpen()); assert.equal(rogue.cfg.SurvivalUILayers.Top(), 'rogue_choice');
assert(rogue.timers.size > 0, 'visible reveal schedules animation and fitting');
rogue.cfg.SurvivalUILayers.CloseTop();
assert(!rogueUI.IsOpen()); assert(rogueResume.visible); assert.equal(rogue.cfg.SurvivalUILayers.Top(), null);
assert.equal(rogue.timers.size, 0, 'Escape cancels reveal and fitting callbacks');
assert.equal(rogue.sent.length, 0, 'dismissal never selects or cancels a server offer');
const fitsBeforeHide = rogue.fitCount(); rogue.runUntil(4);
assert.equal(rogue.fitCount(), fitsBeforeHide, 'hidden choice does not continue fitting');
rogue.update(rogueOffer('rogue_1')); assert(!rogueUI.IsOpen()); assert(rogueResume.visible);
rogue.update(rogueOffer('rogue_1', 'instant_gold'));
assert(!rogueUI.IsOpen()); assert.equal(rogue.timers.size, 0, 'same-token candidate refresh remains paused');
rogueUI.SetReducedMotion(true); assert.equal(rogue.timers.size, 0, 'motion setting does not restart a hidden offer');
rogueResume.handlers.onactivate(); assert(rogueUI.IsOpen()); assert(!rogueResume.visible);
const rogueButton = rogue.nodes.get('RogueRewardCards').children[0].children[0];
assert(rogueButton.enabled, 'resume makes an interrupted reveal immediately selectable');
rogueButton.handlers.onactivate();
assert.equal(rogue.sent.length, 1); assert.equal(rogue.sent[0].payload.token, 'rogue_1'); assert.equal(rogue.sent[0].payload.card_id, 'instant_gold');
rogue.cfg.SurvivalUILayers.CloseTop(); rogueResume.handlers.onactivate();
assert(!rogueButton.enabled, 'reopen preserves an in-flight selection');
rogue.event('ui_rogue_reward_result', { token: 'rogue_1', ok: 0, error: 'retry' }); assert(rogueButton.enabled);
rogue.cfg.SurvivalUILayers.CloseTop(); rogue.update(rogueOffer('rogue_2'));
assert(rogueUI.IsOpen(), 'a new offer reopens'); assert(!rogueResume.visible);
rogue.cfg.SurvivalUILayers.CloseTop(); rogue.update({ active: 0 });
assert(!rogueUI.IsOpen()); assert(!rogueResume.visible); assert.equal(rogue.timers.size, 0);
rogue.update(rogueOffer('rogue_3')); rogueUI.Dispose();
assert(!rogueUI.IsOpen()); assert(!rogueResume.IsValid()); assert.equal(rogue.timers.size, 0);
assert.equal(rogue.events.size, 0); assert.equal(rogue.tables.size, 0); assert.equal(rogue.cfg.SurvivalUILayers.Top(), null);

function skillOffer(token, skillId = 'critical') {
    return { pending: 1, choice_token: token, rerolls: 1, candidates: [{ skill_id: skillId, next_level: 1 }] };
}
const skills = harness('panorama/src/scripts/custom_game/hero_skill_ui.js', skillOffer('skill_1'), 'survival_hero_skill_choice',
    ['HeroSkillChoiceBackdrop', 'HeroSkillChoiceList', 'HeroSkillChoiceResult']);
const skillUI = skills.cfg.SurvivalHeroSkillChoice;
const skillResume = skills.nodes.get('HeroSkillChoiceResume');
assert(skillUI.IsOpen()); assert.equal(skills.cfg.SurvivalUILayers.Top(), 'hero_skill_choice');
skills.cfg.SurvivalUILayers.CloseTop(); assert(!skillUI.IsOpen()); assert(skillResume.visible);
assert.equal(skills.sent.length, 0, 'Escape preserves skill choice token without selecting or cancelling');
skills.update(skillOffer('skill_1', 'chain_lightning')); assert(!skillUI.IsOpen()); assert(skillResume.visible);
skills.event('ui_hero_skill_choice', skillOffer('skill_1', 'chain_lightning')); assert(!skillUI.IsOpen());
skillResume.handlers.onactivate(); assert(skillUI.IsOpen()); assert(!skillResume.visible);
skills.nodes.get('HeroSkillChoiceList').children[0].handlers.onactivate();
assert.equal(skills.sent.length, 1); assert.equal(skills.sent[0].payload.choice_token, 'skill_1'); assert.equal(skills.sent[0].payload.skill_id, 'chain_lightning');
skills.cfg.SurvivalUILayers.CloseTop(); skills.update(skillOffer('skill_2'));
assert(skillUI.IsOpen(), 'new skill token reopens'); assert(!skillResume.visible);
skills.cfg.SurvivalUILayers.CloseTop(); skills.update({ pending: 0 });
assert(!skillUI.IsOpen()); assert(!skillResume.visible); assert.equal(skills.cfg.SurvivalUILayers.Top(), null);
skills.update(skillOffer('skill_3')); skillUI.Dispose();
assert(!skillUI.IsOpen()); assert(!skillResume.IsValid()); assert.equal(skills.events.size, 0); assert.equal(skills.tables.size, 0);
assert.equal(skills.cfg.SurvivalUILayers.Top(), null); assert.equal(skills.timers.size, 0);

console.log('ESCAPE_CHOICE_WINDOWS_PASS: dismissal, token preservation, resume, same-token updates, new offers, timer pause and disposal');
