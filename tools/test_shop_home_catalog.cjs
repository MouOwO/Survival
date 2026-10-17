"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const {spawnSync} = require("node:child_process");

const root = path.resolve(__dirname, "..");
const argv = process.argv.slice(2);
let dataRoot = root;
if (argv.length) {
    assert.equal(argv[0], "--data-root", "Only --data-root <repository> is supported");
    assert.equal(argv.length, 2);
    dataRoot = path.resolve(argv[1]);
}
const generator = path.join(root, "tools/build_shop_home_catalog.py");
assert(fs.existsSync(generator), "The production home catalog generator must exist");
const manifestPath = path.join(root, "data/ui/commerce_product_art_v1.json");
const art = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const knownSkus = art.products.map(row => row.sku);
assert.equal(new Set(knownSkus).size, 137, "Use the reviewed real product identities");
const presentationPath = path.join(dataRoot, "data/ui/shop_catalog_presentation_20261016.json");
const presentation = JSON.parse(fs.readFileSync(presentationPath, "utf8"));
const componentsPath = path.join(root, "panorama/src/scripts/custom_game/common/commerce_components.js");
const modelPath = path.join(dataRoot, "panorama/src/scripts/custom_game/black_lion_market_model.js");
const componentsSource = fs.readFileSync(componentsPath, "utf8");
const modelSource = fs.readFileSync(modelPath, "utf8");
const productionManifest = path.join(root, "data/ui/shop_home_catalog_20261016.json");
const productionManifestBefore = fs.existsSync(productionManifest) ? fs.readFileSync(productionManifest) : null;
const copy = value => JSON.parse(JSON.stringify(value));
const array = value => Array.from(value);

function python() {
    const choices = [process.env.SURVIVAL_PYTHON,
        path.join(os.homedir(), "AppData/Local/Programs/Python/Python314/python.exe"), "python3", "py", "python"].filter(Boolean);
    for (const candidate of choices) {
        const args = candidate === "py" ? ["-3"] : [];
        const check = spawnSync(candidate, [...args, "-B", "-c", "import sys;print(sys.version_info.major)"], {encoding:"utf8"});
        if (!check.error && check.status === 0 && check.stdout.trim() === "3") return {command:candidate, args};
    }
    throw new Error("Python 3 is required; set SURVIVAL_PYTHON to its executable");
}
const py = python();
function runPython(args, input) {
    const result = spawnSync(py.command, [...py.args, "-B", ...args], {input, encoding:"utf8", cwd:root,
        env:{...process.env, PYTHONIOENCODING:"utf-8"}, maxBuffer:16*1024*1024});
    assert(!result.error, String(result.error));
    return result;
}
function successful(result, action) {
    assert.equal(result.status, 0, action + "\n" + result.stderr + "\n" + result.stdout);
    return result.stdout;
}
// Import the actual Python implementation with bytecode writes disabled. Sources
// and generated blocks cross stdin as structured data, without shell quoting.
const bridge = String.raw`
import base64, importlib.util, json, sys
spec=importlib.util.spec_from_file_location("shop_home_catalog_under_test",sys.argv[1])
module=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=module
spec.loader.exec_module(module)
value=json.loads(sys.stdin.buffer.read().decode("utf-8"))
if sys.argv[2]=="generated_block":
    blob=base64.b64decode(value["manifest_blob"]) if "manifest_blob" in value else json.dumps(value["manifest"],ensure_ascii=False).encode("utf-8")
    result=module.generated_block(blob,set(value["known_skus"]))
    assert isinstance(result,str)
    sys.stdout.buffer.write(result.encode("utf-8"))
else:
    source=base64.b64decode(value["source"])
    result=getattr(module,sys.argv[2])(source,value["block"]) if "block" in value else getattr(module,sys.argv[2])(source)
    assert isinstance(result,bytes)
    sys.stdout.buffer.write(base64.b64encode(result))
`;
function api(name, value, shouldPass = true) {
    const result = runPython(["-c", bridge, generator, name], JSON.stringify(value));
    if (!shouldPass) { assert.notEqual(result.status, 0, "The generator must reject invalid homepage evidence"); return; }
    const text = successful(result, name);
    return name === "generated_block" ? text : Buffer.from(text.trim(), "base64").toString("utf8");
}
function patched(name, source, block) {
    return api(name, {source:Buffer.from(source).toString("base64"), ...(block === undefined ? {} : {block})});
}

