'use strict';

// Run the actual commerce renderer and shared dismissal policy. This models
// native UI scale separately from a menu's CSS Fit transform; no game runs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {harness} = require('./helpers/commerce_tooltip_harness.cjs');

test('Commerce hover is synchronous and informational with one active cancellable layout follow-up', () => {
    const h = harness(), item = h.bind();
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0, 'hidden cards do not register idle owners');
    const start = h.scheduled.length;
    h.hover(item);
    assert(item.tip.BHasClass('Visible'), 'onmouseover shows before the next frame');
    assert.equal(h.scheduled.slice(start).filter(value => value.delay === 0).length, 1);
    assert(h.scheduled.slice(start).every(value => value.delay === 0 || value.delay === .03),
        'only one layout task and the shared policy watcher may be scheduled');
    const labels = h.descendants(item.tip).filter(node => node.paneltype === 'Label');
    assert.equal(labels.length, 3);
    assert(labels[0].BHasClass('RCPurpleDetailTitle'));
    assert(labels[1].BHasClass('RCPurpleDetailQuality'));
    assert(labels[2].BHasClass('RCProductEffect'));
    assert.equal(labels[0].text, '样例商品');
    assert.equal(labels[1].text, '');assert.equal(labels[1].visible,false,'missing grade is hidden from players');
    assert.equal(labels[2].text, '攻击力 +10');
    assert(!h.descendants(item.tip).some(node => node.paneltype === 'Image' || node.paneltype === 'Button'),
        'the tooltip contains no icon, price control, purchase button, or bundle interaction');
    assert.equal(item.tip.hittest, false); assert.equal(item.tip.hittestchildren, false);
    assert.equal(item.surface.hittest, false); assert.equal(item.surface.hittestchildren, false);
    const staleLayout = h.scheduled.slice(start).find(value => value.delay === 0).fn;
    item.card.events.onmouseout();
    assert(!item.tip.BHasClass('Visible'), 'source leave hides synchronously');
    assert.equal([...h.jobs.values()].filter(value => value.delay === 0).length, 0);
    staleLayout(); h.advance(.5);
    assert(!item.tip.BHasClass('Visible'), 'a captured layout callback cannot revive a hidden tooltip');
    assert.equal(h.checkoutCount(), 0); assert.equal(h.requests.length, 0);
    h.dispose(item);
    staleLayout();
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
    assert.equal(h.jobs.size, 0);
});

test('Entering a scaled tooltip dismisses continuous hover and rearms on a fresh source entry', () => {
    const h = harness({nativeScale: .75, fitScale: .5}), first = h.bind(), second = h.bind({}, {y: 400});
    h.hover(first); h.advance(0);
    const tipBounds = first.surface.GetPositionWithinWindow();
    h.setCursor([tipBounds.x + first.surface.actuallayoutwidth * h.fitScale + 8, tipBounds.y + 8]);
    h.advance(.031);
    assert(first.tip.BHasClass('Visible'), 'the unscaled layout envelope must not falsely count as tooltip pixels');
    h.setCursor([tipBounds.x + first.surface.actuallayoutwidth * h.fitScale - 2, tipBounds.y + 8]);
    h.advance(.031);
    assert(!first.tip.BHasClass('Visible'), 'passive geometry uses the CSS Fit-scaled surface');
    first.card.events.onmouseover(); second.card.events.onmouseover(); h.advance(.2);
    assert(!first.tip.BHasClass('Visible')); assert(!second.tip.BHasClass('Visible'));
    h.inside(first.card); first.card.events.onmouseover();
    assert(first.tip.BHasClass('Visible'), 'Returning after leaving the source rearms without exiting the old tooltip footprint');
    const source = first.card.GetPositionWithinWindow();
    const sourceRight = source.x + first.card.actuallayoutwidth * h.fitScale;
    assert(sourceRight < tipBounds.x, 'fixture leaves a physical gap between source and tooltip');
    h.setCursor([(sourceRight + tipBounds.x) / 2, source.y + 8]); h.advance(.04);
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().blocked, false);
    h.hover(first); assert(first.tip.BHasClass('Visible'));
    first.tip.events.onmouseover();
    assert(!first.tip.BHasClass('Visible'), 'tooltip input events use the same immediate dismissal');
    first.card.events.onmouseover(); h.advance(0);
    assert(!first.tip.BHasClass('Visible'));
    h.setCursor([1900, 1000]); h.advance(.04); h.hover(first);
    first.surface.events.onmouseover();
    assert(!first.tip.BHasClass('Visible'), 'the shared surface handler also dismisses immediately');
    h.dispose(first, second);
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0); assert.equal(h.jobs.size, 0);
});

