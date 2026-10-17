"use strict";

// Exercise the production storefront, renderer, dismissal policy and controller.
// This fixture performs no account requests, payments or native-game input.
const test = require("node:test");
const assert = require("node:assert/strict");
const {harness} = require("../shop_catalog_20261016/harness.cjs");

function product(sku, extra = {}) {
    return {sku, title: sku, category_id: "item", product_type: "single",
        icon: "items/rapier.png", enabled: true, owned: 0, purchase_limit: 0,
        currency: "u_coin", amount_fen: 100, u_coin_price: 1000,
        u_coin_per_yuan: 1000, description: "攻击力 +10", reward_lines: [], ...extra};
}
function setup(products = [product("item-a"), product("item-b")]) {
    const h = harness({paid: {catalog_hash: "ICON_HOVER_FIXTURE", products, categories: []},
        presentation: {groups: {home: []}}});
    h.load("../../../../tools/shop_icon_hover_20261017/cursor_fixture.js");
    h.load("common/tooltip_dismiss.js");
    h.cfg.SurvivalCommerceView.Open();
    assert(h.cfg.SurvivalCommerceView.SelectCategory("all"));
    return h;
}
function icon(h, row) { return h.descendants(row, "BLMarketArt")[0]; }
function visible(row) { return row.__purpleDetail.BHasClass("Visible"); }
function event(node, name) { if (node && node.events[name]) return node.events[name](); }
function pendingLeave(h) {
    return h.timers.filter(timer => !timer.cancelled && timer.delay === .12).at(-1);
}

test("Only the icon well owns product tooltip entry events", () => {
    const h = setup(), row = h.cardList()[0], well = icon(h, row);
    const name = h.descendants(row, "BLMarketName")[0];
    const price = h.descendants(row, "BLMarketRowPrice")[0];
    const buy = h.descendants(row, "BLMarketBuy")[0];
    assert.equal(typeof well.events.onmouseover, "function");
    assert.equal(row.__purpleDetail.__purpleSource, well, "The dismissal policy tracks the icon surface");
    for (const node of [row, name, price, buy]) {
        assert.equal(node.events.onmouseover, undefined, "Non-icon regions cannot open product detail");
        event(node, "onmouseover");
        assert.equal(visible(row), false);
    }
    assert.notEqual(well.hittest, false, "The icon surface receives native mouse input");
    event(well, "onmouseover");
    assert(visible(row));
    assert(row.BHasClass("ShopSelected"), "Selection remains on the complete row");
    event(well, "onmouseout");
    assert.equal(visible(row), false, "Moving to a product name or empty row hides short detail");
    event(row, "onactivate");
    assert.equal(visible(row), false, "Clicking empty row cannot open detail");
    event(buy, "onactivate");
    assert.deepEqual(h.paidCheckouts, ["item-a"], "The purchase action still checks out the actual SKU");
    assert.equal(visible(row), false, "The purchase button does not show detail");
});

test("Moving between product icons replaces the active detail; row gaps do not reopen it", () => {
    const h = setup(), [first, second] = h.cardList();
    event(icon(h, first), "onmouseover");
    assert(visible(first));
    event(icon(h, first), "onmouseout");
    event(second, "onmouseover");
    assert.equal(visible(first), false);
    assert.equal(visible(second), false);
    event(icon(h, second), "onmouseover");
    assert(visible(second));
    assert.equal(visible(first), false);
});

test("Closing and reopening recreates details without losing icon-only entry or row lifecycle hooks", () => {
    const h = setup(), row = h.cardList()[0], oldTip = row.__purpleDetail;
    event(icon(h, row), "onmouseover");
    h.cfg.SurvivalCommerceView.Close();
    assert.equal(oldTip.IsValid(), false, "Close disposes detached detail panels");
    event(icon(h, row), "onmouseover");
    assert.equal(oldTip.IsValid(), false, "Stale icon callbacks cannot revive a disposed detail");
    h.cfg.SurvivalCommerceView.Open();
    assert.equal(h.cardList()[0], row, "A stable catalog keeps the row and its icon");
    assert.notEqual(row.__purpleDetail, oldTip);
    assert(row.__purpleDetail.IsValid());
    assert.equal(row.events.onmouseover, undefined);
    event(icon(h, row), "onmouseover");
    assert(visible(row), "The rebuilt icon entry points to the new detail");
});

test("Numeric refresh preserves the hovered icon while a product revision retires stale detail", () => {
    const initial = product("item-a"), h = setup([initial]), row = h.cardList()[0];
    const oldIcon = icon(h, row);
    event(oldIcon, "onmouseover");
    h.updatePaid({catalog_hash: "ICON_HOVER_FIXTURE", products: [{...initial, stat_preview: [{value: 999}]}], categories: []});
    assert.equal(h.cardList()[0], row);
    assert(visible(row), "Nonstructural refresh does not interrupt the inspected product");
    const oldTip = row.__purpleDetail;
    h.updatePaid({catalog_hash: "ICON_HOVER_FIXTURE", products: [{...initial, description: "攻击力 +20"}], categories: []});
    assert.equal(oldTip.IsValid(), false);
    const replacement = h.cardList()[0];
    assert.notEqual(replacement, row);
    event(oldIcon, "onmouseover");
    assert.equal(visible(replacement), false, "Deleted-row handlers cannot open the replacement");
    event(icon(h, replacement), "onmouseover");
    assert(visible(replacement));
    assert.equal(h.descendants(replacement.__purpleDetail, "RCProductEffect")[0].text, "攻击力 +20");
});

