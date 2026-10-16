// Real Lua recipe projection -> JSON transport -> real Panorama fusion queue.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {execFileSync} = require('node:child_process');

const root = path.resolve(__dirname, '..');
const lua = process.env.LUA51 || process.env.LUA
    || (process.platform === 'win32' ? 'C:/Program Files/lua/bin/lua5.1.exe' : 'lua5.1');
const fixtureSource = String.raw`
package.path = "scripts/vscripts/?.lua;" .. package.path
local override = os.getenv("SURVIVAL_FUSION_ELIGIBILITY_SOURCE")
if override and override ~= "" then
    package.preload["systems/lumberjack_fusion_eligibility"] = function()
        return assert(loadfile(override))()
    end
end
local builder = require("ui/ability_runtime_builder")
local definitions = require("config/generated/lumberjack_fusion_definitions")
local json = require("core/json_encoder")
local function fixture(level, city, count, selected_count)
    local row = definitions.by_id[string.format("lumberjack_fusion_%02d", level)]
    local snapshot = {city_level = city, counts = {[level] = count}, eligible = {}}
    for id = 1, count do snapshot.eligible[id] = true end
    local result = {level = level, city = city, count = count,
        selected_count = selected_count or count, runtime_by_ability = {}}
    for id = 1, count do
        local unit_id = id
        local unit = {survival_player_id = 0, survival_worker_type = "lumberjack",
            survival_lumberjack_level = level}
        function unit:IsNull() return false end
        function unit:IsAlive() return true end
        function unit:entindex() return unit_id end
        function unit:GetTeamNumber() return 2 end
        local runtime = builder.build(row.ability_id, {player_id = 0, unit = unit},
            {wood = row.wood_cost, gold = row.gold_cost}, snapshot)
        -- These transport identities are added by ability_runtime_service;
        -- every recipe/city/count/cost field comes from the actual builder.
        runtime.owner_entindex = tostring(id)
        runtime.ability_name = row.ability_id
        result.runtime_by_ability[tostring(id + 1000)] = runtime
    end
    return result
end
local fixtures = {
    lv2_city3 = fixture(2, 3, 3),
    lv2_city4 = fixture(2, 4, 3),
    lv2_missing_material = fixture(2, 4, 2),
    lv2_missing_selected_material = fixture(2, 4, 3, 2),
    lv3_city4 = fixture(3, 4, 3),
    lv3_city5 = fixture(3, 5, 3),
}
for _, row in ipairs(definitions.rows) do
    fixtures["tier_" .. row.level] = fixture(row.level, row.required_city_level, row.required_count)
end
print(json.encode(fixtures))
`;
const fixtures = JSON.parse(execFileSync(lua, ['-'], {
    cwd: root, input: fixtureSource, encoding: 'utf8', windowsHide: true,
}));

// Reuse the established engine/time fixture without running its mock-recipe
// scenarios. Expose only its existing environment so the NetTables transport
// can return the real Lua payload instead of fabricated recipe metadata.
const harnessPath = path.join(root, 'tools/test_lumberjack_fusion_queue.cjs');
const harnessSource = fs.readFileSync(harnessPath, 'utf8');
const scenarioMarker = harnessSource.indexOf('let n=0;');
assert(scenarioMarker > 0, 'queue harness prelude must precede its scenarios');
const originalReturn = 'return {units,requests,cfg,advance,emit,';
const prelude = harnessSource.slice(0, scenarioMarker);
assert(prelude.includes(originalReturn), 'queue fixture environment seam must exist');
const fixtureFs = {...fs, readFileSync(file, options) {
    return fs.readFileSync(path.resolve(root, file), options);
}};
const sandbox = {
    require(name) { return name === 'node:fs' ? fixtureFs : require(name); },
};
vm.createContext(sandbox);
vm.runInContext(prelude.replace(originalReturn,
    'return {runtimeEnvironment:env,units,requests,cfg,advance,emit,')
    + '\nthis.makeHarness = harness;', sandbox, {filename: harnessPath});

