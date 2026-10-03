'use strict';
// Inspect the compiled particle data, not just the source generator's claims.
const fs=require('fs'), path=require('path'), cp=require('child_process');
const assert=require('assert'), crypto=require('crypto');
const {Vpk,endOf}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..');
const pack=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const art=path.join(root,'art/effects/death_willow');
const manifest=JSON.parse(fs.readFileSync(path.join(art,'manifest.json')));
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const out=path.join(root,'output/death_reference_base_20261002/compiled_audit');
fs.mkdirSync(out,{recursive:true});
assert.equal(manifest.outputs.length,2);
assert.equal(manifest.total_max_particles,2);
assert.equal(manifest.handles_per_tower,1);
assert.equal(hash(pack.read(manifest.native_texture+'_c')),manifest.native_texture_sha256);
const systems=[];
function blocks(data,key){
    const m=new RegExp('\\b'+key+'\\s*=').exec(data);assert(m,key);
    const start=data.indexOf('[',m.index),input=data.slice(start,endOf(data,start,'[',']'));
    const result=[];
    for(let i=0;(i=input.indexOf('{',i))!==-1;){const end=endOf(input,i);result.push(input.slice(i,end));i=end;}
    return result;
}
for(const row of manifest.outputs){
    assert.equal(hash(pack.read(row.native+'_c')),row.native_sha256);
    const source=fs.readFileSync(path.join(art,'source',row.resource));
    assert.equal(hash(source),row.source_sha256);
    const content=path.resolve(root,'../../../content/dota_addons/survival',row.resource);
    assert(source.equals(fs.readFileSync(content)),'compiled content source mismatch');
    const runtime=path.join(root,row.resource+'_c');
    const dump=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),
        ['-i',runtime,'-all'],{encoding:'utf8',windowsHide:true});
    fs.writeFileSync(path.join(out,path.basename(runtime)+'.txt'),dump);
    const data=dump.slice(dump.indexOf('--- vpcf block DATA'));
    assert(/m_nMaxParticles\s*=\s*1\b/.test(data));
    assert(/m_flConstantLifespan\s*=\s*999999\.0\b/.test(data));
    assert(data.includes(manifest.native_texture));
    assert(data.includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'));
    assert(!data.includes('m_bDisableZBuffering = true'));
    assert(!/C_OP_StopAfterCPDuration|C_OP_ColorInterpolate|C_OP_InheritFromParentParticles|C_INIT_CreateOnModel/.test(data));
    const ops=blocks(data,'m_Operators');
    assert(ops.some(b=>b.includes('C_OP_SetToCP')&&/m_vecOffset\s*=\s*\[\s*0\.0,\s*0\.0,\s*15\.0\s*\]/.test(b)));
    for(const [field,axis] of [[3,0],[7,2]]){
        // Radius (3) is C_OP_SetFloat's default, so the compiler elides it.
        assert(ops.some(b=>b.includes('C_OP_SetFloat')
            &&Number((/m_nOutputField\s*=\s*(\d+)\b/.exec(b)||[,3])[1])===field
            &&b.includes('PF_TYPE_CONTROL_POINT_COMPONENT')&&/m_nControlPoint\s*=\s*1\b/.test(b)
            // The compiler omits zero-valued axes, so missing is also axis zero.
            &&(axis===0?!/m_nVectorComponent\s*=\s*[12]\b/.test(b):/m_nVectorComponent\s*=\s*2\b/.test(b))));
    }
    assert(ops.some(b=>b.includes('C_OP_RemapCPtoVector')&&/m_nCPInput\s*=\s*2\b/.test(b)&&/m_nFieldOutput\s*=\s*6\b/.test(b)));
    const children=[...data.matchAll(/m_ChildRef\s*=\s*resource:"([^"]+)"/g)].map(m=>m[1]);
    assert.deepEqual(children,row.children);
    assert.equal(blocks(data,'m_Emitters').length,1);
    assert(data.includes('C_OP_InstantaneousEmitter')&&!data.includes('C_OP_ContinuousEmitter'));
    const initial=blocks(data,'m_Initializers');
    assert(initial.some(b=>b.includes('C_INIT_RandomSequence')));
    if(row.resource.includes('_soft'))assert(initial.some(b=>b.includes('C_INIT_RandomSequence')&&/m_nSequenceMin\s*=\s*1\b/.test(b)&&/m_nSequenceMax\s*=\s*1\b/.test(b)));
    systems.push({resource:row.resource,compiled_sha256:hash(fs.readFileSync(runtime)),max_particles:1,children});
}
const report={status:'PASS',native_ground_layers:true,persistent:true,late_controls_recover:true,
    attached_position_without_lua_updates:true,total_max_particles:2,handles:1,
    texture_dependencies_present:true,normal_depth_testing:true,systems,in_game_visual_verified:false};
fs.writeFileSync(path.join(out,'validation.json'),JSON.stringify(report,null,2)+'\n');
console.log('DEATH_WILLOW_COMPILED_PASS: native sigil/soft atlas, persistent CP radius/alpha/color, relocation, depth, 2 sprites');