test('Switching cards leaves one tooltip and preserves the independent market purchase action', () => {
    const h = harness(), first = h.bind(), second = h.bind({}, {y: 400});
    h.hover(first);
    const staleLayout = h.scheduled.find(value => value.delay === 0).fn;
    h.hover(second);
    assert(!first.tip.BHasClass('Visible')); assert(second.tip.BHasClass('Visible'));
    assert.equal([...h.jobs.values()].filter(value => value.delay === 0).length, 1);
    staleLayout(); h.advance(0);
    assert(!first.tip.BHasClass('Visible')); assert(second.tip.BHasClass('Visible'));
    second.card.events.onactivate();
    assert.equal(h.checkoutCount(), 0, 'market row inspection never checks out');
    assert.strictEqual(second.buy.events.onactivate, second.purchase, 'binding info does not replace the row purchase callback');
    second.buy.events.onactivate(); assert.equal(h.checkoutCount(), 1);
    second.card.events.onmouseout(); assert(!second.tip.BHasClass('Visible'), 'clicking does not pin');
    h.dispose(first, second);
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0); assert.equal(h.requests.length, 0);
});

test('Quality uses authoritative identity and rejects a shared placeholder or mixed bundle inference', () => {
    const h = harness();
    const id = 'lottery_heaven_reaching_tower_seal';
    assert.equal(h.cfg.SurvivalItemArt.Lookup({item_id: id}).quality.toLowerCase(), 'ur', 'the real catalog maps 通天塔印 to UR');
    const cases = [
        [{quality: 'ssr'}, [], 'SSR'],
        [{item_id: id}, [], 'UR'],
        [{}, [{kind: 'item', id}], 'UR'],
        [{title: '通天塔印 · 永久', icon: 'custom_game/archive_items_v2/' + id + '.png'}, [], ''],
        [{title: '无关科技', icon: 'custom_game/archive_items_v2/lottery_attribute_crystal.png'}, [], ''],
        [{title: '名字不一致', icon: 'custom_game/archive_items_v2/' + id + '.png'}, [], ''],
        [{quality: 'legendary'}, [], ''],
        [{product_type: 'bundle'}, [{kind: 'item', id}], ''],
        [{product_type: 'bundle', quality: 'ur'}, [{kind: 'item', id}], 'UR']
    ];
    for (const [item, rewards, expected] of cases) {
        const entry = h.bind(item, {rewards});
        const grade=h.find(entry.tip, 'RCPurpleDetailQuality');
        assert.equal(grade.text, expected?'品级：'+expected:'');assert.equal(grade.visible,!!expected);
        h.dispose(entry);
    }
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
});

test('Bundles show plain text effects and the compact fallback keeps its existing card action', () => {
    const h = harness(), rewards = [{kind: 'item', id: 'a', label: '道具甲', description: '攻击力 +20'},
        {kind: 'item', id: 'b', label: '道具乙', quantity: 3}];
    const bundle = h.bind({product_type: 'bundle', bundle_reviewed: true}, {rewards});
    const effect = h.find(bundle.tip, 'RCProductEffect');
    assert.equal(effect.text, '道具甲\n攻击力 +20\n\n道具乙 ×3');
    assert.equal(h.descendants(bundle.tip).filter(node => node.paneltype === 'Label').length, 3);
    assert(!h.descendants(bundle.tip).some(node => node.events.onactivate), 'bundle contents have no nested interaction');
    h.hover(bundle); assert.equal(h.checkoutCount(), 0);
    h.dispose(bundle);
    h.setCursor([1900, 1000]); h.advance(.04);
    const fallback = h.bind({}, {market: false});
    h.hover(fallback); assert.equal(h.checkoutCount(), 0, 'hover is informational on the fallback path too');
    fallback.card.events.onactivate(); assert.equal(h.checkoutCount(), 1);
    h.dispose(fallback); assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
    assert.equal(h.requests.length, 0);
});

