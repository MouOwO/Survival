'use strict';
// Complete native Mortimer Kisses ground graph, independently sized for Meteor.
// No projectile, no Lua movement, no extra emitters or particle-count increases.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert'),crypto=require('crypto');
const {Vpk,endOf}=require('./lib.cjs');
const repo=path.resolve(__dirname,'../..'),engine=path.resolve(repo,'../../..');
const info=path.join(engine,'game/bin/win64/resourceinfo.exe');
const output=path.join(repo,'art/effects/meteor_snapfire_ground');
const evidence=path.join(repo,'output/meteor_snapfire_ground');
const nativeRoot='particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_linger.vpcf';
const root='particles/survival/skills/meteor_snapfire_ground.vpcf';
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const num=value=>({__number:value,raw:Number.isInteger(value)?value.toFixed(1):String(value)});
const integer=value=>({__number:value,raw:String(value)});
const n=value=>value&&typeof value==='object'&&'__number'in value?value.__number:value;
const literal=value=>({m_nType:'PF_TYPE_LITERAL',m_flLiteralValue:num(value)});
const component=(point,axis)=>({m_nType:'PF_TYPE_CONTROL_POINT_COMPONENT',m_nControlPoint:integer(point),m_nVectorComponent:integer(axis)});
function parse(text){
    const tokens=text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g);let i=0;
    function value(){const token=tokens[i++];
        if(token==='{'){const result={};while(tokens[i]!=='}'){const key=tokens[i++];assert.equal(tokens[i++],'=');result[key]=value();if(tokens[i]===',')i++;}i++;return result;}
        if(token==='['){const result=[];while(tokens[i]!==']'){result.push(value());if(tokens[i]===',')i++;}i++;return result;}
        if(token.startsWith('resource:'))return {__resource:JSON.parse(token.slice(9))};
        if(token.startsWith('"'))return JSON.parse(token);if(token==='true'||token==='false')return token==='true';if(token==='null')return null;
        assert(Number.isFinite(Number(token)),token);return {__number:Number(token),raw:token};
    }
    const result=value();assert.equal(i,tokens.length);return result;
}
function kv(value,indent=0){
    if(value===null)return'null';if(Array.isArray(value))return'[ '+value.map(v=>kv(v,indent)).join(', ')+' ]';
    if(value&&typeof value==='object'&&'__number'in value)return value.raw;
    if(value&&typeof value==='object'&&'__resource'in value)return'resource:'+JSON.stringify(value.__resource);
    if(typeof value==='object')return'{\n'+Object.entries(value).map(([key,v])=>'\t'.repeat(indent+1)+key+' = '+kv(v,indent+1)).join('\n')+'\n'+'\t'.repeat(indent)+'}';
    return JSON.stringify(value);
}
function walk(value,callback){callback(value);if(Array.isArray(value))value.forEach(v=>walk(v,callback));else if(value&&typeof value==='object'&&!('__number'in value)&&!('__resource'in value))Object.values(value).forEach(v=>walk(v,callback));}
function dump(bytes,name){const file=path.join(evidence,'native',name+'_c');fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);
    const text=cp.execFileSync(info,['-i',file,'-all'],{encoding:'utf8',windowsHide:true,maxBuffer:16*1024*1024});fs.writeFileSync(file+'.txt',text);
    const marker=text.indexOf('--- vpcf block DATA'),open=text.indexOf('{',marker);assert(marker>=0);return parse(text.slice(open,endOf(text,open)));}
