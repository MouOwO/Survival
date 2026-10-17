'use strict';
// The real daily controller and archive tooltip run together against native
// Panel fixtures. No server, entitlement, reward grant or payment is invoked.
const assert = require('node:assert/strict');
const test = require('node:test');
const {createHarness} = require('../tests/fixtures/menus_v10_harness.cjs');
const {fixture} = require('../daily_gw2/fixture.cjs');

function plain(value) {
    return String(value).replace(/<br\s*\/?\s*>/gi, '\n').replace(/<[^>]*>/g, '')
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/&quot;/g, '"');
}

function setup() {
    const h = createHarness(), {cfg, nodes} = h;
    // These dependencies occur before the daily controller in archive.xml.
    for (const source of ['archive_theme_tokens.js', 'archive_parchment_data.js',
        'archive_handoff_180de7e38b.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js']) h.load(source);
    const instances = [], create = cfg.SurvivalArchiveTooltip.Create;
    cfg.SurvivalArchiveTooltip.Create = options => {
        const api = create(options);
        instances.push({api, options});
        return api;
    };
    h.setCursor(4000, 3000);
    h.load('daily_gw2_data.js');
    h.load('daily_remaining_5d5c1152eb.js');
    cfg.SurvivalDaily.Open(false);
    assert.equal(nodes.DailySpecials.GetChildCount(), 0, 'Unloaded monthly rewards do not draw empty frames');
    const official = fixture();
    let sequence = 0;
    let current = {
        ok: true, today: 25004, period_id: 'isolated-daily-tooltip', count: 3,
        ordinary_status: 'claimable', pending: 0, has_pass: 0, purchase_enabled: 0,
        price: '20元', duration_days: 30, makeup_days: 30, missed: [25002],
        calendar28: Array.from({length: 28}, (_, index) => ({
            day: index + 1, status: index < 3 ? 'claimed' : index === 3 ? 'claimable' : 'not_open',
            rewards: official.rewards[index % 7].rewards.map(item => ({...item}))
        })), calendar_current_day: 4, calendar_start_count: 0,
        specials: official.specials.map(item => ({...item})), premium: {status: 'unconfigured'},
        rule_text: '隔离测试：奖励及条件仍由原每日快照提供'
    };
    function send(patch = {}) {
        current = {...current, ...patch, sequence: ++sequence};
        h.emit('survival_daily_snapshot', current);
    }
    send();
    assert.equal(instances.length, 1, 'Daily owns one real shared archive renderer');
    const {api: tip, options} = instances[0];
    function hover(panel) {
        h.setCursor(4000, 3000);
        panel.events.onmouseover();
        h.flushFinite();
        return plain(tip.elements.Effect.text);
    }
    function noTransactions() {
        assert(!h.sent.some(row => /claim|purchase|checkout/.test(row.name)),
            'Hover and lifecycle never submit a transaction');
    }
    return {h, cfg, nodes, tip, options, official, hover, send, noTransactions, get current() { return current; }};
}

test('Monthly rewards use archive material and retain every configured effect and eligibility line', () => {
    const t = setup();
    for (const item of t.official.specials) {
        const card = t.nodes['DailyGW2Special_' + item.id], body = t.hover(card);
        assert(t.tip.IsVisible());
        assert.equal(t.tip.elements.Title.text, item.name);
        for (const effect of item.description.split(/[;；\n]+/).filter(Boolean))
            assert(body.includes(effect), item.name + ': ' + effect);
        assert(body.includes('累计签到' + item.day + '次'));
        assert(body.includes('开通月卡后解锁'));
        assert(body.includes('自动发放'));
        assert.equal(t.tip.elements.State.text, '', 'A reward preview does not invent archive unlock state');
        assert.equal(t.tip.elements.Metric.visible, false, 'A reward amount is not archive owned quantity');
        assert.equal(t.tip.elements.Condition.visible, false, 'Daily conditions remain the authoritative daily text');
        assert.equal(t.tip.Inspect().nineSlices.Backing.count, 9);
        assert.equal(t.tip.Inspect().nineSlices.Frame.count, 9);
        assert.equal(t.tip.Inspect().nineSlices.Backing.asset, 'tooltip_reference_clean');
        assert(!/daily_accepted_v1\/(?:tooltip_background|tooltip_frame)/.test(
            t.tip.elements.Backing.Children().map(n => n.Children()[0].style.backgroundImage).join('')));
    }
    t.noTransactions();
    t.cfg.SurvivalDaily.Dispose();
});

