'use strict';
// Compile success alone does not reject unknown/legacy particle operators.
// Verify the actual DATA after Valve's format migration and resolve resources.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');
const { packs, references } = require('./inspect-effect-resources.cjs');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, 'output/effect_reference/compiled_validation');
fs.mkdirSync(output, { recursive: true });
const towerSource = JSON.parse(fs.readFileSync(path.join(root, 'art/effects/tower_bases/source_manifest.json')));
const weapons = ['weapon_glow', 'weapon_trail', 'weapon_shards'].map(name => ({
  resource: 'particles/survival/weapons/' + name + '.vpcf', name,
}));
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function sameTowerEvidence(previous, records, inputs) {
  if (!previous || !Array.isArray(previous.records) || previous.records.length !== records.length
      || !previous.art_inputs || JSON.stringify(previous.art_inputs) !== JSON.stringify(inputs)) return false;
  const old = new Map(previous.records.map(row => [row.resource, row]));
  return old.size === records.length && records.every(row => {
    const before = old.get(row.resource);
    return before && row.source_sha256 && before.source_sha256 === row.source_sha256 && before.sha256 === row.sha256;
  });
}
function verify(rows, family) {
  const records = [];
  for (const row of rows) {
    const resource = row.resource + '_c', absolute = path.join(root, resource);
    const bytes = fs.readFileSync(absolute);
    let sourceSha;
    if (family === 'towers') {
      const source = fs.readFileSync(path.join(root, 'art/effects/tower_bases/source', row.resource));
      const content = fs.readFileSync(path.resolve(root, '../../../content/dota_addons/survival', row.resource));
      if (!source.equals(content)) throw Error('Tower source/content mismatch: ' + row.resource);
      sourceSha = sha256(source);
    }
    for (const dep of references(bytes)) {
      if (!fs.existsSync(path.join(root, dep + '_c')) && !packs.valve.entries.has(dep + '_c')) {
        throw Error('Unresolved particle dependency: ' + dep);
      }
    }
    const result = cp.spawnSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
      ['-i', absolute, '-all'], { encoding: 'utf8', windowsHide: true });
    if (result.status !== 0) throw Error(result.stderr || 'resourceinfo failed');
    const data = result.stdout.slice(result.stdout.indexOf('--- vpcf block DATA'));
    if (/_class = "C_INIT_CreateWithinSphere"/.test(data)) {
      throw Error('Unmigrated legacy sphere operator: ' + resource);
    }
    if (!data.includes('C_INIT_CreateWithinSphereTransform')
        || !data.includes('C_OP_SetFloat')
        || !data.includes('m_nOutputField = 7')
        || data.includes('m_nOpEndCapState = ""')) {
      throw Error('Incomplete particle operator migration/alpha contract: ' + resource);
    }
    if (family === 'towers' && !data.includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED')) {
      throw Error('Tower ornament is not ground aligned: ' + resource);
    }
    if (family === 'towers' && (data.match(/_class = "C_OP_SetFloat"/g) || []).length < 2) {
      throw Error('Tower size must update the actual particle radius as well as alpha: ' + resource);
    }
    // Resource serialization omits the native 1.0 default on alpha/MOD2X
    // renderers. Compare the effective value instead of requiring that line.
    const overbright = Number(data.match(/m_flOverbrightFactor = ([\d.]+)/)?.[1] || 1);
    if (family === 'towers' && (!data.includes(row.texture)
        || Math.abs(overbright - row.overbright) > 0.00001
        || data.includes('m_bDisableZBuffering = true')
        || !data.includes('C_OP_SetToCP'))) {
      throw Error('Compiled tower must retain current texture, bounded bloom, depth testing and CP follow: ' + resource);
    }
    if ((row.blend === 'alpha' || row.name === 'weapon_shards')
        && data.includes('PARTICLE_OUTPUT_BLEND_MODE_ADD')) {
      throw Error('Alpha-mask texture cannot use RGB-only additive blending: ' + resource);
    }
    if (row.name === 'base_death_void' && (
        !data.includes('PARTICLE_OUTPUT_BLEND_MODE_MOD2X')
        || !data.includes('materials/particle/particle_modulate_03.vtex')
        || data.includes('m_ConstantColor = [ 0, 0, 0,'))) {
      throw Error('Death center must use the native Enigma modulate texture/blend, never a black-tinted white rectangle.');
    }
    if (family === 'weapons' && !data.includes('PF_MAP_TYPE_MULT')) {
      throw Error('Weapon CP inputs must use the explicit direct-value multiplier mapping.');
    }
    if (row.name === 'weapon_glow' && (data.includes('m_bDisableZBuffering = true')
        || !data.includes('materials/particle/particle_glow_01.vtex'))) {
      throw Error('Weapon glow must use a RGB/Alpha soft mask and normal depth testing at the weapon attachment.');
    }
    const dump = path.join(output, row.name + '.txt');
    fs.writeFileSync(dump, result.stdout);
    const logName = (family === 'towers' ? 'compile_tower_' : 'compile_') + row.name + '.log';
    const log = fs.readFileSync(path.join(root, 'output/effect_reference', logName), 'utf8');
    if (!/0 failed/.test(log) || log.includes('RESOURCE COMPILE ERROR')) {
      throw Error('Failed compile log: ' + logName);
    }
    records.push({ resource, bytes: bytes.length,
      sha256: sha256(bytes), ...(sourceSha ? { source_sha256: sourceSha } : {}),
      dependencies: references(bytes), total_max_particles: row.total_max_particles,
      data_dump: path.relative(root, dump).replace(/\\/g, '/') });
  }
  return records;
}
function main() {
const familyIndex = process.argv.indexOf('--family');
const family = familyIndex < 0 ? 'all' : process.argv[familyIndex + 1];
if (!['all', 'towers', 'weapons'].includes(family)) throw Error('--family must be all, towers or weapons');
const towerRecords = family === 'weapons' ? [] : verify(towerSource.resources, 'towers');
const weaponRecords = family === 'towers' ? [] : verify(weapons, 'weapons');
for (const [folder, records] of [['tower_bases', towerRecords], ['weapon_visuals', weaponRecords]]) {
  if (!records.length) continue;
  const file = path.join(root, 'art/effects', folder, 'validation.json');
  const previous = JSON.parse(fs.readFileSync(file));
  if (folder === 'tower_bases') {
    const inputs = {
      manifest_sha256: sha256(fs.readFileSync(path.join(root, 'art/effects/tower_bases/source_manifest.json'))),
      profiles_sha256: sha256(fs.readFileSync(path.join(root, 'data/csv/资源系统/tower_visual_profiles.csv'))),
      service_sha256: sha256(fs.readFileSync(path.join(root, 'scripts/vscripts/systems/tower_visual_service.lua'))),
    };
    const keepWorkshop = sameTowerEvidence(previous, records, inputs)
      && previous.workshop && /^PASS/.test(previous.workshop.result || '');
    if (!keepWorkshop) {
      if (previous.workshop && /^PASS/.test(previous.workshop.result || '')) {
        previous.previous_art_workshop = previous.workshop;
      }
      previous.workshop = { result: 'NOT_VERIFIED', reason: 'No Workshop acceptance matches the current source, compiled resources and profile/service hashes.' };
      previous.validation = previous.validation.filter(line => !line.startsWith('WORKSHOP:'));
    }
    previous.art_revision = towerSource.art_revision;
    previous.art_inputs = inputs;
  }
  previous.validation = previous.validation.filter(line => !line.startsWith('COMPILE:') && !line.startsWith('DATA:'));
  previous.validation = previous.validation.map(line => line.replace('CP1.x dynamic renderer radius', 'CP1.x dynamic particle radius'));
  if (folder === 'tower_bases') {
    previous.validation = previous.validation.map(line => line
      .replace(/all \d+ compiled VPCFs/, 'all ' + towerRecords.length + ' compiled VPCFs')
      .replace(/Z\+\d+\.\.\d+/, 'Z+12..18'));
  }
  previous.validation.push('COMPILE: all targets zero failed; source format vpcf45 intentionally triggers legacy operator migration');
  previous.validation.push('DATA: all sphere initializers migrated to CreateWithinSphereTransform; no zero-default legacy operator; C_OP_SetFloat continuously reads alpha from CP1.z');
  previous.review_fixes = [
    'Alpha-only sprite masks use native alpha blending, not RGB-only additive blending (target glyphs, ground symbols, leaves and snowflakes).',
    'Tower radius now writes actual particle radius for culling/occlusion; renderer radius multiplier remains 1.',
    'Electrical base uses a full circular texture; rope/half-rune strips are excluded from sprite disks.',
  ];
  if (folder === 'tower_bases') previous.review_fixes.push(
    'Source refinement: R/SR/SSR/UR radii are 96/100/112/128; additive overbright is 1.2; ground layers remain +12..18 with normal depth testing. New appearance requires cold Workshop review.',
    'Anti-air uses native ping_world_crosshairs3 circular aiming art. SR/SSR select contained profession-specific details; only mystery uses witch_rune. Red-star/UR glints remain inside the main circle.',
    'Death center uses native Enigma particle_modulate_03/MOD2X at 0.65x radius; the screenshot rectangle was separately confirmed to be the N5 tower model shadow.',
    'Frost uses fine native ground cracks; lightning/frost boundary uses Enigma softouter texture at 0.20x profile alpha instead of a hard ring.');
  else previous.review_fixes.push(
    'Weapon CP scalar inputs explicitly map by multiplier 1; glow/trail use particle_glow_01 with soft RGB and alpha, not a white-RGB alpha-only mask.',
    'Weapon visuals retain depth testing; Workshop confirmed body attachment occlusion, so runtime binds the actual sword attachment instead of rendering through the hero.');
  if (folder === 'tower_bases') previous.records = records;
  else previous.resources = records;
  previous.total_bytes = records.reduce((n, r) => n + r.bytes, 0);
  fs.writeFileSync(file, JSON.stringify(previous, null, 2) + '\n');
}
console.log(JSON.stringify({ verified: towerRecords.length + weaponRecords.length,
  towers: towerRecords.length, weapons: weaponRecords.length, format: 'vpcf45 -> engine Transform operators' }));
}
if (require.main === module) main();
module.exports = { sameTowerEvidence };
