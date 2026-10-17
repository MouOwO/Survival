"use strict";
// Real browser pointer input against frozen production sources. No game input,
// purchase activation, account traffic or edits to the production assembly.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const assert = require("node:assert/strict");
const {browser, sleep} = require("../shop_ui_12h/cdp.cjs");
const repo = path.resolve(__dirname, "../..");
process.chdir(repo);
const sourceEntry = path.resolve(process.argv[2] || "output/shop_icon_hover_20261017/header_preview/index.html");
const out = path.resolve("output/shop_icon_hover_20261017/pointer");
fs.mkdirSync(out, {recursive: true});
const sha = file => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const html = fs.readFileSync(sourceEntry, "utf8"), key = "window.PREVIEW_SOURCES=";
const begin = html.indexOf(key) + key.length, end = html.indexOf(";window.PREVIEW_FIXTURE=", begin);
assert(begin >= key.length && end > begin);
const frozen = JSON.parse(html.slice(begin, end));
const sources = ["scripts/custom_game/common/commerce_components.js", "scripts/custom_game/black_lion_market.js", "styles/custom_game/black_lion_market.css"].map(relative => ({
    path: "panorama/src/" + relative,
    sha256: crypto.createHash("sha256").update(frozen[relative]).digest("hex")
}));
// The header fixture has no paid products. Retain its exact frozen source and
// image assembly, adding the existing reviewed formal-catalog offline state.
const preview = path.join(out, "preview"), entry = path.join(preview, "index.html");
fs.mkdirSync(preview, {recursive: true});
const catalogs = JSON.parse(fs.readFileSync("output/shop_icon_quality_20261017/catalogs.json", "utf8").replace(/^\uFEFF/, ""));
function wire(raw, payment) { const grants=raw.grants||{},pricing=grants.pricing||{};return {...raw,owned:0,
    amount_fen:raw.amount_fen??raw.amount,purchase_method:payment?'cash':raw.purchase_method,
    u_coin_price:raw.u_coin_price??pricing.u_coin_price,u_coin_per_yuan:raw.u_coin_per_yuan??pricing.u_coin_per_yuan,
    required_vip_level:Number(grants.required_vip_level)||0,reward_lines:grants.lines||raw.reward_lines||[]}; }
