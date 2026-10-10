// Execute the real portrait lifecycle through the shared Panorama engine mock.
// This checks load requests and ownership, not rendered pixels or live FPS.
const assert = require('node:assert/strict');
const {setup} = require('./test_combat_stats_callbacks.cjs');

const builder = (entity, version, patch = {}) => ({
    entindex: entity, refresh_version: version,
    model_asset_id: 'builder_io_benevolent_companion',
    portrait_unit_name: 'npc_dota_hero_wisp', portrait_item_def: '9235',
    health: 1000, max_health: 1000, attack_min: 1, attack_max: 1, ...patch,
});
const city = version => ({entindex: 8, refresh_version: version,
    health: 10000, max_health: 10000, attack_min: 0, attack_max: 0});
const tower = (version, patch = {}) => ({
    entindex: 20, refresh_version: version,
    model_asset_id: 'tower_native_route_one',
    portrait_unit_name: 'npc_dota_hero_windrunner', portrait_item_def: '100',
    health: 2000, max_health: 2000, attack_min: 10, attack_max: 10, ...patch,
});

function customVisible(t, entity, scene = t.scene) {
    assert.equal(t.overlay.values.visibility, 'visible');
    assert.equal(scene.values.visibility, 'visible');
    assert.equal(t.overlay.GetParent(), t.nativeHost());
    assert.equal(t.native().values.opacity, '0');
    const state = t.api.portraitState();
    assert.equal(state.entity, entity, 'Visible ownership follows the current selected entity');
    assert.equal(state.scene, scene);
    assert.equal(state.mode, 'tower_scene');
}

function nativeVisible(t) {
    assert.equal(t.overlay.values.visibility, 'collapse');
    assert.equal(t.overlay.GetParent(), t.context);
    assert.equal(t.native().values.opacity, '0.35');
    const state = t.api.portraitState();
    assert.equal(state.mode, '');
    assert.equal(state.key, '');
    assert.equal(state.entity, -1);
    assert.equal(state.scene, null, 'Hidden loaded content must not remain an active portrait');
}

function selectBuilder(t, entity, version) {
    t.select(entity, 'npc_survival_builder_proxy');
    t.api.portraitTransition('builder_selected');
    t.api.updateSnapshot(builder(entity, version));
    customVisible(t, entity);
}

{
    const t = setup({portrait: true});
    selectBuilder(t, 7, 1);
    assert.deepEqual(t.metrics.setUnit.map(call => call.args),
        [['npc_dota_hero_wisp', 'default', false]]);
    t.api.cosmeticPortraitSentinel();
    for (let version = 2; version <= 65; version++) {
        t.api.updateSnapshot(builder(7, version, {health: 1000 - version, attack_min: version}));
        t.run([...t.jobs.keys()][0]);
        customVisible(t, 7);
        assert.equal(t.jobs.size, 1);
    }
    assert.equal(t.metrics.setUnit.length, 1, '64 authoritative stat updates reuse the loaded Scene');

    for (let cycle = 0; cycle < 10; cycle++) {
        t.select(8, 'building_main_city');
        t.api.portraitTransition('main_city_selected');
        t.api.updateSnapshot(city(cycle + 1));
        nativeVisible(t);
        const acceptedCity = t.api.portraitState().snapshot;
        t.api.updateSnapshot(builder(7, 10000 + cycle));
        assert.equal(t.api.portraitState().snapshot, acceptedCity,
            'A late builder packet cannot replace the selected main city snapshot');
        nativeVisible(t);
        selectBuilder(t, 7, 66 + cycle);
        t.run([...t.jobs.keys()][0]);
        customVisible(t, 7);
    }
    assert.equal(t.metrics.setUnit.length, 1,
        'Ten builder/main-city cycles reuse one loaded model despite hide and parent moves');
    assert(t.metrics.parents > 10, 'The test must exercise real native-layer/home reparenting');

    // Reusing model content does not transfer ownership from an old entity.
    selectBuilder(t, 9, 1);
    assert.equal(t.metrics.setUnit.length, 1, 'Another allowed builder with the same signature reuses content');
    const acceptedNewBuilder = t.api.portraitState().snapshot;
    t.api.updateSnapshot(builder(7, 99999));
    assert.equal(t.api.portraitState().snapshot, acceptedNewBuilder);
    customVisible(t, 9);
    assert.equal(t.metrics.setUnit.length, 1);
    t.api.shutdown('selection_reuse_complete');
    nativeVisible(t);
    assert.equal(t.jobs.size, 0);
}

