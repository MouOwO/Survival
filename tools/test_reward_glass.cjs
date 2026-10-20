'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game/common/reward_feedback.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'panorama/src/styles/custom_game/common/reward_feedback.css'), 'utf8');

function harness(residentRewardFX) {
    const config = {SurvivalUI: residentRewardFX ? {RewardFX: residentRewardFX} : {}}, panels = [], jobs = new Map(), allJobs = [];
    let sequence = 0, now = 0;
    class Panel {
        constructor(type, parent, id) {
            this.paneltype = type; this.parent = parent; this.id = id; this.children = [];
            this.style = {}; this.classes = new Set(); this.valid = true; this.visible = true;
            this.actuallayoutwidth = 1200; this.actuallayoutheight = 900;
            this.actualuiscale_x = 1; this.actualuiscale_y = 1;
            this.position = {x: 0, y: 0};
            if (parent) parent.children.push(this);
            panels.push(this);
        }
        IsValid() { return this.valid && (!this.parent || this.parent.IsValid()); }
        GetParent() { return this.parent; }
        GetPositionWithinWindow() { return this.position; }
        AddClass(name) { this.classes.add(name); }
        RemoveClass(name) { this.classes.delete(name); }
        BHasClass(name) { return this.classes.has(name); }
        SetHasClass(name, present) { if (present) this.classes.add(name); else this.classes.delete(name); }
        FindChildTraverse(id) {
            for (const child of this.children) {
                if (child.id === id && child.IsValid()) return child;
                const found = child.FindChildTraverse(id); if (found) return found;
            }
            return null;
        }
        BLoadLayout() { assert.fail('Daily glass does not load a particle/3D XML layout'); }
        DeleteAsync(delay) { assert.equal(delay, 0); this.valid = false; }
    }
    const $ = {
        CreatePanel(type, parent, id) {
            assert.equal(type, 'Panel', 'Glass adds only two flat panels, with no labels, particles or 3D scenes');
            assert(parent.IsValid());
            return new Panel(type, parent, id);
        },
        Schedule(delay, fn) {
            const id = ++sequence, job = {id, delay, at: now + delay, fn};
            jobs.set(id, job); allJobs.push(job); return id;
        },
        CancelScheduled(id) { jobs.delete(id); }
    };
    vm.runInNewContext(source, {$, GameUI: {CustomUIConfig: () => config}}, {filename: 'reward_feedback.js'});
    function advance(seconds) {
        const until = now + seconds;
        for (;;) {
            const due = [...jobs.values()].filter(job => job.at <= until).sort((a, b) => a.at - b.at || a.id - b.id)[0];
            if (!due) break;
            jobs.delete(due.id); now = due.at; due.fn();
        }
        now = until;
    }
    const owner = new Panel('Panel', null, 'DailyCanvas');
    function card(id = 'RewardCard') {
        const result = new Panel('Panel', owner, id);
        result.position = {x: 320, y: 180};
        result.actuallayoutwidth = 126; result.actuallayoutheight = 94;
        return result;
    }
    function effects() { return panels.filter(panel => panel.BHasClass('RewardGlassSurface')); }
    function sweeps() { return panels.filter(panel => panel.BHasClass('RewardGlassSweep')); }
    return {config, Panel, panels, owner, card, jobs, allJobs, advance, effects, sweeps};
}