function queueFor(fixture) {
    const harness = sandbox.makeHarness();
    const ids = Array.from({length: fixture.count}, (_, index) => index + 1);
    harness.add(ids, fixture.level);
    const netTables = harness.runtimeEnvironment.CustomNetTables;
    const originalGet = netTables.GetTableValue;
    netTables.GetTableValue = (table, key) => table === 'survival_ability_runtime'
        ? fixture.runtime_by_ability[String(key)] || null : originalGet(table, key);
    harness.select(ids.slice(0, fixture.selected_count).reverse());
    return harness;
}

let scenarios = 0;
function check(name, fixture, expected) {
    const runtime = fixture.runtime_by_ability['1001'];
    const queue = queueFor(fixture);
    const decorated = queue.cfg.SurvivalLumberjackFusionQueue.Decorate(1001, runtime);
    const sent = queue.cast();
    assert.equal(sent, true, `${name}: selected workers must use scoped casting`);
    assert.equal(queue.requests.length, expected.ready ? 1 : 0,
        `${name}: actual server recipe must control whether a scoped request is sent`);
    assert.equal(decorated.available, expected.ready ? 1 : 0,
        `${name}: the displayed button and cast gate must agree`);
    assert.equal(runtime.available, expected.ownerReady ? 1 : 0);
    assert.equal(runtime.prerequisite_met, expected.ownerReady ? 1 : 0);
    assert.equal(runtime.fusion_level, fixture.level);
    assert.equal(runtime.fusion_required_count, expected.requiredCount);
    assert.equal(runtime.fusion_count, fixture.count);
    assert.equal(runtime.fusion_city_level, fixture.city);
    assert.equal(runtime.fusion_required_city_level, expected.requiredCity);
    assert.equal(runtime.fusion_city_ready, fixture.city >= expected.requiredCity ? 1 : 0);
    assert.equal(runtime.cost_wood, expected.wood);
    assert.equal(runtime.cost_gold, expected.gold);
    const cityField = decorated.fields.find(field => field.label === '主城等级');
    assert.equal(cityField.value, `${fixture.city}/${expected.requiredCity}`,
        `${name}: tooltip must show actual city progress`);
    assert(!decorated.fields.some(field => field.value.includes('0/0')),
        `${name}: missing metadata cannot become a 0/0 tooltip`);
    assert.equal(decorated.fusion_count, fixture.selected_count);
    if (expected.ready) {
        const request = queue.requests[0];
        assert.equal(request.entindex, 1);
        assert.equal(request.ability_entindex, 1001);
        assert.deepEqual(Array.from(request.selected_entindexes),
            Array.from({length: fixture.selected_count}, (_, index) => index + 1));
        assert(request.fusion_queue_request_id);
    }
    console.log('PASS ' + name);
    scenarios++;
}

const lv2 = {requiredCity: 4, requiredCount: 3, wood: 20000, gold: 0};
check('LV2 main city 4: three workers and 20000 wood submit a scoped request',
    fixtures.lv2_city4, {...lv2, ready: true, ownerReady: true});
check('LV2 main city 3 stays disabled and sends no request',
    fixtures.lv2_city3, {...lv2, ready: false, ownerReady: false});
check('LV2 city 4 with only two workers stays disabled',
    fixtures.lv2_missing_material, {...lv2, ready: false, ownerReady: false});
check('LV2 owner has three workers but only two selected cannot consume outsiders',
    fixtures.lv2_missing_selected_material, {...lv2, ready: false, ownerReady: true});

const lv3 = {requiredCity: 5, requiredCount: 3, wood: 30000, gold: 5000};
check('LV3 main city 4 remains disabled',
    fixtures.lv3_city4, {...lv3, ready: false, ownerReady: false});
check('LV3 main city 5 unlocks its actual queue',
    fixtures.lv3_city5, {...lv3, ready: true, ownerReady: true});

// All tiers consume these same metadata fields; assert the actual CSV-backed
// projection agrees with the actual queue rather than guessing recipe sizes.
for (let level = 1; level <= 8; level++) {
    const fixture = fixtures['tier_' + level];
    const runtime = fixture.runtime_by_ability['1001'];
    check('configured tier ' + level + ' shares a complete queue contract', fixture, {
        ready: true, ownerReady: true, requiredCity: fixture.city,
        requiredCount: fixture.count, wood: runtime.cost_wood, gold: runtime.cost_gold,
    });
}
console.log(`LUMBERJACK_FUSION_CITY4_CONTRACT_PASS ${scenarios} real Lua -> real JS scenarios`);
