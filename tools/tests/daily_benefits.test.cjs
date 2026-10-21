'use strict';
const assert = require('node:assert/strict');
const {createHarness} = require('./fixtures/menus_v10_harness.cjs');
const {fixture} = require('../daily_gw2/fixture.cjs');

function setup() {
    const h = createHarness();
    for (const source of ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js',
        'common/item_resources.js', 'archive_theme_tokens.js', 'archive_parchment_data.js',
        'archive_handoff_180de7e38b.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js',
        'reward_presentation.js', 'item_art_remaining_5d5c1152eb.js',
        'daily_gw2_data.js', 'daily_remaining_5d5c1152eb.js']) h.load(source);
    return h;
}
const ordinary = count => ({id: 'lottery_ticket', name: '普通抽奖券', count, description: '用于地图宝箱'});
const gold = count => ({id: 'special_lottery_ticket', name: '金色抽奖券', count, description: '用于修仙、龙骑与暑期宝箱'});
const group = (track, targets, progress, counts) => ({period_id: '2026-10-21-05', progress,
    rows: targets.map((required, index) => ({id: `${track}_${required}`, required,
        base_rewards: [ordinary(counts[index])], monthly_rewards: track === 'weekly_time' ? [ordinary(counts[index]), ...(required >= 840 ? [gold(1)] : [])] : [ordinary(1)],
        status: progress >= required ? 'claimable' : 'locked', can_claim: progress >= required ? 1 : 0}))});
function snapshot() {
    const f = fixture();
    const calendar28 = Array.from({length: 28}, (_, index) => ({day: index + 1,
        is_today: index === 3 ? 1 : 0, status: index < 3 ? 'claimed' : index === 3 ? 'claimable' : 'not_open',
        rewards: f.rewards[index % 7].rewards.map(item => ({...item}))}));
    const snapshot = {ok: true, sequence: 1, today: 25004, period_id: '0', count: 3,
        ordinary_status: 'claimable', pending: 0, has_pass: 0, purchase_enabled: 1,
        price: '20元', duration_days: 30, makeup_days: 30, missed: [], calendar28,
        calendar_current_day: 4, calendar_start_count: 0, specials: f.specials,
        premium: {status: 'unconfigured'}, rule_text: '北京时间每日05:00刷新',
        benefits: {daily_time: group('daily_time', [30, 60, 90, 120, 150], 60, [1, 1, 1, 2, 2]),
            daily_wins: group('daily_win', [1, 2, 3, 4, 5], 1, [1, 1, 1, 1, 2]),
            weekly_time: group('weekly_time', [120, 240, 360, 480, 600, 720, 840, 960, 1080], 240, [2, 3, 4, 5, 5, 5, 5, 5, 5])}};
    const zongzi = count => ({id: 'welfare_zongzi', name: '粽子', count, description: '可叠加属性道具'});
    const ember = count => ({id: 'lottery_ember_of_legacy', name: '薪火余烬', count, description: '新的可叠加薪火属性'});
    snapshot.benefits.daily_time.rows[3].base_rewards = [ordinary(2), zongzi(1)];
    snapshot.benefits.daily_time.rows[3].monthly_rewards = [ordinary(2), zongzi(1)];
    snapshot.benefits.daily_time.rows[4].base_rewards = [ordinary(2), zongzi(2), ember(1)];
    snapshot.benefits.daily_time.rows[4].monthly_rewards = [ordinary(2), zongzi(2), ember(2), gold(1)];
    snapshot.benefits.daily_wins.rows[2].monthly_rewards = [ordinary(1), gold(1)];
    snapshot.benefits.daily_wins.rows[3].monthly_rewards = [];
    snapshot.benefits.daily_wins.rows[4].monthly_rewards = [gold(1)];
    return snapshot;
}
const h = setup(), {nodes, cfg} = h;
cfg.SurvivalDaily.Open(false);
h.click(nodes.DailyGW2Tab_daily);
assert.equal(cfg.SurvivalDaily.Inspect().page, 'daily');
assert.equal(nodes.DailyCards.visible, false, 'Calendar cannot intercept daily benefit input');
assert.equal(nodes.DailyGW2Benefits_daily.visible, true);
assert.equal(h.sent.filter(event => event.name === 'survival_benefit_claim').length, 0,
    'Opening or switching pages never grants a reward');
let next = snapshot();
h.emit('survival_daily_snapshot', next);
assert.equal(nodes.DailyGW2BenefitGroup_daily_time.GetChildCount(), 7, 'Two headers and all five time tiers');
assert.equal(nodes.DailyGW2BenefitGroup_daily_wins.GetChildCount(), 7, 'Two headers and all five victory tiers');
assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_30.enabled, true);
assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_90.enabled, false);
assert.equal(nodes.DailyGW2FooterText.text.includes('北京时间每日 05:00'), true);
const lastTime = nodes.DailyGW2Benefit_daily_time_daily_time_150;
const icons = lastTime.Children().filter(node => node.BHasClass('DailyGW2BenefitReward'));
assert.equal(icons.length, 7, '150 minutes shows all three base and four monthly additive rewards');
assert.equal(lastTime.__benefitRow.monthly_rewards.find(item => item.id === 'special_lottery_ticket').count, 1);
for (const [tier, extra] of [[3, 2], [4, 0], [5, 1]]) {
    const row = nodes['DailyGW2Benefit_daily_wins_daily_win_' + tier];
    assert.equal(row.Children().filter(node => node.BHasClass('DailyGW2BenefitMonthlyReward')).length, extra, 'Each victory tier renders only the actual monthly extras, including no extras at four wins');
}
assert(icons.some(node => node.__dailyGW2Tooltip.body.includes('新的可叠加薪火属性')),
    'The server description is used for the newly stackable ember');