const h = harness(), anchor = h.card();
const fx = h.config.SurvivalUI.RewardFX.Create(h.owner, {channel: 'daily'});
assert.equal(h.config.SurvivalUI.RewardFX.version, '1.2.2');
assert.equal(h.effects().length, 0); assert.equal(h.jobs.size, 0);
assert.equal(fx.Play({key: 'missing-anchor'}), false, 'A card shine cannot fall back to a centered reward burst');
anchor.valid = false;
assert.equal(fx.Play({key: 'invalid-anchor', anchor}), false);
assert.equal(h.jobs.size, 0); anchor.valid = true;
assert.equal(fx.Play({key: 'one', anchor, title: '领取成功', text: '木材 +100'}), true);
assert.equal(h.jobs.size, 1);
assert.equal(h.allJobs.at(-1).delay, 0.65, 'The only callback is finite cleanup, without a layout or frame polling timer');
assert.equal(fx.Play({key: 'one', anchor}), false, 'Duplicate responses do not restart the shine');
const first = h.effects()[0], band = h.sweeps()[0];
assert(first && band); assert.equal(band.GetParent(), first);
assert.equal(first.hittest, false); assert.equal(first.hittestchildren, false);
assert.equal(band.hittest, false); assert.equal(band.hittestchildren, false);
assert.equal(first.visible, true);
assert.equal(first.GetParent(), anchor, 'The glass follows the newly rendered reward card natively');
assert.equal(first.style.position, '0px 0px 0px');
assert.equal(first.style.width, '100%'); assert.equal(first.style.height, '100%');
assert(anchor.BHasClass('RewardGlassActive'), 'The just-claimed card remains bright for the pass');
assert.equal(h.jobs.size, 1); assert.equal(h.allJobs.length, 1, 'One cleanup callback, with no layout or frame polling');
assert.equal(h.allJobs.at(-1).delay, 0.65);
const oldCleanup = h.allJobs.at(-1).fn;
const firstAnimation = JSON.stringify([...first.classes, ...band.classes].sort());
assert.equal(fx.Play({key: 'one', anchor}), false, 'Visible rewards remain deduplicated');
assert.equal(fx.Play({key: 'two', anchor}), true);
h.advance(0);
assert.equal(h.effects().length, 1); assert.equal(h.sweeps().length, 1, 'Rapid successful rewards reuse the same two panels');
assert.notEqual(JSON.stringify([...first.classes, ...band.classes].sort()), firstAnimation, 'Alternate animation names replay CSS without a per-frame timer');
oldCleanup();
assert.equal(first.IsValid(), true); assert.equal(first.visible, true, 'Stale cleanup cannot hide a newer reward');
h.advance(0.64); assert.equal(first.IsValid(), true);
h.advance(0.02); assert.equal(first.IsValid(), false); assert.equal(h.jobs.size, 0);
assert(!anchor.BHasClass('RewardGlassActive'), 'Normal claimed styling returns when the pass finishes');
assert.equal(fx.Play({key: 'two', anchor}), false, 'Finished reward keys remain deduplicated');
assert.equal(fx.Play({key: 'three', anchor}), true); h.advance(0);
fx.Clear(); assert.equal(h.jobs.size, 0); assert.equal(h.effects().at(-1).IsValid(), false);
assert.equal(fx.Play({key: 'three', anchor}), false, 'Clear retains successful response history');
assert.equal(fx.Play({key: '__proto__', anchor}), true); h.advance(0);
assert.equal(fx.Play({key: 'constructor', anchor}), true); h.advance(0);
for (let i = 0; i < 65; i++) {
    assert.equal(fx.Play({key: 'bounded-' + i, anchor}), true); h.advance(0);
    assert.equal(h.effects().filter(panel => panel.IsValid()).length, 1);
    assert.equal(h.jobs.size, 1);
}
assert.equal(fx.Play({key: 'one', anchor}), true, 'Response history evicts keys beyond 64 entries');
fx.Dispose(); fx.Dispose(); assert.equal(h.jobs.size, 0);
assert.equal(fx.Play({key: 'disposed', anchor}), false);