const starterRewards = [
    {id:'video_p028', label:'熟练工头·永久（功能版）', description:'伐木效率+2\n每秒木材+3\n不包含农民皮肤'},
    {id:'video_p020', label:'地精油锯·永久', description:'开局木材+300\n每局清场一次'},
    {id:'video_p018', label:'时间科技·永久', description:'科技返还8%的费用\n立即完成科技升级'},
    {id:'video_p032', label:'快速建造·永久', description:'箭塔攻击+1000\n能立即完成建筑建造和升级'},
];
function starter(h) {
    return h.bind({sku:'video_bundle_b003',title:'新手礼包',product_type:'bundle',
        description:'本项目功能版：不包含农民皮肤。\n限购1次，与单品共用持有记录。\n后续完整商品描述'}, {rewards:starterRewards});
}

test('Starter pack keeps four text selectors visible and defaults to complete instant-build effects', () => {
    const h=harness(),entry=starter(h),members=h.descendants(entry.tip).filter(p=>p.BHasClass('BLMarketBundleMember'));
    assert.equal(members.length,4);
    assert.deepEqual(members.map(p=>p.Children()[0].text),starterRewards.map(r=>r.label));
    assert(!h.descendants(entry.tip).some(p=>p.paneltype==='Image'),'the inspector adds no new icons');
    assert.equal(h.find(entry.tip,'RCBundleMemberEffect').text,starterRewards[3].description);
    assert(members[3].BHasClass('UISelected'));
    const buyCallback=entry.buy.events.onactivate;
    h.hover(entry);h.advance(0);
    assert(entry.tip.hittestchildren&&entry.surface.hittestchildren,'member selection must be reachable');
    for(let index=0;index<4;index++){
        members[index].events.onmouseover();h.advance(0);
        assert.equal(h.find(entry.tip,'RCBundleMemberEffect').text,starterRewards[index].description);
        assert.equal(members.filter(p=>p.BHasClass('UISelected')).length,1);
        members[index].events.onactivate();
    }
    assert.equal(h.checkoutCount(),0);assert.equal(h.requests.length,0);
    assert.strictEqual(entry.buy.events.onactivate,buyCallback,'member inspection preserves purchase handling');
    h.dispose(entry);assert.equal(h.jobs.size,0);
});

test('Starter inspector survives the pointer gap and surface entry, then closes after leaving both regions', () => {
    const h=harness({nativeScale:.75,fitScale:.5}),entry=starter(h);
    h.hover(entry);h.advance(0);
    entry.card.events.onmouseout();
    h.inside(entry.surface);entry.surface.events.onmouseover();h.advance(.2);
    assert(entry.tip.BHasClass('Visible'),'entering the interactive surface must preserve the inspector');
    entry.tip.events.onmouseout();h.setCursor([1900,1000]);h.advance(.121);
    assert(!entry.tip.BHasClass('Visible'),'leaving the source and inspector closes it');
    assert.equal(h.jobs.size,0,'no idle polling remains after close');
    h.hover(entry);h.advance(0);entry.card.events.onmouseout();
    const staleLeave=h.scheduled.at(-1).fn;
    h.dispose(entry);staleLeave();assert.equal(h.jobs.size,0,'disposed rows cancel delayed close safely');
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners,0);
});

test('Changing rows cancels starter layout and leave jobs without altering passive tooltip policy', () => {
    const h=harness(),bundle=starter(h),ordinary=h.bind({}, {y:400});
    h.hover(bundle);h.advance(0);bundle.card.events.onmouseout();
    h.hover(ordinary);h.advance(.2);
    assert(!bundle.tip.BHasClass('Visible')&&ordinary.tip.BHasClass('Visible'));
    h.inside(ordinary.surface);ordinary.surface.events.onmouseover();
    assert(!ordinary.tip.BHasClass('Visible'),'existing single-product tooltips remain informational');
    assert.equal(h.checkoutCount(),0);assert.equal(h.requests.length,0);
    h.dispose(bundle,ordinary);assert.equal(h.jobs.size,0);
});

const bundles = JSON.parse(fs.readFileSync(path.resolve(__dirname,
    '../../data/ui/video_shop_bundles_20261015.json'), 'utf8')).products;