const first = "video_p045", second = "video_p042";
assert(knownSkus.includes(first) && knownSkus.includes(second));
const unavailableId = "home_unavailable_P008";
const fixture = {schema_version:1, source:{kind:"user_confirmed", reference:"Automated fixture only; not an approved production homepage"}, entries:[
    {kind:"product", source_id:"P042", name:"妖刀村正", sku:second},
    {kind:"unavailable", source_id:"P008", name:"焚天曜轮"},
    {kind:"product", source_id:"P045", name:"渡鸦之眼", sku:first}
]};
const fixtureBytes = Buffer.from(JSON.stringify(fixture, null, 2) + "\n");
const block = api("generated_block", {manifest_blob:fixtureBytes.toString("base64"), known_skus:knownSkus});
const componentsCandidate = patched("patch_components_source", componentsSource, block);
const modelCandidate = patched("patch_model_source", modelSource);
assert.equal(patched("patch_components_source", componentsCandidate, block), componentsCandidate, "Component patching is repeatable");
assert.equal(patched("patch_model_source", modelCandidate), modelCandidate, "Model patching is repeatable");

const tempParent = path.join(root, "tmp");
fs.mkdirSync(tempParent, {recursive:true});
const temp = fs.mkdtempSync(path.join(tempParent, "shop_home_catalog_test-"));
const fixturePath = path.join(temp, "homepage.fixture.json");
fs.writeFileSync(fixturePath, fixtureBytes);
const printed = successful(runPython([generator, "--manifest", fixturePath, "--print-block"]), "The fixture-only CLI prints its generated block");
assert.equal(printed.replace(/\r\n/g, "\n").trim(), block.trim(), "The CLI emits executable block text without status output");
const modelOutput = path.join(temp, "black_lion_market_model.candidate.js");
successful(runPython([generator, "--model-source", modelPath, "--model-output", modelOutput]), "Model candidate generation needs no production homepage manifest");
assert.equal(fs.readFileSync(modelOutput, "utf8"), modelCandidate);
assert.notEqual(fixturePath, productionManifest, "The test fixture stays outside production data");

function runtime({catalog = true, originalModel = false, lateCatalog = false, catalogBlock = block} = {}) {
    const cfg = {SurvivalUI:{}, SurvivalShopPresentation:copy(presentation)};
    const context = vm.createContext({GameUI:{CustomUIConfig:() => cfg}});
    vm.runInContext(catalog && !lateCatalog ? patched("patch_components_source", componentsSource, catalogBlock) : componentsSource, context, {filename:componentsPath});
    if (!catalog || lateCatalog) delete cfg.SurvivalShopHomeCatalog;
    vm.runInContext(originalModel ? modelSource : modelCandidate, context, {filename:modelPath});
    return {cfg, context, model:cfg.SurvivalBlackLionMarketModel, inject(){vm.runInContext(block, context, {filename:"homepage.fixture.generated.js"});}};
}
function product(sku, overrides = {}) {
    const vip = (presentation.groups.vip || []).includes(sku), bundle = (presentation.groups.bundles || []).includes(sku) || vip;
    return {sku, title:sku, category_id:vip ? "vip" : bundle ? "bundles" : "item", product_type:bundle ? "bundle" : "single",
        purchase_method:"cash", enabled:true, owned:0, purchase_limit:1, currency:"u_coin", amount_fen:100,
        u_coin_price:1000, u_coin_per_yuan:1000, reward_lines:[], ...(vip ? {required_vip_level:2} : {}), ...overrides};
}
function visible(model, products, group) { return array(model.SortProducts(products.filter(row => model.InGroup(row, group)), group)).map(row => row.sku); }
function displayed(rows) { return array(rows).map(row => row.home_unavailable ? row.home_display_id : row.sku); }
function unavailable(row, model, sourceId, title) {
    assert.equal(row.home_unavailable, true);
    assert.equal(row.home_display_id, "home_unavailable_" + sourceId);
    assert.equal(row.source_id, sourceId); assert.equal(row.title, title);
    assert.equal(row.enabled, false);
    assert.equal(typeof row.description, "string"); assert(row.description.length > 0);
    for (const field of ["sku", "price", "amount_fen", "u_coin_price", "u_coin_per_yuan", "purchase_method", "currency", "reward_lines", "ownership_id", "purchase_limit"])
        assert(!Object.prototype.hasOwnProperty.call(row, field), "A local unavailable display row has no purchase field: " + field);
    assert.equal(model.IsListed(row), false); assert.equal(model.IsActionable(row), false);
    for (const group of ["home", "all", "bundles", "promotions", "vip"]) assert.equal(model.InGroup(row, group), false, "Display rows never become formal products");
}

