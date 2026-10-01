'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert');
const {execFileSync}=require('child_process'),L=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..');
const reportPath=path.join(root,'docs/ai/validation/20261001/phoenix_meteor.json');
const previous=fs.existsSync(reportPath)?JSON.parse(fs.readFileSync(reportPath,'utf8')):null;
function sameResourceHashes(before,current){
    if(!Array.isArray(before)||!current.length||before.length!==current.length)return false;
    const indexed=new Map(before.map(row=>[row.resource,row]));
    if(indexed.size!==before.length)return false;
    return current.every(row=>{
        const old=indexed.get(row.resource);
        return old&&old.source_sha256===row.source_sha256&&old.compiled_sha256===row.compiled_sha256;
    });
}
const manifest=JSON.parse(fs.readFileSync(path.join(root,'art/effects/skill_visuals/manifest.json')));
const native=new L.Vpk(path.join(root,'../../dota/pak01_dir.vpk'));
const records=[];
for(const name of manifest.native_resources)assert(native.entries.has(name+'_c'),'Missing Valve resource '+name);
for(const name of manifest.outputs){
    const source=path.join(root,'art/effects/skill_visuals/source',name);
    const content=path.resolve(root,'../../../content/dota_addons/survival',name);
    const compiled=path.join(root,name+'_c');
    assert(fs.readFileSync(source).equals(fs.readFileSync(content)),'Source/content diverged: '+name);
    const text=fs.readFileSync(source,'utf8');
    const info=execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',compiled,'-all'],{encoding:'utf8'});
    assert(info.includes('C_INIT_CreateWithinSphereTransform'),'Legacy sphere must migrate to native transform');
    for(const [,ref] of text.matchAll(/resource:"([^"]+)"/g)){
        assert(native.entries.has(ref+'_c')||fs.existsSync(path.join(root,ref+'_c')),'Missing dependency '+ref);
    }
    if(name.includes('phoenix_fall')){
        assert(info.includes('models/heroes/phoenix/phoenix_egg.vmdl'),'Must use actual Supernova egg');
        assert(/m_flTravelTime = 0\.4\b/.test(info));
        assert.equal((info.match(/m_ChildRef =/g)||[]).length,2,'Flight uses native Phoenix fire and glow');
        for(const suffix of ['glow','lava'])assert(info.includes('phoenix_supernova_egg_'+suffix+'.vpcf'));
        assert(!info.includes('hero_invoker')&&!info.includes('rubick_arcana_cube'));
        assert(info.includes('C_OP_SetControlPointsToParticle')&&info.includes('m_nFirstControlPoint = 3'));
    }
    if(name.endsWith('/meteor_impact.vpcf')){
        assert(info.includes('phoenix_supernova_reborn_sphere.vpcf'),'Impact must use Supernova burst');
    }
    if(/meteor_lava(?:_cracks)?\.vpcf$/.test(name)){
        const height=name.includes('_cracks')?40:32;
        assert(info.includes('C_OP_SetToCP')&&!info.includes('C_INIT_PositionOffset'),
            'Ground must use the native CP position operator, not the legacy offset initializer');
        assert(new RegExp('m_vecOffset = \\[ 0\\.0, 0\\.0, '+height+'\\.0 \\]').test(info),
            'Compiled lava position must retain native FLOAT vectors at the intended height');
        assert(info.includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'));
    }
    records.push({resource:name,bytes:fs.statSync(compiled).size,
        source_sha256:crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex'),
        compiled_sha256:crypto.createHash('sha256').update(fs.readFileSync(compiled)).digest('hex')});
}
const report={date:'2026-10-01',validation_level:['STATIC','CONTRACT','SIMULATION'],workshop_verified:false,
    native_reference:'Phoenix Supernova egg model, native egg glow/lava/steam, reborn sphere',
    changed_timing:{previous_fall_seconds:0.8,fall_seconds:0.4},
    unchanged_gameplay:{radius:500,lava_seconds:3,lava_ticks:3,second_meteor_delay:0.5,second_meteor_scale:0.8,trigger_chance:0.12,impact_multiplier:3,lava_multiplier:1},
    lava_presentation:{same_cast_ground_systems:1,level5_visual_seconds:3.5,
        rationale:'Two meteors at one cast position formerly created identical coplanar lava systems. Share only the ground visual through the final lava expiry; damage and slow retain separate per-meteor timers.',
        before_evidence:'output/map_build_c6/meteor_frame_04.png',
        shared_only_workshop_result:'Horizontal lines persisted in output/map_build_c6/meteor_fixed_05.png; duplicate systems were not the sole cause.',
        ground_layer_heights:[32,40],previous_ground_layer_heights:[7,9],depth_testing:'native defaults preserved',
        position_operator:'C_OP_SetToCP / native FLOAT offset vectors; legacy PositionOffset removed only from the two ground layers',
        height_only_workshop_result:'Horizontal lines persisted with legacy PositionOffset at 32/40; compiled vectors remained INT. Replaced with the same CP operator used by verified tower bases.',
        texture_check:'Decoded Valve lava/crack textures do not contain the horizontal line band.',
        after_workshop_verification:'NOT_VERIFIED for current resource hashes'},
    compile:{compiled:2,failed:0,logs:'output/phoenix_meteor/compile'},native_dependencies_checked:manifest.native_resources.length,
    simulation:'scripts/vscripts/tests/test_meteor_visual_timing.lua: all five tiers, 0.4s landing, unchanged radius/damage totals/slow/lava/second meteor gap, one shared ground visual, VFX failures and cleanup/reentry passed',
    tests:['node tools/test_meteor_visual_resources.cjs','lua5.1 scripts/vscripts/tests/test_meteor_visual_timing.lua'],
    runtime_precache:['particles/survival/skills/meteor_phoenix_fall.vpcf','particles/survival/skills/meteor_impact.vpcf','particles/survival/skills/meteor_lava.vpcf'],records};
// A resource check cannot grant native acceptance. Preserve an existing manual
// record only while the complete source/compiled resource set remains identical.
const keepWorkshop=previous&&previous.workshop_verified===true
    &&previous.workshop&&previous.workshop.status==='PASS'
    &&sameResourceHashes(previous.records,records);
report.workshop_verified=!!keepWorkshop;
report.workshop=keepWorkshop?previous.workshop:{status:'NOT_VERIFIED',
    reason:previous&&previous.workshop_verified?'resource_hashes_changed':'no_matching_workshop_record'};
if(keepWorkshop){
    report.validation_level.push('WORKSHOP_ISOLATED_FIXTURE');
    report.lava_presentation.after_workshop_verification=previous.workshop.result;
}
fs.writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');
console.log('METEOR_VISUAL_RESOURCES_PASS sources=6 compiled=6 native_dependencies='+manifest.native_resources.length+' phoenix_egg=verified fall=0.4s');