function actualBundle(h, sku = 'video_bundle_b001') {
    const item = bundles.find(row => row.sku === sku);
    assert(item, 'The regression uses an actual authored bundle');
    return h.bind(item, {rewards: item.reward_lines, y: 650});
}
function assertCompleteScrollable(h, entry) {
    const body = h.find(entry.tip, 'MenuV10CommerceDetailBody');
    const content = h.find(entry.tip, 'MenuV10CommerceDetailContent');
    const effect = h.find(entry.tip, 'RCProductEffect');
    assert.equal(body.Children().length, 1);
    assert.strictEqual(body.Children()[0], content);
    assert.equal(h.computed(content).flowChildren, 'down');
    assert.equal(h.logicalHeight(effect), h.logicalHeight(effect, true),
        'The complete effect text must retain its natural height, including its final line');
    const scrolls = h.descendants(entry.tip).filter(node => /\bscroll\b/.test(h.computed(node).overflow || ''));
    assert.deepEqual(scrolls, [body], 'Only the whole-body viewport scrolls; no inner Label may clip its text');
    assert(h.logicalHeight(content) > h.logicalHeight(body), 'The actual long description exceeds the viewport');
    assert(entry.tip.BHasClass('Scrollable'));
    assert(entry.tip.hittest && body.hittest && entry.surface.hittest, 'The scrollbar must be reachable');
    body.ScrollToBottom();
    assert(body.scrollOffset > 0);
    assert.equal(body.scrollOffset + h.logicalHeight(body), h.logicalHeight(content),
        'Scrolling reaches the final content edge rather than the edge of an internally truncated label');
    return {body, content, effect};
}

test('Real long bundle descriptions retain every member and final rule behind one reachable scrollbar', () => {
    for (const sku of ['video_bundle_b001', 'video_bundle_b002', 'video_bundle_b004', 'video_bundle_b005']) {
        const h = harness({nativeScale: 1, fitScale: 1, rootHeight: 720}), entry = actualBundle(h, sku);
        h.hover(entry); h.advance(.36);
        const {effect} = assertCompleteScrollable(h, entry);
        const expected = entry.props.rewards.map(row => row.label + '\n' + row.description).join('\n\n')
            .replace(/\r\n?/g, '\n').replace(/[；;][ \t]*/g, '\n');
        assert.equal(effect.text, expected, 'Complete source text is retained verbatim after documented newline normalization');
        assert(effect.text.includes(entry.props.rewards.at(-1).label), 'The final bundle member is retained');
        if (sku === 'video_bundle_b004') assert(h.logicalHeight(effect) > 600, 'Fixture exposes the old six-hundred-pixel cap');
        h.dispose(entry); assert.equal(h.jobs.size, 0);
    }
});

test('A long product stays visible during scroll interaction and closes after leaving both source and surface', () => {
    const h = harness(), entry = actualBundle(h, 'video_bundle_b004');
    h.hover(entry); h.advance(.36);
    const {body} = assertCompleteScrollable(h, entry);
    h.setCursor([500, 500]); entry.card.events.onmouseout();
    h.inside(body); body.events.onmouseover(); h.advance(.4);
    assert(entry.tip.BHasClass('Visible'), 'Entering the scroll viewport cancels source-leave dismissal');
    body.ScrollToBottom(); h.advance(.1);
    assert(entry.tip.BHasClass('Visible'), 'Shared passive dismissal does not interrupt reading and scrolling');
    h.setCursor([1900, 1000]); body.events.onmouseout();
    h.advance(.119); assert(entry.tip.BHasClass('Visible'));
    h.advance(.002); assert(!entry.tip.BHasClass('Visible'), 'The tooltip closes after the 120ms bridge grace');
    h.dispose(entry); assert.equal(h.jobs.size, 0);
});

test('The compact non-market renderer uses the same complete-text viewport and preserves its existing action', () => {
    const h = harness({nativeScale: 1.25, fitScale: .8, rootHeight: 720});
    const text = Array.from({length: 80}, (_, index) => '第' + (index + 1) + '项属性：攻击力增加100%').join('\n');
    const entry = h.bind({title: '很长的完整效果商品'}, {market: false, effect: text, y: 650});
    h.hover(entry); h.advance(.36);
    const {body, effect} = assertCompleteScrollable(h, entry);
    assert.equal(effect.text.split('\n').at(-1), '第80项属性：攻击力增加100%');
    assert.equal(parseFloat(body.style.height), parseFloat(entry.tip.style.height) - 88,
        'The compact frame and its body padding are included in the height budget');
    h.inside(body); body.events.onmouseover(); h.advance(.1);
    assert(entry.tip.BHasClass('Visible'));
    entry.card.events.onactivate(); assert.equal(h.checkoutCount(), 1, 'Existing fallback checkout behavior is preserved');
    h.dispose(entry); assert.equal(h.jobs.size, 0);
});

