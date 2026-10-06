'use strict';
// Adapt the native blue Io portal's art to a bounded, persistent frost pedestal.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const {Vpk, endOf} = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const pack = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
let out, prefix, outputs;
const temp = path.join(root, 'output/ice_base_reference_20261006/native');
fs.mkdirSync(temp, {recursive: true});
const nativePrefix = 'particles/econ/items/wisp/wisp_relocate_marker_ti7_';
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
function data(name) {
    const resource = nativePrefix + name + '.vpcf';
    const file = path.join(temp, name + '.vpcf_c');
    fs.writeFileSync(file, pack.read(resource + '_c'));
    const text = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
        ['-i', file, '-all'], {encoding: 'utf8', windowsHide: true});
    return text.slice(text.indexOf('{', text.indexOf('--- vpcf block DATA')));
}
function array(text, key) {
    const start = text.indexOf('[', text.indexOf(key + ' ='));
    if (start < 0) throw Error('Missing native array: ' + key);
    return text.slice(start, endOf(text, start, '[', ']'));
}
function renderer(name) {
    return array(data(name), 'm_Renderers')
        .replace(/\s*m_nScaleCP[12] = \d+/g, '')
        .replace(/m_n(Min|Max)Tesselation = 4/g, 'm_n$1Tesselation = 2');
}
const literal = n => `{ m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${Number(n).toFixed(3)} }`;
const cpInput = (axis, scale) => `{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 1 m_nVectorComponent = ${axis} m_nMapType = "PF_MAP_TYPE_MULT" m_flMultFactor = ${scale} }`;
// A one-unit seed survives CP1=0 during client creation. Constraints expand it
// to the requested ring radius after control points arrive; no respawn required.
const ringRadius = `{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 1 m_nVectorComponent = 0 m_nMapType = "PF_MAP_TYPE_REMAP" m_flInput0 = 0.0 m_flInput1 = 160.0 m_flOutput0 = 1.0 m_flOutput1 = 145.0 }`;
const init = (field, value) => `{ _class = "C_INIT_InitFloat" m_nOutputField = ${field} m_InputValue = ${value} }`;
const set = (field, value) => `{ _class = "C_OP_SetFloat" m_nOutputField = ${field} m_InputValue = ${value} }`;
const lock = '{ _class = "C_OP_PositionLock" }';
const color = '{ _class = "C_OP_RemapCPtoVector" m_nCPInput = 2 m_nFieldOutput = 6 m_vInputMax = [255.0,255.0,255.0] m_vOutputMax = [1.0,1.0,1.0] }';
const offset = z => `{ _class = "C_INIT_PositionOffset" m_OffsetMin = [0.0,0.0,${z}.0] m_OffsetMax = [0.0,0.0,${z}.0] }`;
const once = n => `{ _class = "C_OP_InstantaneousEmitter" m_nParticlesToEmit = ${literal(n)} }`;
const constraint = (distance, z) => `[ { _class = "C_OP_ConstrainDistance" m_nControlPointNumber = 0 m_CenterOffset = [0.0,0.0,${z}.0] m_bGlobalCenter = false m_fMinDistance = ${distance} m_fMaxDistance = ${distance} } ]`;
function write(name, native, count, render, initial, operators, emitters, constraints = '[]', children = []) {
    const resource = prefix + name + '.vpcf';
    const file = path.join(out, 'source', resource);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    if (!initial.some(op => op.includes('m_nOutputField = 1 '))) initial.push(init(1, literal(999999)));
    const source = header + `{
 _class = "CParticleSystemDefinition" m_nBehaviorVersion = 12
 m_nMaxParticles = ${count} m_flConstantLifespan = 999999.0 m_ConstantColor = [255,255,255,255]
 m_BoundingBoxMin = [-180.0,-180.0,-16.0] m_BoundingBoxMax = [180.0,180.0,64.0]
 m_Renderers = ${render}
 m_Initializers = [${initial.join(',\n')}]
 m_Operators = [${operators.concat('{ _class = "C_OP_EndCapTimedDecay" m_flDecayTime = 0.15 }').join(',\n')}]
 m_Emitters = [${emitters.join(',\n')}]
 m_Constraints = ${constraints}
 m_Children = [${children.map(r => `{ m_ChildRef = resource:"${r}" }`).join(',')}]
}\n`;
    fs.writeFileSync(file, source);
    outputs.push({resource, native: nativePrefix + native + '.vpcf', maximum_particles: count});
    return resource;
}
for (const theme of ['ice_portal', 'amber_portal']) {
out = path.join(root, 'art/effects', theme);
prefix = 'particles/survival/towers/' + theme + '/';
outputs = [];
const blue = theme === 'ice_portal';
const nativeRing = blue ? 'endpoint_ring' : 'ring';
const nativeCore = blue ? 'endpoint_ring_core' : 'ring_core';
// Both native rope layers share one closed orbit. The thinner core uses the
// renderer's radius scale, avoiding a second particle simulation for the ring.
const bodyRenderer = renderer(nativeRing);
const coreRenderer = renderer(nativeCore).replace('m_flRadiusScale = 0.5', 'm_flRadiusScale = 0.20');
if (!coreRenderer.includes('m_flRadiusScale = 0.20')) throw Error('Native core width changed');
const ringRenderers = '[' + bodyRenderer.slice(1, -1).trim().replace(/,$/, '') + ',' + coreRenderer.slice(1, -1) + ']';
// Every layer is attached directly, including the visible 17-particle root.
// Radius/color must not depend on an empty parent's child CP inheritance.
const entry = write('ground', nativeRing, 17, ringRenderers, [
    '{ _class = "C_INIT_RingWave" m_bEvenDistribution = true m_flParticlesPerOrbit = 16.0 m_flInitialRadius = ' + literal(1) + ' m_flInitialSpeedMin = ' + literal(0) + ' m_flInitialSpeedMax = ' + literal(0) + ' }',
    offset(12), init(3, cpInput(0, 0.16)), init(7, cpInput(2, 0.80)),
], [lock, color, set(3, cpInput(0, 0.16)), set(7, cpInput(2, 0.80)),
    '{ _class = "C_OP_MovementRotateParticleAroundAxis" m_flRotRate = 12.0 }'], [once(17)], constraint(ringRadius, 12));
write('dark_center', blue ? 'endpoint_light' : 'light', 1, renderer(blue ? 'endpoint_light' : 'light'),
    ['{ _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 }'],
    ['{ _class = "C_OP_SetToCP" m_vecOffset = [0.0,0.0,8.0] }',
        set(3, cpInput(0, 0.85)), set(7, cpInput(2, 0.50))], [once(1)]);
write('interior', blue ? 'interior_blue' : 'interior', 3,
    renderer(blue ? 'interior_blue' : 'interior').replace('m_flOverbrightFactor = 5.0', 'm_flOverbrightFactor = 1.5'),
    ['{ _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 }',
        '{ _class = "C_INIT_RandomSequence" m_nSequenceMax = 3 }',
        init(4, '{ m_nType = "PF_TYPE_RANDOM_UNIFORM" m_flRandomMin = 0.0 m_flRandomMax = 360.0 }')],
    ['{ _class = "C_OP_SetToCP" m_vecOffset = [0.0,0.0,10.0] }', color,
        set(3, cpInput(0, 0.72)), set(7, cpInput(2, 0.12)),
        '{ _class = "C_OP_SpinUpdate" }'], [once(3)]);
write('sparkles', blue ? 'sparkle_blue' : 'sparkle', 6, renderer(blue ? 'sparkle_blue' : 'sparkle'), [
    '{ _class = "C_INIT_RingWave" m_flInitialRadius = ' + literal(1) + ' }',
    offset(12), init(1, literal(1.2)), init(3, cpInput(0, 0.035)),
], [lock, color, set(3, cpInput(0, 0.035)), set(7, cpInput(2, 0.70)),
    '{ _class = "C_OP_FadeInSimple" m_flFadeInTime = 0.1 }',
    '{ _class = "C_OP_FadeOutSimple" m_flFadeOutTime = 0.4 }',
    '{ _class = "C_OP_Decay" }'],
    ['{ _class = "C_OP_ContinuousEmitter" m_flEmitRate = ' + literal(3) + ' }'], constraint(ringRadius, 12));
const manifest = {
    video: 'https://www.bilibili.com/video/BV13oLszLE9z/', timestamp: blue ? '53:01' : '16:47–17:05',
    identification: 'Native Io Relocate art adapted to the supplied ' + (blue ? 'blue' : 'orange dark-center') + ' pedestal reference; exact original binding and in-engine visual comparison remain unverified.',
    native_root: blue ? nativePrefix + 'endpoint.vpcf' : nativePrefix.slice(0, -1) + '.vpcf', entry, outputs,
    binding: 'Four directly attached layers, explicit CP0 feet / CP1 radius and alpha / CP2 color; visible persistent root, no empty parent or child CP inheritance.',
    particle_budget: outputs.reduce((n, r) => n + r.maximum_particles, 0),
    adaptation: 'Two native rope renderers share a closed 16-segment orbit; native sprite textures, permanent bounded ring with late-CP recovery, 3 sparks/s; no dynamic lights, teleport flash, expanding velocity or Lua position polling.',
};
fs.mkdirSync(out, {recursive: true});
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(theme.toUpperCase() + '_SOURCE_PASS systems=' + outputs.length + ' particles<=' + manifest.particle_budget);
}
