'use strict';
// Clone the complete native graph, including parent-particle inheritance.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const {Vpk, endOf} = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const pack = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
const temp = path.join(root, 'output/native_portal_full_20261006/native_source');
fs.mkdirSync(temp, {recursive: true});
const nativePrefix = 'particles/econ/items/wisp/wisp_relocate_marker_ti7';
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
        const resource=names.get(native), file=path.join(root,'art/effects',theme,'source',resource);
        fs.mkdirSync(path.dirname(file),{recursive:true}); fs.writeFileSync(file,header+text+'\n');
        outputs.push({resource,native,maximum_particles:Number(/m_nMaxParticles = (\d+)/.exec(text)?.[1]||1000)});
    }
    const manifest={native_root:nativeRoot,entry:names.get(nativeRoot),outputs,
        identification:'Complete native Io TI7 Relocate graph. Exact video asset binding remains unconfirmed.',
        binding:'One root; CP0/CP1 feet, CP3 orbit radius. Native parent-particle inheritance preserved.',
        particle_budget:outputs.reduce((n,r)=>n+r.maximum_particles,0),
        adaptation:'Native black center, nebula, swirl, embers, glow, rays and trails; ground orientation, persistent lifetime, bounded emission and radius; no terrain traces, dynamic lights or Lua polling.'};
    fs.writeFileSync(path.join(root,'art/effects',theme,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
    console.log(theme.toUpperCase()+'_SOURCE_PASS systems='+outputs.length+' particles<='+manifest.particle_budget);
}
