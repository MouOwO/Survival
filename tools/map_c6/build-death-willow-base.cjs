'use strict';
// Extract Shadow Realm's native two-layer foot sigil. No hero/body effects.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const {Vpk, endOf} = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const pack = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
const art = path.join(root, 'art/effects/death_willow');
const work = path.join(root, 'output/death_reference_base_20261002/resource_build');
const prefix = 'particles/survival/towers/death_willow/';
const nativePrefix = 'particles/units/heroes/hero_dark_willow/';
const texture = 'materials/particle/dark_willow/dark_willow_symbol.vtex';
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
fs.mkdirSync(work, {recursive:true});
assert(pack.entries.has(texture + '_c'), 'native sigil texture is missing');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
function native(name) {
    const resource = nativePrefix + name + '.vpcf';
    const bytes = pack.read(resource + '_c');
    const file = path.join(work, name + '.vpcf_c');
    fs.writeFileSync(file, bytes);
    const dump = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
        ['-i', file, '-all'], {encoding:'utf8', windowsHide:true});
    fs.writeFileSync(file + '.txt', dump);
    const data = dump.slice(dump.indexOf('--- vpcf block DATA'));
    return {resource, bytes, data:data.slice(data.indexOf('{'))};
}
function array(data, name) {
    const found = new RegExp('\\b' + name + '\\s*=').exec(data);
    assert(found, 'missing native array ' + name);
    const start = data.indexOf('[', found.index);
    return data.slice(start, endOf(data, start, '[', ']'));
}
function blocks(data, name) {
    const input = array(data, name), result = [];
    for (let pos = 0; (pos = input.indexOf('{', pos)) !== -1;) {
        const end = endOf(input, pos); result.push(input.slice(pos, end)); pos = end;
    }
    return result;
}
const literal = n => '{ m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ' + n.toFixed(3) + ' }';
const cpInput = (axis, scale=1) => '{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 1 m_nVectorComponent = '
    + axis + ' m_nMapType = "PF_MAP_TYPE_MULT" m_flMultFactor = ' + scale.toFixed(3) + ' }';
const setFloat = (kind, field, value) => '{ _class = "' + kind + '" m_nOutputField = ' + field + ' m_InputValue = ' + value + ' }';
const outputs = [];
function layer(name, source, soft, children) {
    const renderers = array(source.data, 'm_Renderers');
    assert(renderers.includes(texture) && renderers.includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'));
    assert(!renderers.includes('m_bDisableZBuffering = true'), 'preserve normal depth');
    // Native atlas sequence 0 is the sharp rune; sequence 1 is its soft glow.
    const sequence = blocks(source.data, 'm_Initializers').find(b => b.includes('C_INIT_RandomSequence'));
    assert(sequence, 'preserve the actual native atlas sequence');
    const initial = [
        '{ _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 }',
        setFloat('C_INIT_InitFloat', 1, literal(999999)),
        setFloat('C_INIT_InitFloat', 3, cpInput(0)),
        setFloat('C_INIT_InitFloat', 7, cpInput(2, soft ? .3921569 : 1)), sequence,
    ];
    const operators = [
        // Re-read CPs every engine frame so late network controls recover.
        '{ _class = "C_OP_SetToCP" m_vecOffset = [0.0,0.0,15.0] }',
        setFloat('C_OP_SetFloat', 3, cpInput(0)),
        setFloat('C_OP_SetFloat', 7, cpInput(2, soft ? .3921569 : 1)),
        '{ _class = "C_OP_RemapCPtoVector" m_nCPInput = 2 m_nFieldOutput = 6 m_vInputMax = [255.0,255.0,255.0] m_vOutputMax = [1.0,1.0,1.0] }',
        // Native main ring rotates at one radian/second; soft originally inherits it.
        '{ _class = "C_OP_RampScalarLinearSimple" m_nField = 4 m_Rate = 1.0 m_flEndTime = 999999.0 }',
        '{ _class = "C_OP_EndCapTimedDecay" m_flDecayTime = 0.15 }',
    ];
    const resource = prefix + name + '.vpcf';
    const text = header + '{\n _class = "CParticleSystemDefinition" m_nBehaviorVersion = 12\n'
        + ' m_nMaxParticles = 1 m_flConstantLifespan = 999999.0 m_ConstantColor = [255,255,255,255]\n'
        + ' m_BoundingBoxMin = [-160.0,-160.0,-20.0] m_BoundingBoxMax = [160.0,160.0,50.0]\n'
        + ' m_Renderers = ' + renderers + '\n'
        + ' m_Initializers = [' + initial.join(',\n') + ']\n'
        + ' m_Operators = [' + operators.join(',\n') + ']\n'
        + ' m_Emitters = [{ _class = "C_OP_InstantaneousEmitter" m_nParticlesToEmit = ' + literal(1) + ' }]\n'
        + ' m_Children = [' + children.map(c => '{ m_ChildRef = resource:"' + c + '" }').join(',') + ']\n}\n';
    const output = path.join(art, 'source', resource);
    fs.mkdirSync(path.dirname(output), {recursive:true});
    fs.writeFileSync(output, text);
    outputs.push({resource, native:source.resource, native_sha256:hash(source.bytes),
        source_sha256:hash(text), max_particles:1, children, preserved_renderers:true,
        preserved_native_texture:true, persistent:true});
    return resource;
}
const sharp = native('dark_willow_shadow_realm_ground');
const soft = native('dark_willow_shadow_realm_ground_soft');
const child = layer('shadow_ground_soft', soft, true, []);
const effect = layer('shadow_ground', sharp, false, [child]);
const manifest = {reference_video:'https://www.bilibili.com/video/BV1Jg411C7Fm/?t=1635',
    reference_time:'27:15', identified_by_user:'Dark Willow W, Shadow Realm',
    root:effect, outputs, native_texture:texture, native_texture_sha256:hash(pack.read(texture+'_c')),
    total_max_particles:2, handles_per_tower:1,
    controls:{CP0:'tower origin, attached', CP1:'x=radius,z=alpha', CP2:'RGB, 0..255'},
    changes:['Persistent until owner cleanup','Fixed tier colour instead of native 5-second charge colour shift',
        'Authoritative footprint radius and alpha','Both native atlas layers follow CP0 without Lua timers',
        'Omit body smoke, alert icon, charge burst and start/end effects']};
fs.writeFileSync(path.join(art, 'manifest.json'), JSON.stringify(manifest, null, 2)+'\n');
console.log('DEATH_WILLOW_SOURCE_PASS layers=2 max_particles=2 handles=1 native_symbol=true');
