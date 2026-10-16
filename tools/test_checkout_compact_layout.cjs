"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

// Use the production XML controls and shared modal rather than a checkout-shaped mock.
function harness() {
    const ids = {}, requests = [], urls = [], handlers = {}, timers = new Map();
    let serial = 0, now = 0, top = null;
    class Panel {
        constructor(type, parent, id) {
            this.type = this.paneltype = type; this.id = id || ""; this.parent = null;
            this.children = []; this.classes = new Set(); this.style = {}; this.events = {};
            this.visible = true; this.enabled = true; this.text = "";
            this.actualuiscale_x = this.actualuiscale_y = 1;
            this.SetParent(parent); if (id) ids[id] = this;
        }
        AddClass(c) { this.classes.add(c); }
        RemoveClass(c) { this.classes.delete(c); }
        BHasClass(c) { return this.classes.has(c); }
        SetHasClass(c, value) { value ? this.AddClass(c) : this.RemoveClass(c); }
        SetPanelEvent(name, fn) { this.events[name] = fn; }
        Children() { return this.children; }
        GetParent() { return this.parent; }
        GetChildCount() { return this.children.length; }
        GetChild(i) { return this.children[i]; }
        SetParent(parent) {
            if (this.parent) this.parent.children = this.parent.children.filter(p => p !== this);
            this.parent = parent;
            if (parent) parent.children.push(this);
        }
        FindChildTraverse(id) { return this.id === id ? this : this.children.map(p => p.FindChildTraverse(id)).find(Boolean); }
        GetPositionWithinWindow() { return { x: 0, y: 0 }; }
        SetImage(value) { this.image = value; }
        SetScaling() {}
        SetAcceptsFocus() {}
        IsValid() { return !this.deleted; }
        RemoveAndDeleteChildren() { this.children.slice().forEach(p => p.DeleteAsync()); }
        DeleteAsync() { this.children.slice().forEach(p => p.DeleteAsync()); this.deleted = true; this.SetParent(null); }
    }
    const root = new Panel("Panel", null, "CheckoutTestRoot");
    root.actuallayoutwidth = 1600; root.actuallayoutheight = 900;
    function $(id) { return ids[id.slice(1)] || null; }
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.GetContextPanel = () => root;
    $.Schedule = (delay, fn) => { const id = ++serial; timers.set(id, { at: now + delay, fn }); return id; };
    $.CancelScheduled = id => timers.delete(id);
    $.Msg = () => {};
    $.DispatchEvent = (name, value) => { if (name === "ExternalBrowserGoToURL") urls.push(value); };
    const cfg = { SurvivalUILayers: {
        Open: id => { top = id; }, Close: id => { if (top === id) top = null; }, Top: () => top
    } };
    const env = { $, GameUI: { CustomUIConfig: () => cfg }, Game: {},
        GameEvents: { Subscribe: (name, fn) => { handlers[name] = fn; return name; }, Unsubscribe: () => {},
            SendCustomGameEventToServer: (name, data) => requests.push({ ...data }) } };
    vm.createContext(env);
    const stack = [root], xml = fs.readFileSync("panorama/src/layout/custom_game/payment_test.xml", "utf8");
    for (const tag of xml.matchAll(/<(\/?)(Panel|Button|Label|Image|TextEntry)\b([^>]*)>/g)) {
        if (tag[1]) { stack.pop(); continue; }
        const attrs = Object.fromEntries([...tag[3].matchAll(/([\w-]+)="([^"]*)"/g)].map(x => [x[1], x[2]]));
        const panel = new Panel(tag[2], stack.at(-1), attrs.id);
        (attrs.class || "").split(/\s+/).filter(Boolean).forEach(c => panel.AddClass(c));
        if (attrs.text) panel.text = attrs.text;
        for (const attr of ["visible", "enabled", "hittest", "hittestchildren"]) if (attrs[attr]) panel[attr] = attrs[attr] !== "false";
        if (attrs.onactivate) panel.events.onactivate = () => vm.runInContext(attrs.onactivate, env);
        if (!/\/\s*$/.test(tag[3])) stack.push(panel);
    }
    require("./load_shared_ui_test.cjs")(env, Panel, root);
    const adopted = [], fits = [], U = cfg.SurvivalUI;
    const adopt = U.ModalShell.Adopt, fit = U.Fit;
    U.ModalShell.Adopt = props => { adopted.push(props); return adopt(props); };
    U.Fit = (...args) => { const scale = fit(...args); fits.push({ panel: args[0], width: args[2], height: args[3], scale }); return scale; };
    vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js", "utf8"), env);
    function advance(seconds) {
        const end = now + seconds;
        for (let count = 0; count < 1000; count++) {
            const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
            if (!next) { now = end; return; }
            timers.delete(next[0]); now = next[1].at; next[1].fn();
        }
        throw new Error("Checkout timer loop did not settle");
    }
    function respond(data) {
        const request = requests.at(-1); assert(request, "response must correspond to an actual request");
        handlers.survival_payment_result({ request_id: request.request_id, action: request.action, ...data });
    }
    return { ids, root, cfg, requests, urls, adopted, fits, advance, respond, top: () => top };
}

function findClass(panel, cls) {
    if (panel.BHasClass(cls)) return panel;
    for (const child of panel.Children()) { const found = findClass(child, cls); if (found) return found; }
    return null;
}
function visible(panel) {
    return !!panel && panel.visible !== false && panel.style.visibility !== "collapse" && panel.style.visibility !== "hidden" &&
        (!panel.parent || visible(panel.parent));
}
function px(value, description) {
    assert.match(String(value), /^-?\d+(?:\.\d+)?px$/, description + " has a concrete pixel size");
    return parseFloat(value);
}
function rect(panel) {
    assert(panel, "layout panel exists");
    const position = String(panel.style.position || "").trim().split(/\s+/);
    assert(position.length >= 2, (panel.id || [...panel.classes].join(" ")) + " has an explicit position");
    return { x: px(position[0], "x"), y: px(position[1], "y"),
        width: px(panel.style.width, "width"), height: px(panel.style.height, "height") };
}
function contained(panel, parent, label) {
    assert.equal(panel.parent, parent, label + " stays in its layout container");
    const r = rect(panel), p = rect(parent);
    assert(r.x >= 0 && r.y >= 0 && r.width > 0 && r.height > 0, label + " has a positive visible rectangle");
    assert(r.x + r.width <= p.width + .01 && r.y + r.height <= p.height + .01, label + " fits its container");
    return r;
}
function layoutFits(ui, stage) {
    const dialog = ui.ids.PaymentDialog, body = findClass(dialog, "PaymentBody");
    const bounds = rect(body), width = px(dialog.style.width, "dialog width"), height = px(dialog.style.height, "dialog height");
    assert.equal(width, 580, stage + " retains the compact popup width");
    assert(bounds.x >= 0 && bounds.y >= 0 && bounds.x + bounds.width <= width && bounds.y + bounds.height <= height,
        stage + " body fits the popup");
    const blocks = body.Children().filter(p => visible(p));
    assert(blocks.length > 0, stage + " has visible content");
    const rectangles = blocks.map(p => ({ panel: p, ...contained(p, body, stage + ": " + (p.id || [...p.classes].join(" "))) }));
    for (let i = 0; i < rectangles.length; i++) for (let j = i + 1; j < rectangles.length; j++) {
        const a = rectangles[i], b = rectangles[j];
        const intersects = Math.min(a.x + a.width, b.x + b.width) > Math.max(a.x, b.x) + .01 &&
            Math.min(a.y + a.height, b.y + b.height) > Math.max(a.y, b.y) + .01;
        assert(!intersects, stage + ": " + (a.panel.id || [...a.panel.classes]) + " overlaps " + (b.panel.id || [...b.panel.classes]));
    }
    const bottom = Math.max(...rectangles.map(r => r.y + r.height));
    assert(bounds.height - bottom <= 24, stage + " does not reserve a hidden content block below its controls");
    assert(height - (bounds.y + bottom) <= 36, stage + " popup height follows its visible content");
    assert.equal(ui.adopted.length, 1, "all checkout stages reuse one real ModalShell");
    assert.equal(ui.adopted[0].width, width);
    assert.equal(ui.adopted[0].height, height, stage + " updates the modal's fitting dimensions");
    ui.advance(.26);
    const fit = ui.fits.at(-1);
    assert(fit && fit.panel === dialog, stage + " uses the production fit function");
    assert.equal(fit.width, width); assert.equal(fit.height, height);
    assert(fit.scale > 0 && fit.scale * width <= ui.root.actuallayoutwidth && fit.scale * height <= ui.root.actuallayoutheight,
        stage + " remains inside the viewport after fitting");
    return height;
}

const ui = harness(), ids = ui.ids;
const product = { sku: "compact_bundle_test", title: "完整奖励礼包", description: "商品的奖励说明应保留在到账详情中。",
    amount_fen: 777, enabled: true, icon: "custom_game/archive_items_v2/lottery_lumber_crystal.png",
    reward_lines: [{ kind: "stat", id: "initial_wood", quantity: 100, label: "初始木材" },
        { kind: "entitlement", id: "vip", quantity: 1, label: "VIP权限" }],
    stat_preview: [{ field_id: "initial_wood", value: 10, after: 110, delta: 100 }] };
ui.cfg.SurvivalPayments.Checkout(product.sku);
assert.equal(ui.requests.at(-1).action, "catalog");
ui.respond({ ok: true, products: [product], wechat: 1, alipay: 1, game_values: { initial_wood: 10 }, wallet: { wood: 1000 } });
const dialog = ids.PaymentDialog, body = findClass(dialog, "PaymentBody"), summary = findClass(dialog, "PaymentSummary");
const quantity = findClass(dialog, "PaymentQuantity"), methods = findClass(dialog, "PaymentMethods"), footer = findClass(dialog, "PaymentFooter");
assert(dialog.BHasClass("LeanCheckout") || dialog.BHasClass("CompactCheckout"));
assert(!dialog.BHasClass("MenuV10Page"), "checkout opens directly in the compact modal");
assert.equal(ui.top(), "payment_shop");
const quantityInput = !!ids.PaymentQuantityInput;
const expectedAmount = (quantityInput ? "合计 " : "") + "¥7.77";
assert.equal(ids.PaymentTitle.text, product.title); assert.equal(ids.PaymentPrice.text, expectedAmount);
assert.equal(ids.PaymentProductArt.image, "file://{images}/" + product.icon);
for (const panel of [ids.PaymentUnitPrice, summary, ids.PaymentDescription, ids.PaymentValues, ids.PaymentHint, ids.PaymentStatus])
    assert(!visible(panel), "confirmation hides redundant unit price, reward copy and default notices");
for (const panel of [ids.PaymentProductArt, ids.PaymentTitle, ids.PaymentPrice, quantity, methods, footer, ids.PaymentWeChat, ids.PaymentAlipay, ids.PaymentBack, ids.PaymentBuy])
    assert(visible(panel), "confirmation retains the product, amount, quantity, payment methods and actions");
assert.equal(ids.PaymentProductArt.parent, body, "hiding reward summary does not hide the product image");
const quantityValue = findClass(quantity, "PaymentQuantityValue");
assert(quantityValue && quantityValue.text === "1", "the existing single-item quantity remains visible");
assert.equal(ids.PaymentQuantityMinus.enabled, false); assert.equal(ids.PaymentQuantityPlus.enabled, quantityInput);
const confirmationHeight = layoutFits(ui, "confirmation");
const originalScale = ui.fits.at(-1).scale;
ui.root.actuallayoutwidth = 640; ui.root.actuallayoutheight = 360;
layoutFits(ui, "small viewport");
assert(ui.fits.at(-1).scale < originalScale, "real fitting responds to a smaller viewport");
ui.root.actuallayoutwidth = 1600; ui.root.actuallayoutheight = 900;

ids.PaymentAlipay.events.onactivate();
assert(ids.PaymentAlipay.BHasClass("Selected"));
assert.equal(ui.requests.filter(r => r.action === "create").length, 0, "selecting a method does not submit an order");
ids.PaymentBuy.events.onactivate(); ids.PaymentBuy.events.onactivate();
assert.equal(ui.requests.filter(r => r.action === "create").length, 1, "repeat clicks submit only one order");
const firstCreate = ui.requests.at(-1);
assert.deepEqual(Object.keys(firstCreate).sort(), (quantityInput ? ["action", "provider", "quantity", "request_id", "sku"] : ["action", "provider", "request_id", "sku"]));
if (quantityInput) assert.equal(firstCreate.quantity, 1);
assert.equal(firstCreate.provider, "alipay"); assert.equal(firstCreate.sku, product.sku);
ui.respond({ ok: false, error: "purchase_limit_reached" });
assert(visible(ids.PaymentStatus)); assert.match(ids.PaymentStatus.text, /次数限制/);
assert(layoutFits(ui, "create failure") > confirmationHeight, "a real failure adds space for its message");
assert(!visible(summary) && !visible(ids.PaymentHint), "failure does not restore the removed confirmation copy");
ids.PaymentBuy.events.onactivate(); ids.PaymentBuy.events.onactivate();
assert.equal(ui.requests.filter(r => r.action === "create").length, 2, "one explicit retry submits one new order");
const order = { ...product, ok: true, provider: "alipay", state: "pending", checkout_mode: "qr", order_id: "AL" + "1".repeat(30),
    checkout_url: "https://pay.xiaofengnet.com/checkout/alipay?order=AL" + "1".repeat(30) + "&token=" + "a".repeat(64),
    qr_matrix: Array(29).fill("0".repeat(29)).join("|"), effects: { initial_wood: 100 } };
ui.respond(order);
assert.equal(ids.PaymentHeading.text, "扫码支付");
assert(visible(findClass(dialog, "PaymentQRStage")) && visible(ids.PaymentQR) && !visible(ids.PaymentQRState));
assert(visible(ids.PaymentStatus) && visible(ids.PaymentOpen) && visible(ids.PaymentRefresh) && visible(ids.PaymentCancel));
assert.equal(ui.urls.length, 0, "receiving a QR order never opens a browser");
const qrFrame = rect(ids.PaymentQR.parent);
assert(px(ids.PaymentQR.style.width, "QR width") <= qrFrame.width && px(ids.PaymentQR.style.height, "QR height") <= qrFrame.height,
    "the centered QR code fits its frame");
layoutFits(ui, "QR order");
ids.PaymentBuy.events.onactivate();
assert.equal(ui.requests.filter(r => r.action === "create").length, 2, "an active order prevents another create request");
ids.PaymentRefresh.events.onactivate();
assert.equal(ui.requests.at(-1).action, "status");
ui.respond({ ...order, expired: true });
assert(!visible(ids.PaymentQR) && visible(ids.PaymentQRState));
assert.match(ids.PaymentQRState.text, /已过期/); assert.match(ids.PaymentStatus.text, /已过期/);
assert(!visible(ids.PaymentOpen), "an expired order cannot offer a stale payment link");
layoutFits(ui, "expired order");
ids.PaymentRefresh.events.onactivate();
ui.respond({ ...order, state: "delivered", effect_changes: { initial_wood: { before: 10, after: 110, delta: 100 } },
    game_values: { initial_wood: 110 }, wallet: { wood: 1100 }, game_entitlements: { vip: { active: true } } });
assert.equal(ids.PaymentHeading.text, "支付结果");
assert(visible(summary) && visible(ids.PaymentValues) && visible(ids.PaymentDescription), "receipt retains the full reward details");
assert.match(ids.PaymentValues.text, /本单存档：10 → 110/); assert.match(ids.PaymentValues.text, /本局已生效/);
assert.match(ids.PaymentValues.text, /1100/); assert.match(ids.PaymentDescription.text, /奖励说明/);
assert(!visible(findClass(dialog, "PaymentQRStage")) && !visible(ids.PaymentQR));
assert(visible(ids.PaymentStatus)); assert.match(ids.PaymentStatus.text, /支付成功/);
layoutFits(ui, "receipt");
assert.equal(ids.PaymentPrice.text, expectedAmount, "receipt preserves the authoritative order amount");
ui.cfg.SurvivalPayments.Dispose();
console.log("CHECKOUT_COMPACT_LAYOUT_PASS: real XML/ModalShell, visible-content sizing, failure/QR/expired/receipt bounds, amount and request guards");
