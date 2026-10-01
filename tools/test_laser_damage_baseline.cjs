const fs = require('fs');
const assert = require('assert');
const {execFileSync} = require('child_process');
const baseline = 'bab1753e';
const normalize = text => text.replace(/\r\n/g, '\n').trim();
const current = path => normalize(fs.readFileSync(path, 'utf8'));
const original = path => normalize(execFileSync('git', ['show', baseline + ':' + path], {encoding:'utf8', windowsHide:true}));
function section(text, start, end) {
    const from = text.indexOf(start);
    const to = text.indexOf(end, from + start.length);
    assert(from >= 0 && to > from, 'baseline markers must exist');
    return text.slice(from, to);
}
const path = 'scripts/vscripts/modifiers/modifier_tower_attack_effects.lua';
const before = original(path), after = current(path);
const tickStart = 'local function deal_laser_tick(';
const tickEnd = '\nfunction modifier_tower_attack_effects:OnIntervalThink';
const tick = section(after, tickStart, tickEnd).replace(
    /    local hit_position = effect\.target_surface == true[\s\S]*?    if hit_position then laser_visual\.hit\(caster, hit_position, result\) end/,
    '    deal(caster, target, amount)');
assert.equal(tick, section(before, tickStart, tickEnd), 'damage, multiplier, event and tick accounting match the original');
for (const [start,end] of [
    ['    self.laser_elapsed = self.laser_elapsed + elapsed', '\nfunction modifier_tower_attack_effects:OnAttackStart'],
    ['        if start_laser(self, target, effect) then', '\nfunction modifier_tower_attack_effects:OnAttack(params)'],
]) assert.equal(section(after,start,end), section(before,start,end), 'original timing and immediate hit are preserved');
const multiplier = 'scripts/vscripts/systems/tower_laser_damage.lua';
assert.equal(current(multiplier), original(multiplier), 'original multiplier function is unchanged');
const skills = 'data/csv/建筑与工人系统/防御塔/tower_skill_definitions.csv';
function values(csv) {
    return csv.split('\n').filter(line => line.startsWith('laser_lv')).map(line => {
        const fields = line.split(',');
        return [fields[0], fields[11], fields[12]];
    });
}
assert.equal(values(current(skills)).length, 5);
assert.deepEqual(values(current(skills)), values(original(skills)), 'all five damage intervals and multipliers are unchanged');
assert(!after.includes('laser_damage_state') && !after.includes('damage_tick_interval'));
console.log('LASER_BASELINE_PASS: original hit arithmetic, event accounting, first hit, cadence and five skill values');