for (const explicit of [false, true]) {
    const g = harness(), outer = new g.Panel('Panel', null, 'Fit');
    outer.style.transform = 'scale3d(0.6,0.6,1)';
    g.owner.parent = outer; outer.children.push(g.owner);
    g.owner.position = {x: 100, y: 50};
    g.owner.actualuiscale_x = g.owner.actualuiscale_y = 0.8;
    g.owner.actuallayoutwidth = 960; g.owner.actuallayoutheight = 720;
    const card = g.card(); card.position = {x: 400, y: 230};
    card.actuallayoutwidth = 80; card.actuallayoutheight = 60;
    const f = g.config.SurvivalUI.RewardFX.Create(g.owner, explicit ? {channel: 'daily', getScale: () => 0.6} : {channel: 'daily'});
    assert(f.Play({key: 'scaled', anchor: card})); g.advance(0);
    const surface = g.effects()[0];
    assert.equal(surface.GetParent(), card, 'Native parenting follows the card under both implicit and explicit Fit');
    assert.equal(surface.style.position, '0px 0px 0px');
    assert.equal(surface.style.width, '100%'); assert.equal(surface.style.height, '100%', 'Shine fills its card without rounding or double-applying UI scale');
    f.Dispose(); assert.equal(g.jobs.size, 0);
}

const nested = harness(), fit = new nested.Panel('Panel', null, 'NonUniformFit');
fit.style.transform = 'scale3d(0.5,0.75,1)';
nested.owner.parent = fit; fit.children.push(nested.owner);
nested.owner.position = {x: 40, y: 60};
nested.owner.actualuiscale_x = 0.8; nested.owner.actualuiscale_y = 0.9;
const nestedCard = nested.card(); nestedCard.position = {x: 240, y: 262.5};
nestedCard.style.transform = 'scale3d(0.8,0.6,1)';
nestedCard.actuallayoutwidth = 80; nestedCard.actuallayoutheight = 90;
const nestedFX = nested.config.SurvivalUI.RewardFX.Create(nested.owner, {channel: 'daily'});
assert(nestedFX.Play({key: 'nested-fit', anchor: nestedCard})); nested.advance(0);
assert.equal(nested.effects()[0].GetParent(), nestedCard, 'Nested nonuniform transforms affect the card and glass together');
assert.equal(nested.effects()[0].style.position, '0px 0px 0px');
assert.equal(nested.effects()[0].style.width, '100%');
assert.equal(nested.effects()[0].style.height, '100%');
nestedFX.Dispose();

const fresh = harness(), freshCard = fresh.card();
const waiting = fresh.config.SurvivalUI.RewardFX.Create(fresh.owner, {channel: 'daily'});
freshCard.actuallayoutwidth = freshCard.actuallayoutheight = 0;
freshCard.GetPositionWithinWindow = () => assert.fail('A just-rendered card has not completed native layout');
assert(waiting.Play({key: 'fresh-anchor', anchor: freshCard}));
fresh.advance(0.1);
assert.equal(fresh.effects()[0].visible, true, 'The saved response is not discarded when native layout remains zero for multiple frames');
freshCard.position = {x: 301, y: 202}; freshCard.actuallayoutwidth = 84; freshCard.actuallayoutheight = 72;
assert.equal(fresh.effects()[0].GetParent(), freshCard);
assert.equal(fresh.effects()[0].style.width, '100%'); assert.equal(fresh.effects()[0].style.height, '100%');
waiting.Clear();
freshCard.actuallayoutwidth = 0;
assert(waiting.Play({key: 'close-before-paint', anchor: freshCard}));
const canceledCleanup = fresh.allJobs.at(-1).fn;
waiting.Clear(); canceledCleanup(); fresh.advance(1);
assert.equal(fresh.jobs.size, 0); assert.equal(fresh.effects().at(-1).IsValid(), false, 'Closing before the next paint cannot resurrect a shine');
assert(!freshCard.BHasClass('RewardGlassActive'));
assert(waiting.Play({key: 'deleted-card', anchor: freshCard}));
freshCard.valid = false;
assert.equal(fresh.effects().at(-1).IsValid(), false, 'Deleting a reward card immediately hides its local shine');
fresh.advance(1); assert.equal(fresh.jobs.size, 0);
freshCard.valid = true;
assert(waiting.Play({key: 'deleted-root', anchor: freshCard}));
fresh.owner.valid = false; fresh.advance(1);
assert.equal(fresh.jobs.size, 0);
assert.equal(waiting.Play({key: 'root-deleted', anchor: freshCard}), false);
waiting.Dispose();

