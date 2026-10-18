'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {createHarness} = require('./fixtures/menus_v10_harness.cjs');
const {fixture} = require('../daily_gw2/fixture.cjs');
const project = path.resolve(__dirname, '../..');

// Real renderer, art registry, icon resolver, ModalShell/Fit and layer manager.
// Native Panel geometry is simulated: this verifies authored layout and resize
// behavior, not Panorama rasterization, font metrics or an actual Dota capture.
function descendants(panel) {
    return panel.Children().flatMap(child => [child, ...descendants(child)]);
}
function tagged(panel, cls) { return descendants(panel).filter(child => child.BHasClass(cls)); }
function quantities(panel) { return tagged(panel, 'DailyGW2Quantity').map(child => child.text); }
function auditAssets(data) {
    const manifest = JSON.parse(fs.readFileSync(path.join(project, 'data/ui/daily_accepted_layers.json'), 'utf8'));
    const selected = {window_edge: 'assets/window_brush_edge.png', header_rule: 'assets/header_rule.png',
        divider: 'assets/monthly_divider.png', reward_frame: 'assets/week_r1_c1_frame.png',
        button: 'assets/monthly_button_base.png', close_base: 'assets/close_base.png',
        close: 'assets/close_cross.png', lock: 'assets/monthly_1_lock.png', check: 'assets/week_r1_c1_claimed.png'};
    for (const key of ['window_background', 'tooltip_background', 'tooltip_frame'])
        selected[key] = 'panorama/src/images/custom_game/daily_gw2_v1/' + key + '.png';
    assert.deepEqual(manifest.assets.map(asset => asset.id).sort(), Object.keys(selected).sort(),
        'Only reviewed separate components are imported, without concept icons, text, quantities or composites');
    const hash = value => crypto.createHash('sha256').update(value).digest('hex');
    for (const asset of manifest.assets) {
        assert.equal(asset.origin, selected[asset.id]);
        const png = fs.readFileSync(path.join(project, asset.destination));
        assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
        assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], [asset.width, asset.height]);
        assert.equal(png[25], 6, 'Component PNG preserves its own RGBA transparency');
        assert.equal(hash(png), asset.sha256, 'Imported component matches its provenance hash');
        const recipe = fs.readFileSync(path.join(project, asset.recipe));
        assert.equal(hash(recipe), asset.recipe_sha256);
        assert.match(recipe.toString(), /"m_outputFormat"\s+"string"\s+"BGRA8888"/);
        assert.match(recipe.toString(), /"m_bNoLod"\s+"bool"\s+"1"/);
        assert.equal(data.assets[asset.id].file, asset.runtime_uri);
        assert.match(asset.runtime_uri, /^s2r:\/\/panorama\/images\/custom_game\/daily_accepted_v1\/[a-z_]+_v10\.vtex$/);
    }
    assert.equal(data.assets.premium_frame.file, data.assets.reward_frame.file,
        'Weekly and monthly slots use the same accepted frame pixels');
    assert.deepEqual(Object.keys(data.assets).sort(), [...Object.keys(selected), 'premium_frame'].sort());
}
function box(panel, canvas) {
    const at = panel.GetPositionWithinWindow(), origin = canvas.GetPositionWithinWindow();
    return [at.x - origin.x, at.y - origin.y, parseFloat(panel.style.width), parseFloat(panel.style.height)];
}
function snapshot() {
    const official = fixture();
    const calendar28 = Array.from({length: 28}, (_, index) => ({
        day: index + 1, absolute_count: index + 1, is_today: index === 3 ? 1 : 0,
        status: index < 3 ? 'claimed' : index === 3 ? 'claimable' : 'not_open',
        rewards: official.rewards[index % 7].rewards.map(item => ({...item}))
    }));
    return {ok: true, sequence: 1, today: 25004, period_id: '0', count: 3,
        ordinary_status: 'claimable', pending: 0, has_pass: 0, purchase_enabled: 1,
        price: '20元', duration_days: 30, makeup_days: 30, missed: [25002],
        calendar28, calendar_current_day: 4, calendar_start_count: 0,
        cycle: calendar28.slice(0, 7), specials: official.specials.map(item => ({...item})),
        premium: {status: 'unconfigured'}, rule_text: '以正式配置及服务端快照为准'};
}