test('A long starter member stays fully readable and repeated hover of the current selection does no text work', () => {
    const h = harness({nativeScale: 1.25, fitScale: 1, rootHeight: 720, layoutDelay: .08});
    const item = bundles.find(row => row.sku === 'video_bundle_b003');
    const rewards = item.reward_lines.map((reward, index) => ({...reward,
        description: reward.description + '\n' + Array.from({length: 40}, (_, line) => '成员' + index + '完整效果' + line).join('\n')}));
    const entry = h.bind(item, {rewards, y: 650}); h.hover(entry); h.advance(.36);
    const members = h.descendants(entry.tip).filter(node => node.BHasClass('BLMarketBundleMember'));
    const body = h.find(entry.tip, 'MenuV10CommerceDetailBody'), content = body.Children()[0];
    const effect = h.find(entry.tip, 'RCBundleMemberEffect');
    assert.equal(members.length, 4);
    assert(parseFloat(entry.tip.style.height) <= 600, 'The fixed starter frame may shrink to its physical screen');
    for (let index = 0; index < 4; index++) {
        h.inside(entry.surface); members[index].events.onmouseover(); h.advance(.36);
        assert.equal(effect.text, rewards[index].description.replace(/\r\n?/g, '\n').replace(/[；;][ \t]*/g, '\n'));
        assert.equal(h.logicalHeight(effect), h.logicalHeight(effect, true), 'Long member effects have no hidden 360px cap');
        assert(h.logicalHeight(content) > h.logicalHeight(body));
        body.ScrollToBottom(); assert.equal(body.scrollOffset + h.logicalHeight(body), h.logicalHeight(content));
        const before = h.counters();
        members[index].events.onmouseover(); members[index].events.onactivate(); h.advance(.36);
        assert.deepEqual(h.counters(), before, 'Hovering or activating the already inspected member must not rewrite its text');
    }
    const scrolls = h.descendants(entry.tip).filter(node => /\bscroll\b/.test(h.computed(node).overflow || ''));
    assert.deepEqual(scrolls, [body], 'Starter selectors and member explanation share the one complete-body scrollbar');
    h.dispose(entry); assert.equal(h.jobs.size, 0);
});

function fastReturn(h) {
    const entry = h.bind();
    h.hover(entry);
    h.setCursor([1900, 1000]); entry.card.events.onmouseout();
    assert(!entry.tip.BHasClass('Visible'));
    h.hover(entry); // Deliberately no geometry watcher or simulated frame.
    assert(entry.tip.BHasClass('Visible'), 'Returning after a real physical exit reopens before the next watcher tick');
    h.dispose(entry);
}
test('Fast source leave and re-entry reopen without a timer tick or idle mouse movement', () => {
    fastReturn(harness());
    const h = harness(), first = h.bind(), second = h.bind({}, {y: 400});
    h.hover(first);
    h.inside(first.surface); first.surface.events.onmouseover();
    assert(!first.tip.BHasClass('Visible'));
    h.hover(second);
    assert(second.tip.BHasClass('Visible'), 'CanShow itself observes the exit from the old blocked geometry');
    h.dispose(first, second);
});

