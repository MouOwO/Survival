const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../..');
const output = 'panorama/src/scripts/custom_game/benefit_presentation_data.js';
const read = name => fs.readFileSync(path.join(root, name), 'utf8');

// Read the maintained CSV independently of the Python generator. Fields may be
// quoted and may contain commas or newlines; metadata records start with #.
function csv(source) {
    const rows = [], row = [];
    let text = '', quoted = false;
    for (let i = 0; i < source.length; i++) {
        const char = source[i];
        if (char === '"') {
            if (quoted && source[i + 1] === '"') { text += '"'; i++; }
            else quoted = !quoted;
        } else if (!quoted && (char === ',' || char === '\n')) {
            row.push(text.replace(/\r$/, '')); text = '';
            if (char === '\n') { rows.push(row.splice(0)); }
        } else text += char;
    }
    assert.equal(quoted, false, 'CSV quotes must close');
    if (text || row.length) { row.push(text.replace(/\r$/, '')); rows.push(row); }
    const header = rows.shift();
    return rows.filter(values => values[0] && !values[0].startsWith('#')).map(values =>
        Object.fromEntries(header.map((key, index) => [key, values[index] || ''])));
}

function definitions() {
    const cfg = { dailySnapshot: { progress: 42, can_claim: 1 } };
    vm.runInNewContext(read(output), { GameUI: { CustomUIConfig: () => cfg } });
    return cfg;
}

test('preview definitions match every enabled authoritative reward tier and quantity', () => {
    const data = definitions().SurvivalBenefitDefinitions;
    const actual = Object.values(data.tracks).flat();
    const configured = csv(read('data/csv/存档系统/archive_benefit_rewards.csv')).filter(row => row.enabled === '1');
    assert.equal(actual.length, configured.length);
    const rewards = (ids, counts) => ids ? ids.split('|').map((id, i) => ({ id, count: Number(counts.split('|')[i]) })) : [];
    for (const row of configured) {
        const preview = data.tracks[row.track].find(item => item.id === row.reward_id);
        assert.ok(preview, row.reward_id);
        assert.equal(preview.required, Number(row.required));
        assert.equal(preview.monthly_only, row.monthly_only === '1');
        assert.equal(preview.auto_claim, row.auto_claim === '1');
        for (const [field, ids, counts] of [
            ['base_rewards', row.base_item_ids, row.base_counts],
            ['monthly_rewards', row.pass_item_ids, row.pass_counts],
        ]) {
            assert.deepEqual(JSON.parse(JSON.stringify(preview[field].map(({ id, count }) => ({ id, count })))), rewards(ids, counts));
        }
    }
});

test('preview names resolve resource aliases and stackable descriptions take precedence', () => {
    const items = JSON.parse(read('data/ui/item_resources.json')).items;
    const resources = new Map(items.flatMap(item => [item.id, ...item.aliases].map(id => [id, item])));
    const stackables = csv(read('data/csv/存档系统/archive_stackable_items.csv')).filter(row => row.enabled === '1');
    const previews = Object.values(definitions().SurvivalBenefitDefinitions.tracks).flat()
        .flatMap(row => [...row.base_rewards, ...row.monthly_rewards]);
    for (const item of previews) {
        const resource = resources.get(item.id);
        assert.ok(resource, item.id);
        const property = (csvKey, jsonKey) => stackables.find(row => row.item_id === item.id && row[csvKey])?.[csvKey] || resource[jsonKey] || '';
        assert.equal(item.name, property('display_name', 'name'));
        assert.equal(item.description, property('description', 'description'));
        assert.equal(item.quality, property('quality', 'quality').toUpperCase());
    }
    assert.equal(previews.find(item => item.id === 'special_lottery_ticket').name, '金色抽奖券');
    assert.equal(previews.find(item => item.id === 'lottery_ticket').name, '普通抽奖券');
    const ember = previews.find(item => item.id === 'lottery_ember_of_legacy');
    assert.match(ember.description, /无持有上限/);
    assert.match(ember.description, /不会转化为积分/);
    assert.doesNotMatch(ember.description, /1000商城积分|最多拥有1份/);
});

test('preview is deeply read-only and cannot supply eligibility or overwrite server data', () => {
    const cfg = definitions(), data = cfg.SurvivalBenefitDefinitions;
    assert.deepEqual(cfg.dailySnapshot, { progress: 42, can_claim: 1 });
    function verify(value) {
        if (!value || typeof value !== 'object') return;
        assert.ok(Object.isFrozen(value));
        for (const key of Object.keys(value)) {
            assert.ok(!['status', 'can_claim', 'progress', 'claimed', 'period_id', 'has_pass'].includes(key), key);
            verify(value[key]);
        }
    }
    verify(data);
    assert.throws(() => data.tracks.daily_time.push({ can_claim: 1 }));
});

