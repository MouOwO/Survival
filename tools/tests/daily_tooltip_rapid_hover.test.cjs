const assert = require('node:assert/strict');
const test = require('node:test');
const {createHarness} = require('./fixtures/menus_v10_harness.cjs');

function dailyPage(beforeDaily) {
    const h = createHarness();
    for (const source of ['archive_theme_tokens.js', 'archive_parchment_data.js', 'archive_handoff_180de7e38b.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js']) h.load(source);
    if (beforeDaily) beforeDaily(h);
    h.setCursor(0, 0);
    h.load('daily_remaining_5d5c1152eb.js');
    h.cfg.SurvivalDaily.Open(false);
    h.emit('survival_daily_snapshot', {
        ok:true, sequence:1, today:1, count:0, has_pass:0,
        ordinary_status:'not_open', purchase_enabled:0,
        calendar28:Array.from({length:28}, (_, i) => ({
            day:i + 1, status:'not_open',
            rewards:[{id:'hover_reward_' + (i + 1), name:'奖励' + (i + 1), description:'攻击力+' + (i + 1), count:1}]
        })),
        specials:[
            {id:'monthly_first', name:'月卡奖励一', day:7, description:'生命值+100', count:1},
            {id:'monthly_second', name:'月卡奖励二', day:14, description:'护甲+10', count:1}
        ]
    });
    return h;
}

function cursorOn(h, card) {
    const at = card.GetPositionWithinWindow();
    h.setCursor(at.x + 10, at.y + 40);
}

function assertReward(h, day) {
    assert(h.nodes.DailyGW2Tooltip.visible, 'The last hovered daily reward remains visible without another mouse movement');
    assert.match(h.nodes.DailyGW2TooltipTitle.text, new RegExp('第' + day + '天'));
    assert(h.nodes.DailyGW2TooltipEffect.text.replace(/<[^>]+>/g, '').includes('攻击力+' + day), 'The displayed effects belong to the last hovered reward');
}

function dispose(h) {
    h.cfg.SurvivalDaily.Dispose();
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
    assert(!h.sent.some(row => /claim|purchase|checkout/.test(row.name)), 'Hovering never claims or purchases a reward');
}

test('a delayed leave from the previous reward cannot hide the current daily reward', () => {
    const h = dailyPage();
    try {
        const first = h.nodes.DailyGW2Day_1, second = h.nodes.DailyGW2Day_2;
        cursorOn(h, first);
        first.events.onmouseover();
        h.flushFinite();
        assertReward(h, 1);
        cursorOn(h, second);
        second.events.onmouseover();
        first.events.onmouseout();
        h.flushFinite();
        h.flushFinite();
        assertReward(h, 2);
        cursorOn(h, first);
        first.events.onmouseover();
        second.events.onmouseout();
        h.flushFinite();
        assertReward(h, 1);
    } finally { dispose(h); }
});

test('a daily reward under a dismissed tooltip can open when the mouse stops on it', () => {
    const h = dailyPage();
    try {
        const first = h.nodes.DailyGW2Day_1, second = h.nodes.DailyGW2Day_2;
        cursorOn(h, first);
        first.events.onmouseover();
        h.flushFinite();
        assertReward(h, 1);
        const surface = h.nodes.DailyGW2TooltipSurface;
        const old = surface.GetPositionWithinWindow(), next = second.GetPositionWithinWindow();
        assert(next.x + 10 >= old.x && next.x + 10 < old.x + surface.actuallayoutwidth);
        assert(next.y + 40 >= old.y && next.y + 40 < old.y + surface.actuallayoutheight, 'Use the actual adjacent daily tile covered by the previous tooltip');
        cursorOn(h, second);
        surface.events.onmouseover();
        first.events.onmouseout();
        second.events.onmouseover();
        h.flushFinite();
        h.flushFinite();
        assertReward(h, 2);
    } finally { dispose(h); }
});