function wholeRowSwitch(h, {switches = 50, surfaceFirst = true, verifyAvoidance = true} = {}) {
    function marketRow(y) {
        const entry = h.bind({}, {y});
        // Match the real M.Row hit region: the 48px art well anchors a popup
        // beside the icon while its source is a complete 1072px product row.
        entry.card.style.width = '1072px'; entry.card.style.height = '82px';
        entry.buy.style.position = '8px 8px 0px';
        entry.buy.style.width = '48px'; entry.buy.style.height = '48px';
        entry.props.sourcePanel = entry.buy; entry.props.sourceWidth = 48;
        return entry;
    }
    function rect(node) {
        const at = node.GetPositionWithinWindow();
        return {x: at.x, y: at.y, width: node.actuallayoutwidth * h.fitScale,
            height: node.actuallayoutheight * h.fitScale};
    }
    function contains(box, point) {
        return point[0] >= box.x && point[0] < box.x + box.width
            && point[1] >= box.y && point[1] < box.y + box.height;
    }
    function overlapPoint(a, b) {
        const left = Math.max(a.x, b.x), top = Math.max(a.y, b.y);
        const right = Math.min(a.x + a.width, b.x + b.width), bottom = Math.min(a.y + a.height, b.y + b.height);
        assert(right > left && bottom > top, 'The next product row overlaps the previous tooltip footprint');
        return [(left + right) / 2, (top + bottom) / 2];
    }
    const a = marketRow(600), b = marketRow(682), counters = h.counters();
    const trees = [h.descendants(a.tip), h.descendants(b.tip)];
    h.hover(a); let current = a, next = b;
    for (let step = 0; step < switches; step++) {
        const target = overlapPoint(rect(current.surface), rect(next.card));
        const evidence = {step, nativeScale: h.nativeScale, fitScale: h.fitScale,
            oldRow: rect(current.card), nextRow: rect(next.card), oldTooltip: rect(current.surface), cursor: target};
        assert(!contains(rect(current.card), target), 'The target has physically left the old source row');
        if (surfaceFirst && step % 3 === 2) {
            h.inside(current.surface); current.surface.events.onmouseover();
            assert(!current.tip.BHasClass('Visible'), 'Passive surface entry first creates its own dismissal lock');
        }
        h.setCursor(target); current.card.events.onmouseout(); next.card.events.onmouseover();
        assert(next.tip.BHasClass('Visible'),
            'The next native market row must display before a watcher tick: ' + JSON.stringify(evidence));
        assert(!current.tip.BHasClass('Visible'));
        if (verifyAvoidance) assert(!contains(rect(next.surface), target), 'A new tooltip must avoid its source hover entry point');
        h.advance(.4);
        assert(next.tip.BHasClass('Visible'), 'A new whole-row tooltip must survive its passive watcher after 400ms');
        if (verifyAvoidance) assert(!contains(rect(next.surface), target), 'All delayed placement passes keep the original entry point outside the surface');
        assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 1, 'Each real source exit releases its previous owner');
        assert.deepEqual(h.counters(), counters, 'Rapid switching reuses panels and complete text without rewriting either');
        for (const [entry, nodes] of [[a, trees[0]], [b, trees[1]]]) {
            assert.strictEqual(entry.card.__purpleDetail, entry.tip);
            assert(h.descendants(entry.tip).every((node, index) => node === nodes[index]), 'Every tooltip child retains its identity');
        }
        [current, next] = [next, current];
    }
    h.setCursor([1900, 1000]); current.card.events.onmouseout();
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0, 'Leaving the final row releases every dismissal owner');
    assert.equal(h.jobs.size, 0, 'No layout or pointer polling remains after leaving all rows');
    h.dispose(a, b); assert.equal(h.jobs.size, 0);
}

test('Rapid whole-row market hover survives fifty switches, delayed layout, and prior surface dismissal', () => {
    wholeRowSwitch(harness({nativeScale: .75, fitScale: .6}));
});

test('Delayed native text layout expands the viewport across native and CSS Fit scales without rebuilding text', () => {
    for (const [nativeScale, fitScale, rootHeight] of [[1, 1, 1080], [.75, .6, 720], [1.25, .8, 720], [.6, .42, 480]]) {
        const h = harness({nativeScale, fitScale, rootHeight, layoutDelay: .11}), entry = actualBundle(h, 'video_bundle_b004');
        const before = h.counters(); h.hover(entry);
        const initialHeight = parseFloat(entry.tip.style.height);
        h.advance(.16);
        const {body} = assertCompleteScrollable(h, entry);
        assert(parseFloat(entry.tip.style.height) > initialHeight, 'Later placement reads the completed native label layout');
        const at = entry.tip.GetPositionWithinWindow(), painted = entry.tip.actuallayoutheight * fitScale;
        assert(at.y >= 0 && at.y + painted <= rootHeight + 1, 'The complete tooltip remains within the physical screen');
        assert(parseFloat(body.style.height) <= parseFloat(entry.tip.style.height) - 36 + 1e-6);
        h.advance(.3);
        const after = h.counters();
        assert.deepEqual(after, before, 'Hover and layout follow-ups neither recreate panels nor rewrite label text');
        h.hover(entry); h.advance(.4); assert.deepEqual(h.counters(), before, 'Repeated hover repositions the same existing content');
        const layouts = h.scheduled.filter(job => [0, .05, .1, .2].includes(job.delay));
        assert.equal(layouts.length, 8, 'Each hover schedules exactly four finite placement passes');
        h.dispose(entry); assert.equal(h.jobs.size, 0);
    }
});

