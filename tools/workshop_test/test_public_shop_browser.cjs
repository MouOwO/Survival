"use strict";

// Real, isolated Chrome against static files over loopback. This exercises no
// Dota session, account login, order creation, payment channel or cloud reward.
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const {browser, sleep} = require("../archive_official_variants_20261019/browser.cjs");

const ROOT = path.resolve(__dirname, "../..");
const OUTPUT_ROOT = path.join(ROOT, "output/payment_shop_20261026");
const KIND = "WS4-PUBLIC-SHOP-STATIC-BROWSER";
const FILES = new Map([["index.html", "text/html; charset=utf-8"],
    ["shop.css", "text/css; charset=utf-8"], ["shop.js", "text/javascript; charset=utf-8"],
    ["catalog.js", "text/javascript; charset=utf-8"], ["catalog.json", "application/json; charset=utf-8"]]);
const digest = raw => crypto.createHash("sha256").update(raw).digest("hex");
let stage = "initialize";

async function until(check, code) {
    for (let attempt = 0; attempt < 180; attempt++) {
        if (await check()) return;
        await sleep(50);
    }
    throw Error(code);
}

async function run(options = {}) {
    const webRoot = path.resolve(options.webRoot || path.join(OUTPUT_ROOT, "web_release_v1"));
    const output = path.join(OUTPUT_ROOT, "browser_test_" + new Date().toISOString().replace(/[-:.]/g, "") + "_" + crypto.randomBytes(5).toString("hex"));
    fs.mkdirSync(output, {recursive: true});
    const raw = Object.fromEntries([...FILES.keys()].map(name => [name, fs.readFileSync(path.join(webRoot, name))]));
    const manifest = JSON.parse(fs.readFileSync(path.join(webRoot, "manifest.json"), "utf8"));
    for (const [name, bytes] of Object.entries(raw)) assert.equal(digest(bytes), manifest.files[name], "static_manifest_hash_mismatch:" + name);
    const catalog = JSON.parse(raw["catalog.json"]);
    assert.equal(catalog.products.length, 173);
    assert.equal(catalog.checkout_enabled, false);
    const normalize = value => String(value).replace(/U币/g, "G币");
    const expectedPrice = item => item.currency === "CNY" ? "¥" + (item.price / 100).toFixed(2)
        : item.price + " " + {u_coin: "G币", shop_points: "商城积分", shop_gold: "商店金币"}[item.currency];
    const hostile = '</script><img src="/unexpected-image" onerror="window.__shopXssExecuted=1"><svg onload="window.__shopXssExecuted=2">& "';
    const fixture = structuredClone(catalog);
    fixture.products[0].title = hostile;
    fixture.products[0].description = "描述 " + hostile;
    fixture.products[0].reward_lines = [{label: "奖励 " + hostile, quantity: 1}];
    fixture.categories[0].label = "分类 " + hostile;
    const fixtureData = Buffer.from("window.SurvivalPublicShop = " + JSON.stringify(fixture)
        .replace(/</g, "\\u003c").replace(/>/g, "\\u003e").replace(/&/g, "\\u0026") + ";\n");
    const requests = [];
    const server = http.createServer((request, response) => {
        const url = new URL(request.url, "http://127.0.0.1");
        requests.push({method: request.method, path: url.pathname});
        const match = /^\/(shop|xss)\/([a-z.]+)$/.exec(url.pathname);
        if (request.method !== "GET" || !match || !FILES.has(match[2])) {
            // Chrome may ask for a favicon. No other route exists, including
            // catalog APIs, account APIs, checkout, order, create or delivery.
            response.writeHead(404, {"Content-Length": 0, "Connection": "close"});
            response.end();
            return;
        }
        const body = match[1] === "xss" && match[2] === "catalog.js" ? fixtureData : raw[match[2]];
        response.writeHead(200, {"Content-Type": FILES.get(match[2]), "Content-Length": body.length,
            "Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "Connection": "close"});
        response.end(body);
    });
    let active;
    const checks = [];
    try {
        stage = "listen_loopback";
        const origin = await new Promise((resolve, reject) => {
            server.once("error", reject);
            server.listen(0, "127.0.0.1", () => resolve("http://127.0.0.1:" + server.address().port));
        });
        stage = "launch_isolated_chrome";
        active = await browser({output, executable: "C:/Program Files/Google/Chrome/Application/chrome.exe"});
        await active.call("Network.enable");
        async function go(kind) {
            const url = origin + "/" + kind + "/index.html";
            const navigation = await active.call("Page.navigate", {url});
            assert(!navigation.errorText, "static_navigation_failed");
            await until(async () => {
                try { return await active.run("location.href === " + JSON.stringify(url) + " && document.readyState === 'complete' && document.getElementById('products').children.length > 0"); }
                catch (_) { return false; }
            }, "static_shop_render_timeout");
            await active.run("document.fonts.ready.then(function(){return true;})");
        }
        async function control(name, value, event) {
            await active.run("(function(){var x=document.getElementById(" + JSON.stringify(name) + ");x.value=" + JSON.stringify(value) + ";x.dispatchEvent(new Event(" + JSON.stringify(event || "change") + ",{bubbles:true}));return true;})()");
        }
        async function shown() {
            return await active.run("Array.from(document.getElementById('products').children).map(function(x){return x.dataset.offer;})");
        }
        async function clickOffer(identity) {
            const point = await active.run("(function(){var x=Array.from(document.getElementById('products').children).find(function(b){return b.dataset.offer===" + JSON.stringify(identity) + ";});if(!x)throw Error('offer_missing');x.scrollIntoView({block:'center'});var r=x.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()");
            // Dispatch native pointer input rather than replacing the click or
            // detail handler. This catches overlays that obstruct the list.
            await active.click(point.x, point.y);
            await until(() => active.run("document.querySelector('#products button[aria-pressed=true]').dataset.offer === " + JSON.stringify(identity)), "shop_offer_click_timeout");
        }
        stage = "render_all_formal_offers";
        await go("shop");
        assert.deepEqual(await shown(), catalog.products.map(p => p.offer_id));
        assert.match(await active.run("document.getElementById('status').textContent"), /173/);
        assert.equal(await active.run("document.querySelectorAll('input').length"), 1);
        assert.equal(await active.run("document.querySelectorAll('input[type=password],input[name*=account],form,a[href*=checkout],button[type=submit]').length"), 0);
        await active.shot(path.join(output, "shop_all_offers.png"));
        checks.push("all_173_formal_offers_visible_without_account_or_order_controls");

        stage = "currency_filters_and_price_units";
        for (const currency of ["CNY", "u_coin", "shop_points", "shop_gold"]) {
            await control("currency", currency);
            const expected = catalog.products.filter(p => p.currency === currency);
            assert.deepEqual(await shown(), expected.map(p => p.offer_id));
            if (expected.length) {
                await clickOffer(expected[0].offer_id);
                assert.equal(await active.run("document.getElementById('price').textContent"), expectedPrice(expected[0]));
            } else {
                assert.equal(await active.run("document.getElementById('title').textContent"), "没有符合筛选的商品");
                assert.equal(await active.run("document.getElementById('rewards').children.length"), 0);
            }
        }
        await control("currency", "CNY");
        for (const sku of ["archive_pass_monthly", "special_lottery_ticket_single", "u_coin_recharge"]) {
            const item = catalog.products.find(p => p.offer_id === "cash:" + sku);
            await clickOffer(item.offer_id);
            assert.equal(await active.run("document.getElementById('price').textContent"), expectedPrice(item));
        }
        checks.push("all_four_currency_filters_and_cash_fen_formatting");

        stage = "category_filters";
        await control("currency", "all");
        for (const category of catalog.categories) {
            await control("category", category.id);
            assert.deepEqual(await shown(), catalog.products.filter(p => p.category_id === category.id).map(p => p.offer_id));
        }
        checks.push("every_formal_category_filter");

        stage = "search_titles_rewards_empty_reset";
        await control("category", "all");
        const searchTerms = [catalog.products[4].title, catalog.products.find(p => p.reward_lines.length).reward_lines[0].label,
            "NO_SUCH_WS4_PRODUCT_59a30e"];
        for (const term of searchTerms) {
            await control("search", normalize(term), "input");
            const query = normalize(term).trim().toLocaleLowerCase();
            const expected = catalog.products.filter(item => normalize(item.title + " " + item.description + " " + item.reward_lines.map(line => line.label).join(" ")).toLocaleLowerCase().includes(query));
            assert.deepEqual(await shown(), expected.map(p => p.offer_id));
            if (!expected.length) {
                assert.equal(await active.run("document.getElementById('price').textContent"), "");
                assert.equal(await active.run("document.getElementById('rewards').children.length"), 0);
            }
        }
        await control("search", "", "input");
        assert.equal((await shown()).length, 173);
        checks.push("title_and_reward_search_empty_state_and_restore");

        stage = "long_list_details_and_vip";
        const last = catalog.products.at(-1);
        await clickOffer(last.offer_id);
        assert.equal(await active.run("document.getElementById('title').textContent"), normalize(last.title));
        assert.equal(await active.run("document.getElementById('price').textContent"), expectedPrice(last));
        assert.equal(await active.run("document.getElementById('rewards').children.length"), last.reward_lines.length);
        assert(await active.run("document.getElementById('products').scrollTop > 0"), "long_list_must_scroll");
        const highestVip = Math.max(...catalog.products.map(p => p.required_vip_level));
        const vip = catalog.products.find(p => p.required_vip_level === highestVip);
        assert.equal(highestVip, 10, "formal_highest_enabled_vip_changed");
        assert(vip, "formal_vip_fixture_missing");
        await clickOffer(vip.offer_id);
        assert.match(await active.run("document.getElementById('limit').textContent"), /需要 VIP 10/);
        await active.shot(path.join(output, "shop_vip_detail.png"));
        checks.push("last_long_list_offer_click_and_vip10_eligibility_display");

        stage = "narrow_viewport";
        await active.viewport(390, 844);
        assert(await active.run("document.documentElement.scrollWidth <= innerWidth"), "narrow_shop_horizontal_overflow");
        await active.shot(path.join(output, "shop_narrow.png"));
        await active.viewport(1600, 900);
        checks.push("390px_layout_has_no_horizontal_overflow");

        stage = "hostile_catalog_text_rendering";
        await go("xss");
        assert.equal(await active.run("document.getElementById('title').textContent"), hostile);
        assert.equal(await active.run("document.getElementById('description').textContent"), "描述 " + hostile);
        assert.match(await active.run("document.getElementById('rewards').textContent"), /<img/);
        assert(await active.run("Array.from(document.getElementById('category').options).some(function(x){return x.textContent.indexOf('<img')>=0;})"));
        assert.equal(await active.run("typeof window.__shopXssExecuted"), "undefined");
        assert.equal(await active.run("document.querySelectorAll('img,svg,iframe').length"), 0);
        await active.shot(path.join(output, "shop_hostile_text_fixture.png"));
        checks.push("hostile_product_category_description_reward_stay_literal_text");

        stage = "read_only_network_audit";
        await sleep(200);
        const network = active.events.filter(event => event.method === "Network.requestWillBeSent").map(event => event.params);
        assert(network.length >= 8, "actual_browser_static_requests_missing");
        for (const event of network) {
            assert.equal(event.request.method, "GET", "browser_must_not_post_orders");
            assert(!["XHR", "Fetch", "WebSocket", "EventSource"].includes(event.type), "shop_must_not_call_account_or_order_apis");
            const url = new URL(event.request.url);
            assert.equal(url.origin, origin, "static_shop_must_not_call_external_origins");
            assert(/^\/(shop|xss)\/(index\.html|shop\.css|shop\.js|catalog\.js)$/.test(url.pathname) || url.pathname === "/favicon.ico", "unexpected_browser_route");
        }
        assert(requests.every(request => request.method === "GET"));
        assert(!requests.some(request => /unexpected-image|checkout|payments|orders|authorize|login/.test(request.path)));
        const jsErrors = active.events.filter(event => event.method === "Runtime.exceptionThrown");
        assert.equal(jsErrors.length, 0, "browser_runtime_exception");
        checks.push("real_network_contains_only_loopback_static_gets_no_xhr_fetch_orders_or_payments");
        const result = {ok: true, kind: KIND, catalog_sha256: catalog.catalog_sha256,
            offers: 173, cash_offers: 48, wallet_offers: 125, checks,
            network_requests: network.map(event => ({method: event.request.method, path: new URL(event.request.url).pathname, type: event.type})),
            existing_browser_profile_used: false, real_browser_used: true, dota_native_test: false,
            accounts_accessed: false, orders_created: false, payments_attempted: false,
            evidence_directory: path.relative(ROOT, output).replaceAll("\\", "/")};
        fs.writeFileSync(path.join(output, "verification.json"), JSON.stringify(result, null, 2) + "\n");
        return result;
    } catch (error) {
        if (active) {
            try { await active.shot(path.join(output, "failure.png")); } catch (_) { /* Preserve the primary error. */ }
        }
        fs.writeFileSync(path.join(output, "failure.json"), JSON.stringify({ok: false, kind: KIND, stage,
            error: String(error.message), checks}, null, 2) + "\n");
        throw error;
    } finally {
        if (active) await active.close();
        server.closeAllConnections();
        if (server.listening) await new Promise(resolve => server.close(resolve));
    }
}

module.exports = {run};
if (require.main === module) {
    const args = process.argv.slice(2);
    if (args.length && !(args.length === 2 && args[0] === "--web-root")) {
        console.log(JSON.stringify({ok: false, kind: KIND, error: "usage: --web-root <generated-static-directory>"}));
        process.exitCode = 1;
    } else run({webRoot: args[1]}).then(result => console.log(JSON.stringify(result))).catch(error => {
        console.log(JSON.stringify({ok: false, kind: KIND, stage, error: String(error.message)}));
        process.exitCode = 1;
    });
}