test('the automatic tooltip geometry watcher cannot suppress an adjacent reward hover', () => {
    const h = dailyPage();
    try {
        const first = h.nodes.DailyGW2Day_1, second = h.nodes.DailyGW2Day_2;
        cursorOn(h, first);
        first.events.onmouseover();
        h.flushFinite();
        cursorOn(h, second);
        // Run the existing cursor watcher without synthesizing a surface enter.
        h.flushFinite();
        assert.equal(h.nodes.DailyGW2Tooltip.visible, false, 'The watcher really dismisses the old short tooltip at this position');
        first.events.onmouseout();
        second.events.onmouseover();
        h.flushFinite();
        assertReward(h, 2);
    } finally { dispose(h); }
});

test('leaving and immediately returning to the same dismissed reward does not require a geometry sampling tick', () => {
    const h = dailyPage();
    try {
        const card = h.nodes.DailyGW2Day_1, surface = h.nodes.DailyGW2TooltipSurface;
        cursorOn(h, card);
        card.events.onmouseover();
        h.flushFinite();
        const at = surface.GetPositionWithinWindow();
        h.setCursor(at.x + 10, at.y + 40);
        surface.events.onmouseover();
        assert.equal(h.nodes.DailyGW2Tooltip.visible, false, 'Entering the current short tooltip retains immediate dismissal');
        h.setCursor(0, 0);
        card.events.onmouseout();
        // No timer runs while the cursor briefly leaves both old regions.
        cursorOn(h, card);
        card.events.onmouseover();
        h.flushFinite();
        h.flushFinite();
        assertReward(h, 1);
    } finally { dispose(h); }
});

test('closing and immediately reopening rearms the same dismissed reward without a geometry tick', () => {
    const h = dailyPage();
    try {
        const card = h.nodes.DailyGW2Day_1, surface = h.nodes.DailyGW2TooltipSurface;
        cursorOn(h, card);
        card.events.onmouseover();
        h.flushFinite();
        const at = surface.GetPositionWithinWindow();
        h.setCursor(at.x + 10, at.y + 40);
        card.events.onmouseout();
        surface.events.onmouseover();
        assert.equal(h.nodes.DailyGW2Tooltip.visible, false);
        assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().blocked, true, 'Use an actual passive dismissal lock');
        h.cfg.SurvivalDaily.Close();
        assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().blocked, false, 'Closing releases this daily tooltip owner lock immediately');
        assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().watching, false, 'A closed daily page has no dismissal polling');
        // Neither source/surface leave events nor a watcher tick occur while closed.
        cursorOn(h, card);
        h.cfg.SurvivalDaily.Open(false);
        assert.equal(h.nodes.DailyGW2Day_1, card, 'Reopening retains the original reward source');
        card.events.onmouseover();
        assertReward(h, 1);
        h.flushFinite();
        h.flushFinite();
        assertReward(h, 1);
    } finally { dispose(h); }
});

