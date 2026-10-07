// Remove the four crypt-style spawn assemblies and pull their wave markers
// inward by a fixed distance while keeping the matching portal effects aligned.
'use strict';

const fs = require('fs');
const L = require('./lib.cjs');

const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Usage: node clean_spawn_visuals.cjs <text-vmap> <output-text-vmap>');

const text = fs.readFileSync(input, 'utf8');
const center = [-1024, 4096];
const moveDistance = 1000;
const removals = [];
const shifts = new Map();

for (const entity of L.blocks(text, 'CMapEntity')) {
  const name = L.value(entity.text, 'targetname') || '';
  const waveMatch = name.match(/^monsterborn_player([1-4])$/);
  const particleMatch = name.match(/^valley_decor_v1_fx_monsterborn_player([1-4])$/);

  if (/^valley_v3_spawn_reference_[0-3]_\d+$/.test(name)) {
    if (L.value(entity.text, 'classname') !== 'prop_static') {
      throw new Error(`Unexpected spawn visual class: ${name}`);
    }
    removals.push(entity);
    continue;
  }

  if (waveMatch) {
    const origin = (L.value(entity.text, 'origin') || '').split(/\s+/).map(Number);
    if (origin.length !== 3 || origin.some(value => !Number.isFinite(value))) {
      throw new Error(`Invalid spawn marker origin: ${name}`);
    }
    const dx = center[0] - origin[0];
    const dy = center[1] - origin[1];
    const distance = Math.hypot(dx, dy);
    if (distance <= moveDistance) throw new Error(`Spawn marker is already inside move radius: ${name}`);
    const next = [
      origin[0] + dx / distance * moveDistance,
      origin[1] + dy / distance * moveDistance,
      origin[2],
    ];
    shifts.set(waveMatch[1], { before: origin, after: next });
  }

  if (particleMatch) {
    const shift = shifts.get(particleMatch[1]);
    if (!shift) throw new Error(`Wave marker must precede its portal effect: ${name}`);
    const origin = (L.value(entity.text, 'origin') || '').split(/\s+/).map(Number);
    const wave = shift.before;
    if (Math.hypot(origin[0] - wave[0], origin[1] - wave[1]) > 0.1) {
      throw new Error(`Portal effect is not aligned to its wave marker: ${name}`);
    }
  }
}

if (shifts.size !== 4) throw new Error(`Expected four moved markers; found ${shifts.size}`);
if (removals.length !== 28) throw new Error(`Expected 28 spawn props (7 per point); found ${removals.length}`);

let result = text;
const edits = [];
for (const entity of L.blocks(result, 'CMapEntity')) {
  const name = L.value(entity.text, 'targetname') || '';
  const waveMatch = name.match(/^monsterborn_player([1-4])$/);
  const particleMatch = name.match(/^valley_decor_v1_fx_monsterborn_player([1-4])$/);
  if (waveMatch) {
    const position = shifts.get(waveMatch[1]).after.map(value => Number(value.toFixed(3))).join(' ');
    edits.push({ start: entity.start, end: entity.end, value: L.setValue(entity.text, 'origin', position) });
  } else if (particleMatch) {
    const shift = shifts.get(particleMatch[1]);
    const x = shift.after[0] - shift.before[0];
    const y = shift.after[1] - shift.before[1];
    const origin = (L.value(entity.text, 'origin') || '').split(/\s+/).map(Number);
    const position = [origin[0] + x, origin[1] + y, origin[2]].map(value => Number(value.toFixed(3))).join(' ');
    edits.push({ start: entity.start, end: entity.end, value: L.setValue(entity.text, 'origin', position) });
  }
}

for (const entity of removals) {
  let end = entity.end;
  while (/\s/.test(result[end] || '') && result[end] !== '\n') end++;
  if (result[end] === ',') end++;
  edits.push({ start: entity.start, end, value: '' });
}

edits.sort((a, b) => b.start - a.start);
for (const edit of edits) result = result.slice(0, edit.start) + edit.value + result.slice(edit.end);

// Removing the last children of a Hammer group can leave the preceding
// separator as a trailing comma. DMX element arrays do not accept that form.
result = result.replace(/,(\s*\])/g, '$1');

for (let id = 1; id <= 4; id++) {
  const marker = L.blocks(result, 'CMapEntity').find(entity => L.value(entity.text, 'targetname') === `monsterborn_player${id}`);
  const particle = L.blocks(result, 'CMapEntity').find(entity => L.value(entity.text, 'targetname') === `valley_decor_v1_fx_monsterborn_player${id}`);
  if (!marker || !particle) throw new Error(`Missing marker or matching effect for player ${id}`);
  const markerOrigin = L.value(marker.text, 'origin').split(/\s+/).map(Number);
  const particleOrigin = L.value(particle.text, 'origin').split(/\s+/).map(Number);
  if (Math.hypot(markerOrigin[0] - particleOrigin[0], markerOrigin[1] - particleOrigin[1]) > 0.1) {
    throw new Error(`Portal effect drifted from player ${id} marker`);
  }
  if (L.blocks(result, 'CMapEntity').some(entity => /^valley_v3_spawn_reference_[0-3]_\d+$/.test(L.value(entity.text, 'targetname') || ''))) {
    throw new Error('Spawn props remain after removal');
  }
}

fs.writeFileSync(output, result, 'utf8');
console.log(JSON.stringify({ removedSpawnProps: removals.length, movedPoints: [...shifts.entries()].map(([id, shift]) => ({ id, before: shift.before, after: shift.after })), portalEffectsMoved: 4 }));
