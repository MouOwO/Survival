'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game/common/reward_feedback.js'), 'utf8');
const xml = fs.readFileSync(path.join(root, 'panorama/src/layout/custom_game/common/reward_feedback.xml'), 'utf8');
const css = fs.readFileSync(path.join(root, 'panorama/src/styles/custom_game/common/reward_feedback.css'), 'utf8');
assert.equal((xml.match(/<DOTAParticleScenePanel\b/g) || []).length, 1);
assert.match(xml, /particleName="particles\/ui\/ui_godrays_soft_glow\.vpcf"/);
assert.match(xml, /startActive="false"/);
assert.match(xml, /cameraOrigin="0 0 120" lookAt="0 0 0" fov="80"/);
assert(!/animation-iteration-count\s*:\s*infinite/.test(css));

function harness() {
    const jobs = new Map(), allJobs = [], particles = [], panels = [], config = {SurvivalUI: {}};
    let seq = 0, time = 0, maximumActive = 0, failLoad = false, failStart = false;
    class Panel {
        constructor(type, parent, id) {
            this.paneltype = type; this.parent = parent; this.id = id; this.children = [];
            this.style = {}; this.classes = new Set(); this.valid = true; this.visible = true;
            this.actuallayoutwidth = 1200; this.actuallayoutheight = 900;
            this.actualuiscale_x = 1; this.actualuiscale_y = 1; this.position = {x: 0, y: 0};
            if (parent) parent.children.push(this);
            panels.push(this);
            if (type === 'DOTAParticleScenePanel') {
                particles.push(this); this.playing = false; this.starts = 0; this.stops = 0;
                this.StartParticles = () => {
                    if (failStart) throw Error('Native scene failed');
                    this.playing = true; this.starts++;
                    maximumActive = Math.max(maximumActive, particles.filter(p => p.IsValid() && p.playing).length);
                };
                this.StopParticlesImmediately = immediate => {
                    assert.equal(immediate, true); this.playing = false; this.stops++;
                };
            }
        }
        IsValid() { return this.valid && (!this.parent || this.parent.IsValid()); }
        GetParent() { return this.parent; }
        GetPositionWithinWindow() { return this.position; }
        SetHasClass(name, yes) { if (yes) this.classes.add(name); else this.classes.delete(name); }
        FindChildTraverse(id) {
            for (const child of this.children) {
                if (child.id === id && child.IsValid()) return child;
                const found = child.FindChildTraverse(id); if (found) return found;
            }
            return null;
        }
        BLoadLayout(uri, reload, controls) {
            assert.equal(uri, 'file://{resources}/layout/custom_game/common/reward_feedback.xml');
            assert.equal(reload, false); assert.equal(controls, false);
            if (failLoad) return false;
            const scene = new Panel('DOTAParticleScenePanel', this, 'RewardFXParticle');
            scene.hittest = false; scene.hittestchildren = false;
            new Panel('Label', this, 'RewardFXTitle');
            new Panel('Label', this, 'RewardFXDetail');
            return true;
        }
        DeleteAsync(delay) { assert.equal(delay, 0); this.valid = false; }
    }
    const $ = {
        CreatePanel(type, parent, id) { assert(parent.IsValid()); return new Panel(type, parent, id); },
        Schedule(delay, fn) { const id = ++seq; const job = {id, at: time + delay, fn}; jobs.set(id, job); allJobs.push(job); return id; },
        CancelScheduled(id) { jobs.delete(id); }
    };
    vm.runInNewContext(source, {$, GameUI: {CustomUIConfig: () => config}}, {filename: 'reward_feedback.js'});
    function advance(seconds) {
        const until = time + seconds;
        for (;;) {
            const due = [...jobs.values()].filter(j => j.at <= until).sort((a, b) => a.at - b.at)[0];
            if (!due) break;
            jobs.delete(due.id); time = due.at; due.fn();
        }
        time = until;
    }
    const owner = new Panel('Panel', null, 'Canvas');
    return {config, owner, Panel, jobs, allJobs, particles, panels, advance,
        maximumActive: () => maximumActive,
        failLoad: value => { failLoad = value; }, failStart: value => { failStart = value; }};
}

