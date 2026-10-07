'use strict';
// Verify full native hierarchy, compiled blend modes, lifetime and dependencies.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const {references}=require('./map_c6/inspect-effect-resources.cjs');
const root=path.resolve(__dirname,'..'), pack=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
for(const theme of ['ice_portal','amber_portal']) {
    const manifest=JSON.parse(fs.readFileSync(path.join(root,'art/effects',theme,'manifest.json')));
    const out=path.join(root,'output/native_portal_full_20261006/compiled_audit',theme);
    fs.mkdirSync(out,{recursive:true});
    const seen=new Set(), resources=[], mapped=new Map(manifest.outputs.map(row=>[row.native,row.resource]));
    function visit(resource) {
        if(seen.has(resource))return;seen.add(resource);
        const local=path.join(root,resource+'_c');
        const bytes=fs.existsSync(local)?fs.readFileSync(local):pack.read(resource+'_c');
        const deps=references(bytes);resources.push({resource,bytes:bytes.length,dependencies:deps});
        for(const dependency of deps)visit(dependency);
    }
    visit(manifest.entry);
    let budget=0;
    for(const row of manifest.outputs) {
        assert(seen.has(row.resource),'Every native layer must be reachable from one root: '+row.resource);
        const file=path.join(root,row.resource+'_c');
        const full=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
        const text=full.slice(full.indexOf('--- vpcf block DATA'));
        fs.writeFileSync(path.join(out,path.basename(row.resource)+'.txt'),text);
        const source=path.join(root,'art/effects',theme,'source',row.resource);
        const content=path.resolve(root,'../../../content/dota_addons/survival',row.resource);
        assert(fs.readFileSync(source).equals(fs.readFileSync(content)),'Game/Content sources differ');
        const nativeSource=fs.readFileSync(path.join(root,'output/native_portal_full_20261006/native_source',path.basename(row.native)+'_c'),'binary');
        assert(nativeSource.length>0);
        const original=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',path.join(root,'output/native_portal_full_20261006/native_source',path.basename(row.native)+'_c'),'-all'],{encoding:'utf8',windowsHide:true});
        assert.equal(/m_nBehaviorVersion = (\d+)/.exec(text)?.[1],/m_nBehaviorVersion = (\d+)/.exec(original)?.[1],
            'Preserve native particle behavior compatibility');
        const expectedChildren=[...original.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(m=>mapped.get(m[1])).sort();
        const actualChildren=[...text.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(m=>m[1]).sort();
        assert.deepEqual(actualChildren,expectedChildren,'Preserve every native child link');
        assert(!text.includes('C_OP_StopAfterCPDuration'),'Persistent portal cannot stop on native spell duration');
        assert(!text.includes('C_OP_RenderDeferredLight')&&!text.includes('C_INIT_PositionPlaceOnGround'),
            'No dynamic light or per-particle terrain trace');
        assert(!text.includes('m_bDisableZBuffering = true'));
        assert(text.includes('C_OP_PositionLock'),'Follow unit through engine particles');
        const cap=Number(/m_nMaxParticles = (\d+)/.exec(text)?.[1]||1000);
        assert.equal(cap,row.maximum_particles);budget+=cap;
        if(row.resource.endsWith('/dark_center.vpcf')) {
            assert(text.includes('PARTICLE_OUTPUT_BLEND_MODE_MOD2X')&&text.includes('m_flOverbrightFactor = -1.0'));
            assert(text.includes('particle_modulate_04.vtex')&&text.includes('C_OP_InterpolateRadius'));
            assert(!text.includes('C_OP_RemapCPtoVector'),'Never tint the native dark center');
        }
        if(/_ring(?:_core)?\.vpcf$/.test(row.native)) {
            assert.equal(cap,33,'Native rope keeps its full segment count');
            assert(text.includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED')&&text.includes('C_OP_BasicMovement'));
            assert(text.includes('C_OP_ConstrainDistance')&&text.includes('m_nControlPoint = 3'));
            // Legacy behavior omits the serialized false default; require the
            // explicit source setting and reject any compiled global override.
            assert(fs.readFileSync(source,'utf8').includes('m_bGlobalCenter = false')
                && !text.includes('m_bGlobalCenter = true')&&text.includes('m_flOutput0 = 1.0'),
                'Constraint follows the tower and survives late client CPs');
        }
        if(row.native.endsWith('_ring_swirl.vpcf')) {
            assert(text.includes('C_INIT_CreateFromParentParticles')&&text.includes('steam.vtex'));
            assert(text.includes('C_OP_Orient2DRelToCP'));
        }
        if(row.native.endsWith('_ring_glow.vpcf')) {
            assert(text.includes('C_OP_InheritFromParentParticles')&&text.includes('particle_glow_04.vtex'));
        }
    }
    assert.equal(budget,manifest.particle_budget);
    assert.equal(manifest.outputs.length,theme==='ice_portal'?15:13);
    const service=fs.readFileSync(path.join(root,'scripts/vscripts/systems/tower_visual_service.lua'),'utf8');
    assert(service.includes('"/native_full/ground.vpcf"')&&service.includes('SetParticleControl(id, 3, Vector(radius, 0, 0))'));
    const report={status:'PASS',native_systems:manifest.outputs.length,maximum_particles:budget,resources,
        in_game_visual_verified:false,in_game_gpu_cost_measured:false};
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
    console.log(theme.toUpperCase()+'_RESOURCE_PASS systems='+manifest.outputs.length+' particles<='+budget+' dependencies='+resources.length+'; complete native graph/black center/inheritance/ground/persistent/Game+Content');
}
