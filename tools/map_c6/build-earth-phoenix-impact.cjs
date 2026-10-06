'use strict';
// Earth Line splits the complete Phoenix rebirth graph into a ground footprint
// and an airborne core. Small damage footprints must not shrink the core below
// the rolling meteor or bury it in the terrain. Native emission/life stay intact.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert');
const {build}=require('./build-phoenix-meteor-impact.cjs');
const {endOf}=require('./lib.cjs');
const repo=path.resolve(__dirname,'../..');
const assetRoot=path.join(repo,'art/effects/earth_phoenix_impact');
const sourceRoot=path.join(assetRoot,'source');
const manifestFile=path.join(assetRoot,'manifest.json');
const output=path.join(repo,'output/earth_phoenix_impact');
const radii=[75,125,300];
const suffixes=['','scorch_b','embers','glow','ground_flare','light','scorch','shockwave',
    'shockwave_dust','shockwave_dust_glow','sparks','sphere','sphere_model','sphere_shockwave',
    'flek','star_sphere','shake'];
const resource=(radius,suffix='')=>'particles/survival/skills/earth_phoenix_impact_'+radius+(suffix?'_'+suffix:'')+'.vpcf';
const coreResource='particles/survival/skills/earth_phoenix_impact_core.vpcf';
const coreSuffixes=['embers','glow','light','sparks','sphere','sphere_model','flek','star_sphere'];
const coreLayerSuffixes=[...coreSuffixes,'sphere_shockwave'];
const groundSuffixes=['scorch_b','ground_flare','scorch','shockwave','shake'];
const expected=[...radii.flatMap(radius=>suffixes.map(suffix=>resource(radius,suffix))),coreResource];
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function childrenOf(source) {
    return [...source.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(match=>match[1]);
}
function rootChildren(source,children) {
    const at=source.indexOf('m_Children = '),open=source.indexOf('[',at);
    assert(at>=0&&open>at,'Native Phoenix container needs a child array');
    const end=endOf(source,open,'[',']');
    return source.slice(0,open)+'[ '+children.map(child=>'{\n\t\tm_ChildRef = resource:'+JSON.stringify(child)+'\n\t}').join(', ')+' ]'+source.slice(end);
}
function saveLayer(layer,source) {
    fs.writeFileSync(path.join(repo,layer.source),source);
    layer.source_sha256=hash(source);
    layer.derived_children=childrenOf(source);
}
function check(manifest) {
    assert.deepEqual(manifest.radii,radii);
    assert.deepEqual(manifest.outputs,expected,'Three original 17-layer asset sets plus one shared airborne root');
    assert.equal(manifest.variants.length,3);assert.equal(manifest.layers.length,52);
    assert.equal(manifest.particle_systems,52);
    assert.equal(manifest.airborne_core.root_particle,coreResource);
    assert.equal(manifest.airborne_core.height,90);
    assert.equal(manifest.airborne_core.cp3_height,60);
    assert.equal(manifest.airborne_core.source_radius,300);
    assert.deepEqual(manifest.airborne_core.layer_suffixes,coreLayerSuffixes);
    const meteor=JSON.parse(fs.readFileSync(path.join(repo,'art/effects/skill_visuals/manifest.json'),'utf8')).impact;
    const baseline=new Map(meteor.layers.map(layer=>[layer.native_source,layer]));
    const union=[];
    for(const variant of manifest.variants) {
        assert(radii.includes(variant.fixed_radius));
        const factor=variant.fixed_radius/500;
        assert.equal(variant.root_particle,resource(variant.fixed_radius));
        assert.equal(variant.particle_systems,17);assert.equal(variant.layers.length,17);
        assert.equal(variant.cp3_height,100*factor);
        assert.equal(variant.core_particle,coreResource);
        assert.equal(variant.core_height,90);
        assert.deepEqual(variant.outputs,suffixes.map(suffix=>resource(variant.fixed_radius,suffix)));
        const mapping=new Map(variant.layers.map(layer=>[layer.native_source,layer.resource]));
        for(const layer of variant.layers) {
            const old=baseline.get(layer.native_source);assert(old,'Same installed native graph as meteor');
            assert.equal(layer.native_bytes_sha256,old.native_bytes_sha256,'Native source revision must match verified meteor');
            assert.deepEqual(layer.native_children,old.native_children);
            const completeChildren=layer.native_children.map(child=>mapping.get(child));
            assert.deepEqual(layer.derived_children,layer.resource===variant.root_particle
                ?groundSuffixes.map(suffix=>resource(variant.fixed_radius,suffix)):completeChildren);
            assert.equal(layer.source,path.relative(repo,path.join(sourceRoot,layer.resource)).replace(/\\/g,'/'));
            const bytes=fs.readFileSync(path.join(repo,layer.source));
            assert.equal(hash(bytes),layer.source_sha256,'Current source hash: '+layer.resource);
            const children=childrenOf(bytes.toString('utf8'));
            assert.deepEqual(children,layer.derived_children,'Complete serialized child graph');
            for(const flag of ['preserved_emission','preserved_lifespan','preserved_native_drawing_and_colors'])assert.equal(layer[flag],true);
            const range=layer.range_contract;
            if(range) {
                assert.equal(range.fixed_radius,variant.fixed_radius);
                assert.equal(range.curve_envelope,old.range_contract.curve_envelope);
                for(const key of ['spatial_size_scale','motion_scale','center_max_distance','renderer_extent_budget',
                    'allocated_world_extent','radius_override','ring_radius_override']) {
                    const previous=old.range_contract[key];
                    if(previous===null)assert.equal(range[key],null);
                    else assert(Math.abs(range[key]-previous*factor)<1e-7,'Uniform spatial reduction: '+key);
                }
                assert(range.allocated_world_extent<=variant.fixed_radius);
            } else assert.equal(layer.resource,variant.root_particle);
            union.push(layer);
        }
    }
    const core=manifest.layers[manifest.layers.length-1];
    const coreSource=fs.readFileSync(path.join(repo,core.source),'utf8');
    assert.equal(core.resource,coreResource);
    assert.equal(hash(coreSource),core.source_sha256);
    assert.deepEqual(childrenOf(coreSource),coreSuffixes.map(suffix=>resource(300,suffix)));
    assert.deepEqual(core.derived_children,childrenOf(coreSource));
    assert.equal(core.native_bytes_sha256,baseline.get(core.native_source).native_bytes_sha256);
    for(const flag of ['preserved_emission','preserved_lifespan','preserved_native_drawing_and_colors'])assert.equal(core[flag],true);
    const coreBody=fs.readFileSync(path.join(sourceRoot,resource(300,'sphere_model')),'utf8');
    const offsets=[...coreBody.matchAll(/m_Offset(?:Min|Max) = \[ ([^\]]+) \]/g)].map(match=>match[1]);
    assert.deepEqual(offsets,['0.0, 0.0, 0.0','0.0, 0.0, 0.0'],'Airborne core model is centered on its Lua origin');
    // Every impact pair still contains the entire native drawing graph. The
    // extra container only permits an independent world position for its core.
    const byResource=new Map(manifest.layers.map(layer=>[layer.resource,layer]));
    for(const variant of manifest.variants) {
        const visited=new Set(),nativeVisited=new Set();
        function visit(id) {if(visited.has(id))return;visited.add(id);const layer=byResource.get(id);assert(layer);nativeVisited.add(layer.native_source);layer.derived_children.forEach(visit);}
        visit(variant.root_particle);visit(coreResource);
        assert.equal(visited.size,18,'One ground root and one core root with all sixteen native layers');
        assert.equal(nativeVisited.size,17,'The full native Phoenix graph is visible in every impact pair');
    }
    union.push(core);
    assert.deepEqual(manifest.layers,union,'Flat build allowlist matches all variants');
    return manifest;
}
function generate() {
    const variants=radii.map(radius=>{
        const variant=build({radius,rootParticle:resource(radius),sourceRoot,
            output:path.join(output,'radius_'+radius)});
        return {...variant,cp3_height:100*radius/500,core_particle:coreResource,core_height:90};
    });
    const coreBase=variants.find(variant=>variant.fixed_radius===300).layers[0];
    const originalRoot=fs.readFileSync(path.join(repo,coreBase.source),'utf8');
    const core={...structuredClone(coreBase),resource:coreResource,
        source:path.relative(repo,path.join(sourceRoot,coreResource)).replace(/\\/g,'/'),
        visual_role:'airborne_core_container'};
    saveLayer(core,rootChildren(originalRoot,coreSuffixes.map(suffix=>resource(300,suffix))));
    for(const variant of variants) {
        const root=variant.layers[0];
        saveLayer(root,rootChildren(fs.readFileSync(path.join(repo,root.source),'utf8'),
            groundSuffixes.map(suffix=>resource(variant.fixed_radius,suffix))));
        root.visual_role='ground_container';
        variant.cp_contract={...variant.cp_contract,
            0:'Ground footprint world position. Airborne core is allocated independently at ground + Vector(0,0,90).',
            radius:'Only ground layers use this fixed damage-footprint radius; core retains the 300-unit spatial adapter.'};
    }
    const sphereBody=variants.find(variant=>variant.fixed_radius===300).layers.find(layer=>layer.resource===resource(300,'sphere_model'));
    const oldBody=fs.readFileSync(path.join(repo,sphereBody.source),'utf8');
    assert.equal([...oldBody.matchAll(/m_Offset(?:Min|Max) = \[ [^\]]+ \]/g)].length,2);
    saveLayer(sphereBody,oldBody.replace(/(m_Offset(?:Min|Max) = )\[ [^\]]+ \]/g,'$1[ 0.0, 0.0, 0.0 ]'));
    sphereBody.visual_role='airborne_core_body';
    sphereBody.spatial_origin_override='The native upward model offset is zeroed; Lua positions this root at the rolling meteor center, 90 units above ground.';
    const manifest={generated_by:'tools/map_c6/build-earth-phoenix-impact.cjs',
        source_reference:'Complete Valve Phoenix Supernova rebirth DAG, split into radius-matched ground layers and a visible airborne core from the 300-unit adapter',
        radii,particle_systems:52,outputs:[...variants.flatMap(variant=>variant.outputs),coreResource],
        native_resources:[...new Set(variants.flatMap(variant=>variant.native_resources))].sort(),
        layers:[...variants.flatMap(variant=>variant.layers),core],variants,
        airborne_core:{root_particle:coreResource,height:90,cp3_height:60,source_radius:300,
            layer_suffixes:coreLayerSuffixes,model_axis_radius:7.94487*50*.65*300/500,
            cp_contract:{0:'Ground position + Vector(0,0,90), allocated separately from the ground root.',
                1:[1,1,1],3:'Core position + Vector(0,0,60). No CP5 is used.'}},
        retained_compatibility_assets:'Unused 75/125 airborne children remain in the original 51-output allowlist. Every impact renders ground-specific layers plus the shared 300-size core, with no duplicate airborne layers.',
        maximum_native_tail_seconds:7,fallback_cleanup_seconds:8,
        runtime_cleanup:'Earth configures and releases two independent finite one-shot roots per impact, ground and airborne. Native Decay/FadeAndKill finishes all layers within the authored 7-second tail. The inherited 8-second fallback value is a meteor reference, not an Earth runtime timer.',
        validation:{source_numeric_allocations:'PASS',preserved_full_native_dag:true,
            compiler_serialization:'PENDING',in_game_visual_verified:false}};
    check(manifest);
    fs.writeFileSync(manifestFile,JSON.stringify(manifest,null,2)+'\n');
    return manifest;
}
if(require.main===module) {
    const args=process.argv.slice(2);assert(args.length===0||(args.length===1&&args[0]==='--check'),'Usage: build-earth-phoenix-impact.cjs [--check]');
    const manifest=args.includes('--check')?check(JSON.parse(fs.readFileSync(manifestFile,'utf8'))):generate();
    console.log('EARTH_PHOENIX_IMPACT_SOURCE_PASS variants='+manifest.variants.length+' layers='+manifest.layers.length+' radii='+radii.join(','));
}
module.exports={generate,check};