// The visual tile is smaller than its calendar card. The shine must follow
// that explicit tile, including zero-layout frames, rather than the card date
// and footer area. It must never regain pointer hit testing.
{
    const bounded = harness(), card = bounded.card('DailyGW2Day_4');
    const icon = new bounded.Panel('Panel', card, 'DailyRewardIcon');
    icon.style.position = '2px 25px 0px';
    icon.style.width = '127px'; icon.style.height = '97px';
    icon.actuallayoutwidth = icon.actuallayoutheight = 0;
    const f = bounded.config.SurvivalUI.RewardFX.Create(bounded.owner, {channel:'daily'});
    assert.equal(f.Play({key:'missing-surface',anchor:card,surface:null}),false,'A missing explicit icon cannot fall back to a larger card or button');
    assert.equal(bounded.effects().length,0);
    assert(f.Play({key:'icon-bounds',anchor:card,surface:icon}));
    const glass = bounded.effects()[0];
    assert.equal(glass.GetParent(),icon,'The clip host is parented directly to the reward tile');
    assert.equal(glass.style.position,'0px 0px 0px');
    assert.equal(glass.style.width,'100%'); assert.equal(glass.style.height,'100%');
    assert.equal(glass.hittest,false);assert.equal(glass.hittestchildren,false);
    assert(card.BHasClass('RewardGlassActive'),'Claim state belongs to the card independently of the shine rectangle');
    assert(!icon.BHasClass('RewardGlassActive'));
    icon.actuallayoutwidth=127;icon.actuallayoutheight=97;
    assert.equal(glass.GetParent(),icon,'Native layout and Fit cannot expand the icon-local clip host');
    const second = new bounded.Panel('Panel',card,'ReplacementRewardIcon');
    assert(f.Play({key:'replacement-icon',anchor:card,surface:second}));
    assert.equal(glass.IsValid(),false,'Changing the visual surface retires the old clip host');
    assert.equal(bounded.effects().at(-1).GetParent(),second);
    f.Clear();assert(!card.BHasClass('RewardGlassActive'));
    assert.equal(bounded.jobs.size,0);f.Dispose();
}

for (const version of ['1.1.0', '1.2.0', '1.2.1']) {
    const staleCreate = () => assert.fail('Hot reload must not keep the resident reward implementation');
    const resident = {version, Create: staleCreate}, reload = harness(resident);
    assert.notEqual(reload.config.SurvivalUI.RewardFX, resident, 'Hot reload replaces resident '+version);
    assert.equal(reload.config.SurvivalUI.RewardFX.version, '1.2.2');
    const card = reload.card(); card.actuallayoutwidth = card.actuallayoutheight = 0;
    const effect = reload.config.SurvivalUI.RewardFX.Create(reload.owner, {channel:'daily'});
    assert(effect.Play({key:'resident-'+version,anchor:card}));
    assert.equal(reload.effects()[0].GetParent(),card, 'The freshly installed implementation uses native card parenting');
    effect.Dispose(); assert.equal(reload.jobs.size,0);
}

{
    const resident = {version:'1.2.2',Create:()=>null}, current = harness(resident);
    assert.equal(current.config.SurvivalUI.RewardFX,resident,'The matching version guard remains idempotent');
}

assert.match(css, /\.RewardGlassSurface\s*\{[^}]*overflow:\s*clip;/, 'The glare is clipped to its card glass');
assert.match(css, /\.RewardGlassSweep\s*\{[^}]*animation-duration:\s*0?\.58s;/);
assert(!/animation-iteration-count\s*:\s*infinite/.test(css), 'There are no idle shine animation loops');
console.log('REWARD_GLASS_PASS: zero-size native layout, card-local sizing, nested Fit/UI scale, finite cleanup, dedup, stale/deleted panels and resident module hot reload');