test('legacy dismissal owners without SourceLeft or Reset survive explicit hide and repeated close/open', () => {
    let renderer;
    const retainedOwners = [];
    const h = dailyPage(h => {
        const policy = h.cfg.SurvivalTooltipDismiss, createOwner = policy.Create;
        policy.Create = options => {
            const owner = createOwner(options);
            delete owner.SourceLeft;
            delete owner.Reset;
            retainedOwners.push(owner);
            return owner;
        };
        const createRenderer = h.cfg.SurvivalArchiveTooltip.Create;
        h.cfg.SurvivalArchiveTooltip.Create = options => (renderer = createRenderer(options));
    });
    try {
        const card = h.nodes.DailyGW2Day_1, surface = h.nodes.DailyGW2TooltipSurface;
        function checkSingleOwner() {
            assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 1, 'Replacing a legacy owner cannot accumulate policy owners');
            assert.equal(retainedOwners.filter(owner => owner.alive()).length, 1);
            assert(retainedOwners.every(owner => !owner.SourceLeft && !owner.Reset), 'Every policy owner has the legacy method surface');
        }
        function dismissSurface() {
            const at = surface.GetPositionWithinWindow();
            h.setCursor(at.x + 10, at.y + 40);
            card.events.onmouseout();
            surface.events.onmouseover();
            assert.equal(h.nodes.DailyGW2Tooltip.visible, false);
            assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().blocked, true);
        }
        for (let cycle = 0; cycle < 4; cycle++) {
            cursorOn(h, card);
            card.events.onmouseover();
            h.flushFinite();
            assertReward(h, 1);
            checkSingleOwner();
            dismissSurface();
            renderer.Hide();
            assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().blocked, false, 'Explicit Hide accepts an owner without Reset');
            assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().watching, false);
            checkSingleOwner();
            cursorOn(h, card);
            card.events.onmouseover();
            assertReward(h, 1);
            dismissSurface();
            h.cfg.SurvivalDaily.Close();
            assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().blocked, false);
            assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().watching, false);
            checkSingleOwner();
            cursorOn(h, card);
            h.cfg.SurvivalDaily.Open(false);
            card.events.onmouseover();
            // No watcher or source leave is needed after reopening the same card.
            assertReward(h, 1);
            surface.events.onmouseover();
            assertReward(h, 1);
            h.flushFinite();
            assertReward(h, 1);
            checkSingleOwner();
        }
    } finally { dispose(h); }
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().watching, false);
});

test('late enter and leave from the moved tooltip surface cannot dismiss the new reward', () => {
    const h = dailyPage();
    try {
        const first = h.nodes.DailyGW2Day_1, second = h.nodes.DailyGW2Day_2;
        cursorOn(h, first);
        first.events.onmouseover();
        h.flushFinite();
        const surface = h.nodes.DailyGW2TooltipSurface;
        cursorOn(h, second);
        second.events.onmouseover();
        // Panorama delivers events queued for the previous floating position
        // after the same surface has already moved to the second reward.
        surface.events.onmouseover();
        surface.events.onmouseout();
        first.events.onmouseout();
        h.flushFinite();
        h.flushFinite();
        assertReward(h, 2);
        h.setCursor(0, 0);
        second.events.onmouseout();
        h.flushFinite();
        assert.equal(h.nodes.DailyGW2Tooltip.visible, false, 'An actual leave still hides the current reward');
    } finally { dispose(h); }
});

test('nested monthly reward card and icon events keep the current item visible', () => {
    const h = dailyPage();
    try {
        const card = h.nodes.DailySpecials.Children()[0];
        function rewardSlot(panel) {
            if (panel.BHasClass('DailyGW2PassReward')) return panel;
            return panel.Children().map(rewardSlot).find(Boolean);
        }
        const slot = rewardSlot(card);
        assert(slot, 'The real monthly reward supplies a nested hover source');
        cursorOn(h, slot);
        card.events.onmouseover();
        slot.events.onmouseover();
        card.events.onmouseout();
        h.flushFinite();
        h.flushFinite();
        assert(h.nodes.DailyGW2Tooltip.visible, 'A delayed parent leave cannot hide the hovered monthly icon');
        assert.equal(h.nodes.DailyGW2TooltipTitle.text, '月卡奖励一');
        assert(h.nodes.DailyGW2TooltipEffect.text.replace(/<[^>]+>/g, '').includes('生命值+100'));
        slot.events.onmouseout();
        h.flushFinite();
        assert(h.nodes.DailyGW2Tooltip.visible, 'Child leave events do not hide a tooltip while the cursor remains in its real source');
        const second = h.nodes.DailySpecials.Children()[1];
        cursorOn(h, second);
        second.events.onmouseover();
        slot.events.onmouseout();
        card.events.onmouseout();
        h.flushFinite();
        assert(h.nodes.DailyGW2Tooltip.visible);
        assert.equal(h.nodes.DailyGW2TooltipTitle.text, '月卡奖励二');
    } finally { dispose(h); }
});
