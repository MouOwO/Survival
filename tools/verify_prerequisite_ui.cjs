'use strict';
const fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'output/prerequisite_shading_20261008/regression_final');
fs.mkdirSync(out, {recursive: true});
const lua = 'C:/Program Files/lua/bin/lua5.1.exe';
const luaTests = [
    'test_native_prerequisite_activation',
    'test_research_runtime_projection', 'test_research_catalog_prerequisites',
    'test_resource_ui_coalescing', 'test_research_production_auto', 'test_production_ui_router',
    'test_building_upgrade_lifecycle', 'test_tower_class_preflight', 'test_wall_quick_upgrade',
    'test_lumberjack_fusion_runtime', 'test_lumberjack_fusion',
    'test_lumberjack_fusion_ui', 'test_lumberjack_training_queue_integration',
    'test_hero_summon_runtime_availability'
].map(name => 'scripts/vscripts/tests/' + name + '.lua');
const luaTools = ['test_upgrade_prerequisite_projection.lua', 'test_lumberjack_fusion_runtime.lua', 'test_tower_upgrade_visibility.lua'];
const jsTests = [
    'test_shop_prerequisites.cjs', 'test_shop_shared_ui.cjs', 'test_shop_v2_tooltip.cjs',
    'test_production_hud.cjs', 'test_action_resources_tooltip.cjs', 'test_prerequisite_shading.cjs',
    'test_lumberjack_fusion_queue.cjs', 'test_research_hud_completion.cjs',
    'test_ability_tooltip_stability.cjs', 'test_ability_tooltip_recovery.cjs',
    'test_tower_auto_upgrade_input.cjs', 'test_paid_hero_ui.cjs'
];
const rows = [];
for (const [command, files] of [[lua, luaTests.concat(luaTools.map(name => 'tools/' + name))],
    [process.execPath, jsTests.map(name => 'tools/' + name)]]) {
    for (const file of files) {
        const result = cp.spawnSync(command, [file], {cwd: root, encoding: 'utf8',
            env: {...process.env, LUA: lua, LUA_BIN: lua},
            windowsHide: true, timeout: 60000, maxBuffer: 8e6});
        fs.writeFileSync(path.join(out, file.replace(/[\\/]/g, '_') + '.log'),
            (result.stdout || '') + (result.stderr || ''));
        const passed = result.status === 0;
        rows.push({file, passed, exit_code: result.status, error: result.error?.message});
        console.log((passed ? 'PASS ' : 'FAIL ') + file);
    }
}
fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify({created_at: new Date().toISOString(),
    scope: 'Offline production Lua and Panorama behavior regressions; game not running', tests: rows}, null, 2));
console.log('REGRESSIONS ' + rows.filter(row => row.passed).length + '/' + rows.length);
if (rows.some(row => !row.passed)) process.exitCode = 1;