function dailyAccepted() {
    const h = createHarness(), {cfg, nodes} = h;
    for (const source of ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js']) h.load(source);
    // The committed art catalog and the pending unified registry are both real
    // production resolvers. Do not require an unrelated registry migration.
    const itemResources = 'common/item_resources.js';
    if (fs.existsSync(path.join(project, 'panorama/src/scripts/custom_game', itemResources))) h.load(itemResources);
    for (const source of ['archive_theme_tokens.js', 'archive_parchment_data.js',
        'archive_handoff_180de7e38b.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js',
        'reward_presentation.js', 'item_art_remaining_5d5c1152eb.js',
        'daily_gw2_data.js', 'daily_remaining_5d5c1152eb.js']) h.load(source);
    auditAssets(cfg.DailyGW2Data);
    // A formal reward falling back to the old generic crystal fails immediately.
    cfg.RemainingHandoff.DailyImage = () => assert.fail('A real daily reward must use the existing item art resolver');
    cfg.SurvivalDaily.Open(false);
    const canvas = nodes.DailyGW2Canvas;
    assert.deepEqual([parseFloat(canvas.style.width), parseFloat(canvas.style.height)], [1382, 784]);
    assert.equal(nodes.DailyGW2Title.text, '每日登录奖励');
    assert.deepEqual(Array.from({length: 7}, (_, index) => nodes['DailyGW2Weekday_' + index].text),
        ['Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ', 'Ⅴ', 'Ⅵ', 'Ⅶ']);
    assert.equal(nodes.DailyCards.GetChildCount(), 28);
    assert.equal(nodes.DailySpecials.GetChildCount(), 0, 'Loading does not draw unconfigured monthly reward frames');
    assert.equal(tagged(nodes.DailyCards, 'DailyGW2ItemArt').length, 0, 'Loading does not invent rewards');

    function noEmptyMonthlySlots() {
        assert(!nodes.DailyGW2SpecialEmpty_4, 'No fourth empty frame is generated');
        assert.equal(tagged(nodes.DailySpecials, 'DailyGW2SpecialEmpty').length, 0,
            'Every visible monthly frame represents a configured reward');
    }
    function geometry() {
        const columns = [62, 207, 355, 505, 652, 802, 952], rows = [152, 293, 437, 582];
        for (let index = 0; index < 28; index++) {
            const day = nodes['DailyGW2Day_' + (index + 1)];
            assert.deepEqual(box(day, canvas), [columns[index % 7], rows[Math.floor(index / 7)], 118, 119]);
            const frame = tagged(day, 'DailyGW2RewardFrame')[0];
            assert.equal(frame.style.backgroundImage, 'url("' + cfg.DailyGW2Data.assets.reward_frame.file + '")');
            for (const reward of tagged(day, 'DailyGW2Reward')) {
                const slot = box(reward, day);
                assert.equal(slot[1], 2, 'Reward art starts immediately inside the border');
                assert.equal(slot[1] + slot[3], 117, 'Reward art fills the frame height');
                assert(slot[0] >= 2 && slot[0] + slot[2] <= 116, 'Reward art stays inside the border');
            }
        }
        nodes.DailySpecials.Children().forEach((special, index) => {
            assert.deepEqual(box(special, canvas), [1175, rows[index], 118, 119]);
            const frame = tagged(special, 'DailyGW2SpecialFrame')[0];
            assert(frame, 'Each monthly slot has a separate frame');
            assert.deepEqual(box(frame, special), [0, 0, 118, 119]);
            assert.equal(frame.style.backgroundImage, 'url("' + cfg.DailyGW2Data.assets.reward_frame.file + '")');
        });
        const purchase = box(nodes.PassPurchase, canvas);
        assert(purchase[1] >= rows[3] + 119, 'Purchase button stays below the monthly reward area');
        assert(purchase[1] + purchase[3] <= 784, 'Purchase button remains inside the canvas');
        assert.equal(nodes.DailySubtitle.visible, false);
        assert.equal(nodes.DailySubtitle.style.visibility, 'collapse');
        assert.equal(nodes.DailySubtitle.text, '');
        assert.equal(nodes.DailySubtitle.style.height, '0px');
        assert(!nodes.DailyWindow.style.opacity || Number(nodes.DailyWindow.style.opacity) === 1,
            'Background transparency cannot fade all text, icons and states');
        noEmptyMonthlySlots();
        for (const card of [...nodes.DailyCards.Children(), ...nodes.DailySpecials.Children()]) {
            const slots = [...tagged(card, 'DailyGW2Reward'), ...tagged(card, 'DailyGW2PassReward')];
            if (!slots.length) continue;
            const bounds = slots.map(slot => box(slot, card));
            assert.equal(bounds[0][0], 2);
            assert.equal(bounds.at(-1)[0] + bounds.at(-1)[2], 116);
            for (let i = 0; i < slots.length; i++) {
                if (i) assert.equal(bounds[i - 1][0] + bounds[i - 1][2], bounds[i][0], 'Two rewards leave no unpainted gap');
                const icon = tagged(slots[i], 'DailyGW2ItemArt')[0];
                assert.deepEqual(box(icon, slots[i]), [0, 0, bounds[i][2], bounds[i][3]], 'Icon fills the complete slot, including tall paired rewards');
                assert.equal(icon.scaling, 'stretch-to-cover-preserve-aspect', 'Daily art overrides catalog contain without distorting the image');
            }
        }
    }
    geometry();

    let current = snapshot();
    function send(changes = {}) {
        current = {...current, ...changes, sequence: current.sequence + 1};
        h.emit('survival_daily_snapshot', current);
    }
    send();
    assert.equal(nodes.DailySpecials.GetChildCount(), 3, 'The formal three milestones produce exactly three frames');
    assert.equal(cfg.SurvivalDaily.Inspect().monthlySlots, 3);
    geometry();
    function realIcon(parent, id) {
        const expected = cfg.SurvivalItemResources ? cfg.SurvivalItemResources.Lookup({id}) : cfg.SurvivalItemArt.Lookup({id});
        const uri = expected && (expected.uri || expected.runtime_uri || (expected.icon_path && 'file://{images}/' + expected.icon_path));
        assert(uri, 'Formal CSV reward has an actual shared image resource: ' + id);
        assert(tagged(parent, 'DailyGW2ItemArt').some(icon => icon.image === uri),
            'Rendered image follows the shared reward ID, not the concept artwork: ' + id);
    }
    for (let index = 0; index < 28; index++) {
        const day = nodes['DailyGW2Day_' + (index + 1)];
        assert.equal(tagged(day, 'DailyGW2Reward').length, current.calendar28[index].rewards.length);
        current.calendar28[index].rewards.forEach(reward => realIcon(day, reward.id));
    }
    current.specials.forEach(item => {
        const card = nodes['DailyGW2Special_' + item.id];
        realIcon(card, item.id);
        assert.deepEqual(quantities(card), [], 'Missing monthly count is not replaced with 1');
        assert.equal(tagged(card, 'DailyGW2Lock').length, 1);
    });
    assert.equal(tagged(nodes.DailyCards, 'DailyGW2Check').length, 3);

    const formalSpecials = current.specials.slice(), unchangedMonthlyCards = nodes.DailySpecials.Children().slice();
    send();
    assert.deepEqual(nodes.DailySpecials.Children(), unchangedMonthlyCards, 'Unchanged three-reward snapshots reuse monthly cards');
    // Branch fixture only: a future server may schedule this existing formal
    // daily resource as a fourth milestone. No CSV or production reward changes.
    const fourth = {...current.calendar28[0].rewards[0], day: 28, owned: 0};
    send({specials: formalSpecials.concat(fourth)});
    assert.equal(nodes.DailySpecials.GetChildCount(), 4, 'A real fourth server item appears instead of being discarded');
    assert.equal(cfg.SurvivalDaily.Inspect().monthlySlots, 4);
    const fourthCard = nodes['DailyGW2Special_' + fourth.id];
    realIcon(fourthCard, fourth.id);
    assert(fourthCard.BHasClass('DailyGW2Locked'));
    fourthCard.events.onmouseover();
    h.flushFinite();
    assert(nodes.DailyGW2Tooltip.visible);
    assert.equal(nodes.DailyGW2TooltipTitle.text, fourth.name);
    const fourthText = nodes.DailyGW2TooltipEffect.text.replace(/<br\s*\/?\s*>/gi, '\n').replace(/<[^>]*>/g, '');
    assert(fourthText.includes(fourth.description));
    assert(fourthText.includes('累计签到28次'));
    geometry();
    send();
    assert.equal(nodes['DailyGW2Special_' + fourth.id], fourthCard, 'Unchanged four-reward snapshots reuse the fourth card');
    send({specials: formalSpecials});
    assert.equal(nodes.DailySpecials.GetChildCount(), 3, 'Removing the fourth server item removes its frame');
    assert(!fourthCard.IsValid());
    assert(!nodes.DailyGW2Tooltip.visible, 'Removing a hovered fourth item retires its description');
    assert.equal(cfg.SurvivalDaily.Inspect().monthlySlots, 3);
    const restoredMonthlyCards = nodes.DailySpecials.Children().slice();
    send();
    assert.deepEqual(nodes.DailySpecials.Children(), restoredMonthlyCards, 'The restored three-reward state remains cached');
    assert(restoredMonthlyCards.every(card => card.BHasClass('DailyGW2Locked')));
    geometry();

    const changedDays = current.calendar28.map(day => ({...day, rewards: day.rewards.map(item => ({...item}))}));
    changedDays[0].rewards[0].count = 17;
    changedDays[4].rewards[0].count = 17;
    changedDays[4].rewards[1].count = 123;
    changedDays[3].status = 'claimed';
    const changedSpecials = current.specials.map((item, index) => ({...item, owned: index === 0 ? 9 : 0}));
    send({calendar28: changedDays, specials: changedSpecials, count: 4, ordinary_status: 'claimed', has_pass: 1});
    assert.deepEqual(quantities(nodes.DailyGW2Day_1), ['17']);
    assert.deepEqual(quantities(nodes.DailyGW2Day_5).sort(), ['123', '17']);
    assert.equal(tagged(nodes.DailyCards, 'DailyGW2Check').length, 4);
    assert.equal(tagged(nodes.DailySpecials, 'DailyGW2Lock').length, 0);
    assert.equal(tagged(nodes.DailySpecials, 'DailyGW2Check').length, 1);
    assert.deepEqual(quantities(nodes.DailyGW2Special_daily_wealth_talisman), [], 'Owned 9 is not an award quantity');
    geometry();

    const finalDays = changedDays.map(day => ({...day, rewards: day.rewards.map(item => ({...item}))}));
    const replacement = {...finalDays[1].rewards[0], count: 123};
    finalDays[0].rewards = [replacement];
    send({calendar28: finalDays, has_pass: 0,
        specials: changedSpecials.map((item, index) => index === 1 ? {...item, count: 7} : item)});
    assert.deepEqual(quantities(nodes.DailyGW2Day_1), ['123']);
    realIcon(nodes.DailyGW2Day_1, replacement.id);
    assert.deepEqual(quantities(nodes.DailyGW2Special_daily_ancient_tree), ['7'], 'An explicit server quantity is shown');
    assert.equal(tagged(nodes.DailySpecials, 'DailyGW2Lock').length, 2, 'Expired pass relocks only unowned formal rewards');
    assert.equal(tagged(nodes.DailySpecials, 'DailyGW2Check').length, 1);
    geometry();

    send({pending: 1, ordinary_status: 'claimable', has_pass: 1});
    const pendingRequests = h.sent.length;
    for (const id of ['DailyClaim', 'DailyMakeup', 'PassPurchase']) {
        assert.equal(nodes[id].enabled, false, 'Server pending disables ' + id);
        nodes[id].events.onactivate();
    }
    assert.equal(h.sent.length, pendingRequests, 'Server pending blocks claim, makeup and purchase callbacks');
    send({pending: 0, ordinary_status: 'claimed'});

    const before = h.sent.length;
    const originalCards = nodes.DailyCards.Children().slice();
    // Exercise the actual shared Fit and its scheduled open-window resize path.
    for (const [width, height] of [[1280, 720], [1600, 1000], [2560, 1080]]) {
        h.root.style.width = width + 'px'; h.root.style.height = height + 'px';
        h.flushFinite();
        const scale = Number(nodes.DailyWindow.style.transform.match(/^scale3d\(([^,]+)/)?.[1]);
        assert(scale > 0 && scale * 1382 <= width + 0.01 && scale * 784 <= height + 0.01,
            'Shared resize keeps the authored canvas inside the simulated viewport');
        assert.deepEqual(nodes.DailyCards.Children(), originalCards, 'Resize does not rebuild reward content');
        geometry();
    }
    assert.equal(h.sent.length, before, 'Resize does not submit rewards or purchases');
    assert.equal(cfg.SurvivalUILayers.Top(), 'daily_rewards');
    nodes.DailyWindow.handlers.Cancelled();
    assert.equal(cfg.SurvivalDaily.Inspect().open, false, 'Real layer-manager Escape path closes the page');
    cfg.SurvivalDaily.Open(false);
    geometry();
    assert.deepEqual(quantities(nodes.DailyGW2Day_1), ['123'], 'Reopening retains the latest real snapshot values');
    nodes.DailyScrim.events.onactivate();
    assert.equal(cfg.SurvivalDaily.Inspect().open, false, 'Real shared outside-click path still closes');
    assert(!h.sent.some(row => /claim|purchase|payment/.test(row.name)), 'This visual regression sends only view requests');
    cfg.SurvivalDaily.Dispose();
    console.log('DAILY_ACCEPTED_LAYOUT_PASS: real JS/shared UI in simulated Panorama, 28 daily slots, configured 0/3/4 monthly frames, real fourth-item icon/tooltip, 4-to-3 retirement/cache, dynamic counts/states, resize and reopen; native rendering unverified');
}

module.exports = {dailyAccepted};
if (require.main === module) dailyAccepted();