const commerceSkus = art.products.filter(row => row.catalog_source === "commerce").map(row => row.sku);
assert.equal(commerceSkus.length, 129);
assert(presentation.groups.all.includes(first) && presentation.groups.all.includes(second), "The real old presentation contains both fixture SKUs");
const products = commerceSkus.map(sku => product(sku)).reverse();
const productsBefore = JSON.stringify(products), presentationBefore = JSON.stringify(presentation);
const live = runtime();
const home = live.cfg.SurvivalShopHomeCatalog;
assert.deepEqual(array(home.List()), [second, unavailableId, first]);
assert.deepEqual(visible(live.model, products, "home"), [second, first], "Homepage membership and order come only from the independent list");
const composed = home.Compose(products, live.model.IsListed);
assert.deepEqual(displayed(composed), [second, unavailableId, first]);
assert.equal(composed[0], products.find(row => row.sku === second), "Compose retains the exact authoritative product reference");
assert.equal(composed[2], products.find(row => row.sku === first));
unavailable(composed[1], live.model, "P008", "焚天曜轮");
assert.deepEqual(displayed(live.model.HomeProducts(products)), [second, first]);
assert.equal(live.model.Groups({products}).find(row => row.id === "home").count, 2, "Live home counts exclude unavailable video display rows");
const bundleSkus = presentation.groups.bundles, vipSkus = presentation.groups.vip;
const singleSkus = presentation.groups.all.filter(sku => !bundleSkus.includes(sku) && !vipSkus.includes(sku));
const expectedGroups = {bundles:bundleSkus, promotions:presentation.groups.promotions, vip:vipSkus, all:singleSkus};
for (const [group, expected] of Object.entries(expectedGroups)) {
    assert.deepEqual(visible(live.model, products, group), expected, group + " follows the reviewed order within its allowed product type");
    assert.equal(live.model.Groups({products}).find(row => row.id === group).count, expected.length);
}
assert.deepEqual(Object.fromEntries(Object.entries(expectedGroups).map(([group, skus]) => [group, skus.length])),
    {bundles:5, promotions:25, vip:10, all:114});

// Discounted packs used to leak into Promotions and All. Legacy lists must not
// override the authoritative product type, VIP level or category either.
const pack = product("ordinary_pack", {product_type:"bundle", category_id:"bundles", original_u_coin_price:2000});
const vipPack = product("vip_pack", {product_type:"bundle", category_id:"vip", required_vip_level:3, original_u_coin_price:2000});
const vipSingle = product("vip_single", {required_vip_level:3, original_u_coin_price:2000});
const changedHome = product(second, {product_type:"bundle", category_id:"bundles", original_u_coin_price:2000});
const adversarial = [pack, vipPack, vipSingle, changedHome, product(first)];
const grouped = runtime();
grouped.model.SetPresentation({groups:Object.fromEntries(["home", "all", "promotions", "bundles", "vip"].map(group =>
    [group, adversarial.map(row => row.sku)]))});