test('All ordinary rewards, multiple items and known amounts survive the renderer switch', () => {
    const t = setup();
    for (let index = 0; index < t.official.rewards.length; index++) {
        const day = t.nodes['DailyGW2Day_' + (index + 1)], text = t.hover(day);
        for (const item of t.official.rewards[index].rewards) {
            assert(text.includes(item.name), item.name);
            assert(text.includes('×' + item.count), item.name + ' amount');
            for (const line of item.description.split(/[;；\n]+/).filter(Boolean))
                assert(text.includes(line), item.name + ': ' + line);
        }
        for (const slot of day.Children().filter(n => n.BHasClass('DailyGW2Reward'))) {
            const slotBody = t.hover(slot);
            assert(slotBody.includes('数量：'));
        }
    }
    assert.equal(t.nodes.DailyTooltip.visible, false, 'The retired native tooltip stays hidden');
    t.noTransactions();
    t.cfg.SurvivalDaily.Dispose();
});

test('Monthly frames follow configured items and a server fourth item keeps its icon, tooltip and removal lifecycle', () => {
    const t = setup(), formal = t.current.specials.slice();
    assert.equal(t.nodes.DailySpecials.GetChildCount(), 3);
    assert.equal(t.nodes.DailyGW2SpecialEmpty_4, undefined);
    const initial = t.nodes.DailySpecials.Children().slice();
    t.send();
    assert.deepEqual(t.nodes.DailySpecials.Children(), initial, 'Identical formal snapshots preserve card identity');
    // Isolated server-payload branch uses an existing formal resource. This
    // does not add a reward to the production CSV or grant any entitlement.
    const fourth = {...t.current.calendar28[0].rewards[0], day: 28, owned: 0};
    t.send({specials: formal.concat(fourth)});
    assert.equal(t.nodes.DailySpecials.GetChildCount(), 4);
    const card = t.nodes['DailyGW2Special_' + fourth.id];
    assert(card.IsValid());
    assert.equal(card.Children().filter(n => n.BHasClass('DailyGW2SpecialFrame')).length, 1);
    const slot = card.Children().find(n => n.BHasClass('DailyGW2PassReward'));
    assert(slot.Children().some(n => n.BHasClass('DailyGW2ItemArt') && n.image), 'The fourth item has a real icon child');
    assert(t.hover(card).includes(fourth.description));
    assert.equal(t.tip.elements.Title.text, fourth.name);
    assert(t.hover(slot).includes('累计签到28次'));
    assert(card.BHasClass('DailyGW2Locked'));
    t.send();
    assert.equal(t.nodes['DailyGW2Special_' + fourth.id], card);
    assert(t.tip.IsVisible(), 'Unchanged data does not retire the hovered fourth item');
    t.send({specials: formal});
    assert.equal(t.nodes.DailySpecials.GetChildCount(), 3);
    assert(!card.IsValid());
    assert(!t.tip.IsVisible(), 'Removing the hovered fourth source hides its tooltip');
    const restored = t.nodes.DailySpecials.Children().slice();
    t.send();
    assert.deepEqual(t.nodes.DailySpecials.Children(), restored);
    assert.equal(t.nodes.DailyGW2SpecialEmpty_4, undefined);
    t.noTransactions();
    t.cfg.SurvivalDaily.Dispose();
});

test('A monthly snapshot replacing the hovered card retires the deleted anchor and updates eligibility', () => {
    const t = setup(), first = t.current.specials[0];
    const oldCard = t.nodes['DailyGW2Special_' + first.id];
    t.hover(oldCard);
    const queued = t.h.scheduled.slice();
    t.send({has_pass: 1, count: 8, specials: t.current.specials.map((item, index) => ({...item, owned: index === 0 ? 1 : 0}))});
    assert(!oldCard.IsValid());
    assert(!t.tip.IsVisible(), 'Replacing the source immediately hides its tooltip');
    assert.doesNotThrow(() => queued.filter(job => !job.cancelled).forEach(job => job.fn()));
    assert(!t.tip.IsVisible(), 'Stale measurements cannot revive a deleted card');
    assert(t.hover(t.nodes['DailyGW2Special_' + first.id]).includes('已获得'));
    const second = t.current.specials[1];
    assert(!t.hover(t.nodes['DailyGW2Special_' + second.id]).includes('开通月卡后解锁'));
    t.noTransactions();
    t.cfg.SurvivalDaily.Dispose();
});