{
    const t = setup({portrait: true});
    t.select(20, 'building_arrow_tower');
    t.api.portraitTransition('tower_selected');
    let expectedLoads = 1;
    t.api.updateSnapshot(tower(1));
    customVisible(t, 20);
    const variants = [
        tower(2, {portrait_item_def: '101'}),
        tower(3, {portrait_item_def: '101', model_asset_id: 'tower_native_route_two'}),
        tower(4, {portrait_item_def: '101', model_asset_id: 'tower_native_route_two',
            portrait_unit_name: 'npc_dota_hero_drow_ranger'}),
    ];
    for (const snapshot of variants) {
        t.api.updateSnapshot(snapshot);
        assert.equal(t.metrics.setUnit.length, ++expectedLoads,
            'A supported item, model asset, or portrait unit change requires one fresh SetUnit');
        t.api.updateSnapshot({...snapshot});
        t.api.portraitUpdate(snapshot);
        assert.equal(t.metrics.setUnit.length, expectedLoads, 'Repeated same-signature updates do not reload');
        customVisible(t, 20);
    }

    // A released Scene cannot lend its loaded identity to a replacement object.
    const released = t.scene;
    released.alive = false;
    assert.doesNotThrow(() => t.api.portraitHide('scene_disposed'));
    nativeVisible(t);
    const replacement = new t.Panel('SurvivalTowerPortraitScene', t.overlay, 'DOTAScenePanel');
    t.api.updateSnapshot({...variants.at(-1), refresh_version: 5});
    assert.equal(t.metrics.setUnit.length, ++expectedLoads);
    assert.equal(t.metrics.setUnit.at(-1).panel, replacement);
    customVisible(t, 20, replacement);
    t.api.updateSnapshot({...variants.at(-1), refresh_version: 6});
    assert.equal(t.metrics.setUnit.length, expectedLoads);

    // If a released native handle throws on validity checks, hide is still safe,
    // and having no replacement must restore the independent native portrait.
    replacement.alive = 'throw';
    assert.doesNotThrow(() => t.api.portraitHide('scene_handle_released'));
    assert.doesNotThrow(() => t.api.updateSnapshot({...variants.at(-1), refresh_version: 7}));
    nativeVisible(t);
    assert.equal(t.metrics.setUnit.length, expectedLoads);
    const nextScene = new t.Panel('SurvivalTowerPortraitScene', t.overlay, 'DOTAScenePanel');
    t.api.updateSnapshot({...variants.at(-1), refresh_version: 8});
    assert.equal(t.metrics.setUnit.length, ++expectedLoads);
    assert.equal(t.metrics.setUnit.at(-1).panel, nextScene);
    customVisible(t, 20, nextScene);
    t.api.shutdown('scene_replacement_complete');
}

for (const failure of ['false', 'throw']) {
    const t = setup({portrait: true});
    t.select(7, 'npc_survival_builder_proxy');
    t.scene.setUnitFailure = failure;
    t.api.portraitTransition('first_load_pending');
    t.api.updateSnapshot(builder(7, 1));
    nativeVisible(t);
    assert.equal(t.metrics.setUnit.length, 1);
    t.api.updateSnapshot(builder(7, 2));
    nativeVisible(t);
    assert.equal(t.metrics.setUnit.length, 2, 'Failed native loads never become reusable cache entries');
    t.scene.setUnitFailure = null;
    t.api.updateSnapshot(builder(7, 3));
    customVisible(t, 7);
    assert.equal(t.metrics.setUnit.length, 3, 'A later successful update retries the exact failed signature');
    t.api.portraitHide('temporary_hidden');
    t.api.updateSnapshot(builder(7, 4));
    customVisible(t, 7);
    assert.equal(t.metrics.setUnit.length, 3, 'Only a successful native load can be reused after hiding');
    t.api.shutdown('first_load_failure_complete');

    // Failure after a previous successful model must invalidate that older
    // cache as well: the native SetUnit attempt may have altered Scene content.
    const changed = setup({portrait: true});
    changed.select(20, 'building_arrow_tower');
    changed.api.updateSnapshot(tower(1));
    changed.scene.setUnitFailure = failure;
    changed.api.updateSnapshot(tower(2, {model_asset_id: 'tower_failed_attempt'}));
    nativeVisible(changed);
    assert.equal(changed.metrics.setUnit.length, 2);
    changed.scene.setUnitFailure = null;
    changed.api.updateSnapshot(tower(3));
    customVisible(changed, 20);
    assert.equal(changed.metrics.setUnit.length, 3,
        'Returning to the earlier signature must reload after any intervening failed SetUnit');
    changed.api.portraitHide('temporary_hidden');
    changed.api.updateSnapshot(tower(4));
    assert.equal(changed.metrics.setUnit.length, 3);
    changed.api.shutdown('changed_load_failure_complete');
}