test('archive loads display definitions before the welfare renderer', () => {
    const archive = read('panorama/src/layout/custom_game/archive.xml');
    const preview = archive.indexOf('/scripts/custom_game/benefit_presentation_data.js');
    const renderer = archive.indexOf('/scripts/custom_game/daily_remaining_5d5c1152eb.js');
    assert.ok(preview > 0 && preview < renderer);
    assert.equal(archive.match(/\/scripts\/custom_game\/benefit_presentation_data\.js/g).length, 1);
});

test('real generated definitions fill missing welfare data without enabling claims; a server snapshot restores claiming', () => {
    const { createHarness } = require('./fixtures/menus_v10_harness.cjs');
    const { fixture } = require('../daily_gw2/fixture.cjs');
    const h = createHarness();
    for (const source of ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js',
        'common/item_resources.js', 'archive_theme_tokens.js', 'archive_parchment_data.js',
        'archive_handoff_180de7e38b.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js',
        'reward_presentation.js', 'item_art_remaining_5d5c1152eb.js',
        'daily_gw2_data.js', 'benefit_presentation_data.js', 'daily_remaining_5d5c1152eb.js']) h.load(source);
    const { cfg, nodes } = h;
    const claims = () => h.sent.filter(event => event.name === 'survival_benefit_claim');
    cfg.SurvivalDaily.Open(false);
    cfg.SurvivalDaily.SelectPage('daily');
    const cards = track => Object.values(nodes).filter(node => node.BHasClass('DailyGW2BenefitCard') && node.id.startsWith('DailyGW2Benefit_' + track + '_'));
    for (const [track, count] of [['daily_time', 6], ['daily_wins', 5]]) {
        assert.equal(cards(track).length, count);
        for (const row of cfg.SurvivalBenefitDefinitions.tracks[track]) {
            const button = nodes['DailyGW2BenefitClaim_' + track + '_' + row.id];
            assert.equal(button.enabled, false);
            h.click(button);
        }
    }
    assert.equal(claims().length, 0);
    cfg.SurvivalDaily.SelectPage('weekly');
    assert.equal(cards('weekly_time').length, 9);
    for (const row of cfg.SurvivalBenefitDefinitions.tracks.weekly_time) {
        const button = nodes['DailyGW2BenefitClaim_weekly_time_' + row.id];
        assert.equal(button.enabled, false);
        h.click(button);
    }
    const f = fixture();
    const snapshot = { ok: true, sequence: 1, today: 25004, period_id: '0', count: 3,
        ordinary_status: 'claimable', pending: 0, has_pass: 1, purchase_enabled: 1,
        price: '20元', duration_days: 30, makeup_days: 30, missed: [],
        calendar28: Array.from({ length: 28 }, (_, index) => ({ day: index + 1,
            status: 'not_open', rewards: f.rewards[index % 7].rewards })),
        calendar_current_day: 4, calendar_start_count: 0, specials: f.specials,
        premium: { status: 'unconfigured' } };
    h.emit('survival_daily_snapshot', snapshot);
    cfg.SurvivalDaily.SelectPage('daily');
    assert.equal(cards('daily_time').length, 6, 'A legacy snapshot without benefits keeps the real definitions');
    assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_0.enabled, false,
        'Knowing monthly-card ownership still cannot authorize a preview claim');
    assert.equal(claims().length, 0);
    snapshot.sequence = 2;
    snapshot.benefits = Object.fromEntries(Object.entries(cfg.SurvivalBenefitDefinitions.tracks).map(([track, rows]) => [track, {
        period_id: '2026-10-21-05', progress: 0,
        rows: JSON.parse(JSON.stringify(rows)).map(row => ({ ...row,
            status: row.id === 'daily_time_0' ? 'claimable' : 'locked',
            can_claim: row.id === 'daily_time_0' ? 1 : 0 }))
    }]));
    h.emit('survival_daily_snapshot', snapshot);
    assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_0.enabled, true);
    assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_30.enabled, false);
    assert.equal(claims().length, 0, 'Receiving authority never auto-claims');
    h.click(nodes.DailyGW2BenefitClaim_daily_time_daily_time_0);
    assert.equal(claims().length, 1);
    assert.deepEqual(JSON.parse(JSON.stringify(claims()[0].payload)), { track: 'daily_time', tier_id: 'daily_time_0' });
    assert.equal(nodes.DailyGW2BenefitClaim_daily_time_daily_time_0.enabled, false);
    h.assertCleanDispose(cfg.SurvivalDaily);
});