for (const [row, onlyGroup] of [[pack,"bundles"], [vipPack,"vip"], [changedHome,"bundles"]]) {
    for (const group of ["home", "all", "promotions", "bundles", "vip"])
        assert.equal(grouped.model.InGroup(row, group), group === onlyGroup, row.sku + " is exclusive to " + onlyGroup);
    assert.equal(grouped.model.GroupFor(row), onlyGroup);
}
assert.equal(grouped.model.InGroup(vipSingle, "vip"), false, "A VIP restriction does not turn a single product into a VIP bundle");
assert.equal(grouped.model.InGroup(vipSingle, "bundles"), false);
assert.equal(grouped.model.InGroup(vipSingle, "all"), true);
assert.equal(grouped.model.InGroup(vipSingle, "promotions"), true);
assert.equal(grouped.model.GroupFor(vipSingle), "promotions");
assert.deepEqual(displayed(grouped.model.HomeProducts(adversarial)), [first], "A reviewed SKU retyped as a bundle cannot leak through Home composition");
for (const row of [pack, vipPack]) {
    for (const blocked of [{...row, owned:1}, {...row, enabled:false, disabled_reason:"product_unavailable"}])
        assert.equal(grouped.model.InGroup(blocked, grouped.model.GroupFor(row)), false, "Bundle tabs retain ownership and availability filtering");
}
const extra = product("server_added_after_home_review", {sort_order:0});
assert(visible(live.model, [...products, extra], "all").includes(extra.sku), "New formally listed products still enter All");
assert.deepEqual(visible(live.model, [...products, extra], "home"), [second, first], "Adding an All product cannot leak into Home");
assert.deepEqual(displayed(live.model.HomeProducts([...products, extra])), [second, first]);
const mutatedList = home.List(); mutatedList.reverse(); mutatedList.push(extra.sku);
assert.deepEqual(array(home.List()), [second, unavailableId, first], "List returns an independent copy");
const mutatedCompose = home.Compose(products, live.model.IsListed); mutatedCompose.reverse(); mutatedCompose.pop();
assert.deepEqual(displayed(home.Compose(products, live.model.IsListed)), [second, unavailableId, first], "Compose returns a new result array");
const previousDisplay = composed[1];
try { previousDisplay.title = "Changed by a caller"; } catch (error) { assert(error instanceof TypeError); }
try { previousDisplay.sku = "must_not_become_a_product"; } catch (error) { assert(error instanceof TypeError); }
const freshDisplay = home.Compose(products, live.model.IsListed)[1];
assert.notEqual(freshDisplay, previousDisplay, "Each composition returns a separate local unavailable display object");
unavailable(freshDisplay, live.model, "P008", "焚天曜轮");
assert.deepEqual(visible(live.model, products, "home"), [second, first]);

assert.deepEqual(visible(live.model, [product(first)], "home"), [first], "Metadata cannot create an absent formal product");
assert.deepEqual(displayed(live.model.HomeProducts([product(first)])), [first], "Only present, formally eligible products enter the live home");
const blocked = [product(first, {owned:1}), product(second, {enabled:false, disabled_reason:"product_unavailable"})];
assert.deepEqual(visible(live.model, blocked, "home"), [],
    "Owned and delisted products are filtered by existing authoritative availability rules");
assert.deepEqual(displayed(live.model.HomeProducts(blocked)), []);
assert.equal(live.model.Groups({products:blocked}).find(row => row.id === "home").count, 0);
assert.deepEqual(displayed(home.Compose(products, () => false)), [unavailableId], "Compose honors the supplied authoritative listing predicate");
assert.equal(live.model.InGroup(extra, "home"), false, "An unknown homepage SKU remains outside the list");
const missing = runtime({catalog:false});
assert.deepEqual(visible(missing.model, products, "home"), [], "Missing independent homepage data stays empty even when the legacy Home list equals All");
assert.deepEqual(array(missing.model.HomeProducts(products)), []);
assert.equal(missing.model.Groups({products}).find(row => row.id === "home").count, 0);
missing.model.SetPresentation({groups:{...copy(presentation.groups), home:commerceSkus}});
assert.deepEqual(visible(missing.model, products, "home"), [], "SetPresentation cannot revive the legacy Home-to-All fallback");
const late = runtime({catalog:false, lateCatalog:true});
assert.deepEqual(visible(late.model, products, "home"), []);
late.inject();
assert.deepEqual(visible(late.model, products, "home"), [second, first], "Late component loading reads the real independent catalog without rebuilding the model");
assert.deepEqual(displayed(late.model.HomeProducts(products)), [second, first]);
assert.equal(JSON.stringify(products), productsBefore, "Homepage grouping never rewrites price, grants, ownership or quantity");
assert.equal(JSON.stringify(presentation), presentationBefore, "The original presentation data remains unchanged");