const h = harness(), fx = h.config.SurvivalUI.RewardFX.Create(h.owner, {channel: 'daily'});
assert.equal(h.particles.length, 0, 'Creating an owner never creates a hidden idle particle scene');
assert.equal(h.jobs.size, 0);
assert.equal(fx.Play({key: 'one', title: '领取成功', text: '木材 +100'}), true);
const first = h.particles[0], firstHost = first.parent;
assert.equal(h.jobs.size, 1);
assert.equal(firstHost.hittest, false); assert.equal(firstHost.hittestchildren, false);
assert.equal(firstHost.visible, false); assert.equal(first.starts, 0);
assert.equal(fx.Play({key: 'one'}), false, 'Queued responses also deduplicate before the first layout turn');
h.advance(0);
const oldCallback = h.allJobs.at(-1).fn;
assert.equal(firstHost.style.position, '490px 374px 0px', 'Missing anchors center the compact burst');
assert.equal(firstHost.FindChildTraverse('RewardFXDetail').text, '木材 +100');
assert.equal(fx.Play({key: 'one'}), false, 'Duplicate response never replays or replaces the current reward');
assert.equal(first.starts, 1);
assert.equal(fx.Play({key: 'two', text: ''}), true);
assert.equal(firstHost.visible, false); assert.equal(first.playing, false);
h.advance(0);
assert.equal(h.particles.length, 1, 'Rapid successive rewards reuse one native scene');
assert.equal(h.maximumActive(), 1);
assert.equal(first.starts, 2); assert(first.stops > 0);
assert.equal(h.jobs.size, 1);
assert.equal(firstHost.FindChildTraverse('RewardFXDetail').visible, false);
oldCallback();
assert.equal(first.playing, true, 'A canceled old callback cannot delete the replacement reward');
h.advance(1.6);
assert.equal(h.jobs.size, 0); assert.equal(first.playing, false); assert.equal(first.IsValid(), false);
assert.equal(fx.Play({key: 'two'}), false, 'Completed responses remain deduplicated');
assert.equal(fx.Play({key: 'three'}), true);
h.advance(0);
fx.Clear();
assert.equal(h.jobs.size, 0); assert.equal(h.particles.at(-1).playing, false);
assert.equal(fx.Play({key: 'three'}), false, 'Closing does not reset response history');
assert.equal(fx.Play({key: '__proto__'}), true, 'Response keys cannot poison deduplication');
h.advance(0);
for (let i = 0; i < 65; i++) { assert.equal(fx.Play({key: 'bounded-' + i}), true); h.advance(0); }
assert.equal(fx.Play({key: 'one'}), true, 'History has a fixed 64 response bound');
fx.Dispose(); fx.Dispose();
assert.equal(h.jobs.size, 0); assert.equal(fx.Play({key: 'after-dispose'}), false);
assert.equal(h.maximumActive(), 1);

for (const explicit of [false, true]) {
    const g = harness(), outer = new g.Panel('Panel', null, 'Fit');
    outer.style.transform = 'scale3d(0.6,0.6,1)';
    g.owner.parent = outer; outer.children.push(g.owner);
    g.owner.actualuiscale_x = g.owner.actualuiscale_y = 0.8;
    g.owner.actuallayoutwidth = 960; g.owner.actuallayoutheight = 720;
    g.owner.position = {x: 100, y: 50};
    const anchor = new g.Panel('Panel', g.owner, 'RewardCard');
    anchor.position = {x: 400, y: 230};
    anchor.actuallayoutwidth = 80; anchor.actuallayoutheight = 60;
    const f = g.config.SurvivalUI.RewardFX.Create(g.owner, explicit ? {getScale: () => 0.6} : {});
    assert(f.Play({key: 'scaled', anchor}));
    g.advance(0);
    assert.equal(g.particles[0].parent.style.position, '565px 337px 0px', 'Fit 0.6 plus UI scale 0.8 converts once');
    f.Clear();
    assert.equal(g.jobs.size, 0);
    anchor.valid = false;
    assert(f.Play({key: 'fallback', anchor}));
    g.advance(0);
    assert.equal(g.particles.at(-1).parent.style.position, '490px 374px 0px');
    g.owner.valid = false;
    assert.equal(f.Play({key: 'invalid-root'}), false);
    assert.equal(g.jobs.size, 0, 'Invalid roots cancel pending cleanup without touching stale panels');
    f.Dispose();
}
const bad = harness(), failing = bad.config.SurvivalUI.RewardFX.Create(bad.owner);
bad.failLoad(true);
assert.equal(failing.Play({key: 'retry'}), false); assert.equal(bad.jobs.size, 0);
bad.failLoad(false); bad.failStart(true);
assert.equal(failing.Play({key: 'retry'}), true); bad.advance(0); assert.equal(bad.jobs.size, 0);
bad.failStart(false);
assert.equal(failing.Play({key: 'retry'}), true, 'Failed scene startup does not consume response keys');
bad.advance(0);
failing.Dispose(); assert.equal(bad.jobs.size, 0);

const fresh = harness(), waiting = fresh.config.SurvivalUI.RewardFX.Create(fresh.owner);
const newCard = new fresh.Panel('Panel', fresh.owner, 'JustRenderedReward');
newCard.actuallayoutwidth = newCard.actuallayoutheight = 0;
assert(waiting.Play({key: 'fresh-anchor', anchor: newCard}));
const waitingScene = fresh.particles[0];
assert.equal(waitingScene.starts, 0); assert.equal(waitingScene.parent.visible, false);
newCard.position = {x: 300, y: 200};
newCard.actuallayoutwidth = newCard.actuallayoutheight = 84;
fresh.advance(0);
assert.equal(waitingScene.parent.style.position, '232px 166px 0px', 'The first visible frame uses the newly laid out card, not the canvas center');
assert.equal(waitingScene.starts, 1); assert.equal(fresh.jobs.size, 1);
waiting.Clear();
assert(waiting.Play({key: 'close-before-start', anchor: newCard}));
const canceledScene = fresh.particles.at(-1), canceledStart = fresh.allJobs.at(-1).fn;
waiting.Clear(); canceledStart(); fresh.advance(10);
assert.equal(canceledScene.starts, 0); assert.equal(fresh.jobs.size, 0, 'Closing before layout cancels the pending start and cannot resurrect it');
assert(waiting.Play({key: 'root-deleted-before-start', anchor: newCard}));
fresh.owner.valid = false; fresh.advance(0);
assert.equal(fresh.jobs.size, 0); assert.equal(fresh.particles.at(-1).starts, 0);
waiting.Dispose();
console.log('REWARD_FEEDBACK_PASS: native XML, one active scene, finite cleanup, dedup, replay, disposal, deferred fresh anchors, scaled anchors and failure recovery');