test('Rules, close, reopen, unchanged snapshots and source reload own a single reusable renderer', () => {
    const t = setup(), first = t.nodes.DailyGW2Day_1, panel = t.tip.panel;
    t.hover(first);
    t.send();
    assert.equal(t.nodes.DailyGW2Day_1, first, 'Unchanged data preserves source panels');
    t.h.click(t.nodes.DailyRules);
    assert(!t.tip.IsVisible());
    first.events.onmouseover();
    assert(!t.tip.IsVisible(), 'Rules visibility blocks reward descriptions');
    t.h.click(t.nodes.DailyRules);
    t.hover(first);
    assert(t.tip.IsVisible());
    const queued = t.h.scheduled.slice();
    t.cfg.SurvivalDaily.Close();
    assert(!t.tip.IsVisible());
    assert.doesNotThrow(() => queued.filter(job => !job.cancelled).forEach(job => job.fn()));
    for (let index = 0; index < 6; index++) {
        t.cfg.SurvivalDaily.Open(false);
        assert.equal(t.tip.panel, panel);
        t.hover(first);
        t.cfg.SurvivalDaily.Close();
    }
    const oldMouseOver = first.events.onmouseover;
    t.cfg.SurvivalDaily.Dispose();
    assert(!panel.IsValid());
    assert.doesNotThrow(oldMouseOver);
    assert.equal(t.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
    t.h.load('daily_remaining_5d5c1152eb.js');
    t.cfg.SurvivalDaily.Open(false);
    assert.equal(t.cfg.SurvivalTooltipDismiss.Inspect().owners, 1);
    t.cfg.SurvivalDaily.Dispose();
    t.noTransactions();
});

test('Long archive descriptions retain scrolling, then short content restores ordinary dismissal', () => {
    const t = setup();
    const first = t.current.specials[0], long = '实际长效果+1；'.repeat(220);
    t.send({specials: t.current.specials.map((item, index) => index ? item : {...item, description: long})});
    // Native fit-children geometry is modeled from the actual populated rows.
    Object.defineProperty(t.tip.elements.Body, 'actuallayoutheight', {get() {
        return this.Children().filter(n => n.visible !== false)
            .reduce((total, n) => total + n.actuallayoutheight + (parseFloat(n.style.marginBottom) || 0), 0);
    }});
    const card = t.nodes['DailyGW2Special_' + first.id];
    t.hover(card);
    assert(t.tip.elements.Body.actuallayoutheight > t.tip.elements.Viewport.actuallayoutheight);
    assert(parseFloat(t.tip.panel.style.height) <= 570, 'Long content is bounded within the daily window');
    const created = t.h.counts.created, at = t.tip.elements.Surface.GetPositionWithinWindow();
    card.events.onmouseout();
    t.h.setCursor(at.x + 10, at.y + 10);
    t.tip.elements.Surface.events.onmouseover();
    t.h.flushFinite();
    assert(t.tip.IsVisible(), 'The source-to-scroll gap permits reading long content');
    assert.equal(t.h.counts.created, created);
    t.h.setCursor(4000, 3000);
    t.tip.elements.Surface.events.onmouseout();
    t.h.flushFinite();
    assert(!t.tip.IsVisible());
    t.hover(t.nodes.DailyGW2Day_1);
    const shortAt = t.tip.elements.Surface.GetPositionWithinWindow();
    t.h.setCursor(shortAt.x + 10, shortAt.y + 10);
    t.tip.elements.Surface.events.onmouseover();
    assert(!t.tip.IsVisible(), 'Short tooltips use the same dismissal policy as archive');
    t.noTransactions();
    t.cfg.SurvivalDaily.Dispose();
});

test('Weekday headings stay passive and tooltip disposal tolerates native layout retirement', () => {
    const t = setup();
    for (let index = 0; index < 7; index++) {
        const heading = t.nodes['DailyGW2Weekday_' + index];
        assert.equal(heading.hittest, false);
        assert.equal(heading.events.onmouseover, undefined);
        assert.equal(heading.__dailyGW2Tooltip, undefined);
    }
    t.hover(t.nodes.DailyGW2Day_1);
    t.noTransactions();
    t.h.assertCleanDispose(t.cfg.SurvivalDaily);
    assert.equal(t.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
});