function readVariable(input, key, stopKey) { const start=input.indexOf(key)+key.length,end=input.indexOf(stopKey,start);assert(start>=key.length&&end>start);return JSON.parse(input.slice(start,end)); }
function replaceVariable(input, key, stopKey, value) { const start=input.indexOf(key)+key.length,end=input.indexOf(stopKey,start);return input.slice(0,start)+JSON.stringify(value).replaceAll('</script','<\\/script')+input.slice(end); }
const fixture=readVariable(html,'window.PREVIEW_FIXTURE=',';window.PREVIEW_SOURCE_ROOT=');
fixture.commerce={paid:{...catalogs.payment,catalog_hash:'FORMAL_COMPILER_LOCAL_ACCOUNT_VIP12',products:catalogs.payment.products.map(row=>wire(row,true))},wallet:{...catalogs.wallet,products:catalogs.wallet.products.map(row=>wire(row,false)),balances:{u_coin:999999,shop_points:999999,shop_gold:999999}}};
fs.writeFileSync(path.join(preview, "state.js"), fs.readFileSync("tools/menus_v10/state.js", "utf8")+"\nwindow.pointerFormalReady=previewReady.then(ok=>{if(!ok)return false;cfg.SurvivalCommerceView.UpdateCatalog(PREVIEW_FIXTURE.commerce.paid);cfg.SurvivalCommerceView.UpdateWalletCatalog(PREVIEW_FIXTURE.commerce.wallet);cfg.SurvivalCommerceView.SelectCategory('bundles');syncLayout();return true;});\n");
fs.copyFileSync(path.join(path.dirname(sourceEntry), "style.css"), path.join(preview, "style.css"));
let pointerHtml=replaceVariable(html,'window.PREVIEW_FIXTURE=',';window.PREVIEW_SOURCE_ROOT=',fixture);
const qualityHtml=fs.readFileSync('output/shop_icon_clarity_20261017/preview/index.html','utf8');
const aliases={...readVariable(html,'window.PREVIEW_ASSET_PATHS=',';window.PREVIEW_BASELINE='),...readVariable(qualityHtml,'window.PREVIEW_ASSET_PATHS=',';window.PREVIEW_BASELINE=')};
pointerHtml=replaceVariable(pointerHtml,'window.PREVIEW_ASSET_PATHS=',';window.PREVIEW_BASELINE=',aliases);
fs.writeFileSync(path.join(preview,'adapter.js'),fs.readFileSync('tools/archive_v10/adapter.js','utf8').replace("v==='stretch-to-fit'?'fill':'contain'","v==='stretch-to-fit'?'fill':v==='stretch-to-cover-preserve-aspect'?'cover':'contain'"));
pointerHtml=pointerHtml.replace(/<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>/,'<script src="adapter.js"></script>');
fs.writeFileSync(entry, pointerHtml.replace(/<script src="[^"]*tools\/menus_v10\/state\.js"><\/script>/, '<script src="state.js"></script>'));
function stable() { for (const source of sources) assert.equal(sha(source.path), source.sha256, "Frozen source must match production"); }

(async () => {
    stable();
    const b = await browser(), report = {scope: "Frozen production browser preview with real CDP mouse movement; not a native game capture", noAccountOrOrderWrites: true,
        sources, entry, entrySha256: sha(entry), scenarios: [], iconBounds: []};
    async function move(point) {
        await b.run("window.pointerAuditAt=" + JSON.stringify(point));
        await b.call("Input.dispatchMouseEvent", {type: "mouseMoved", x: point[0], y: point[1]});
        await sleep(210);
    }
    async function state() { return b.run("({shown:pointerRow.__purpleDetail.BHasClass('Visible'),errors:previewErrors,orders:previewCalls.filter(row=>row.method==='paid'||row.method==='wallet'||row.payload&&row.payload.action==='purchase')})"); }
    try {
        await b.call("Network.enable");
        await b.call("Network.setBlockedURLs", {urls: ["http://*", "https://*"]});
        for (const [width, height] of [[1920, 1080], [1280, 720]]) {
            await b.call("Emulation.setDeviceMetricsOverride", {width, height, deviceScaleFactor: 1, mobile: false});
            await b.go(entry, "?page=commerce&state=vip12&category=bundles");
            assert.equal(await b.run("previewReady"), true);
            assert.equal(await b.run("pointerFormalReady"), true);
            await b.run("window.pointerAuditAt=[0,0];GameUI.GetCursorPosition=()=>window.pointerAuditAt;cfg.SurvivalCommerceView.SelectCategory('bundles');syncLayout();");
            await sleep(180);
            const products = await b.run("cfg.SurvivalCommerceView.Inspect().visibleSkus");
            assert(products.includes("video_bundle_b001") && products.includes("video_bundle_b004"), "The four actual gift products are listed: " + JSON.stringify(await b.run("cfg.SurvivalCommerceView.Inspect()")));
            for (const sku of ["video_bundle_b001", "video_bundle_b002", "video_bundle_b003", "video_bundle_b004"]) {
                await move([5, 5]);
                const rects = await b.run(`(()=>{const view=cfg.SurvivalCommerceView,market=cfg.SurvivalBlackLionMarket.GetWindow();view.SelectCategory('bundles');syncLayout();const index=view.Inspect().visibleSkus.indexOf(${JSON.stringify(sku)});window.pointerRow=market.content.FindChildrenWithClassTraverse('BLMarketRow')[index];market.content.el.scrollTop=Math.max(0,pointerRow.el.offsetTop-120);syncLayout();function rect(panel){const r=panel.el.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height,cy:r.y+r.height/2,right:r.right,bottom:r.bottom};}return{row:rect(pointerRow),icon:rect(pointerRow.__menuCell.iconPanel),name:rect(pointerRow.__menuCell.namePanel),price:rect(pointerRow.FindChildrenWithClassTraverse('BLMarketRowPrice')[0]),buy:rect(pointerRow.FindChildrenWithClassTraverse('BLMarketBuy')[0]),rowEntry:!!pointerRow.events.onmouseover};})()`);
                assert.equal(rects.rowEntry, false);
                const centers = {name: [rects.name.x + 20, rects.name.cy], blank: [rects.row.right - 8, rects.row.bottom - 4],
                    price: [rects.price.x + rects.price.width / 2, rects.price.cy], buy: [rects.buy.x + rects.buy.width / 2, rects.buy.cy]};
                const checks = [];
                for (const [region, point] of Object.entries(centers)) {
                    await move(point); const current = await state();
                    assert.equal(current.shown, false, sku + " " + region + " cannot open tooltip");
                    checks.push({region, point, shown: current.shown});
                }
                const iconPoint = [rects.icon.x + rects.icon.width / 2, rects.icon.cy];
                await move(iconPoint);
                const opened = await state();
                assert.equal(opened.shown, true, sku + " opens from actual icon hover");
                const tip = await b.run("(()=>{const r=pointerRow.__purpleDetail.el.getBoundingClientRect();return{x:r.x,y:r.y,right:r.right,bottom:r.bottom,interactive:pointerRow.__purpleDetail.hittest};})()");
                // A long interactive popup can cover part of the name. Choose
                // an actual name position beyond that popup for source exit.
                const nameExit = [Math.min(rects.name.right - 10, Math.max(rects.name.x + 20, tip.right + 12)), rects.name.cy];
                assert(nameExit[0] > tip.right || nameExit[0] < tip.x || nameExit[1] < tip.y || nameExit[1] > tip.bottom, "Exit point lies outside interactive detail");
                await move(nameExit);
                const left = await state();
                assert.equal(left.shown, false, sku + " leaves to name region and hides");
                assert.deepEqual(left.errors, []); assert.deepEqual(left.orders, []);
                report.scenarios.push({viewport: [width, height], sku, rects, checks, iconPoint, opened: opened.shown, nameExit, hiddenAfterLeave: !left.shown});
            }
            await move([5, 5]);
            await b.run("cfg.SurvivalCommerceView.SelectCategory('bundles');cfg.SurvivalBlackLionMarket.GetWindow().content.el.scrollTop=0;syncLayout();");
            const shot = path.join(out, "four_gifts_" + width + "x" + height + ".png");
            await b.shot(shot, {x: 0, y: 0, width, height});
            report.scenarios.at(-1).screenshot = {path: path.relative(repo, shot).replaceAll("\\", "/"), sha256: sha(shot)};
        }
        const categories = await b.run("cfg.SurvivalCommerceView.Inspect().groups.map(group=>group.id)");
        for (const category of categories) {
            await b.run("cfg.SurvivalCommerceView.SelectCategory(" + JSON.stringify(category) + ");syncLayout();");
            let page = 0, pages = 1;
            while (page < pages) {
                await b.run("syncLayout();Promise.all([...document.images].map(image=>image.decode().catch(()=>false)))");
                const measured = await b.run(`(()=>{const view=cfg.SurvivalCommerceView.Inspect(),market=cfg.SurvivalBlackLionMarket.GetWindow(),rows=market.content.FindChildrenWithClassTraverse('BLMarketRow');return{pages:Math.max(1,Math.ceil(view.visibleSkus.length/40)),rows:rows.map((row,index)=>{const well=row.__menuCell.iconPanel,art=well.Children()[0],r=well.el.getBoundingClientRect(),i=art.el.getBoundingClientRect(),style=getComputedStyle(well.el),scale=r.width/well.el.offsetWidth,images=art.el.tagName==='IMG'?[art.el]:[...art.el.querySelectorAll('img')];return{sku:view.visibleSkus[view.page*40+index],category:view.category,page:view.page,well:{x:r.x,y:r.y,width:r.width,height:r.height},inner:{x:r.x+parseFloat(style.borderLeftWidth)*scale,y:r.y+parseFloat(style.borderTopWidth)*scale,width:well.el.clientWidth*scale,height:well.el.clientHeight*scale},art:{x:i.x,y:i.y,width:i.width,height:i.height},images:images.map(image=>({decoded:image.complete&&image.naturalWidth>0,natural:[image.naturalWidth,image.naturalHeight],fit:getComputedStyle(image).objectFit}))};})};})()`);
                pages = measured.pages;
                for (const row of measured.rows) {
                    for (const coordinate of ["x", "y", "width", "height"]) assert(Math.abs(row.inner[coordinate] - row.art[coordinate]) < 1.1, row.sku + " artwork fills the icon interior: " + coordinate);
                    assert(row.images.length > 0 && row.images.every(image => image.decoded), row.sku + " actual image decodes");
                    assert(row.images.every(image => image.fit === "cover"), row.sku + " image uses cover scaling");
                    report.iconBounds.push(row);
                }
                page++;
                if (page < pages) await b.run("(()=>{const actions=cfg.SurvivalBlackLionMarket.GetWindow().actions.FindChildrenWithClassTraverse('CJPageAction');actions[actions.length-1].events.onactivate();syncLayout();})()");
            }
        }
        report.uniqueProductIcons = new Set(report.iconBounds.map(row => row.sku)).size;
        report.listedProductCount = await b.run("cfg.SurvivalCommerceView.Inspect().productCount");
        assert.equal(report.uniqueProductIcons, report.listedProductCount, "All listed market product icons were measured; recharge uses its separate header entry");
        stable(); report.status = "PASS";
    } catch (error) { report.status = "FAIL"; report.failure = error.stack; throw error; }
    finally { fs.writeFileSync(path.join(out, "pointer_report.json"), JSON.stringify(report, null, 2) + "\n"); b.close(); }
    console.log("PASS_POINTER_ICON_ONLY " + JSON.stringify({scenarios: report.scenarios.length, uniqueProductIcons: report.uniqueProductIcons}));
})().catch(error => { console.error(error); process.exitCode = 1; });
