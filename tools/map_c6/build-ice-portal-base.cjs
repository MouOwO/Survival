'use strict';
// Clone the complete native graph, including parent-particle inheritance.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const {Vpk, endOf} = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const pack = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
const temp = path.join(root, 'output/native_portal_full_20261006/native_source');
fs.mkdirSync(temp, {recursive: true});
const nativePrefix = 'particles/econ/items/wisp/wisp_relocate_marker_ti7';
const spatialScale = 0.75;
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const cache = new Map();
function data(resource) {
    if (cache.has(resource)) return cache.get(resource);
    const file = path.join(temp, path.basename(resource) + '_c');
    fs.writeFileSync(file, pack.read(resource + '_c'));
    const dump = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'), ['-i', file, '-all'], {encoding:'utf8', windowsHide:true});
    const start = dump.indexOf('{', dump.indexOf('--- vpcf block DATA'));
    const text = dump.slice(start, endOf(dump, start)); cache.set(resource, text); return text;
}
const children = text => [...text.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(m => m[1]);
function editArray(text, key, callback) {
    const at = text.indexOf(key + ' ='); if (at < 0) return text;
    const open = text.indexOf('[', at), end = endOf(text, open, '[', ']');
    const body = text.slice(open+1,end-1), blocks=[]; let cursor=0;
    while ((cursor=body.indexOf('{',cursor))>=0) {
        const next=endOf(body,cursor), changed=callback(body.slice(cursor,next));
        if(changed)blocks.push(changed); cursor=next;
    }
    return text.slice(0,open)+'[\n'+blocks.join(',\n')+'\n]'+text.slice(end);
}
function append(text, key, body) { return text.replace(/\}\s*$/, key+' = '+body+'\n}\n'); }
function lock(text) {
    if(text.includes('C_OP_PositionLock'))return text;
    const at=text.indexOf('m_Operators =');
    if(at<0)return append(text,'m_Operators','[{ _class = "C_OP_PositionLock" }]');
    const open=text.indexOf('[',at);
    return text.slice(0,open+1)+'\n{ _class = "C_OP_PositionLock" },\n'+text.slice(open+1);
}
// Scale authored distances, not arbitrary KV3 numbers. In particular lifetime,
// color, alpha, emission, rotation and radius *multipliers* keep native timing
// and appearance. CP0/CP1 are world positions and must never be multiplied.
function scaleSpatialText(text) {
    const changes = [];
    const numberPattern = '[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?';
    const format = value => {
        const result = String(Number(value.toFixed(9)));
        return /[.eE]/.test(result) ? result : result + '.0';
    };
    function number(source, field, location) {
        const pattern = new RegExp('(\\b' + field + '\\s*=\\s*)(' + numberPattern + ')(?![\\w.])', 'g');
        return source.replace(pattern, (match, prefix, raw) => {
            const before = Number(raw), after = before * spatialScale;
            if (after === before) return match;
            changes.push({field: location + '.' + field, before, after});
            return prefix + format(after);
        });
    }
    function vector(source, field, location) {
        const pattern = new RegExp('(\\b' + field + '\\s*=\\s*\\[)([^\\]]+)(\\])', 'g');
        return source.replace(pattern, (match, prefix, raw, suffix) => {
            const before = raw.split(',').map(value => Number(value.trim()));
            if (before.length !== 3 || before.some(value => !Number.isFinite(value))) {
                throw Error('Unsupported spatial vector: ' + location + '.' + field);
            }
            const after = before.map(value => value * spatialScale);
            if (before.every((value, index) => value === after[index])) return match;
            changes.push({field: location + '.' + field, before, after});
            return prefix + ' ' + after.map(format).join(', ') + ' ' + suffix;
        });
    }
    function input(source, field, location, cp3Radius = false) {
        const match = new RegExp('\\b' + field + '\\s*=\\s*').exec(source);
        if (!match) return source;
        const start = match.index + match[0].length;
        if (source[start] !== '{') return number(source, field, location);
        const end = endOf(source, start);
        let value = source.slice(start, end);
        const type = /m_nType\s*=\s*"([^"]+)"/.exec(value)?.[1];
        const inner = location + '.' + field;
        if (type === 'PF_TYPE_LITERAL') value = number(value, 'm_flLiteralValue', inner);
        else if (type === 'PF_TYPE_RANDOM_UNIFORM' || type === 'PF_TYPE_RANDOM_BIASED') {
            value = number(value, 'm_flRandomMin', inner);
            value = number(value, 'm_flRandomMax', inner);
        } else if (cp3Radius && type === 'PF_TYPE_CONTROL_POINT_COMPONENT'
            && /m_nControlPoint\s*=\s*3\b/.test(value)
            && /m_nMapType\s*=\s*"PF_MAP_TYPE_REMAP"/.test(value)) {
            // CSV already supplies 75% CP3. Scale BOTH remap domains, keeping
            // its slope unchanged: f_new(0.75*r) == 0.75*f_old(r). This only
            // scales the nonzero late-CP seed; it never multiplies CP3 twice.
            for (const key of ['m_flInput0', 'm_flInput1', 'm_flOutput0', 'm_flOutput1']) {
                value = number(value, key, inner);
            }
        } else throw Error('Unsupported spatial input: ' + inner + ' (' + type + ')');
        return source.slice(0, start) + value + source.slice(end);
    }
    for (const field of ['m_flConstantRadius', 'm_flCullRadius']) {
        text = number(text, field, 'CParticleSystemDefinition');
    }
    for (const array of ['m_Renderers', 'm_Initializers', 'm_Operators', 'm_Constraints']) {
        let index = 0;
        text = editArray(text, array, block => {
            const cls = /_class\s*=\s*"([^"]+)"/.exec(block)?.[1];
            const location = array + '[' + index++ + '].' + cls;
            const inputs = fields => { for (const field of fields) block = input(block, field, location); };
            const vectors = fields => { for (const field of fields) block = vector(block, field, location); };
            if (cls === 'C_INIT_InitFloat') {
                // Radius is the serialized default field (3). Trail length
                // field 10 multiplies particle travel; scaling its velocity
                // already scales the trail. Keep that temporal multiplier.
                const field = Number(/m_nOutputField\s*=\s*(\d+)/.exec(block)?.[1] ?? 3);
                if (field === 3 && !/m_nSetMethod\s*=\s*"PARTICLE_SET_SCALE_INITIAL_VALUE"/.test(block)) {
                    inputs(['m_InputValue']);
                }
            } else if (cls === 'C_INIT_RingWave') {
                inputs(['m_flInitialRadius', 'm_flThickness', 'm_flInitialSpeedMin', 'm_flInitialSpeedMax']);
            } else if (cls === 'C_INIT_CreateWithinSphere' || cls === 'C_INIT_VelocityRandom') {
                inputs(['m_fRadiusMin', 'm_fRadiusMax', 'm_fSpeedMin', 'm_fSpeedMax']);
                vectors(['m_LocalCoordinateSystemSpeedMin', 'm_LocalCoordinateSystemSpeedMax']);
            } else if (cls === 'C_INIT_PositionOffset') {
                vectors(['m_OffsetMin', 'm_OffsetMax']);
            } else if (cls === 'C_OP_BasicMovement') {
                vectors(['m_Gravity']);
            } else if (cls === 'C_OP_AttractToControlPoint') {
                if (!/m_fFalloffPower\s*=\s*0(?:\.0*)?\b/.test(block)) {
                    throw Error('Distance-dependent force needs a separate scaling policy: ' + location);
                }
                inputs(['m_fForceAmount']);
            } else if (cls === 'C_OP_MaxVelocity') {
                inputs(['m_flMaxVelocity']);
            } else if (cls === 'C_INIT_InitialVelocityNoise') {
                vectors(['m_vecOutputMin', 'm_vecOutputMax']);
            } else if (cls === 'C_OP_VectorNoise' && /m_nFieldOutput\s*=\s*0\b/.test(block)) {
                vectors(['m_vecOutputMin', 'm_vecOutputMax']);
            } else if (cls === 'C_INIT_InitVec' && /m_nOutputField\s*=\s*2\b/.test(block)) {
                // Random offsets from the inherited position, not that world
                // position itself or the unitless attribute scale vector.
                vectors(['m_vRandomMin', 'm_vRandomMax']);
            } else if (cls === 'C_OP_RenderTrails') {
                inputs(['m_flMinLength', 'm_flMaxLength']);
            } else if (cls === 'C_OP_RenderRopes') {
                inputs(['m_flTextureVWorldSize']);
            } else if (cls === 'C_OP_ConstrainDistance') {
                vectors(['m_CenterOffset']);
                block = input(block, 'm_fMinDistance', location, true);
                block = input(block, 'm_fMaxDistance', location, true);
            }
            return block;
        });
    }
    return {text, changes};
}
// A nonzero seed preserves each rope point's direction before client CP data
// arrives. A zero-radius constraint would collapse the entire ring permanently.
const radius='{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 3 m_nVectorComponent = 0 m_nMapType = "PF_MAP_TYPE_REMAP" m_flInput0 = 0.0 m_flInput1 = 160.0 m_flOutput0 = 1.0 m_flOutput1 = 160.0 }';
for(const theme of ['ice_portal','amber_portal']) {
    const blue=theme==='ice_portal', nativeRoot=nativePrefix+(blue?'_endpoint':'')+'.vpcf';
    // New paths prevent a running client from retaining the old stripped graph.
    const prefix='particles/survival/towers/'+theme+'/native_full/';
    const names=new Map([
        [nativeRoot,prefix+'ground.vpcf'],
        [nativePrefix+(blue?'_endpoint_light':'_light')+'.vpcf',prefix+'dark_center.vpcf'],
        [nativePrefix+(blue?'_interior_blue':'_interior')+'.vpcf',prefix+'interior.vpcf'],
        [nativePrefix+(blue?'_sparkle_blue':'_sparkle')+'.vpcf',prefix+'sparkles.vpcf'],
    ]);
    const visited=new Set(), resources=[];
    function visit(resource) {
        if(visited.has(resource))return; visited.add(resource); resources.push(resource);
        if(!names.has(resource))names.set(resource,prefix+'native/'+path.basename(resource));
        for(const child of children(data(resource)))visit(child);
    }
    visit(nativeRoot); const outputs=[];
    for(const native of resources) {
        let text=data(native); const isRoot=native===nativeRoot;
        const ring=/_(?:endpoint_)?ring(?:_core)?\.vpcf$/.test(native);
        // Retain native behavior and compatibility flags, especially the black
        // center's MOD2X blend / negative overbright and the child simulations.
        text=text.replace(/resource:"([^"]+\.vpcf)"/g,(_,value)=>{
            if(!names.has(value))throw Error('Unmapped child: '+value);
            return 'resource:"'+names.get(value)+'"';
        });
        text=editArray(text,'m_Renderers',block=>block.includes('C_OP_RenderDeferredLight')?null:block
            .replace(/PARTICLE_ORIENTATION_ALIGN_TO_PARTICLE_NORMAL/g,'PARTICLE_ORIENTATION_WORLD_Z_ALIGNED')
            .replace(/\s*m_nScaleCP[12] = \d+/g,''));
        text=editArray(text,'m_PreEmissionOperators',block=>block.includes('C_OP_StopAfterCPDuration')?null:block);
        text=editArray(text,'m_Initializers',block=>{
            if(block.includes('C_INIT_PositionPlaceOnGround'))return null;
            if(block.includes('C_INIT_PositionOffset'))block=block.replace(/(m_Offset(?:Min|Max) = \[\s*-?[\d.]+,\s*-?[\d.]+,)\s*-?[\d.]+\s*\]/g,'$1 8.0 ]');
            if(ring&&block.includes('C_INIT_RingWave'))block=block.replace(/(m_flInitialSpeed(?:Min|Max) =\s*\{[^}]*m_flLiteralValue =) [\d.]+/g,'$1 0.0');
            return block;
        });
        text=editArray(text,'m_Operators',block=>{
            if(isRoot&&block.includes('C_OP_Decay'))return null;
            if(native.endsWith('_ring_glow.vpcf')&&block.includes('C_OP_Decay'))return null;
            return block;
        });
        if(isRoot&&!text.includes('C_OP_SetChildControlPoints')) {
            text=append(text,'m_Initializers','[{ _class = "C_INIT_CreateWithinSphere" }]');
            text=append(text,'m_Emitters','[{ _class = "C_OP_InstantaneousEmitter" m_nParticlesToEmit = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 1.0 } }]');
            text=append(text,'m_Operators','[{ _class = "C_OP_SetChildControlPoints" m_nFirstControlPoint = 1 }]');
        }
        text=lock(text);
        if(ring)text=append(text,'m_Constraints','[{ _class = "C_OP_ConstrainDistance" m_nControlPointNumber = 1 m_bGlobalCenter = false m_fMinDistance = '+radius+' m_fMaxDistance = '+radius+' m_CenterOffset = [0.0,0.0,8.0] }]');
        // Keep all layers; bound only continuous density for persistent towers.
        let cap,rate;
        if(/_ring_swirl\.vpcf$/.test(native)){cap=24;rate=12;}
        else if(/_embers\.vpcf$/.test(native)){cap=16;rate=8;}
        else if(/_(?:rays|streaks|sparkle(?:_blue)?|end_sparkle)\.vpcf$/.test(native)){cap=12;rate=6;}
        if(cap)text=text.replace(/m_nMaxParticles = \d+/,'m_nMaxParticles = '+cap)
            .replace(/(m_flEmitRate =\s*\{[^}]*m_flLiteralValue =) [\d.]+/g,'$1 '+rate+'.0');
        const scaled = scaleSpatialText(text);
        text = scaled.text;
        const resource=names.get(native), file=path.join(root,'art/effects',theme,'source',resource);
        fs.mkdirSync(path.dirname(file),{recursive:true}); fs.writeFileSync(file,header+text+'\n');
        outputs.push({resource,native,maximum_particles:Number(/m_nMaxParticles = (\d+)/.exec(text)?.[1]||1000),
            spatial_changes:scaled.changes});
    }
    const manifest={native_root:nativeRoot,entry:names.get(nativeRoot),outputs,
        identification:'Complete native Io TI7 Relocate graph. Exact video asset binding remains unconfirmed.',
        binding:'One root; CP0/CP1 feet, CP3 orbit radius already scaled by the profile. Native parent-particle inheritance preserved.',
        spatial_scale:spatialScale,
        spatial_policy:'Authored spatial values scaled once; CP3 remap input and output domains scaled together. Lifetime, emission, alpha, color, rotation, radius multipliers and trail travel multipliers unchanged.',
        particle_budget:outputs.reduce((n,r)=>n+r.maximum_particles,0),
        adaptation:'Native black center, nebula, swirl, embers, glow, rays and trails; ground orientation, persistent lifetime, bounded emission and radius; no terrain traces, dynamic lights or Lua polling.'};
    fs.writeFileSync(path.join(root,'art/effects',theme,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
    console.log(theme.toUpperCase()+'_SOURCE_PASS systems='+outputs.length+' particles<='+manifest.particle_budget);
}