test("A long detail remains reachable for scrolling and hides after leaving its surface", () => {
    const h = setup(), row = h.cardList()[0], tip = row.__purpleDetail;
    const content = h.descendants(tip, "MenuV10CommerceDetailContent")[0];
    const well = icon(h, row), surface = h.descendants(tip, "BLMarketDetailSurface")[0];
    const scrollBody = h.descendants(tip, "MenuV10CommerceDetailBody")[0];
    row.actuallayoutwidth = 1072; row.actuallayoutheight = 96;
    well.actuallayoutwidth = 74; well.actuallayoutheight = 74;
    surface.GetPositionWithinWindow = () => ({x: 900, y: 240});
    surface.actuallayoutwidth = 368; surface.actuallayoutheight = 600;
    h.cfg.__shopIconHoverTestPointer = [460, 250];
    content.actuallayoutheight = 2000;
    event(well, "onmouseover");
    assert(tip.BHasClass("Scrollable"));
    assert.equal(tip.hittestchildren, true);
    event(well, "onmouseout");
    const leavingIcon = pendingLeave(h);
    assert(leavingIcon, "The pointer can cross the small icon-to-tooltip gap");
    h.cfg.__shopIconHoverTestPointer = [910, 250];
    event(surface, "onmouseover");
    leavingIcon.fn();
    assert(visible(row), "Tooltip padding also retains the long detail via its actual pointer bounds");
    event(well, "onmouseout");
    const nextLeave = pendingLeave(h);
    event(scrollBody, "onmouseover");
    assert(nextLeave.cancelled, "Entering scroll content cancels delayed dismissal");
    assert(visible(row));
    h.cfg.__shopIconHoverTestPointer = [600, 250];
    event(scrollBody, "onmouseout");
    pendingLeave(h).fn();
    assert.equal(visible(row), false, "A pointer inside the product row but outside its icon cannot retain detail");
});

test("The new-player bundle still allows its four internal reward selectors", () => {
    const rewards = ["video_p030", "video_p031", "video_p032", "video_p033"].map((id, index) => ({
        id, kind: "item", label: "礼包物品 " + index, description: "物品效果 " + index
    }));
    const h = setup([product("video_bundle_b003", {product_type: "bundle", reward_lines: rewards})]);
    assert(h.cfg.SurvivalCommerceView.SelectCategory("bundles"));
    const row = h.cardList()[0], tip = row.__purpleDetail;
    event(icon(h, row), "onmouseover");
    assert(tip.BHasClass("BLMarketBundleDetail"));
    const buttons = h.descendants(tip, "BLMarketBundleMember");
    const selected = h.descendants(tip, "RCBundleMemberEffect")[0];
    assert.equal(buttons.length, 4);
    assert.equal(selected.text, "物品效果 2");
    event(icon(h, row), "onmouseout");
    const leavingIcon = pendingLeave(h);
    event(buttons[0], "onmouseover");
    assert(leavingIcon.cancelled);
    assert.equal(selected.text, "物品效果 0");
    assert(visible(row));
    event(buttons[3], "onactivate");
    assert.equal(selected.text, "物品效果 3");
    assert(visible(row));
    assert.equal(h.paidCheckouts.length, 0, "Inspecting a bundle member never purchases it");
    h.cfg.SurvivalCommerceView.Close();
    assert.equal(tip.IsValid(), false);
});

test("Consumers without an explicit hover surface retain their complete-card behavior", () => {
    const h = setup(), J = h.cfg.SurvivalCommerceComponents;
    let actions = 0;
    const card = J.Product(h.root, product("legacy-card"), {detailLayer: h.store().detailLayer,
        menu: h.store().menu, action() { actions++; }});
    assert.equal(card.__purpleDetail.__purpleSource, card);
    assert.equal(typeof card.events.onmouseover, "function");
    event(card, "onmouseover");
    assert(visible(card));
    event(card, "onmouseout");
    assert.equal(visible(card), false);
    event(card, "onactivate");
    assert.equal(actions, 1, "Legacy card activation still invokes its supplied action");
    assert(visible(card));
    card.__purpleDispose();
});

test("An explicit icon surface preserves complete-card ownership through detail rebuilding", () => {
    const h = setup(), Panel = h.root.constructor;
    const card = new Panel("Panel", h.root), well = new Panel("Panel", card);
    const tip = h.cfg.SurvivalCommerceComponents.BindDetail(card, product("explicit-source"), {
        market: true, hoverPanel: well, sourcePanel: well, sourceWidth: 64,
        detailLayer: h.store().detailLayer, menu: h.store().menu
    }, false);
    assert.equal(card.events.onmouseover, undefined);
    assert.equal(tip.__purpleSource, well);
    event(well, "onmouseover");
    assert(visible(card));
    assert(card.BHasClass("ShopSelected"));
    assert.equal(well.BHasClass("ShopSelected"), false);
    card.__purpleDispose();
    assert.equal(tip.IsValid(), false);
    const rebuilt = card.__purpleRebuildDetail();
    assert.notEqual(rebuilt, tip);
    assert.equal(card.__purpleDetail, rebuilt);
    event(well, "onmouseover");
    assert(visible(card));
    card.__purpleDispose();
});
