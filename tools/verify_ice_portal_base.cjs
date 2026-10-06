'use strict';
const fs = require('fs'), path = require('path'), cp = require('child_process'), assert = require('assert');
const {Vpk} = require('./map_c6/lib.cjs');
const {references} = require('./map_c6/inspect-effect-resources.cjs');
const root = path.resolve(__dirname, '..');
const pack = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
for (const theme of ['ice_portal', 'amber_portal']) {
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'art/effects', theme, 'manifest.json')));
const out = path.join(root, 'output/ice_base_reference_20261006/compiled_audit', theme);
fs.mkdirSync(out, {recursive: true});
const seen = new Set(), resources = [];
function visit(resource) {
    if (seen.has(resource)) return;
    seen.add(resource);
    const local = path.join(root, resource + '_c');
    const bytes = fs.existsSync(local) ? fs.readFileSync(local) : pack.read(resource + '_c');
    assert(bytes && bytes.length, 'Missing dependency: ' + resource);
    const deps = references(bytes);
    resources.push({resource, bytes: bytes.length, dependencies: deps});
    for (const dependency of deps) visit(dependency);
}
for (const output of manifest.outputs) visit(output.resource);
let budget = 0;
for (const output of manifest.outputs) {
    const file = path.join(root, output.resource + '_c');
    assert(fs.existsSync(file), 'Compiled output missing: ' + output.resource);
    const dump = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
        ['-i', file, '-all'], {encoding: 'utf8', windowsHide: true});
    const text = dump.slice(dump.indexOf('--- vpcf block DATA'));
    fs.writeFileSync(path.join(out, path.basename(output.resource) + '.txt'), text);
    assert(text.includes('CParticleSystemDefinition'));
    assert(!text.includes('C_OP_StopAfterCPDuration'), 'A permanent base cannot auto-stop');
    assert(!text.includes('C_OP_RenderLights') && !text.includes('C_OP_RenderScreenVelocityRotate'));
    assert(!text.includes('m_bDisableZBuffering = true'), 'Respect models/terrain depth');
    const maximum = /m_nMaxParticles = (\d+)/.exec(text);
    const cap = maximum ? Number(maximum[1]) : 0;
    assert(cap > 0, 'Every attached system has persistent visible particles');
    assert(!/m_ChildRef =/.test(text), 'Every layer gets explicit CPs, without parent inheritance');
    assert.equal(cap, output.maximum_particles, 'Compiled particle budget must match source');
    budget += cap;
    if (cap) {
        assert(text.includes('C_OP_PositionLock') || text.includes('C_OP_SetToCP'), 'Follow unit without Lua polling');
        assert(/_class = "C_OP_SetFloat"\s+m_nOutputField = 7/.test(text), 'Recover opacity after late CPs');
    }
    if (output.resource.endsWith('/ground.vpcf')) {
        assert.equal(cap, 17);
        assert.equal((text.match(/_class = "C_OP_RenderRopes"/g) || []).length, 2, 'Two native ring layers share one simulation');
        assert(text.includes('m_flRadiusScale = 0.2'), 'Preserve thinner native core');
        assert(text.includes('C_OP_ConstrainDistance') && text.includes('m_fMinDistance') && text.includes('m_fMaxDistance'));
        assert(text.includes('m_flOutput0 = 1.0') && text.includes('m_flOutput1 = 145.0'), 'Nonzero seed and bounded radius survive compilation');
        assert(text.includes('m_flParticlesPerOrbit = 16.0'), '17 points form one closed 16-segment ring');
        assert(!text.includes('C_OP_BasicMovement'), 'Ring cannot keep expanding over time');
    }
    if (output.resource.endsWith('/sparkles.vpcf')) {
        assert(text.includes('m_flLiteralValue = 3.0') && text.includes('m_flLiteralValue = 1.2'));
        assert.equal(cap, 6);
    }
}
assert.equal(budget, 27);
const profile = fs.readFileSync(path.join(root, 'scripts/vscripts/config/generated/tower_visual_profiles.lua'), 'utf8');
assert(/profile_id = "class_6"[^\n]*native_base = "io_blue_portal"/.test(profile));
const service = fs.readFileSync(path.join(root, 'scripts/vscripts/systems/tower_visual_service.lua'), 'utf8');
assert(service.includes('io_blue_portal = "ice_portal"') && service.includes('io_amber_portal = "amber_portal"'));
assert.equal(manifest.outputs.length, 4);
const report = {status: 'PASS', systems: manifest.outputs.length, maximum_particles: budget,
    resources, in_game_visual_verified: false, in_game_gpu_cost_measured: false};
fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(theme.toUpperCase() + '_RESOURCE_PASS systems=' + manifest.outputs.length + ' particles<=' + budget +
    ' dependencies=' + resources.length + '; persistent/follow/depth/late CP/bounded ring/native textures');
}