{
    const commands = {};
    const ordinary = setup({portrait: true, game: {
        IsInToolsMode: () => false,
        AddCommand: (name, callback) => { commands[name] = callback; },
    }});
    assert.equal(ordinary.cfg.SurvivalPortraitSceneProbe, undefined,
        'The diagnostic API is absent outside Tools mode');
    assert.deepEqual(Object.keys(commands), []);
    selectBuilder(ordinary, 7, 1);
    assert.equal(ordinary.metrics.setUnit.length, 1);
    assert(!ordinary.messages.some(message => message.includes('[PORTRAIT_CACHE_PROBE]')));
    ordinary.api.shutdown('ordinary_game_complete');
}

{
    const commands = {};
    const t = setup({portrait: true, game: {
        IsInToolsMode: () => true,
        AddCommand: (name, callback) => { commands[name] = callback; },
    }});
    const probe = t.cfg.SurvivalPortraitSceneProbe;
    assert(probe && typeof probe.Start === 'function' && typeof probe.Stop === 'function'
        && typeof probe.Inspect === 'function');
    assert.equal(typeof commands.survival_portrait_cache_probe_v2, 'function');
    assert.equal(typeof commands.survival_portrait_cache_report_v2, 'function');
    const probeMessages = () => t.messages.filter(message => message.includes('[PORTRAIT_CACHE_PROBE]'));
    assert.equal(probe.Inspect().enabled, false);
    assert.equal(probe.Inspect().setUnitCalls, 0);
    selectBuilder(t, 7, 1);
    assert.equal(t.metrics.setUnit.length, 1);
    assert.equal(probe.Inspect().setUnitCalls, 0,
        'Tools mode alone must not enable counting of real SetUnit calls');
    assert.equal(probeMessages().length, 0);

    probe.Start();
    assert.equal(probe.Inspect().enabled, true);
    assert.equal(probe.Inspect().setUnitCalls, 0);
    t.select(20, 'building_arrow_tower');
    t.api.portraitTransition('probe_tower_selected');
    t.api.updateSnapshot(tower(1));
    assert.equal(t.metrics.setUnit.length, 2);
    assert.equal(probe.Inspect().setUnitCalls, 1, 'Only a new native load increments the enabled probe');
    assert.equal(probe.Inspect().activeEntity, 20);
    assert.equal(probe.Inspect().sceneValid, true);

    t.select(8, 'building_main_city');
    t.api.portraitTransition('probe_native_city');
    t.api.updateSnapshot(city(1));
    nativeVisible(t);
    assert.equal(probe.Inspect().activeEntity, -1);
    assert.equal(probe.Inspect().activeKey, '');
    assert(probe.Inspect().loadedKey, 'Hidden model content remains loaded while visible ownership is clear');
    t.select(20, 'building_arrow_tower');
    t.api.portraitTransition('probe_cached_return');
    t.api.updateSnapshot(tower(2));
    customVisible(t, 20);
    assert.equal(t.metrics.setUnit.length, 2);
    assert.equal(probe.Inspect().setUnitCalls, 1, 'A cached hide/return is not a native load');
    assert.equal(probeMessages().length, 0, 'Direct API calls and portrait updates do not emit probe reports');

    const stopped = probe.Stop();
    assert.equal(stopped.enabled, false);
    assert.equal(stopped.setUnitCalls, 1);
    t.api.updateSnapshot(tower(3, {portrait_item_def: '101'}));
    assert.equal(t.metrics.setUnit.length, 3);
    assert.equal(probe.Inspect().setUnitCalls, 1, 'Stop freezes counters even when another native model load occurs');

    commands.survival_portrait_cache_probe_v2();
    assert.equal(probe.Inspect().enabled, true);
    assert.equal(probe.Inspect().setUnitCalls, 0, 'Explicit start commands reset prior captured counts');
    assert.equal(probeMessages().length, 1);
    const current = tower(4, {portrait_item_def: '101', model_asset_id: 'tower_probe_changed'});
    t.api.updateSnapshot(current);
    assert.equal(probe.Inspect().setUnitCalls, 1);
    t.api.cosmeticPortraitSentinel();
    for (let frame = 0; frame < 64; frame++) {
        t.api.updateSnapshot({...current, refresh_version: frame + 5});
        t.run([...t.jobs.keys()][0]);
    }
    assert.equal(probe.Inspect().setUnitCalls, 1);
    assert.equal(probeMessages().length, 1, 'Sampling stable frames produces no per-frame probe output');
    commands.survival_portrait_cache_report_v2();
    assert.equal(probeMessages().length, 2);
    assert(probeMessages().at(-1).includes('"setUnitCalls":1'));
    probe.Stop();
    t.api.shutdown('tools_probe_complete');
    assert.equal(probe.Inspect().loadedKey, '', 'Context shutdown releases its loaded-content identity');
    assert.equal(probe.Inspect().enabled, false, 'Context shutdown disables the portrait counter');
}