assert(icons.every(node => !/只能拥有1|转化为.*积分/.test(node.__dailyGW2Tooltip.body)),
    'The old unique ember conversion text is not borrowed into a benefit reward');
for (const icon of icons) {
    const xy = icon.GetPositionWithinWindow(), card = lastTime.GetPositionWithinWindow();
    assert(xy.x >= card.x && xy.x + parseFloat(icon.style.width) < card.x + 520,
        'All four monthly reward icons fit before the claim button');
    assert(xy.y >= card.y && xy.y + parseFloat(icon.style.height) <= card.y + 108);
}
h.click(nodes.DailyGW2BenefitClaim_daily_time_daily_time_30);
assert.deepEqual(JSON.parse(JSON.stringify(h.sent.at(-1))), {name: 'survival_benefit_claim', payload: {track: 'daily_time', tier_id: 'daily_time_30'}});
assert.equal(cfg.SurvivalDaily.Inspect().benefitWaiting, true);
assert.equal(nodes.DailyClaim.enabled, false, 'The login action also waits for the in-flight benefit write');
assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_60.enabled, false, 'All tier actions wait for the server response');
const sent = h.sent.length;
h.click(nodes.DailyGW2BenefitClaim_daily_time_daily_time_60);
assert.equal(h.sent.length, sent);
next = {...next, sequence: 2, pending: 1, benefit_claim_result: {track: 'daily_time', tier_id: 'daily_time_30', ok: true, pending: true}};
h.emit('survival_daily_snapshot', next);
assert.equal(cfg.SurvivalDaily.Inspect().benefitWaiting, true, 'An accepted pending write is not a saved claim');
next = {...next, sequence: 3, pending: 0, benefit_claim_result: {track: 'daily_time', tier_id: 'daily_time_30', ok: false, error: '存档暂时不可用'}};
h.emit('survival_daily_snapshot', next);
assert.equal(cfg.SurvivalDaily.Inspect().benefitWaiting, false);
assert.equal(nodes.DailyNotice.text, '存档暂时不可用');
assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_30.enabled, true, 'A failed claim remains retryable');
h.click(nodes.DailyGW2BenefitClaim_daily_time_daily_time_30);
next = JSON.parse(JSON.stringify(next)); next.sequence = 4;
next.benefits.daily_time.rows[0].status = 'claimed'; next.benefits.daily_time.rows[0].can_claim = 0;
next.benefit_claim_result = {track: 'daily_time', tier_id: 'daily_time_30', ok: true, pending: false};
h.emit('survival_daily_snapshot', next);
assert.equal(cfg.SurvivalDaily.Inspect().benefitWaiting, false);
assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_30.enabled, false);
assert(nodes.DailyGW2Benefit_daily_time_daily_time_30.BHasClass('DailyGW2BenefitClaimed'));
const claimedCard = nodes.DailyGW2Benefit_daily_time_daily_time_30;
h.emit('survival_daily_snapshot', {...next, sequence: 5});
assert.equal(nodes.DailyGW2Benefit_daily_time_daily_time_30, claimedCard, 'Identical polls retain card identity and hover');
h.click(nodes.DailyGW2Tab_weekly);
assert.equal(nodes.DailyGW2Benefits_daily.visible, false);
assert.equal(nodes.DailyGW2Benefits_weekly.visible, true);
assert.equal(nodes.DailyGW2Benefits_weekly.Children().filter(node => node.BHasClass('DailyGW2BenefitCard')).length, 9);
assert(nodes.DailyGW2FooterText.text.includes('北京时间每周一 05:00'));
assert(nodes.DailyGW2Benefits_weekly.Children().some(node => /双倍.*最后三档.*金色抽奖券/.test(node.text)),
    'Weekly page explains doubled base and gold only in the last three tiers');
for (const minute of [120, 240, 360, 480, 600, 720, 840, 960, 1080]) {
    const row = nodes['DailyGW2Benefit_weekly_time_weekly_time_' + minute];
    assert.equal(row.Children().filter(node => node.BHasClass('DailyGW2BenefitMonthlyReward')).length, minute >= 840 ? 2 : 1);
}
h.click(nodes.DailyGW2Tab_login);
assert.equal(nodes.DailyGW2Title.text, '登录奖励');
assert.equal(nodes.DailyCards.visible, true);
assert.equal(nodes.DailyCards.GetChildCount(), 28);
assert.equal(nodes.DailyGW2Benefits_weekly.visible, false);
h.click(nodes.DailyGW2Tab_daily);
h.click(nodes.DailyGW2BenefitClaim_daily_time_daily_time_60);
next = snapshot(); next.sequence = 6; next.benefits.daily_time.period_id = '2026-10-22-05';
next.benefits.daily_time.progress = 0; next.benefits.daily_time.rows.forEach(row => {row.status = 'locked'; row.can_claim = 0;});
h.emit('survival_daily_snapshot', next);
assert.equal(cfg.SurvivalDaily.Inspect().benefitWaiting, false, '05:00 rollover clears the stale pending tier intent');
assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_60.enabled, false);
cfg.SurvivalDaily.Close(); cfg.SurvivalDaily.Open(false);
assert.equal(cfg.SurvivalDaily.Inspect().page, 'daily', 'Closing and reopening keeps the selected welfare page');
cfg.SurvivalDaily.Open(true);
assert.equal(cfg.SurvivalDaily.Inspect().page, 'login', 'Opening the monthly purchase entry returns to its existing panel');
h.assertCleanDispose(cfg.SurvivalDaily);
console.log('daily benefits: tabs, 19 tiers, server authority, claim failures, polling and 05:00 rollover passed');
