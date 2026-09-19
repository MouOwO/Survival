// Independent ten-realm art map and origin-centered prefabs. No gameplay map is edited.
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const ns = 'ten_realm_arenas';
const out = path.join(root, 'output', ns);
const sourceDir = path.join(out, 'source');
const assets = JSON.parse(fs.readFileSync(path.join(out, 'asset_manifest.json'), 'utf8').replace(/^\uFEFF/, ''));
if (!Array.isArray(assets) || assets.length !== 10) throw Error('Expected ten realm assets.');
const zbase = 128, halfExtent = 4096, tileCount = 32, navCount = 128, navCellSize = 64;
const supportRecess = .75, supportThickness = 4, markerClearance = 24;
const finiteVector = (value, size) => Array.isArray(value) && value.length === size && value.every(Number.isFinite);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function collisionCount(asset) {
  let count = asset.collision_count ?? asset.collision_hulls;
  if (count === undefined) {
    count = Array.isArray(asset.collision) ? asset.collision.length : asset.collision;
  }
  if (!Number.isInteger(count) || count <= 0) throw Error('Missing authored collision count: ' + asset.name);
  if (asset.collision_count !== undefined && asset.collision_hulls !== undefined
    && asset.collision_count !== asset.collision_hulls) throw Error('Collision count fields differ: ' + asset.name);
  return count;
}
const realms = assets.map(asset => ({...asset, ...(asset.meta || {}), name: asset.name,
  collision_count: collisionCount(asset)})).sort((a, b) => a.rank - b.rank);
for (let i = 0; i < realms.length; i++) {
  const r = realms[i], rank = i + 1, key = String(rank).padStart(2, '0');
  if (r.rank !== rank || r.name !== `realm_${key}` || !same(r.footprint, [700, 700])
    || !same(r.clear_combat_size, [612, 612]) || r.deck_z !== 0 || r.water_z !== -42) {
    throw Error('Realm spatial specification mismatch: ' + r.name);
  }
  if (!same(r.review_xy, [rank % 2 ? -700 : 700, (Math.floor(i / 2) - 2) * 1280])
    || !same(r.entry, [0, -234, 0]) || !same(r.spawn, [0, 234, 0])
    || r.entry_marker !== `challenge_11_stage_${key}_entry`
    || r.spawn_marker !== `challenge_11_stage_${key}_spawn`) {
    throw Error('Realm placement/marker contract mismatch: ' + r.name);
  }
  if (!(r.wall_height > 0) || !Array.isArray(r.bounds) || r.bounds.length !== 2
    || !r.bounds.every(b => finiteVector(b, 3))
    || r.bounds[0].some((n, axis) => n > r.bounds[1][axis])
    || r.bounds.some(b => b.slice(0, 2).some(n => Math.abs(n) > 580.01))) {
    throw Error('Invalid complete model bounds (including the exterior shore): ' + r.name);
  }
}
// Space using the complete modeled shore/plant envelope, not the 700-square inner platform.
const envelopes = realms.map(r => ({rank: r.rank, name: r.name,
  min: r.bounds[0].slice(0, 2).map((n, axis) => n + r.review_xy[axis]),
  max: r.bounds[1].slice(0, 2).map((n, axis) => n + r.review_xy[axis])}));
let minEnvelopeClearance = Infinity;
for (let i = 0; i < envelopes.length; i++) {
  const a = envelopes[i];
  if (a.min.some(n => n < -halfExtent) || a.max.some(n => n > halfExtent)) {
    throw Error('Complete realm model exceeds the review map: ' + a.name);
  }
  for (let j = 0; j < i; j++) {
    const b = envelopes[j];
    if ([0, 1].every(axis => a.min[axis] < b.max[axis] && b.min[axis] < a.max[axis])) {
      throw Error('Complete realm envelopes overlap: ' + a.name + ' / ' + b.name);
    }
    const gaps = [0, 1].map(axis => Math.max(a.min[axis] - b.max[axis], b.min[axis] - a.max[axis], 0));
    minEnvelopeClearance = Math.min(minEnvelopeClearance, Math.hypot(...gaps));
  }
}
const occupiedBounds = [[0, 1].map(axis => Math.min(...envelopes.map(p => p.min[axis]))),
  [0, 1].map(axis => Math.max(...envelopes.map(p => p.max[axis])))];
const helperSource = fs.readFileSync(path.join(__dirname, 'build_zombie_abyss_map.cjs'), 'utf8');
const prefix = helperSource.slice(0, helperSource.indexOf("water('central_sea'"))
  .replace('../output/zombie_island_v1', '../output/' + ns)
  .replace('zombie-abyss-v1-', 'ten-realm-arenas-review-');
