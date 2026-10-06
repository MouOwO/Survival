'use strict';
// Derive only Call Down's landing endcap. CP0 and CP3 are the fixed landing
// position; CP5.x is the blast radius. Native Call Down is authored at 500.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const {Vpk, endOf} = require('./lib.cjs');
const repo = path.resolve(__dirname, '../..');
const output = path.join(repo, 'output/arcane_gyro_20261003');
const sourceRoot = path.join(repo, 'art/effects/arcane_gyro/source');
const nativeRoot = 'particles/units/heroes/hero_gyrocopter/gyro_calldown_explosion.vpcf';
const rootParticle = 'particles/survival/skills/arcane_gyro_impact.vpcf';
const nativeRadius = 500, radius = 150, spatialScale = radius / nativeRadius;
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const numeric = value => ({__number: value, raw: Number.isInteger(value) ? value.toFixed(1) : String(value)});
const n = value => value && typeof value === 'object' && '__number' in value ? value.__number : value;
function parse(text) {
    const tokens = text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g); let i = 0;
    function val() {
        const token = tokens[i++];
        if (token === '{') { const object = {}; while (tokens[i] !== '}') { const key = tokens[i++]; assert.equal(tokens[i++], '='); object[key] = val(); if (tokens[i] === ',') i++; } i++; return object; }
        if (token === '[') { const values = []; while (tokens[i] !== ']') { values.push(val()); if (tokens[i] === ',') i++; } i++; return values; }
        if (token.startsWith('resource:')) return {__resource: JSON.parse(token.slice(9))};
        if (token.startsWith('"')) return JSON.parse(token);
        if (token === 'true' || token === 'false') return token === 'true';
        if (token === 'null') return null;
        assert(Number.isFinite(Number(token)), 'Unexpected native KV3 token ' + token);
        return {__number: Number(token), raw: token};
    }
    const result = val(); assert.equal(i, tokens.length); return result;
}
function kv(value, indent = 0) {
    if (value === null) return 'null';
    if (Array.isArray(value)) return '[ ' + value.map(v => kv(v, indent)).join(', ') + ' ]';
    if (value && typeof value === 'object' && '__number' in value) return value.raw;
    if (value && typeof value === 'object' && '__resource' in value) return 'resource:' + JSON.stringify(value.__resource);
    if (typeof value === 'object') return '{\n' + Object.entries(value).map(([key, v]) => '\t'.repeat(indent + 1) + key + ' = ' + kv(v, indent + 1)).join('\n') + '\n' + '\t'.repeat(indent) + '}';
    return JSON.stringify(value);
}
function walk(value, visit, key = '') {
    visit(value, key);
    if (Array.isArray(value)) value.forEach(v => walk(v, visit, key));
    else if (value && typeof value === 'object' && !('__number' in value) && !('__resource' in value)) for (const [k, v] of Object.entries(value)) walk(v, visit, k);
}
function scaleInput(input, factor) {
    // CP5 already changes from the original radius 500 to 150 in Lua. Scaling
    // its remap a second time would shrink those layers to 45 instead of 150.
    if (input.m_nType === 'PF_TYPE_CONTROL_POINT_COMPONENT' && n(input.m_nControlPoint) === 5) return;
    for (const key of ['m_flLiteralValue', 'm_flRandomMin', 'm_flRandomMax', 'm_flOutput0', 'm_flOutput1', 'm_vLiteralValue', 'm_vRandomMin', 'm_vRandomMax']) scaleValue(input, key, factor);
}
function scaleValue(object, key, factor = spatialScale) {
    const value = object[key]; if (value === undefined) return;
    if (Array.isArray(value)) object[key] = value.map(v => numeric(n(v) * factor));
    else if (value && '__number' in value) object[key] = numeric(n(value) * factor);
    else if (value && typeof value === 'object') scaleInput(value, factor);
}
function adaptSpatial(tree, modelBounds) {
    scaleValue(tree, 'm_flConstantRadius');
    for (const key of ['m_BoundingBoxMin', 'm_BoundingBoxMax', 'm_flCullRadius', 'm_flDepthSortBias']) scaleValue(tree, key);
    for (const initial of tree.m_Initializers || []) {
        const field = n(initial.m_nOutputField);
        if (initial._class === 'C_INIT_InitFloat' && (field === undefined || field === 3) && initial.m_nSetMethod !== 'PARTICLE_SET_SCALE_INITIAL_VALUE') scaleInput(initial.m_InputValue, spatialScale);
        if (initial._class === 'C_INIT_InitVec' && (field === 0 || field === 2)) scaleInput(initial.m_InputValue, spatialScale);
        if (initial._class === 'C_INIT_CreateWithinSphere') for (const key of ['m_fRadiusMin', 'm_fRadiusMax', 'm_fSpeedMin', 'm_fSpeedMax', 'm_LocalCoordinateSystemSpeedMin', 'm_LocalCoordinateSystemSpeedMax']) scaleValue(initial, key);
        if (initial._class === 'C_INIT_RingWave') for (const key of ['m_flInitialRadius', 'm_flThickness', 'm_flInitialSpeedMin', 'm_flInitialSpeedMax']) scaleValue(initial, key);
        if (initial._class === 'C_INIT_PositionOffset') for (const key of ['m_OffsetMin', 'm_OffsetMax']) scaleValue(initial, key);
        if (initial._class === 'C_INIT_InitialVelocityNoise') for (const key of ['m_vecOutputMin', 'm_vecOutputMax']) scaleValue(initial, key);
        if (initial._class === 'C_INIT_PositionPlaceOnGround') for (const key of ['m_flOffset', 'm_flMaxTraceLength']) scaleValue(initial, key);
    }
    for (const operator of tree.m_Operators || []) {
        if (operator._class === 'C_OP_BasicMovement') scaleValue(operator, 'm_Gravity');
        if (operator._class === 'C_OP_VectorNoise' && [0, 2].includes(n(operator.m_nFieldOutput))) for (const key of ['m_vecOutputMin', 'm_vecOutputMax']) scaleValue(operator, key);
        if (operator._class === 'C_OP_RampScalarLinearSimple' && (operator.m_nField === undefined || n(operator.m_nField) === 3)) scaleValue(operator, 'm_Rate');
    }
    for (const force of tree.m_ForceGenerators || []) for (const key of ['m_fForceAmount', 'm_MinForce', 'm_MaxForce']) scaleValue(force, key);
    for (const renderer of tree.m_Renderers || []) {
        // Renderer radiusScale is a dimensionless multiplier of the radius
        // already scaled above. Only authored absolute trail lengths change.
        if (renderer._class === 'C_OP_RenderTrails') scaleValue(renderer, 'm_flMaxLength');
        if (renderer.m_VisibilityInputs) scaleValue(renderer.m_VisibilityInputs, 'm_flProxyRadius');
    }
    // Call Down's core glow uses radius 290 * startScale 12. Uniform 0.3
    // scaling alone would still leave a 1044-unit flash. Keep its native
    // growth/fade curve, but bound the final radius after native operators.
    // Models use measured model geometry; lights use their native multiplier.
    let geometryMultiplier = 1;
    for (const renderer of tree.m_Renderers || []) {
        if (renderer._class === 'C_OP_RenderModels') for (const model of renderer.m_ModelList || []) geometryMultiplier = Math.max(geometryMultiplier, modelBounds[model.m_model.__resource].unit_radius);
        if (renderer._class === 'C_OP_RenderDeferredLight') geometryMultiplier = Math.max(geometryMultiplier, n(renderer.m_flRadiusScale) || 1);
    }
    const radiusLimit = radius / geometryMultiplier;
    tree.m_Operators = [...(tree.m_Operators || []), {_class: 'C_OP_ClampScalar',
        m_nFieldOutput: {__number: 3, raw: '3'}, m_flOutputMin: numeric(0), m_flOutputMax: numeric(radiusLimit)}];
    // Translate the editor preview too. CP5 is a gameplay-radius input, while
    // color CP60/61/62 and all normalized multipliers remain native.
    for (const config of tree.m_controlPointConfigurations || []) for (const driver of config.m_drivers || []) {
        if ([0, 3].includes(n(driver.m_iControlPoint) || 0)) scaleValue(driver, 'm_vecOffset');
        if (n(driver.m_iControlPoint) === 5) driver.m_vecOffset = [numeric(radius), numeric(0), numeric(0)];
    }
    return {final_radius_limit: radiusLimit, renderer_geometry_multiplier: geometryMultiplier,
        maximum_centered_renderer_radius: radius, boundary: 'Radius only; no positional clipping of sparks or other particle centers'};
}
function selectedFields(tree) {
    const result = []; walk(tree, (v, k) => { if (/Color|HSV|Texture|Material|m_ModelList|m_nSkin/.test(k)) result.push([k, kv(v)]); }); return result;
}
function lifetimeSignature(tree) {
    return kv((tree.m_Initializers || []).filter(x => x._class === 'C_INIT_InitFloat' && n(x.m_nOutputField) === 1));
}
function build() {
    fs.mkdirSync(output, {recursive: true});
    const pack = new Vpk(path.resolve(repo, '../../dota/pak01_dir.vpk'));
    const nodes = new Map(), nativeResources = new Set();
    function load(resource) {
        if (nodes.has(resource)) return;
        assert(!/marker|launch|calldown_(first|second|model|smoke)\.vpcf/.test(resource), 'Unexpected pre-impact resource ' + resource);
        const bytes = pack.read(resource + '_c'), dest = path.join(output, 'builder_native', path.basename(resource) + '_c');
        fs.mkdirSync(path.dirname(dest), {recursive: true}); fs.writeFileSync(dest, bytes);
        const dump = cp.execFileSync(path.resolve(repo, '../../bin/win64/resourceinfo.exe'), ['-i', dest, '-all'], {encoding: 'utf8', windowsHide: true, maxBuffer: 8 * 1024 * 1024});
        fs.writeFileSync(dest + '.txt', dump);
        const at = dump.indexOf('--- vpcf block DATA'), open = dump.indexOf('{', at); assert(at >= 0);
        const body = dump.slice(open, endOf(dump, open)), tree = parse(body);
        nodes.set(resource, {resource, tree, native_bytes_sha256: hash(bytes), native_data_sha256: hash(body)});
        for (const child of tree.m_Children || []) load(child.m_ChildRef.__resource);
    }
    load(nativeRoot); assert.equal(nodes.size, 22, 'Native Call Down impact graph changed');
    const mapping = Object.fromEntries([...nodes.keys()].map(resource => [resource, resource === nativeRoot ? rootParticle :
        'particles/survival/skills/arcane_gyro_impact_' + path.basename(resource, '.vpcf').replace(/^gyro_(?:call_down|calldown)_explosion_/, '') + '.vpcf']));
    assert.equal(new Set(Object.values(mapping)).size, nodes.size, 'Colliding derived particle names');
    const modelBounds = {};
    for (const node of nodes.values()) for (const renderer of node.tree.m_Renderers || []) for (const model of renderer.m_ModelList || []) {
        const resource = model.m_model.__resource; if (modelBounds[resource]) continue;
        const bytes = pack.read(resource + '_c'), dest = path.join(output, 'builder_native', path.basename(resource) + '_c');
        fs.writeFileSync(dest, bytes);
        const dump = cp.execFileSync(path.resolve(repo, '../../bin/win64/resourceinfo.exe'), ['-i', dest, '-b', 'MDAT'], {encoding: 'utf8', windowsHide: true});
        fs.writeFileSync(dest + '.txt', dump);
        const bounds = [...dump.matchAll(/m_v(?:Min|Max)Bounds = \[ ([^\]]+) \]/g)].map(m => m[1].split(',').map(Number));
        assert(bounds.length > 0, 'No native model geometry bounds ' + resource);
        const axis = Math.max(...bounds.flat().map(Math.abs));
        modelBounds[resource] = {sha256: hash(bytes), maximum_axis: axis, unit_radius: axis * Math.sqrt(3)};
    }
    const reflection = fs.readFileSync(path.resolve(repo, '../../bin/win64/particles.dll'));
    for (const field of ['C_OP_ClampScalar', 'm_nFieldOutput', 'm_flOutputMin', 'm_flOutputMax']) assert(reflection.includes(Buffer.from(field)), 'Native radius clamp field missing ' + field);
    const layers = [], outputs = [];
    for (const node of nodes.values()) {
        const nativeTree = structuredClone(node.tree), tree = structuredClone(node.tree), resource = mapping[node.resource];
        const rangeAdaptation = adaptSpatial(tree, modelBounds);
        for (const child of tree.m_Children || []) child.m_ChildRef.__resource = mapping[child.m_ChildRef.__resource];
        assert.equal(kv(tree.m_Emitters || []), kv(nativeTree.m_Emitters || []), 'Emission changed ' + resource);
        assert.equal(lifetimeSignature(tree), lifetimeSignature(nativeTree), 'Lifespan changed ' + resource);
        assert.deepEqual(selectedFields(tree), selectedFields(nativeTree), 'Native drawing/colors changed ' + resource);
        walk(tree, value => { if (value && value.__resource && !Object.values(mapping).includes(value.__resource)) nativeResources.add(value.__resource); });
        const file = path.join(sourceRoot, resource); fs.mkdirSync(path.dirname(file), {recursive: true});
        const source = header + kv(tree) + '\n'; fs.writeFileSync(file, source); outputs.push(resource);
        layers.push({native_source: node.resource, resource, source: path.relative(repo, file).replace(/\\/g, '/'),
            source_sha256: hash(source), native_bytes_sha256: node.native_bytes_sha256, native_data_sha256: node.native_data_sha256,
            native_children: (nativeTree.m_Children || []).map(c => c.m_ChildRef.__resource),
            derived_children: (tree.m_Children || []).map(c => c.m_ChildRef.__resource),
            range_adaptation: rangeAdaptation,
            preserved_emission: true, preserved_lifespan: true, preserved_native_drawing_and_colors: true});
    }
    nativeResources.forEach(resource => assert(pack.entries.has(resource + '_c'), 'Missing native dependency ' + resource));
    const manifest = {generated_by: 'tools/map_c6/build-arcane-gyro-impact.cjs', native_root: nativeRoot, root_particle: rootParticle,
        native_nominal_blast_radius: nativeRadius, nominal_blast_radius: radius, world_spatial_scale: spatialScale,
        particle_systems: nodes.size, outputs, native_resources: [...nativeResources].sort(), layers,
        measured_model_bounds: modelBounds,
        cp_contract: {0: 'Fixed landing world position', 3: 'Same fixed landing world position', 5: [radius, 0, 0],
            colors: 'Native authored CP60/61/62 defaults; do not overwrite',
            radius: 'Fixed world quantities scale by 150/500. Native CP5 radius remaps are unchanged and receive 150, so they scale once.'},
        emission: 'Impact only: all 22 original landing endcap layers. Instant emitters and finite smoke emission (0.75 seconds) remain native; no marker, launch or descending missile.',
        maximum_native_tail_seconds: 10, fallback_cleanup_seconds: 11,
        validation: {native_graph: 'PASS', world_units_scaled: 'PASS', preserved_emission_and_lifespans: 'PASS',
            compiler_serialization: 'PENDING', in_game_visual_verified: false,
            scope: 'Main landing footprint uses radius150. Native world dimensions uniformly scale by0.3; final native particle radius clamps limit oversized flash, glow, model and light geometry to150 after animation multipliers. Sparks may travel beyond the core footprint. No hard positional clipping boundary is added; actual pixels and shader bloom need engine visual acceptance.'}};
    fs.mkdirSync(path.join(repo, 'art/effects/arcane_gyro'), {recursive: true});
    fs.writeFileSync(path.join(repo, 'art/effects/arcane_gyro/manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
    fs.writeFileSync(path.join(output, 'impact_manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
    return manifest;
}
module.exports = {build};
if (require.main === module) { const manifest = build(); console.log('ARCANE_GYRO_IMPACT_SOURCE_PASS layers=' + manifest.particle_systems + ' nominal_radius=' + manifest.nominal_blast_radius + ' scale=' + manifest.world_spatial_scale); }
