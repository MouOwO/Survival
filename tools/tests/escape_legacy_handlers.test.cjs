const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const project = path.resolve(__dirname, '../..');
const read = file => fs.readFileSync(path.join(project, file), 'utf8');
const config = {};
let fallbackCloses = 0;

function assertRouting(invoke, id, label) {
    const calls = [];
    for (const result of [false, true]) {
        config.SurvivalUILayers = {HandleEscape(expectedId) {
            calls.push(expectedId);
            return result;
        }};
        const before = fallbackCloses;
        assert.strictEqual(invoke(), result, label + ' returns the central decision');
        assert.strictEqual(fallbackCloses, before, label + ' leaves closure to the central dispatcher');
    }
    assert.deepStrictEqual(calls, [id, id], label + ' identifies its own popup');

    for (const layers of [undefined, {}]) {
        config.SurvivalUILayers = layers;
        const before = fallbackCloses;
        assert.strictEqual(invoke(), true, label + ' supports independent layouts without the API');
        assert.strictEqual(fallbackCloses, before + 1, label + ' falls back to the local close');
    }
}

const archiveLayout = read('panorama/src/layout/custom_game/archive.xml');
for (const [file, id, panelId] of [
    ['treasure_history.js', 'treasure', 'TreasureWindow'],
    ['vip_window.js', 'vip', 'VIPWindow'],
    ['archive_180de7e38b_titles_compact_v6.js', 'archive', 'ArchiveWindow']
]) {
    assert(archiveLayout.includes('/' + file + '"'), file + ' is loaded by the active layout');
    const source = read('panorama/src/scripts/custom_game/' + file);
    const registration = source.match(/\$\.RegisterEventHandler\(["']Cancelled["'],[\s\S]*?\r?\n    \}\);/);
    assert(registration, file + ' registers a Cancelled callback');
    let handler;
    vm.runInNewContext(registration[0], {
        $: {RegisterEventHandler(event, panel, callback) {
            assert.strictEqual(event, 'Cancelled');
            assert.strictEqual(panel, panelId);
            handler = callback;
        }},
        p: id => id,
        panel: id => id,
        active: () => true,
        layers: () => config.SurvivalUILayers,
        cfg: config,
        GameUI: {CustomUIConfig: () => config},
        close: () => fallbackCloses++
    }, {filename: file});
    assertRouting(handler, id, file);
}

for (const file of ['survival_hud.xml', 'lottery_window.xml']) {
    const source = read('panorama/src/layout/custom_game/' + file);
    const panel = source.match(/<Panel\b[^>]*\bid="LotteryWindow"[^>]*>/);
    assert(panel, file + ' contains the lottery panel');
    const attribute = panel[0].match(/\boncancel="([^"]*)"/);
    assert(attribute, file + ' registers lottery cancellation');
    assert(!attribute[1].includes('CloseTop'), file + ' cannot cancel an unrelated popup');
    const callback = attribute[1].replace(/&amp;/g, '&');
    config.SurvivalLottery = {Close: () => fallbackCloses++};
    assertRouting(() => vm.runInNewContext(callback, {
        GameUI: {CustomUIConfig: () => config}
    }, {filename: file}), 'lottery', file);
    delete config.SurvivalLottery;
    config.SurvivalUILayers = undefined;
    assert.strictEqual(vm.runInNewContext(callback, {
        GameUI: {CustomUIConfig: () => config}
    }), false, file + ' is safe before the popup controller loads');
}

console.log('PASS legacy popup cancellation routes to the central dispatcher and preserves independent-layout fallback');
