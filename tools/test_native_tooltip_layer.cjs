'use strict';
// Exercise the actual shared positioner against native-style sibling stacking.
// A tooltip's own z-index cannot overtake a higher ancestor of the lower HUD.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const rootDirectory = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.resolve(rootDirectory,
    process.argv[2] || 'panorama/src/scripts/custom_game/tooltip_position.js'), 'utf8');

function fixture(options = {}) {
    const config = {}, calls = [], writes = [], panels = [], schedules = [];
    let serial = 0, parentWrites = 0, inputWrites = 0;
    class Panel {
        constructor(id, parent = null, type = 'Panel', z = '') {
            this.id = id; this.paneltype = type; this.parent = parent;
            this.children = []; this.alive = true;
            this.actualuiscale_x = this.actualuiscale_y = 1;
            this.actuallayoutwidth = 1920; this.actuallayoutheight = 1080;
            let hit = true, childrenHit = true;
            Object.defineProperty(this, 'hittest', {get: () => hit,
                set: value => { inputWrites++; hit = value; }});
            Object.defineProperty(this, 'hittestchildren', {get: () => childrenHit,
                set: value => { inputWrites++; childrenHit = value; }});
            this.style = new Proxy({zIndex: z}, {set: (target, key, value) => {
                writes.push({panel: this, key, value: String(value)});
                target[key] = String(value); return true;
            }});
            if (parent) parent.children.push(this);
            panels.push(this);
        }
        IsValid() { return this.alive; }
        GetParent() { return this.parent; }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
        Children() { return this.children.slice(); }
        GetPositionWithinWindow() { return {x: 400, y: 700}; }
        FindChildTraverse(id) {
            for (const child of this.children) {
                if (!child.alive) continue;
                if (child.id === id) return child;
                const match = child.FindChildTraverse(id); if (match) return match;
            }
            return null;
        }
        SetParent() { parentWrites++; throw Error('Native panels must not be reparented'); }
    }
    const root = new Panel('Root'), hud = new Panel('Hud', root, 'DOTAHud', '10');
    const lower = new Panel('lower_hud', root, 'Panel', '100000');
    const health = new Panel('health_mana', lower, 'Panel', '99');
    const context = new Panel('SurvivalHUD', root), owner = new Panel('AttackSpeed', context);
    const otherOwner = new Panel('Armor', context);
    let nativeHost = null;
    function createNativeHost(id = 'Tooltips', parent = hud, type = 'Panel') {
        nativeHost = new Panel(id, parent, type, '12');
        new Panel(options.textId === undefined ? 'TextTooltip' : options.textId,
            nativeHost, 'Panel', '3');
        return nativeHost;
    }
    if (!options.lazy) createNativeHost(options.hostId, options.hostParent === 'root' ? root : hud,
        options.hostType || 'Panel');
    const environment = {
        GameUI: {CustomUIConfig: () => config},
        $: {
            GetContextPanel: () => context,
            DispatchEvent(...args) {
                if (args[0] === 'DOTAHideTitleTextTooltip')
                    assert(args[1] && args[1].IsValid(), 'Do not dispatch a deleted native panel handle');
                calls.push(args);
            },
            Schedule(seconds, callback) { const job = {id: ++serial, seconds, callback}; schedules.push(job); return job.id; },
            CancelScheduled(id) { const job = schedules.find(item => item.id === id); if (job) job.cancelled = true; }
        }
    };
    vm.runInNewContext(source, environment, {filename: 'tooltip_position.js'});
    const api = config.SurvivalTooltipPosition;
    assert.equal(typeof api.ShowText, 'function', 'Shared positioner exposes native text display');
    assert.equal(typeof api.HideText, 'function', 'Shared positioner exposes owned native text dismissal');
    assert.equal(typeof api.ShowTitleText, 'function', 'Shared positioner exposes native title/body display');
    assert.equal(typeof api.HideTitleText, 'function', 'Shared positioner exposes owned native title/body dismissal');
    return {
        api, root, hud, lower, health, context, owner, otherOwner, panels, calls, writes, schedules,
        get host() { return nativeHost; }, createNativeHost,
        flush() { const jobs = schedules.splice(0); jobs.forEach(job => { if (!job.cancelled) job.callback(); }); },
        reload() { vm.runInNewContext(source, environment, {filename: 'tooltip_position.js'}); return config.SurvivalTooltipPosition; },
        panel(id, parent, z = '') { return new Panel(id, parent, 'Panel', z); },
        loadLayers() {
            vm.runInNewContext(fs.readFileSync(path.join(rootDirectory,
                'panorama/src/scripts/custom_game/ui_layers.js'), 'utf8'), environment,
                {filename: 'ui_layers.js'});
            return config.SurvivalUILayers;
        },
        assertUntouched() { assert.equal(parentWrites, 0); assert.equal(inputWrites, 0); }
    };
}