for (const invalid of [
    {...fixture, entries:[fixture.entries[0], fixture.entries[0]]},
    {...fixture, entries:[{...fixture.entries[0], sku:"unknown_not_in_reviewed_catalog"}]},
    {...fixture, entries:[{...fixture.entries[1], sku:"video_p008"}]},
    {...fixture, source:{kind:"navigation_label", reference:"首页"}},
    {...fixture, source:{kind:"user_confirmed", reference:""}}
]) api("generated_block", {manifest:invalid, known_skus:knownSkus}, false);
const videoFixture = {...fixture, source:{kind:"video_frame", reference:"Automated test frame evidence", timestamps_seconds:[1.5, 3]}};
assert(api("generated_block", {manifest:videoFixture, known_skus:knownSkus}).includes("SurvivalShopHomeCatalog"));

// The expected order comes from the independently reviewed original recording,
// tmp/home_catalog_20261016/home_reviewed.json (380s, 420s and 452s).
const expectedHome = [
    ["P033", "伐木斧", "video_p033"], ["P008", "焚天曜轮", null],
    ["P029", "工作效率", "video_p029"], ["P012", "剑圣", "video_p012"],
    ["P032", "快速建造", "video_p032"], ["P005", "双倍通关卡", "video_p005"],
    ["P018", "时间科技", "video_p018"], ["P006", "兔女郎城墙", null],
    ["P007", "昭穹羽君", null], ["P004", "清暑符", "video_p004"],
    ["P066", "陨落天矿", "video_p066"], ["P067", "山海鲲鹏", "video_p067"],
    ["P068", "轮回仙碑", "video_p068"], ["P072", "苍松固城", "video_p072"],
    ["P071", "斫木宗师", "video_p071"], ["P070", "林铸千矢", "video_p070"],
    ["P069", "翠木归元", "video_p069"], ["P073", "天道傀儡", null],
    ["P074", "封神榜", null], ["P075", "诛仙剑阵", "video_p075"]
];
assert(productionManifestBefore, "The approved twenty-entry homepage manifest must exist");
const formal = JSON.parse(productionManifestBefore);
assert.equal(formal.entries.length, 20);
assert.equal(formal.entries.filter(row => row.kind === "product").length, 15);
assert.equal(formal.entries.filter(row => row.kind === "unavailable").length, 5);
assert.deepEqual(formal.entries.map(row => [row.source_id, row.name, row.sku || null]), expectedHome, "The formal homepage preserves all twenty reviewed entries and their exact video order");
const formalBlock = api("generated_block", {manifest_blob:productionManifestBefore.toString("base64"), known_skus:knownSkus});
const formalRuntime = runtime({catalogBlock:formalBlock}), formalRows = formalRuntime.model.HomeProducts(products);
const liveHome = expectedHome.filter(([, , sku]) => !!sku);
assert.deepEqual(displayed(formalRows), liveHome.map(([, , sku]) => sku));
assert.equal(formalRuntime.model.Groups({products}).find(row => row.id === "home").count, 15);
for (let i = 0; i < liveHome.length; i++) assert.equal(formalRows[i], products.find(row => row.sku === liveHome[i][2]));
for (const disabled_reason of ['commerce_balance_insufficient','insufficient_balance','vip_level_required','vip_level_insufficient']) {
    const homeSku=liveHome[0][2], blockedOnlyByPlayer = product(homeSku, {enabled:false, disabled_reason, required_vip_level:3});
    assert.deepEqual(displayed(formalRuntime.model.HomeProducts([blockedOnlyByPlayer])), [homeSku], 'Player-only restrictions remain visible: '+disabled_reason);
}
const allOwned = products.map(row => ({...row, owned:1}));
const unavailableOnly = formalRuntime.model.HomeProducts(allOwned);
assert.equal(unavailableOnly.length, 0, "Unopened display rows cannot fill an otherwise empty live home");
assert.equal(formalRuntime.model.Groups({products:allOwned}).find(row => row.id === "home").count, 0);
if (productionManifestBefore) assert.deepEqual(fs.readFileSync(productionManifest), productionManifestBefore, "The formal homepage manifest remains untouched");
else assert(!fs.existsSync(productionManifest), "The test never creates a formal homepage manifest");

console.log("SHOP_HOME_CATALOG_PASS: twenty reviewed entries, fifteen formal live home products; unopened placeholders hidden, player restrictions retained; exclusive tabs, references/copies and strict empty fallback");
