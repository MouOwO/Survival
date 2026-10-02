'use strict';
// Source-only preflight. Does not deploy/compile resources or claim Workshop
// appearance, GPU cost or FPS. Runtime tier/lifecycle is tested separately.
const fs = require('fs'), path = require('path'), assert = require('assert'), crypto = require('crypto');
const { packs } = require('./map_c6/inspect-effect-resources.cjs');
const { sameTowerEvidence } = require('./map_c6/verify-visual-particles.cjs');
const root = path.resolve(__dirname, '..');
const sourceRoot = path.join(root, 'art/effects/tower_bases/source');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'art/effects/tower_bases/source_manifest.json')));
const byName = new Map(manifest.resources.map(row => [row.name, row]));
assert.equal(byName.size, manifest.resources.length, 'duplicate resource name');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const records = [];
for (const row of manifest.resources) {
  const source = fs.readFileSync(path.join(sourceRoot, row.resource), 'utf8');
  assert(packs.valve.entries.has(row.texture + '_c'), 'missing Valve texture: ' + row.texture);
  assert(source.includes('m_nMaxParticles = 1'), 'one sprite per system');
  assert(source.includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'));
  assert(source.includes('C_OP_SetToCP') && !source.includes('C_INIT_PositionOffset'));
  assert(!source.includes('m_bDisableZBuffering = true'), 'normal depth testing must remain enabled');
  const offset = source.match(/_class = "C_OP_SetToCP" m_vecOffset = \[([^\]]+)\]/);
  assert(offset && offset[1].split(',').every(n => /^-?\d+\.\d+$/.test(n.trim())), 'native FLOAT position vector');
  assert(row.overbright <= 1.2, 'bounded bloom');
  assert.equal((source.match(/_class = "C_OP_SetFloat"/g) || []).length, 2, 'continuous radius and alpha');
  const children = [...source.matchAll(/m_ChildRef = resource:"particles\/survival\/towers\/bases\/([^"/]+)\.vpcf"/g)].map(m => m[1]);
  assert.deepEqual(children, row.children);
  for (const child of children) assert(byName.get(child)?.internal, 'only explicit internal children');
  if (row.texture.includes('witch_rune')) assert(row.name.includes('mystery'), 'arcane rune is exclusive to mystery');
  assert(!source.includes('gyro_ti10_immortal_missile_target'), 'no square anti-air lock-on sprite');
  if (row.name.startsWith('detail_')) {
    assert(!children.length, 'tier detail cannot add child systems');
    assert(row.radius_scale < 1, 'detail remains inside core footprint');
  }
  records.push({ resource: row.resource, source_sha256: hash(source), texture: row.texture,
    total_max_particles: row.total_max_particles });
}
function spriteCount(name, active = new Set()) {
  name = name.replace(/^bases\//, '');
  assert(!active.has(name), 'cyclic child dependency');
  assert(byName.has(name), 'unknown profile resource: ' + name);
  const row = byName.get(name);
  const next = new Set(active).add(name);
  const count = 1 + row.children.reduce((n, child) => n + spriteCount(child, next), 0);
  assert.equal(count, row.total_max_particles, 'manifest must count child sprites');
  return count;
}
const csvPath = path.join(root, 'data/csv/资源系统/tower_visual_profiles.csv');
const csv = fs.readFileSync(csvPath, 'utf8');
const rows = csv.trim().split(/\r?\n/).filter(line => !line.startsWith('#')).map(line => line.split(','));
const headers = rows.shift();
const budgets = [];
const seenDetails = new Set();
const oldCoreSprites = { class_1: 2, class_2: 1, class_3: 2, class_4: 1, class_5: 4, class_6: 2, class_7: 1, ultimate: 1 };
for (const values of rows) {
  assert.equal(values.length, headers.length);
  const row = Object.fromEntries(headers.map((key, i) => [key, values[i]]));
  assert.deepEqual(['r', 'sr', 'ssr', 'ur'].map(tier => +row['radius_' + tier]), row.profile_id === 'ultimate' ? [96, 100, 112, 128] : [96, 108, 120, 128]);
  assert(+row.alpha > 0 && +row.alpha <= 0.95);
  if (row.native_base) {
    assert(['leshrac_edict','bulldoze','psionic_trap','dazzle_weave','willow_shadow_realm','kinetic_markers','clinkz_embers','ice_vortex'].includes(row.native_base));
    if (row.native_base === 'willow_shadow_realm') {
      assert.equal(row.profile_id, 'class_1', 'Shadow Realm ground belongs only to the death route');
      assert.deepEqual([row.color_r, row.color_sr, row.color_ssr], ['25|219|241', '180|95|255', '255|52|83']);
      assert.equal(row.alpha, '0.95');
    }
    for (const key of ['core','detail','detail_ssr','crown']) assert.equal(row[key], '', 'replaced base retains legacy image');
    budgets.push({profile:row.profile_id,native_base:row.native_base,legacy_sprites:0,
      handles:{n:0,r:['bulldoze','psionic_trap'].includes(row.native_base)?2:1,sr:['bulldoze','psionic_trap'].includes(row.native_base)?2:1,
        ssr:['bulldoze','psionic_trap'].includes(row.native_base)?2:1,red_ssr_or_ur:['bulldoze','psionic_trap'].includes(row.native_base)?2:1}});
    continue;
  }
  const core = spriteCount(row.core), sr = core + spriteCount(row.detail), ssr = core + spriteCount(row.detail_ssr);
  const red = ssr + spriteCount(row.crown);
  assert(core <= oldCoreSprites[row.profile_id] && sr <= oldCoreSprites[row.profile_id] + 1);
  assert(ssr <= oldCoreSprites[row.profile_id] + 1 && red <= oldCoreSprites[row.profile_id] + 2);
  if (row.profile_id !== 'ultimate') {
    assert.notEqual(row.detail, row.detail_ssr, 'SSR selects a tier-specific detail');
    assert(!seenDetails.has(row.detail) && !seenDetails.has(row.detail_ssr), 'profession detail is not a shared generic rune');
    seenDetails.add(row.detail); seenDetails.add(row.detail_ssr);
  }
  budgets.push({ profile: row.profile_id, n: 0, r: core, sr, ssr, red_ssr_or_ur: red,
    handles: { n: 0, r: 1, sr: 2, ssr: 2, red_ssr_or_ur: 3 } });
}
const result = { status: 'SOURCE_AND_NATIVE_DEPENDENCIES_PASS', art_revision: manifest.art_revision,
  scope: 'Source/preflight only; compile and cold Workshop visual acceptance are separate and not performed by this test.',
  csv_sha256: hash(csv), service_sha256: hash(fs.readFileSync(path.join(root, 'scripts/vscripts/systems/tower_visual_service.lua'))),
  resources: records.length, native_textures: new Set(records.map(r => r.texture)).size,
  profession_details: seenDetails.size, max_legacy_sprites_per_tower: Math.max(...budgets.map(b => b.red_ssr_or_ur || 0)),
  max_top_level_handles: 3, budgets, records };
// Re-running static checks must never carry old manual acceptance onto changed
// source, compiled output, runtime mapping or profile values.
const acceptedRows = [{resource:'a',source_sha256:'source',sha256:'compiled'}];
const acceptedInputs = {manifest_sha256:'manifest',profiles_sha256:'csv',service_sha256:'service'};
const accepted = {records:acceptedRows,art_inputs:acceptedInputs};
assert(sameTowerEvidence(accepted, acceptedRows, acceptedInputs));
assert(!sameTowerEvidence(accepted, [{...acceptedRows[0],source_sha256:'changed'}], acceptedInputs));
assert(!sameTowerEvidence(accepted, [{...acceptedRows[0],sha256:'changed'}], acceptedInputs));
assert(!sameTowerEvidence(accepted, [], acceptedInputs));
assert(!sameTowerEvidence(accepted, acceptedRows, {...acceptedInputs,profiles_sha256:'changed'}));
assert(!sameTowerEvidence(accepted, acceptedRows, {...acceptedInputs,service_sha256:'changed'}));
assert(!sameTowerEvidence({records:acceptedRows}, acceptedRows, acceptedInputs));
const report = path.join(root, 'output/tower_base_refine/source_preflight.json');
fs.mkdirSync(path.dirname(report), { recursive: true });
fs.writeFileSync(report, JSON.stringify(result, null, 2) + '\n');
console.log('TOWER_BASE_SOURCE_PASS resources=' + records.length + ' professions=7 max_handles=3 max_actual_sprites=6 native_textures=' + result.native_textures);