{
    const config = {}, commands = {
        survival_portrait_cache_probe: () => {throw new Error('dead legacy callback');},
        survival_portrait_cache_report: () => {throw new Error('dead legacy callback');},
    };
    const game = {IsInToolsMode: () => true, AddCommand: (name, callback) => {
        if (commands[name]) throw new Error(`Cannot create ConCommand: ${name}`);
        commands[name] = callback;
    }};
    const first = setup({portrait: true, config, game});
    const firstProbe = config.SurvivalPortraitSceneProbe;
    const stableAlias = commands.survival_portrait_cache_probe_v2;
    const firstUnique = firstProbe.Commands.start;
    stableAlias();assert.equal(firstProbe.Inspect().enabled, true);
    const second = setup({portrait: true, config, game});
    const secondProbe = config.SurvivalPortraitSceneProbe;
    assert.equal(firstProbe.Inspect().enabled, false, 'new HUD shuts down the old active probe');
    assert.notEqual(firstUnique, secondProbe.Commands.start);
    assert.strictEqual(commands.survival_portrait_cache_probe_v2, stableAlias, 'stable native alias is registered once');
    assert(!second.messages.some(message => message.includes('COMMAND_ERROR')), 'hot reload never attempts duplicate AddCommand');
    stableAlias();assert.equal(secondProbe.Inspect().enabled, true, 'old live alias reads the latest API');
    assert.equal(firstProbe.Inspect().enabled, false);
    commands.survival_portrait_cache_report_v2();
    assert.equal(secondProbe.Inspect().enabled, false);
    commands.survival_portrait_cache_probe_v2 = () => {throw new Error('destroyed context');};
    commands[secondProbe.Commands.start]();
    assert.equal(secondProbe.Inspect().enabled, true, 'unique command bypasses a destroyed stable binding');
    second.api.shutdown('reloaded_tools_complete');
    assert.equal(secondProbe.Inspect().enabled, false);
    commands[secondProbe.Commands.start]();
    assert.equal(secondProbe.Inspect().enabled, false, 'dead context cannot re-enable the counter');
    assert(second.messages.at(-1).includes('start_failed'));
}

console.log('PORTRAIT_SELECTION_REUSE_PASS: ten builder/main-city cycles, 64 stat updates, entity ownership and stale packets, three signature fields, Scene replacement/disposal, false/throw recovery, successful-load-only reuse and Tools-only opt-in silent probe; rendered pixels not simulated');
