const assert = require('node:assert/strict');
const test = require('node:test');
const {createHarness} = require('./fixtures/menus_v10_harness.cjs');

test('Daily pass price prefers the validated live quote and retains daily-snapshot fallback and entitlement authority', () => {
    const h = createHarness(), {cfg, nodes} = h;
    for (const source of ['archive_theme_tokens.js', 'archive_parchment_data.js',
        'archive_handoff_180de7e38b.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js',
        'daily_gw2_data.js', 'daily_remaining_5d5c1152eb.js']) h.load(source);
    let catalog;
    cfg.SurvivalPayments = {GetCatalog() { return catalog; }};
    cfg.SurvivalDaily.Open(false);
    let sequence = 0;
    const send = extra => h.emit('survival_daily_snapshot', {ok:true, sequence:++sequence,
        today:25004, period_id:'month-price', count:0, ordinary_status:'not_open', pending:0,
        has_pass:0, purchase_enabled:0, price:'10元', duration_days:30, makeup_days:30,
        missed:[], cycle:[], specials:[], premium:{status:'unconfigured'}, ...extra});
    send();
    assert.equal(nodes.PassPrice.text, '30天 · 10元', 'A missing payment catalog keeps the daily snapshot');
    const product = {sku:'archive_pass_monthly', amount_fen:5800, u_coin_price:5800, u_coin_per_yuan:100};
    catalog = {products:[product]};
    send();
    assert.equal(nodes.PassPrice.text, '30天 · 58元', 'A cached 10-yuan daily module cannot override the live payment quote');
    assert.equal(nodes.PassPurchase.enabled, false, 'A price cannot grant permission to buy');
    assert.equal(cfg.SurvivalDaily.Inspect().hasPass, false, 'A price cannot grant the monthly entitlement');
    for (const invalid of [{u_coin_per_yuan:1000}, {u_coin_price:5801}, {amount_fen:'5800'},
        {amount_fen:0}, {amount_fen:-5800}, {amount_fen:5800.5}, {sku:'different_product'}]) {
        catalog = {products:[{...product, ...invalid}]};
        send();
        assert.equal(nodes.PassPrice.text, '30天 · 10元', 'Invalid or unrelated quotes retain the authoritative daily fallback');
    }
    catalog = {products:[]};
    send({price:'58元'});
    assert.equal(nodes.PassPrice.text, '30天 · 58元', 'A new map with updated rules also works without a payment quote');
    assert(!h.sent.some(request => /claim|purchase|payment/.test(request.name)), 'Rendering prices sends no financial or reward request');
    cfg.SurvivalDaily.Dispose();
});