function scale(object,key,factor){if(object[key]===undefined)return;const value=object[key];
    if(Array.isArray(value))object[key]=value.map(v=>num(n(v)*factor));
    else if(value&&'__number'in value)object[key]=num(n(value)*factor);
    else if(value&&typeof value==='object'){
        for(const key of ['m_flLiteralValue','m_flRandomMin','m_flRandomMax','m_flOutput0','m_flOutput1','m_vLiteralValue','m_vRandomMin','m_vRandomMax'])scale(value,key,factor);
        if(value.m_Curve){for(const point of value.m_Curve.m_spline||[])for(const key of ['y','m_flSlopeIncoming','m_flSlopeOutgoing'])scale(point,key,factor);
            for(const key of ['m_vDomainMins','m_vDomainMaxs'])if(value.m_Curve[key])value.m_Curve[key][1]=num(n(value.m_Curve[key][1])*factor);}
    }
}
function measuredPoolRadius(bytes){
    const table=8+bytes.readUInt32LE(8);let mesh=null;
    for(let i=0;i<bytes.readUInt32LE(12);i++){const record=table+i*12;if(bytes.toString('ascii',record,record+4)==='MBUF')mesh=record+4+bytes.readUInt32LE(record+4);}
    assert(mesh!==null,'Native pool MBUF required');const vertex=mesh+bytes.readUInt32LE(mesh);
    assert.equal(bytes.readUInt32LE(mesh+4),1,'One native pool vertex buffer');
    const count=bytes.readUInt32LE(vertex),stride=bytes.readUInt32LE(vertex+4),layout=vertex+8+bytes.readUInt32LE(vertex+8);
    assert.equal(bytes.toString('ascii',layout,layout+9),'POSITION\0');assert.equal(bytes.readUInt32LE(layout+36),6,'DXGI R32G32B32_FLOAT');assert.equal(bytes.readUInt32LE(layout+40),0);
    const data=vertex+16+bytes.readUInt32LE(vertex+16);assert.equal(bytes.readUInt32LE(vertex+20),count*stride,'Uncompressed native vertices');let maximum=0;
    for(let i=0;i<count;i++)maximum=Math.max(maximum,Math.hypot(bytes.readFloatLE(data+i*stride),bytes.readFloatLE(data+i*stride+4)));
    assert(maximum>7.49&&maximum<7.51);return {maximum_xy_radius:maximum,vertices:count,vertex_stride:stride,sha256:hash(bytes)};
}
const coreNames=new Set(['hero_snapfire_ult_ground_outer','hero_snapfire_ult_ground_bloom','hero_snapfire_ultimate_ground_glow','hero_snapfire_ult_ground_light','hero_snapfire_ult_ground_ring']);
function spatial(tree,factor){
    scale(tree,'m_flConstantRadius',factor);
    for(const init of tree.m_Initializers||[]){
        if(init._class==='C_INIT_InitFloat'&&n(init.m_nOutputField===undefined?3:init.m_nOutputField)===3)scale(init,'m_InputValue',factor);
        if(init._class==='C_INIT_CreateWithinSphere'){
            const point=n(init.m_nControlPointNumber)||0;init._class='C_INIT_CreateWithinSphereTransform';
            init.m_TransformInput={m_nType:'PT_TYPE_CONTROL_POINT',m_nControlPoint:integer(point)};delete init.m_nControlPointNumber;
            for(const key of ['m_fRadiusMin','m_fRadiusMax','m_fSpeedMin','m_fSpeedMax','m_LocalCoordinateSystemSpeedMin','m_LocalCoordinateSystemSpeedMax'])scale(init,key,factor);
        }
        if(init._class==='C_INIT_RingWave')for(const key of ['m_flInitialRadius','m_flThickness','m_flInitialSpeedMin','m_flInitialSpeedMax'])scale(init,key,factor);
        if(init._class==='C_INIT_PositionOffset')for(const key of ['m_OffsetMin','m_OffsetMax'])scale(init,key,factor);
        if(['C_INIT_InitialVelocityNoise','C_INIT_VelocityRandom'].includes(init._class))for(const key of ['m_vecOutputMin','m_vecOutputMax','m_LocalCoordinateSystemSpeedMin','m_LocalCoordinateSystemSpeedMax'])scale(init,key,factor);
        if(init._class==='C_INIT_InitVec'&&n(init.m_nOutputField)===2)scale(init,'m_InputValue',factor);
    }
    for(const op of tree.m_Operators||[]){
        if(op._class==='C_OP_SetFloat'&&n(op.m_nOutputField===undefined?3:op.m_nOutputField)===3)scale(op,'m_InputValue',factor);
        if(op._class==='C_OP_BasicMovement')scale(op,'m_Gravity',factor);
        if(op._class==='C_OP_VectorNoise'&&[0,2].includes(n(op.m_nFieldOutput)))for(const key of ['m_vecOutputMin','m_vecOutputMax'])scale(op,key,factor);
        if(op._class==='C_OP_OscillateVector'&&n(op.m_nField)===2)for(const key of ['m_RateMin','m_RateMax'])scale(op,key,factor);
        if(['C_OP_RampScalarLinear','C_OP_RampScalarLinearSimple'].includes(op._class)&&n(op.m_nField===undefined?3:op.m_nField)===3)for(const key of ['m_Rate','m_RateMin','m_RateMax'])scale(op,key,factor);
    }
    for(const force of tree.m_ForceGenerators||[]){if(force._class==='C_OP_AttractToControlPoint')scale(force,'m_fForceAmount',factor);if(force._class==='C_OP_RandomForce')for(const key of ['m_MinForce','m_MaxForce'])scale(force,key,factor);}
    for(const renderer of tree.m_Renderers||[])for(const key of ['m_flMaxLength','m_flMinLength','m_flTextureVWorldSize','m_cubeWidth','m_cutoffRadius','m_renderRadius'])scale(renderer,key,factor);
    // Retain engine dynamic bounds; broad static bounds would keep an offscreen
    // pool and its expensive lights unnecessarily eligible for rendering.
    for(const key of ['m_BoundingBoxMin','m_BoundingBoxMax'])scale(tree,key,factor);
}
function timedRetirement(tree,name){
    const core=coreNames.has(name);const rendered=(tree.m_Renderers||[]).length>0;
    if(core){
        let life=false;for(const init of tree.m_Initializers||[])if(init._class==='C_INIT_InitFloat'&&n(init.m_nOutputField)===1){init.m_InputValue=component(21,0);life=true;}
        if(!life)(tree.m_Initializers||=[]).push({_class:'C_INIT_InitFloat',m_nOutputField:integer(1),m_InputValue:component(21,0)});
        // Preserve native initial brightness/expansion; retire at the actual
        // damage deadline instead of at each original 3-second alpha curve.
        tree.m_Operators=(tree.m_Operators||[]).filter(op=>op._class!=='C_OP_FadeOutSimple'&&op._class!=='C_OP_FadeOut');
        for(const op of tree.m_Operators){if(op._class!=='C_OP_SetFloat'||n(op.m_nOutputField)!==7)continue;
            const curve=op.m_InputValue&&op.m_InputValue.m_Curve;if(!curve)continue;
            const points=curve.m_spline||[],last=points[points.length-1],previous=points[points.length-2];
            if(last&&previous&&n(last.y)===0){last.y=structuredClone(previous.y);last.m_flSlopeIncoming=num(0);last.m_flSlopeOutgoing=num(0);previous.m_flSlopeIncoming=num(0);previous.m_flSlopeOutgoing=num(0);}
        }
        // Keep the original pool's 0.277s arrival expansion, despite extending
        // the particle's lifetime to include the smooth endcap.
        if(name==='hero_snapfire_ult_ground_outer')for(const op of tree.m_Operators||[]){if(op._class!=='C_OP_SetFloat'||n(op.m_nOutputField===undefined?3:op.m_nOutputField)!==3)continue;
            if(op.m_InputValue.m_nType==='PF_TYPE_PARTICLE_AGE_NORMALIZED'){op.m_InputValue.m_nType='PF_TYPE_PARTICLE_AGE';const curve=op.m_InputValue.m_Curve;
                for(const point of curve.m_spline||[]){point.x=num(n(point.x)*3);for(const key of ['m_flSlopeIncoming','m_flSlopeOutgoing'])if(point[key])point[key]=num(n(point[key])/3);}
                curve.m_vDomainMins[0]=num(n(curve.m_vDomainMins[0])*3);curve.m_vDomainMaxs[0]=num(n(curve.m_vDomainMaxs[0])*3);}
        }
    }
    if(rendered){
        tree.m_Operators||=[];
        tree.m_Operators.push({_class:'C_OP_LerpEndCapScalar',m_nFieldOutput:integer(7),m_flOutput:num(0),m_flLerpTime:num(0.6)});
        // The native model is alpha-tested. Its radius shrinks smoothly too,
        // so the ending works without changing its original shader/material.
        if((tree.m_Renderers||[]).some(renderer=>renderer._class==='C_OP_RenderModels'))tree.m_Operators.push({_class:'C_OP_LerpEndCapScalar',m_nFieldOutput:integer(3),m_flOutput:num(0),m_flLerpTime:num(0.6)});
        tree.m_Operators.push({_class:'C_OP_EndCapTimedDecay',m_flDecayTime:num(0.6)});
    }
    // Stop even descendants with otherwise unbounded continuous emitters.
    tree.m_PreEmissionOperators=(tree.m_PreEmissionOperators||[]).filter(op=>op._class!=='C_OP_StopAfterCPDuration');
    tree.m_PreEmissionOperators.push({_class:'C_OP_StopAfterCPDuration',m_flDuration:component(20,1)});
}
function build(){
    const pack=new Vpk(path.join(engine,'game/dota/pak01_dir.vpk')),nodes=new Map();
    function load(resource){if(nodes.has(resource))return;const bytes=pack.read(resource+'_c'),tree=dump(bytes,path.basename(resource));nodes.set(resource,{tree,bytes});for(const child of tree.m_Children||[])load(child.m_ChildRef.__resource);}
    load(nativeRoot);assert.equal(nodes.size,17,'The full installed native ground closure');
    const pool=measuredPoolRadius(pack.read('models/heroes/snapfire/fx/snapfire_pool.vmdl_c'));
    const factor=500/(40*pool.maximum_xy_radius);
    const mapping=Object.fromEntries([...nodes.keys()].map(resource=>[resource,resource===nativeRoot?root:root.slice(0,-5)+'_'+path.basename(resource,'.vpcf').replace(/^hero_snapfire_(?:ultimate_|ult_)/,'')+'.vpcf']));
    const layers=[],nativeResources=new Set();
    for(const [resource,node]of nodes){const original=structuredClone(node.tree),tree=structuredClone(node.tree),name=path.basename(resource,'.vpcf');
        delete tree.m_controlPointConfigurations;spatial(tree,factor);timedRetirement(tree,name);
        for(const child of tree.m_Children||[])child.m_ChildRef.__resource=mapping[child.m_ChildRef.__resource];
        assert.equal(kv(original.m_Emitters||[]),kv(tree.m_Emitters||[]),'Do not increase emission '+name);
        const drawings=value=>{const copy=structuredClone(value);for(const renderer of copy)for(const key of ['m_flMaxLength','m_flMinLength','m_flTextureVWorldSize','m_cubeWidth','m_cutoffRadius','m_renderRadius'])delete renderer[key];return kv(copy);};
        assert.equal(drawings(original.m_Renderers||[]),drawings(tree.m_Renderers||[]),'Preserve native drawing graph '+name);
        walk(tree,value=>{if(value&&value.__resource&&!Object.values(mapping).includes(value.__resource))nativeResources.add(value.__resource);});
        const text=header+kv(tree)+'\n',destination=path.join(output,'source',mapping[resource]);fs.mkdirSync(path.dirname(destination),{recursive:true});fs.writeFileSync(destination,text);
        layers.push({native_resource:resource,resource:mapping[resource],native_sha256:hash(node.bytes),source_sha256:hash(text),native_children:(original.m_Children||[]).map(child=>child.m_ChildRef.__resource),core_duration_layer:coreNames.has(name),preserved_emission:true});
    }
    const manifest={generated_by:'tools/map_c6/build-meteor-snapfire-ground.cjs',root,native_root:nativeRoot,outputs:layers.map(layer=>layer.resource),layers,native_resources:[...nativeResources].sort(),
        radius:500,uniform_spatial_scale:factor,pool_model:pool,main_pool_native_particle_radius:40,main_pool_derived_world_radius:40*pool.maximum_xy_radius*factor,
        cp_contract:{0:'Fixed landing position',1:'Same landing position: liquid repulsion origin',3:'Same landing position: native burst origins',20:[500,'active damage duration (3 or 3.5)',0.6],21:['active duration + 0.6',0,0],colors:'CP61/62 retain engine defaults, matching the current native Arcane Barrage root'},
        lifecycle:{begin:'One complete native root per Meteor cast at the first landing',stop:'DestroyParticle(false) at damage expiry starts native endcap; ReleaseParticleIndex once',fade_seconds:0.6,core_lifetime:'CP21.x prevents original 3s hard cutoff',model_retirement:'Native alpha fade plus radius shrink to zero: original alpha-test material remains intact',bounded_emission:'Every layer stops emission at CP20.y; every rendered layer has EndCapTimedDecay 0.6',no_lua_tick_required:true},
        validation:{full_native_graph:17,emission_counts_unchanged:true,materials_textures_models_colors_unchanged:true,main_pool_vertex_radius_verified:true,compiled:false,in_game_visual_verified:false,
            limits:'500 is the main lava model footprint; native splash, flare/bloom and flying debris keep authored relative ratios and can extend beyond the damage circle. Shader pixels and rendered endcap require live visual acceptance.'}};
    fs.mkdirSync(output,{recursive:true});fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');return manifest;
}
function verify(){
    const manifest=JSON.parse(fs.readFileSync(path.join(output,'manifest.json'),'utf8'));let count=0;
    const mapping=new Map(manifest.layers.map(layer=>[layer.native_resource,layer.resource]));assert.equal(mapping.size,17);
    for(const layer of manifest.layers){const source=fs.readFileSync(path.join(output,'source',layer.resource));assert.equal(hash(source),layer.source_sha256);
        const content=fs.readFileSync(path.join(engine,'content/dota_addons/survival',layer.resource));assert(source.equals(content),'Source/content mismatch '+layer.resource);
        const bytes=fs.readFileSync(path.join(repo,layer.resource+'_c'));
        const text=cp.execFileSync(info,['-i',path.join(repo,layer.resource+'_c'),'-all'],{encoding:'utf8',windowsHide:true,maxBuffer:16*1024*1024});
        const marker=text.indexOf('--- vpcf block DATA'),open=text.indexOf('{',marker);assert(marker>=0);const tree=parse(text.slice(open,endOf(text,open)));
        assert.deepEqual((tree.m_Children||[]).map(child=>child.m_ChildRef.__resource).sort(),layer.native_children.map(child=>mapping.get(child)).sort(),'Compiled full native child graph '+layer.resource);
        const sourceTree=parse(source.toString('utf8').slice(source.toString('utf8').indexOf('{',source.toString('utf8').indexOf('-->'))));
        const modelRenderers=(tree.m_Renderers||[]).filter(renderer=>renderer._class==='C_OP_RenderModels');
        const sourceModels=(sourceTree.m_Renderers||[]).filter(renderer=>renderer._class==='C_OP_RenderModels');
        assert.equal(modelRenderers.length,sourceModels.length);
        modelRenderers.forEach((renderer,index)=>{assert.equal(renderer.m_szRenderAttribute,sourceModels[index].m_szRenderAttribute);assert.equal(renderer.m_bSuppressTint,sourceModels[index].m_bSuppressTint);});
        assert((tree.m_PreEmissionOperators||[]).some(op=>op._class==='C_OP_StopAfterCPDuration'&&op.m_flDuration.m_nType==='PF_TYPE_CONTROL_POINT_COMPONENT'&&n(op.m_flDuration.m_nControlPoint)===20&&n(op.m_flDuration.m_nVectorComponent)===1));
        if((tree.m_Renderers||[]).length){assert((tree.m_Operators||[]).some(op=>op._class==='C_OP_EndCapTimedDecay'&&n(op.m_flDecayTime)===0.6));assert((tree.m_Operators||[]).some(op=>op._class==='C_OP_LerpEndCapScalar'&&n(op.m_nFieldOutput)===7&&n(op.m_flLerpTime)===0.6));}
        if((tree.m_Renderers||[]).some(renderer=>renderer._class==='C_OP_RenderModels')){
            const radius=tree.m_Operators.findIndex(op=>op._class==='C_OP_LerpEndCapScalar'&&n(op.m_nFieldOutput===undefined?3:op.m_nFieldOutput)===3&&n(op.m_flOutput)===0&&n(op.m_flLerpTime)===0.6);
            assert(radius>=0,'Native model retirement requires compiled radius lerp '+layer.resource);
            assert(tree.m_Operators.every((op,index)=>op._class!=='C_OP_SetFloat'||n(op.m_nOutputField===undefined?3:op.m_nOutputField)!==3||index<radius));
        }
        if(layer.core_duration_layer)assert((tree.m_Initializers||[]).some(init=>init._class==='C_INIT_InitFloat'&&n(init.m_nOutputField)===1&&init.m_InputValue.m_nType==='PF_TYPE_CONTROL_POINT_COMPONENT'&&n(init.m_InputValue.m_nControlPoint)===21));
        layer.compiled_sha256=hash(bytes);count++;fs.mkdirSync(path.join(evidence,'compiled'),{recursive:true});fs.writeFileSync(path.join(evidence,'compiled',path.basename(layer.resource)+'.txt'),text);
    }
    manifest.validation.compiled=true;fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
    fs.writeFileSync(path.join(evidence,'verification.json'),JSON.stringify({status:'PASS',compiled_layers:count,pool_radius:manifest.main_pool_derived_world_radius,fade_seconds:0.6,in_game_visual_verified:false},null,2)+'\n');return count;
}
module.exports={build,verify};
if(require.main===module){if(process.argv.includes('--verify'))console.log('METEOR_SNAPFIRE_GROUND_VERIFY_PASS layers='+verify());else{const manifest=build();console.log('METEOR_SNAPFIRE_GROUND_SOURCE_PASS layers='+manifest.layers.length+' radius='+manifest.main_pool_derived_world_radius+' scale='+manifest.uniform_spatial_scale);}}