const {children, entity, prism} = new Function('require', '__dirname', prefix + '\nreturn {children,entity,prism};')(require, __dirname);
const materialDir = path.join(sourceDir, 'materials', ns);
fs.mkdirSync(materialDir, {recursive: true});
const supportMaterial = `materials/${ns}/floor_support.vmat`;
const supportSource = fs.readFileSync(path.join(materialDir, 'mortar.vmat'), 'utf8');
if (/"Attributes"/.test(supportSource)) throw Error('mortar.vmat unexpectedly already has Attributes.');
fs.writeFileSync(path.join(materialDir, 'floor_support.vmat'), supportSource.replace(/}\s*$/,
  '"Attributes" { "dota.nav.walkable" "1" "mapbuilder.nodraw" "1" }\n}\n'));
// Preserve the proven ocean shader but own its dependencies. These ocean_* names
// cannot overwrite the realm geometry palette's separate water_* textures.
const waterReferenceDir = path.join(root, 'output/main_island/source/materials/main_island');
let waterSource = fs.readFileSync(path.join(waterReferenceDir, 'ocean_surface.vmat'), 'utf8');
const waterDependencies = [];
for (const suffix of ['color', 'normal', 'reflectance']) {
  const filename = `ocean_${suffix}.png`, relative = `materials/${ns}/${filename}`;
  fs.copyFileSync(path.join(waterReferenceDir, `water_${suffix}.png`), path.join(materialDir, filename));
  waterSource = waterSource.replaceAll(`materials/main_island/water_${suffix}.png`, relative);
  waterDependencies.push(relative);
}
if (/materials\/main_island\//.test(waterSource)) throw Error('Unexpected unowned dependency in ocean shader.');
if (!/"mapbuilder.nonsolid"\s*"1"/.test(waterSource)
  || !/"mapbuilder.water"\s*"1"/.test(waterSource)) throw Error('Ocean must retain nonsolid water attributes.');
const waterMaterial = `materials/${ns}/ocean_surface.vmat`;
fs.writeFileSync(path.join(materialDir, 'ocean_surface.vmat'), waterSource, 'utf8');
function box(x, y, width, depth, top, bottom, material) {
  prism([[x-width/2, y-depth/2], [x+width/2, y-depth/2], [x+width/2, y+depth/2], [x-width/2, y+depth/2]],
    top, bottom, material, material, '255 255 255 255');
}
function addRealm(realm, origin) {
  const [x, y, z] = origin, key = String(realm.rank).padStart(2, '0');
  const deckZ = z + realm.deck_z, top = deckZ - supportRecess, bottom = top - supportThickness;
  const [width, depth] = realm.clear_combat_size;
  box(x, y, width, depth, top, bottom, supportMaterial);
  entity('prop_static', `ten_realm_arena_${key}_model`, origin,
    {model: `models/${ns}/${realm.name}.vmdl`, solid: '6', rendercolor: '255 255 255', disableshadows: '0'}, '0 0 0', 1);
  const floorMarkers = [
    {name: realm.entry_marker, kind: 'entry', local_floor_position: realm.entry},
    {name: realm.spawn_marker, kind: 'spawn', local_floor_position: realm.spawn},
    {name: `ten_realm_arena_${key}_center`, kind: 'center', local_floor_position: [0, 0, realm.deck_z]},
  ];
  const markers = floorMarkers.map(marker => {
    const position = marker.local_floor_position.map((n, axis) => n + origin[axis] + (axis === 2 ? markerClearance : 0));
    entity('info_target', marker.name, position);
    return {...marker, rank: realm.rank, origin: position, spawn_clearance: markerClearance};
  });
  const modelBounds = realm.bounds.map(b => b.map((n, axis) => n + origin[axis]));
  const support = {rank: realm.rank, name: realm.name, origin: [x, y, (top+bottom)/2],
    size: [width, depth], top, bottom, material: supportMaterial, rendered: false,
    bounds: [[x-width/2, y-depth/2, bottom], [x+width/2, y+depth/2, top]],
    polygon: [[x-width/2, y-depth/2], [x+width/2, y-depth/2], [x+width/2, y+depth/2], [x-width/2, y+depth/2]]};
  const placement = {name: realm.name, rank: realm.rank, label: realm.label, biome: realm.biome,
    model: `models/${ns}/${realm.name}.vmdl`, origin, yaw: 0, scale: 1,
    footprint: realm.footprint, clear_combat_size: realm.clear_combat_size,
    deck_z: realm.deck_z, world_deck_z: deckZ, water_z: realm.water_z, world_water_z: z + realm.water_z,
    wall_height: realm.wall_height, local_model_bounds: realm.bounds, world_model_bounds: modelBounds,
    collision_count: realm.collision_count, support_size: support.size, support_top: top, support_bottom: bottom,
    entry_marker: realm.entry_marker, spawn_marker: realm.spawn_marker, center_marker: floorMarkers[2].name};
  return {placement, support, markers};
}
const placements = [], supports = [], markers = [], prefabs = [];
for (const realm of realms) {
  const result = addRealm(realm, [...realm.review_xy, zbase]);
  placements.push(result.placement); supports.push(result.support); markers.push(...result.markers);
}
const overviewChildren = children.slice();
for (const realm of realms) {
  children.length = 0;
  const result = addRealm(realm, [0, 0, 0]);
  const name = `ten_realm_arena_${String(realm.rank).padStart(2, '0')}`;
  prefabs.push({rank: realm.rank, name, path: `prefabs/${name}`, origin: [0, 0, 0],
    placement: result.placement, supports: [result.support], markers: result.markers,
    water: {included: false, expected_local_z: realm.water_z, material: waterMaterial},
    includes_review_lighting: false, includes_grid: false, children: children.slice()});
}
children.length = 0; children.push(...overviewChildren);
const waterZ = zbase + realms[0].water_z;
// One nonsolid water mesh for the entire review. No studio floor makes the sea walkable.
box(0, 0, halfExtent*2, halfExtent*2, waterZ, waterZ-1, waterMaterial);
entity('world_bounds', 'ten_realm_review_bounds', [0, 0, 0], {min: '-4096 -4096 0', max: '4096 4096 0'});
const firstEntry = markers.find(m => m.rank === 1 && m.kind === 'entry');
const lastSpawn = markers.find(m => m.rank === 10 && m.kind === 'spawn');
entity('info_player_start_goodguys', 'ten_realm_review_start', firstEntry.origin);
entity('info_player_start', 'ten_realm_editor_start', firstEntry.origin);
entity('info_player_start_badguys', 'ten_realm_review_enemy_start', lastSpawn.origin);
entity('ent_dota_game_events', 'ten_realm_review_events', [0, 0, 0]);
entity('env_global_light', 'ten_realm_review_daylight', [0, 0, 3600],
  {color: '255 243 218 255', lightscale: '1.8', ambientcolor1: '198 208 215 255', ambientscale1: '1.15',
    ambientcolor2: '171 184 186 255', ambientscale2: '.8', ambientcolor3: '142 145 129 255',
    groundscale: '.65', enableshadows: '1', StartDisabled: '0'}, '55 315 0');
entity('env_tonemap_controller', 'ten_realm_review_tonemap', [0, 0, 0],
  {UseCustomAutoExposureMin: '1', UseCustomAutoExposureMax: '1', AutoExposureMin: '.9', AutoExposureMax: '1.1'});
entity('water_lod_control', 'ten_realm_review_water_lod', [0, 0, 0],
  {cheapwaterstartdistance: '30000', cheapwaterenddistance: '40000'});
let template = fs.readFileSync(path.join(root, 'output/zombie_island_v1/source_template.vmap'), 'utf8');
template = template.slice(template.indexOf('"CMapRootElement"'));
function close(text, start, opening, closing) {
  let depth = 0, quoted = false;
  for (let i = start; i < text.length; i++) {
    if (text[i] === '"' && text[i-1] !== '\\') quoted = !quoted;
    if (!quoted) {
      if (text[i] === opening) depth++;
      if (text[i] === closing && --depth === 0) return i;
    }
  }
  throw Error('Unbalanced VMAP template.');
}
const worldStart = template.indexOf('"world" "CMapWorld"');
const worldEnd = close(template, template.indexOf('{', worldStart), '{', '}');
const world = template.slice(worldStart, worldEnd+1);
const childrenStart = world.indexOf('[', world.indexOf('"children" "element_array"'));
const childrenEnd = close(world, childrenStart, '[', ']');
let grid = world.slice(childrenStart+1, childrenEnd).trim();
grid = grid.replace('"-8192 -8192 128"', '"-4096 -4096 128"')
  .replace('"gridWidth" "int" "64"', '"gridWidth" "int" "32"')
  .replace('"gridHeight" "int" "64"', '"gridHeight" "int" "32"');
const resized = {4096: 1024, 4225: 1089, 8320: 2112, 66049: 16641, 65536: 16384, 263169: 66049};
const openCellsByRank = Object.fromEntries(realms.map(r => [r.rank, 0]));
let openCells = 0, navWritten = false;
function walkableRealm(x, y) {
  return placements.find(p => Math.abs(x-p.origin[0]) < p.clear_combat_size[0]/2
    && Math.abs(y-p.origin[1]) < p.clear_combat_size[1]/2);
}
grid = grid.replace(/^(\t{6})"([^"]+)" "(\w+)_array"\s*\[([^\]]*)\]/gm, (all, indent, key, type, body) => {
  if (type === 'element') return all;
  const old = [...body.matchAll(/"([^"]*)"/g)].map(m => m[1]);
  if (/^(cell|object)Configuration/.test(key)) return `${indent}"${key}" "${type}_array" []`;
  const count = resized[old.length]; if (!count) return all;
  let fill = old[0] || '0';
  if (key === 'cellsHidden') fill = '1';
  else if (key === 'verticesHeight' || key === 'verticesWater' || key === 'edgesPath'
    || key === 'edgesDestruction' || key.startsWith('objects')) fill = key === 'objectsVariationId' ? '255' : '0';
  else if (key === 'blendOpacity') fill = '0 255 0 128';
  else if (key === 'blendColor') fill = '255 255 255 0';
  else if (key === 'grassOpacity' || key === 'fogOpacity') fill = '0';
  else if (key === 'flowMap' || key === 'fogFlowMap') fill = '128 128 0 0';
  const values = Array(count).fill(fill);
  if (key === 'gridnavFlags') {
    if (count !== navCount*navCount || navWritten) throw Error('Unexpected navigation grid contract.');
    navWritten = true;
    for (let y = 0; y < navCount; y++) for (let x = 0; x < navCount; x++) {
      const realm = walkableRealm(-halfExtent+x*navCellSize+navCellSize/2, -halfExtent+y*navCellSize+navCellSize/2);
      values[y*navCount+x] = realm ? '0' : '1';
      if (realm) {openCells++; openCellsByRank[realm.rank]++;}
    }
  }
  return `${indent}"${key}" "${type}_array" [${values.map(v => '"'+v+'"').join(',')} ]`;
});
if (!navWritten || Object.values(openCellsByRank).some(n => !n)) throw Error('One or more realms have no open navigation cells.');
function save(name, items) {
  const editedWorld = world.slice(0, childrenStart+1) + items.join(',\n') + world.slice(childrenEnd);
  const file = path.join(sourceDir, 'maps', name+'.vmap');
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, '<!-- dmx encoding keyvalues2 4 format vmap 40 -->\n'
    + template.slice(0, worldStart) + editedWorld + template.slice(worldEnd+1));
}
save('ten_realm_arenas_review', [grid, ...children]);
for (const prefab of prefabs) save(prefab.path, prefab.children);
const water = {material: waterMaterial, dependencies: waterDependencies, world_z: waterZ, local_z: -42,
  bounds: [[-halfExtent, -halfExtent, waterZ-1], [halfExtent, halfExtent, waterZ]],
  nonsolid: true, navigable: false, included_in_prefabs: false, shared_ocean_meshes: 1,
  reference_source: 'output/main_island/source/materials/main_island/ocean_surface.vmat'};