function assertNativeFront(f, host = f.host) {
    assert(Number(f.hud.style.zIndex) > Number(f.lower.style.zIndex),
        'Native tooltip ancestor must overtake the sibling abilities/health HUD');
    for (let panel = host; panel && panel !== f.root; panel = panel.GetParent())
        assert(Number(panel.style.zIndex) > 100000, panel.id + ' is raised along the full native path');
    assert.equal(f.root.style.zIndex, '', 'The global root is never restyled');
    assert.equal(f.lower.style.zIndex, '100000');
    assert.equal(f.health.style.zIndex, '99');
}

// Native anchor, formatted content and native placement are preserved.
{
    const f = fixture(), content = '当前攻速：10.0 刀/秒<br>攻击倍率：1428.57%';
    f.api.ShowText(f.owner, content);
    assert.deepEqual(f.calls.at(-1), ['DOTAShowTextTooltip', f.owner, content]);
    assertNativeFront(f);
    f.flush();
    const written = f.writes.length;
    f.api.ShowText(f.owner, content);
    f.flush();
    assert.equal(f.writes.length, written, 'Repeated hover does not rewrite unchanged native layers');
    assert(!f.writes.some(write => write.key === 'position'), 'The engine retains native text placement');
    f.api.HideText(f.owner);
    assert.equal(f.calls.at(-1)[0], 'DOTAHideTextTooltip');
    assert.equal(f.hud.style.zIndex, '10');
    assert.equal(f.host.style.zIndex, '12');
    f.assertUntouched();
}

// Engine tooltip creation is lazy: allow one guarded next-frame discovery.
{
    const f = fixture({lazy: true});
    f.api.ShowText(f.owner, 'lazy');
    assert.equal(f.schedules.length, 1, 'One bounded discovery callback, no polling loop');
    f.createNativeHost(); f.flush(); assertNativeFront(f);
    assert.equal(f.schedules.length, 0, 'Discovery does not schedule recurring work');
    f.api.HideText(f.owner); f.assertUntouched();
}
{
    const f = fixture({lazy: true});
    f.api.ShowText(f.owner, 'dismiss before native creation');
    f.api.HideText(f.owner);
    f.createNativeHost(); f.flush();
    assert.equal(f.hud.style.zIndex, '10'); assert.equal(f.host.style.zIndex, '12');
    f.assertUntouched();
}

// Refresh the native subtree between two hovers; no stale host cache survives.
{
    const f = fixture();
    f.api.ShowText(f.owner, 'first'); f.flush(); f.api.HideText(f.owner);
    const original = f.host; original.alive = false;
    const replacement = f.createNativeHost();
    f.api.ShowText(f.owner, 'replacement'); f.flush(); assertNativeFront(f, replacement);
    f.api.HideText(f.owner); assert.equal(replacement.style.zIndex, '12');
    f.assertUntouched();
}

// A later modal lease remains authoritative after this hover relinquishes its lease.
{
    const f = fixture();
    f.api.ShowText(f.owner, 'modal race'); f.flush();
    f.hud.style.zIndex = '100002';
    f.api.HideText(f.owner);
    assert.equal(f.hud.style.zIndex, '100002', 'Do not restore over another layer owner');
    assert.equal(f.host.style.zIndex, '12'); f.assertUntouched();
}

// Delayed mouseout from A cannot dismiss the replacement tooltip owned by B.
{
    const f = fixture();
    f.api.ShowText(f.owner, 'A');
    f.api.ShowText(f.otherOwner, 'B');
    const shown = f.calls.length;
    f.api.HideText(f.owner);
    assert.equal(f.calls.length, shown, 'Stale owner does not dispatch a global hide');
    f.flush(); assertNativeFront(f);
    f.api.HideText(f.otherOwner);
    assert.equal(f.calls.at(-1)[0], 'DOTAHideTextTooltip');
    assert.equal(f.hud.style.zIndex, '10'); f.assertUntouched();
}

// The minimal original engine layout uses TextTooltip without a named manager.
{
    const f = fixture({hostId: 'TextTooltip'});
    f.api.ShowText(f.owner, 'old native layout'); f.flush(); assertNativeFront(f);
    f.api.HideText(f.owner); f.assertUntouched();
}

