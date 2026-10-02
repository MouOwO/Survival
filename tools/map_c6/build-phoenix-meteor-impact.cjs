'use strict';
// Derive the complete native Supernova rebirth DAG. Only spatial values and
// control-point writers change; native drawing, color, emission and life stay.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const crypto = require('crypto'), assert = require('assert');
const {Vpk,endOf} = require('./lib.cjs');
const repo = path.resolve(__dirname,'../..');
const output = path.join(repo,'output/meteor_phoenix_20261002');
const sourceRoot = path.join(repo,'art/effects/skill_visuals/source');
const nativeRoot = 'particles/units/heroes/hero_phoenix/phoenix_supernova_reborn.vpcf';
const rootParticle = 'particles/survival/skills/meteor_phoenix_impact.vpcf';
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const numeric = value => ({__number:value,raw:Number.isInteger(value)?value.toFixed(1):String(value)});
const integer = value => ({__number:value,raw:String(value)});
const n = value => value && typeof value === 'object' && '__number' in value ? value.__number : value;
const vector = values => values.map(numeric);
const literal = value => ({m_nType:'PF_TYPE_LITERAL',m_flLiteralValue:numeric(value)});
function parse(text) {
    const tokens = text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g); let i=0;
    function val() {
        const token=tokens[i++];
        if(token==='{'){const object={};while(tokens[i]!=='}'){const key=tokens[i++];assert.equal(tokens[i++],'=');object[key]=val();if(tokens[i]===',')i++;}i++;return object;}
        if(token==='['){const values=[];while(tokens[i]!==']'){values.push(val());if(tokens[i]===',')i++;}i++;return values;}
        if(token.startsWith('resource:'))return {__resource:JSON.parse(token.slice(9))};
        if(token.startsWith('"'))return JSON.parse(token);
        if(token==='true'||token==='false')return token==='true';
        if(token==='null')return null;
        assert(Number.isFinite(Number(token)),'Unexpected native KV3 token '+token);
        return {__number:Number(token),raw:token};
    }
    const result=val();assert.equal(i,tokens.length);return result;
}
function kv(value,indent=0) {
    if(value===null)return 'null';
    if(Array.isArray(value))return '[ '+value.map(v=>kv(v,indent)).join(', ')+' ]';
    if(value&&typeof value==='object'&&'__number' in value)return value.raw;
    if(value&&typeof value==='object'&&'__resource' in value)return 'resource:'+JSON.stringify(value.__resource);
    if(typeof value==='object')return '{\n'+Object.entries(value).map(([key,v])=>'\t'.repeat(indent+1)+key+' = '+kv(v,indent+1)).join('\n')+'\n'+'\t'.repeat(indent)+'}';
    return JSON.stringify(value);
}
function walk(value,visit,key='') {visit(value,key);if(Array.isArray(value))value.forEach(v=>walk(v,visit,key));else if(value&&typeof value==='object'&&!('__number'in value)&&!('__resource'in value))for(const [k,v]of Object.entries(value))walk(v,visit,k);}
function fields(value,predicate) {const result=[];walk(value,(v,k)=>{if(predicate(k))result.push([k,kv(v)]);});return result;}
function scaleValue(object,key,factor) {if(object[key]===undefined)return;const value=object[key];if(Array.isArray(value))object[key]=value.map(v=>numeric(n(v)*factor));else if(value&&'__number'in value)object[key]=numeric(n(value)*factor);else if(value&&typeof value==='object')scaleInput(value,factor);}
function scaleInput(input,factor) {
    // Only values with world units are scaled. Random biases, times, normalized
    // maps, rotations and parent inheritance ratios stay byte-for-byte native.
    if(input.m_nType==='PF_TYPE_CONTROL_POINT_COMPONENT')scaleValue(input,'m_flMultFactor',factor);
    else for(const key of ['m_flLiteralValue','m_flRandomMin','m_flRandomMax','m_flOutput0','m_flOutput1'])scaleValue(input,key,factor);
}
const plans = {
    embers:{size:.8,motion:.1,center:480,extent:15*.8*Math.SQRT2},
    flek:{size:.8,motion:.35,center:340,extent:25*.8*5*Math.SQRT2},
    glow:{size:.8,motion:.25,center:410,extent:50*.8*1.5*Math.SQRT2},
    ground_flare:{size:1,motion:.25,center:60,extent:150*2*Math.SQRT2,radius_override:150},
    light:{size:.4,motion:.25,center:90,extent:250*.4*2*2},
    scorch:{size:.9,motion:.25,center:240,extent:200*.9*Math.SQRT2},
    scorch_b:{size:.7,motion:.25,center:95,extent:400*.7*Math.SQRT2},
    shake:{size:1,motion:.25,center:440,extent:92*.5},
    shockwave:{size:.6,motion:.18,center:280,curve_envelope:1.5,extent:128*.6*.5*Math.SQRT2,ring_override:60},
    shockwave_dust:{size:.6,motion:.12,center:230,extent:200*.6*1.5*Math.SQRT2},
    shockwave_dust_glow:{size:.65,motion:.12,center:140,extent:250*.65*1.5*Math.SQRT2},
    sparks:{size:.8,motion:.1,center:410,extent:4*.8*15*.5*Math.SQRT2+(1300+1050+800)*.1*.1},
    sphere:{size:.65,motion:.25,center:80,extent:20*.65*22*Math.SQRT2},
    sphere_model:{size:.65,motion:.25,center:40,extent:50*.65*14},
    sphere_shockwave:{size:.6,motion:.12,center:280,curve_envelope:1.5,extent:128*.6*.5*Math.SQRT2},
    star_sphere:{size:.7,motion:.35,center:345,extent:150*.7*Math.SQRT2},
};
function adaptSpatial(tree,plan) {
    scaleValue(tree,'m_flConstantRadius',plan.size);
    for(const initial of tree.m_Initializers||[]) {
        const kind=initial._class;
        if(kind==='C_INIT_InitFloat'&&(initial.m_nOutputField===undefined||n(initial.m_nOutputField)===3)) {
            if(initial.m_nSetMethod==='PARTICLE_SET_SCALE_INITIAL_VALUE')continue;
            if(plan.radius_override!==undefined&&initial.m_InputValue.m_nType==='PF_TYPE_CONTROL_POINT_COMPONENT')initial.m_InputValue=literal(plan.radius_override);
            else scaleInput(initial.m_InputValue,plan.size);
        }
        if(kind==='C_INIT_CreateWithinSphere') {
            for(const key of ['m_fRadiusMin','m_fRadiusMax'])scaleValue(initial,key,plan.size);
            for(const key of ['m_fSpeedMin','m_fSpeedMax','m_LocalCoordinateSystemSpeedMin','m_LocalCoordinateSystemSpeedMax'])scaleValue(initial,key,plan.motion);
        }
        if(kind==='C_INIT_RingWave') {
            if(plan.ring_override!==undefined)initial.m_flInitialRadius=literal(plan.ring_override);
            else scaleValue(initial,'m_flInitialRadius',plan.size);
            scaleValue(initial,'m_flThickness',plan.size);
            for(const key of ['m_flInitialSpeedMin','m_flInitialSpeedMax'])scaleValue(initial,key,plan.motion);
        }
        if(kind==='C_INIT_PositionOffset')for(const key of ['m_OffsetMin','m_OffsetMax'])scaleValue(initial,key,plan.size);
        if(kind==='C_INIT_InitialVelocityNoise')for(const key of ['m_vecOutputMin','m_vecOutputMax'])scaleValue(initial,key,plan.motion);
    }
    for(const operator of tree.m_Operators||[]) {
        if(operator._class==='C_OP_BasicMovement')scaleValue(operator,'m_Gravity',plan.motion);
        if(operator._class==='C_OP_VectorNoise'&&n(operator.m_nFieldOutput)===0)for(const key of ['m_vecOutputMin','m_vecOutputMax'])scaleValue(operator,key,plan.size);
    }
    const removed=[];
    tree.m_PreEmissionOperators=(tree.m_PreEmissionOperators||[]).filter(operator=>{
        if(operator._class==='C_OP_SetSingleControlPointPosition'&&n(operator.m_nCP1)===3){removed.push(operator._class);return false;}return true;
    });
    // Registered native constraint fields are checked against particles.dll.
    // Fresh resourcecompiler DATA still must verify their actual serialization.
    tree.m_Constraints=[...(tree.m_Constraints||[]),{_class:'C_OP_ConstrainDistance',m_fMinDistance:numeric(0),
        m_fMaxDistance:numeric(plan.center),m_nControlPointNumber:integer(0),m_CenterOffset:vector([0,0,0]),m_bGlobalCenter:false}];
    tree.m_BoundingBoxMin=vector([-512,-512,-512]);tree.m_BoundingBoxMax=vector([512,512,512]);
    return removed;
}
function build() {
    fs.mkdirSync(output,{recursive:true});
    const pack=new Vpk(path.resolve(repo,'../../dota/pak01_dir.vpk'));
    const reflectedBytes=fs.readFileSync(path.resolve(repo,'../../bin/win64/particles.dll'));
    const constraintFields=['C_OP_ConstrainDistance','m_fMinDistance','m_fMaxDistance','m_nControlPointNumber','m_CenterOffset','m_bGlobalCenter'];
    constraintFields.forEach(field=>assert(reflectedBytes.includes(Buffer.from(field)),'Installed native reflection missing '+field));
    const nodes=new Map(),nativeResources=new Set();
    function load(resource) {
        if(nodes.has(resource))return;
        const bytes=pack.read(resource+'_c'),dest=path.join(output,'builder_native',path.basename(resource)+'_c');
        fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,bytes);
        const text=cp.execFileSync(path.resolve(repo,'../../bin/win64/resourceinfo.exe'),['-i',dest,'-all'],{encoding:'utf8',windowsHide:true,maxBuffer:8*1024*1024});
        fs.writeFileSync(dest+'.txt',text);
        const at=text.indexOf('--- vpcf block DATA'),open=text.indexOf('{',at);assert(at>=0);
        const body=text.slice(open,endOf(text,open)),tree=parse(body);
        nodes.set(resource,{resource,native_bytes_sha256:hash(bytes),native_data_sha256:hash(body),tree});
        for(const child of tree.m_Children||[])load(child.m_ChildRef.__resource);
    }
    load(nativeRoot);assert.equal(nodes.size,17);
    const mapping=Object.fromEntries([...nodes.keys()].map(resource=>[resource,resource===nativeRoot?rootParticle:
        'particles/survival/skills/meteor_phoenix_impact_'+path.basename(resource,'.vpcf').replace('phoenix_supernova_reborn_','')+'.vpcf']));
    // Model bound is measured independently, not inferred from particle radius.
    const sphere=pack.read('models/particle/sphere.vmdl_c'),sphereDest=path.join(output,'builder_native/sphere.vmdl_c');
    fs.writeFileSync(sphereDest,sphere);
    const sphereDump=cp.execFileSync(path.resolve(repo,'../../bin/win64/resourceinfo.exe'),['-i',sphereDest,'-b','MDAT'],{encoding:'utf8',windowsHide:true});
    fs.writeFileSync(sphereDest+'.txt',sphereDump);
    const bounds=[...sphereDump.matchAll(/m_v(?:Min|Max)Bounds = \[ ([^\]]+) \]/g)].map(m=>m[1].split(',').map(Number));
    assert(bounds.length>0);const axis=Math.max(...bounds.flat().map(Math.abs));assert(Math.sqrt(3)*axis<=14);
    const layers=[],outputs=[];
    for(const node of nodes.values()) {
        const nativeTree=structuredClone(node.tree),tree=structuredClone(node.tree),resource=mapping[node.resource];
        const suffix=path.basename(node.resource,'.vpcf').replace('phoenix_supernova_reborn_','');
        const plan=node.resource===nativeRoot?null:plans[suffix];assert(node.resource===nativeRoot||plan,'No range plan '+suffix);
        const removed=plan?adaptSpatial(tree,plan):[];
        for(const child of tree.m_Children||[])child.m_ChildRef.__resource=mapping[child.m_ChildRef.__resource];
        walk(tree,value=>{if(value&&value.__resource&&!Object.values(mapping).includes(value.__resource))nativeResources.add(value.__resource);});
        assert.equal(kv(tree.m_Emitters||[]),kv(nativeTree.m_Emitters||[]),'Emission changed '+suffix);
        const nativeLife=(nativeTree.m_Initializers||[]).filter(x=>x._class==='C_INIT_InitFloat'&&n(x.m_nOutputField)===1);
        const derivedLife=(tree.m_Initializers||[]).filter(x=>x._class==='C_INIT_InitFloat'&&n(x.m_nOutputField)===1);
        assert.equal(kv(nativeLife),kv(derivedLife),'Lifespan changed '+suffix);
        assert.deepEqual(fields(tree,k=>/Color|HSV|Texture|Material|m_ModelList|m_nSkin/.test(k)),fields(nativeTree,k=>/Color|HSV|Texture|Material|m_ModelList|m_nSkin/.test(k)),'Native drawing or colors changed '+suffix);
        const file=path.join(sourceRoot,resource);fs.mkdirSync(path.dirname(file),{recursive:true});const source=header+kv(tree)+'\n';fs.writeFileSync(file,source);outputs.push(resource);
        const geometricBudget=plan?plan.center*(plan.curve_envelope||1)+plan.extent:0;assert(geometricBudget<=500);
        layers.push({native_source:node.resource,resource,source:path.relative(repo,file).replace(/\\/g,'/'),
            source_sha256:hash(source),native_bytes_sha256:node.native_bytes_sha256,native_data_sha256:node.native_data_sha256,
            native_children:(nativeTree.m_Children||[]).map(child=>child.m_ChildRef.__resource),derived_children:(tree.m_Children||[]).map(child=>child.m_ChildRef.__resource),
            range_contract:plan?{fixed_radius:500,spatial_size_scale:plan.size,motion_scale:plan.motion,
                constraint_class:'C_OP_ConstrainDistance',constraint_cp:0,center_max_distance:plan.center,
                renderer_extent_budget:plan.extent,curve_envelope:plan.curve_envelope||1,allocated_world_extent:geometricBudget,
                radius_override:plan.radius_override??null,ring_radius_override:plan.ring_override??null,
                note:'Finite native renderer geometry budget plus native center-distance constraint. Compiler serialization and real renderer behavior still require validation.'}:null,
            removed_spatial_writers:removed,preserved_emission:true,preserved_lifespan:true,preserved_native_drawing_and_colors:true});
    }
    nativeResources.forEach(resource=>assert(pack.entries.has(resource+'_c'),'Missing native '+resource));
    const manifest={generated_by:'tools/map_c6/build-phoenix-meteor-impact.cjs',native_root:nativeRoot,root_particle:rootParticle,
        fixed_radius:500,particle_systems:17,outputs,native_resources:[...nativeResources].sort(),layers,
        cp_contract:{0:'Fixed world landing position. No owner attachment or unit follow.',1:[1,1,1],3:'Fixed landing position plus Vector(0,0,100); native local CP3 writers moved to Lua to preserve translation invariance.',
            colors:'Keep native C_OP_HSVShiftToCP and authored default colors. Lua does not overwrite CP60/61/62.',radius:'Sources are spatially adapted for fixed 500. CP1 is the native parameter vector, not a radius input.'},
        maximum_native_tail_seconds:7,fallback_cleanup_seconds:8,
        native_model_bound:{resource:'models/particle/sphere.vmdl',sha256:hash(sphere),maximum_axis:axis,reserved_unit_radius:14},
        native_constraint_reflection:{binary:'game/bin/win64/particles.dll',sha256:hash(reflectedBytes),registered_fields:constraintFields},
        validation:{source_numeric_allocations:'PASS',preserved_full_native_dag:true,compiler_serialization:'PENDING',in_game_visual_verified:false,
            scope:'Numeric resource contract only. Culling bounds do not clip geometry. Screen shake affects the viewport for nearby cameras; shader bloom, projected materials, trail/spline tessellation and final pixels still require engine visual acceptance.'},
        excluded_particles:['phoenix_supernova_start','phoenix_supernova_egg','phoenix_supernova_death','old custom meteor_impact ring and sparks']};
    fs.writeFileSync(path.join(output,'impact_manifest.json'),JSON.stringify(manifest,null,2)+'\n');
    return manifest;
}
module.exports={build};
if(require.main===module){const manifest=build();console.log('PHOENIX_METEOR_IMPACT_SOURCE_PASS layers='+manifest.layers.length+' radius='+manifest.fixed_radius+' outputs='+manifest.outputs.length+' native_refs='+manifest.native_resources.length);}