const navigation = {tile_count: [tileCount, tileCount], cell_count: [navCount, navCount], cell_size: navCellSize,
  origin: [-halfExtent, -halfExtent], open_flag: 0, blocked_flag: 1, open_cells: openCells,
  open_cells_by_rank: openCellsByRank, regions: supports.map(s => ({rank: s.rank, name: s.name, polygon: s.polygon})),
  exterior_blocked: true, runtime_verified: false};
const layout = {schema_version: 1, namespace: ns, review: 'ten_realm_arenas_review', base_z: zbase,
  footprint: [700, 700], clear_combat_size: [612, 612], columns: 2, rows: 5,
  review_bounds: [[-halfExtent, -halfExtent], [halfExtent, halfExtent]], occupied_bounds: occupiedBounds,
  envelopes, min_envelope_clearance: minEnvelopeClearance, placements, supports, markers,
  prefabs: prefabs.map(({children, ...p}) => p),
  walkable_support: {material: supportMaterial, recess: supportRecess, thickness: supportThickness, rendered: false},
  water, navigation, open_grid_cells: openCells, open_cells_by_rank: openCellsByRank,
  main_map_modified: false, runtime_verified: false};
fs.writeFileSync(path.join(out, 'layout.json'), JSON.stringify(layout, null, 2));
fs.writeFileSync(path.join(out, 'map_manifest.json'), JSON.stringify({schema_version: 1, namespace: ns,
  review: layout.review, prefabs: layout.prefabs.map(p => p.path), instances: placements.length,
  customAssets: assets.length, markers: markers.map(m => m.name), baseZ: zbase,
  footprint: layout.footprint, clearCombatSize: layout.clear_combat_size, reviewBounds: layout.review_bounds,
  occupiedBounds, minEnvelopeClearance, supportCount: supports.length,
  water, navigation, openGridCells: openCells, emissiveEntities: 0, mainMapModified: false, runtimeVerified: false}, null, 2));
console.log(JSON.stringify({map: layout.review, realms: placements.length, prefabs: prefabs.length,
  markers: markers.length, openGridCells: openCells, openCellsByRank, waterZ, minEnvelopeClearance}, null, 2));
