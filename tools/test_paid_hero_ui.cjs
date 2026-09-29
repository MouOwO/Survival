// Exercise the actual UI guard with nettables produced by the real Lua services.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const output = execFileSync('lua', ['scripts/vscripts/tests/test_paid_hero_unlock.lua', '--client-fixtures'],
    {cwd: root, encoding: 'utf8', windowsHide: true});
const prefix = 'HERO_RUNTIME_FIXTURES:';
const fixtures = JSON.parse(output.split(/\r?\n/).find(line => line.startsWith(prefix)).slice(prefix.length));
const script = fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game/ui_bootstrap.js'), 'utf8');
const guardSource = script.split('// BEGIN hero summon initial availability')[1]
    .split('// END hero summon initial availability')[0];
const cfg = {};
let localPlayer = 1, abilityName = 'ability_summon_monkey_king';
vm.runInNewContext(guardSource, {
    GameUI: {CustomUIConfig: () => cfg},
    Game: {GetLocalPlayerID: () => localPlayer},
    Abilities: {GetAbilityName: () => abilityName},
});
const guard = runtime => cfg.SurvivalHeroSummonAvailability(1100, runtime);
assert.equal(guard(fixtures.owned).available, 1, 'paid owner must leave the syncing lock');
assert.equal(guard(fixtures.owned).status_text, '可召唤');
assert.equal(guard(fixtures.pure).available, 0, 'pure mode keeps old account items filtered');
assert.equal(guard({available: 1}).available, 0, 'generic/default availability cannot grant paid access');
assert.equal(guard(undefined).available, 0, 'missing nettable must fail closed');
localPlayer = 0;
assert.equal(guard(fixtures.owned).available, 0, 'teammate purchase cannot unlock local button');
assert.equal(guard(fixtures.unowned).available, 0);
assert.equal(guard(fixtures.revoked).available, 0);
localPlayer = 2;
assert.equal(guard(fixtures.unloaded).available, 0);
localPlayer = 1;
abilityName = 'ability_summon_blademaster';
assert.equal(guard(fixtures.other_hero).available, 0, 'Monkey King purchase is not VIP');
abilityName = 'ability_summon_doom';
assert.equal(guard({available: 1}).available, 1, 'free heroes are unaffected');
console.log('PAID_HERO_UI_PASS: actual server nettable -> actual client guard');
