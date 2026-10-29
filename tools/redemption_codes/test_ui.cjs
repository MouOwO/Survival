'use strict';
const assert = require('node:assert/strict'), test = require('node:test');
const {harness} = require('../shop_catalog_20261016/harness.cjs');
function setup() {
    const h = harness(); h.cfg.SurvivalCommerceView.Open();
    const menu = h.cfg.SurvivalBlackLionMarket.GetWindow();
    const input = h.root.FindChildTraverse('RedemptionCodeInput');
    const host = h.root.FindChildTraverse('RedemptionDialogHost');
    const submit = h.root.FindChildTraverse('RedemptionSubmit');
    const requests = () => h.requests.filter(r => r.payload.action === 'redeem');
    return {h, menu, input, host, submit, requests};
}
test('header reuses purchase button; official input validates and cancellation sends nothing', () => {
    const {h, menu, input, host, requests} = setup();
    const entry = h.root.FindChildTraverse('BlackLionMarketRedeem');
    assert(entry.BHasClass('BLMarketBuy') && entry.BHasClass('ButtonPrimary'));
    entry.events.onactivate(); assert(host.visible && input.focused);
    input.text = '错误'; menu.SubmitRedeem();
    assert.equal(requests().length, 0);
    assert.equal(h.clientEvents.at(-1).name, 'dota_hud_error_message');
    assert.match(h.clientEvents.at(-1).payload.message, /兑换码错误/);
    menu.CloseRedeem(); assert.equal(host.visible, false);
});
test('inflight clicks deduplicate and cancelled dialog stays closed on success', () => {
    const {h, menu, input, host, submit, requests} = setup();
    menu.OpenRedeem(); input.text = ' gc-test-code '; submit.events.onactivate();
    menu.SubmitRedeem(); assert.equal(requests().length, 1);
    const sent = requests()[0].payload;
    assert.equal(sent.code, 'GC-TEST-CODE'); assert.equal(input.enabled, false);
    assert.equal(sent.rewards, undefined); assert.equal(sent.account_id, undefined);
    menu.CloseRedeem();
    h.emit('survival_commerce_result', {action:'redeem', request_id:sent.request_id, ok:true});
    assert.equal(host.visible, false); assert.equal(submit.enabled, true);
    assert.equal(h.cfg.SurvivalRedemptionPending, undefined);
});
test('unknown outcomes retry the same request; stale and unrelated replies cannot finish it', () => {
    const {h, menu, input, host, requests} = setup();
    menu.OpenRedeem(); input.text = 'GC-TEST-CODE'; menu.SubmitRedeem();
    const first = requests()[0].payload;
    h.emit('survival_commerce_result', {action:'purchase', request_id:first.request_id, ok:true});
    h.emit('survival_commerce_result', {action:'redeem', request_id:'wrong_request', ok:true});
    assert.equal(input.enabled, false);
    h.advanceTimers(105); assert.equal(input.enabled, true);
    menu.SubmitRedeem(); assert.equal(requests()[1].payload.request_id, first.request_id);
    h.emit('survival_commerce_result', {action:'redeem', request_id:first.request_id, ok:false,
        terminal:true, error:'redeem_already_used'});
    assert(host.visible); assert.equal(input.enabled, true);
    assert.match(h.clientEvents.at(-1).payload.message, /已使用过/);
    assert.equal(h.cfg.SurvivalRedemptionPending, undefined);
});