test('Stale long-tooltip layout and leave callbacks cannot affect a replacement row or revive disposed content', () => {
    const h = harness({layoutDelay: .11}), old = actualBundle(h), fresh = h.bind({}, {y: 400});
    h.hover(old); const callbacks = h.scheduled.filter(job => job.delay === 0).map(job => job.fn);
    h.advance(.16); old.card.events.onmouseout(); callbacks.push(h.scheduled.at(-1).fn);
    h.hover(fresh); h.dispose(old);
    callbacks.forEach(callback => assert.doesNotThrow(callback)); h.advance(.5);
    assert(fresh.tip.BHasClass('Visible'), 'Old callbacks do not hide the newer hovered source');
    h.dispose(fresh); callbacks.forEach(callback => assert.doesNotThrow(callback));
    assert.equal(h.jobs.size, 0); assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
});

test('Negative controls reproduce the old missed-fast-return and internally clipped-description failures', () => {
    const oldDismiss = code => code.replace('            release(at);\n            if (blocked', '            if (blocked')
        .replace('            release(cursor());', '            // old version waited for its watcher');
    // Production uses CRLF in some checkouts, so normalize only the in-memory
    // negative fixture before reverting the two synchronously observed exits.
    const oldSourceLeave = code => {
        const restored = code.replace(/\r\n/g, '\n').replace('if(dismiss){dismiss.Dispose();dismiss=null;}\n            hide();',
            'if(dismiss)dismiss.Dismiss();else hide();');
        assert.notEqual(restored, code.replace(/\r\n/g, '\n'), 'The negative fixture must actually restore the previous source-leave behavior');
        return restored;
    };
    assert.throws(() => fastReturn(harness({sourceTransform: oldSourceLeave,
        dismissTransform: code => oldDismiss(code.replace(/\r\n/g, '\n'))})),
        /Returning after a real physical exit/, 'The old race must be caught by the fast-return regression');
    assert.throws(() => wholeRowSwitch(harness({sourceTransform: oldSourceLeave}), {switches: 1}),
        /Each real source exit releases its previous owner/, 'Even with shared source rearming, obsolete source owners must be disposed');
    const oldClamp = code => code + '\n.BLMarketDetail .RCProductEffect { max-height:600px; overflow:squish scroll; }';
    assert.throws(() => {
        const h = harness({cssTransform: oldClamp}), entry = actualBundle(h, 'video_bundle_b004');
        h.hover(entry); h.advance(.36); assertCompleteScrollable(h, entry);
    }, /natural height|Only the whole-body/, 'The old nested Label cap must fail even though its text property is complete');
    assert.throws(() => {
        const h = harness({layoutDelay: .11, sourceTransform: code => code.replace('Number(content.actuallayoutheight)', 'Number(body.actuallayoutheight)')});
        const entry = actualBundle(h, 'video_bundle_b004'); h.hover(entry); h.advance(.36);
        assertCompleteScrollable(h, entry);
    }, /Scrollable|actual long description/, 'Measuring a bounded viewport instead of natural content must fail the delayed-layout regression');
    assert.throws(() => wholeRowSwitch(harness({sourceTransform: code => {
        const restored = code.replace('if(hoverPoint&&hoverPoint[0]>=x', 'if(false&&hoverPoint&&hoverPoint[0]>=x');
        assert.notEqual(restored, code, 'The negative fixture must actually disable entry-point avoidance');
        return restored;
    }}), {switches: 1, verifyAvoidance: false}), /survive its passive watcher after 400ms/,
    'An instant-only fix still fails when its new popup covers the hovered row name and the watcher runs');
});