// Anonymous native manager instances are discoverable by their native panel type.
{
    const f = fixture({hostId: '', hostType: 'DOTATextTooltip', textId: 'AnonymousContent'});
    f.api.ShowText(f.owner, 'anonymous native layout'); f.flush(); assertNativeFront(f);
    f.api.HideText(f.owner); f.assertUntouched();
}

// A layout/script refresh disposes the old lease and invalidates its lazy callback.
{
    const f = fixture();
    f.api.ShowText(f.owner, 'layout refresh');
    const fresh = f.reload(); f.flush();
    assert.notEqual(fresh, f.api);
    assert.equal(f.hud.style.zIndex, '10'); assert.equal(f.host.style.zIndex, '12');
    fresh.ShowText(f.owner, 'new layout'); f.flush(); assertNativeFront(f);
    fresh.HideText(f.owner); f.assertUntouched();
}

// Native tooltip and modal have a common HUD ancestor. Modal save/restore must
// never retain the temporary tooltip priority as its permanent saved baseline.
for (const hideBeforeClose of [true, false]) {
    const f = fixture(), layers = f.loadLayers(), modal = f.panel('ArchiveWindow', f.hud, '21');
    f.api.ShowText(f.owner, 'tooltip plus modal'); f.flush(); assertNativeFront(f);
    layers.Open('archive', modal, () => layers.Close('archive'));
    assert.equal(layers.Top(), 'archive');
    assert(Number(f.host.style.zIndex) > Number(modal.style.zIndex),
        'Visible native tooltip stays above an open modal');
    if (hideBeforeClose) f.api.HideText(f.owner);
    layers.Close('archive');
    assert.equal(layers.Top(), null);
    if (!hideBeforeClose) {
        assert(Number(f.host.style.zIndex) > Number(f.lower.style.zIndex),
            'Closing the modal preserves an active tooltip lease');
        f.api.HideText(f.owner);
    }
    assert.equal(f.hud.style.zIndex, '10',
        (hideBeforeClose ? 'Open → hide → close' : 'Open → close → hide') + ' restores real shared HUD baseline');
    assert.equal(f.host.style.zIndex, '12');
    assert.equal(modal.style.zIndex, '21');
    assert.equal(f.lower.style.zIndex, '100000');
    f.assertUntouched();
}

// Ticket acquisition help uses the official title/body widget and the same
// native ancestor lease as ordinary text, with no custom placement or styling.
{
    const f = fixture(), title = '普通抽奖券 · 获取渠道', body = '每日福利。<br>每周福利。';
    f.api.ShowTitleText(f.owner, title, body);
    assert.deepEqual(f.calls.at(-1), ['DOTAShowTitleTextTooltip', f.owner, title, body]);
    assert.equal(f.api.InspectTextLayer().source, f.owner.id);
    assertNativeFront(f); f.flush();
    const writes = f.writes.length;
    f.api.ShowTitleText(f.owner, title, body); f.flush();
    assert.equal(f.writes.length, writes, 'same-source title refresh does not churn the native lease');
    assert(!f.writes.some(write => write.key !== 'zIndex'), 'native title layout and art stay engine-owned');
    f.api.HideTitleText(f.owner);
    assert.deepEqual(f.calls.at(-1), ['DOTAHideTitleTextTooltip', f.owner]);
    assert.equal(f.hud.style.zIndex, '10'); assert.equal(f.host.style.zIndex, '12');
    assert.equal(f.api.InspectTextLayer().raised, 0); f.assertUntouched();
}

// Native text/title are distinct show/hide event types but share one owner.
// A delayed leave from an older source or widget type must not dismiss the new one.
{
    const f = fixture();
    f.api.ShowTitleText(f.owner, 'A', 'body A');
    let start = f.calls.length;
    f.api.ShowText(f.otherOwner, 'B');
    assert.deepEqual(f.calls.slice(start), [
        ['DOTAHideTitleTextTooltip', f.owner], ['DOTAShowTextTooltip', f.otherOwner, 'B']
    ], 'switching to text retires the previous native title widget');
    let shown = f.calls.length;
    f.api.HideTitleText(f.owner); f.api.HideTitleText(f.otherOwner);
    assert.equal(f.calls.length, shown, 'neither stale source nor wrong type dispatches a global hide');
    f.flush(); assertNativeFront(f); assert.equal(f.api.InspectTextLayer().source, f.otherOwner.id);

    start = f.calls.length;
    f.api.ShowTitleText(f.otherOwner, 'C', 'body C');
    assert.deepEqual(f.calls.slice(start), [
        ['DOTAHideTextTooltip'], ['DOTAShowTitleTextTooltip', f.otherOwner, 'C', 'body C']
    ], 'same-source type changes retire the old widget before showing its replacement');
    shown = f.calls.length; f.api.HideText(f.otherOwner); f.api.HideText(f.owner);
    assert.equal(f.calls.length, shown, 'old text mouseout cannot dismiss a new title at the same anchor');
    f.flush(); assertNativeFront(f); f.api.HideTitleText(f.otherOwner);
    assert.equal(f.hud.style.zIndex, '10'); assert.equal(f.host.style.zIndex, '12'); f.assertUntouched();
}

// Engine-created title tooltips may appear only on the next layout frame.
{
    const f = fixture({lazy: true});
    f.api.ShowTitleText(f.owner, 'lazy title', 'body');
    assert.equal(f.schedules.length, 1, 'title discovery is bounded to one frame');
    f.createNativeHost(); f.flush(); assertNativeFront(f);
    assert.equal(f.schedules.length, 0); f.api.HideTitleText(f.owner); f.assertUntouched();
}
{
    const f = fixture({lazy: true});
    f.api.ShowTitleText(f.owner, 'closed title', 'body'); f.api.HideTitleText(f.owner);
    f.createNativeHost(); f.flush();
    assert.equal(f.hud.style.zIndex, '10'); assert.equal(f.host.style.zIndex, '12'); f.assertUntouched();
}

// Closing a renderer can invalidate its anchor before the hide reaches the
// helper. Ownership release must not depend on the anchor remaining valid.
{
    const f = fixture(); f.api.ShowTitleText(f.owner, 'retired source', 'body'); assertNativeFront(f);
    f.owner.alive = false; f.api.HideTitleText(f.owner); f.flush();
    assert.equal(f.api.InspectTextLayer().source, ''); assert.equal(f.api.InspectTextLayer().raised, 0);
    assert.equal(f.hud.style.zIndex, '10'); assert.equal(f.host.style.zIndex, '12'); f.assertUntouched();
}

// Modal apply suspends/reinstates both native tooltip kinds, and snapshots only
// the underlying modal baseline so neither closure order leaves a raised HUD.
for (const hideBeforeClose of [true, false]) {
    const f = fixture(), layers = f.loadLayers(), modal = f.panel('LotteryWindow', f.hud, '21');
    f.api.ShowTitleText(f.owner, '券来源', '福利奖励'); f.flush();
    const dispatches = f.calls.length; layers.Open('lottery', modal, () => layers.Close('lottery'));
    assert.equal(f.calls.length, dispatches, 'modal suspend/resume does not redispatch native content');
    assert(Number(f.host.style.zIndex) > Number(modal.style.zIndex));
    assert.equal(f.api.InspectTextLayer().source, f.owner.id);
    if (hideBeforeClose) f.api.HideTitleText(f.owner);
    layers.Close('lottery');
    if (!hideBeforeClose) {
        assert(Number(f.host.style.zIndex) > Number(f.lower.style.zIndex));
        assert(Number(f.hud.style.zIndex) > Number(f.lower.style.zIndex));
        f.api.HideTitleText(f.owner);
    }
    assert.equal(f.hud.style.zIndex, '10'); assert.equal(f.host.style.zIndex, '12');
    assert.equal(modal.style.zIndex, '21'); f.assertUntouched();
}

// Reload invalidates a title tooltip's guarded next-frame discovery callback.
{
    const f = fixture({lazy: true}); f.api.ShowTitleText(f.owner, 'old layout', 'body');
    const fresh = f.reload(); f.createNativeHost(); f.flush();
    assert.notEqual(fresh, f.api); assert.equal(fresh.InspectTextLayer().source, '');
    assert.equal(f.hud.style.zIndex, '10'); assert.equal(f.host.style.zIndex, '12');
    fresh.ShowTitleText(f.otherOwner, 'new layout', 'new body'); f.flush(); assertNativeFront(f);
    fresh.HideTitleText(f.otherOwner); f.assertUntouched();
}

console.log('NATIVE_TOOLTIP_LAYER_PASS: text/title native events, full ancestor lease, preserved native art/placement, source/type ownership, one-frame lazy host, invalid anchor release, subtree replacement, modal suspend/resume and reload without input/reparent changes');
