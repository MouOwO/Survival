'use strict';
// CP0 world origin; CP1=(gameplay radius, lava duration, reserved). No damage or
// damage rules live here. Phoenix egg uses the native CP0/1/2 path at 0.4s.
const fs=require('fs'), path=require('path'), L=require('./lib.cjs');
const root=path.resolve(__dirname,'../..');
const out=path.join(root,'art/effects/skill_visuals/source/particles/survival/skills');
const native=new L.Vpk(path.join(root,'../../dota/pak01_dir.vpk'));
// These legacy sphere/offset operators are upgraded by the compiler from v45.
// Labelling them v64 would skip those migrations and retain obsolete structs.
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const literal=value=>({m_nType:'PF_TYPE_LITERAL',m_flLiteralValue:value});
const cp=(component,mult=1)=>({m_nType:'PF_TYPE_CONTROL_POINT_COMPONENT',m_nControlPoint:1,
    m_nVectorComponent:component,m_nMapType:'PF_MAP_TYPE_MULT',m_flMultFactor:mult});
const init=(field,value)=>({_class:'C_INIT_InitFloat',m_nOutputField:field,m_InputValue:value});
const resource=x=>'resource:'+x;
const floatVector=(...values)=>({__floatVector:values});
const nativeRefs=new Set();
function nativeRef(x){if(!native.entries.has(x+'_c'))throw Error('Missing native resource '+x);nativeRefs.add(x);return resource(x);}
function kv(value){
    if(Array.isArray(value))return '[ '+value.map(kv).join(', ')+' ]';
    if(value&&value.__floatVector)return '[ '+value.__floatVector.map(n=>Number.isInteger(n)?n.toFixed(1):String(n)).join(', ')+' ]';
    if(value&&typeof value==='object')return '{\n'+Object.entries(value).map(([k,v])=>' '+k+' = '+kv(v)).join('\n')+'\n}';
    if(typeof value==='string'&&value.startsWith('resource:'))return 'resource:'+JSON.stringify(value.slice(9));
    return JSON.stringify(value);
}
const child=name=>({m_ChildRef:resource('particles/survival/skills/'+name+'.vpcf')});
function sprite(texture,ground,additive=true){return {_class:'C_OP_RenderSprites',
    m_vecTexturesInput:[{m_hTexture:nativeRef(texture)}],
    m_nOutputBlendMode:additive?'PARTICLE_OUTPUT_BLEND_MODE_ADD':'PARTICLE_OUTPUT_BLEND_MODE_ALPHA',
    ...(ground?{m_nOrientationType:'PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'}:{})};}
const definitions={};
// Ground core + cracks are two quads, with 24 sparse rising embers at most.
// Pin the quads to CP0 every frame, using the same native operator as the
// verified tower bases. Merely raising legacy PositionOffset to 32/40 left
// its vectors as INT in compiled DATA and did not resolve the ground band.
const lavaGroundHeight=32, lavaCrackHeight=40;
function ground(texture,cracks){return {_class:'CParticleSystemDefinition',m_nBehaviorVersion:5,m_nMaxParticles:1,
    m_flConstantRadius:500,m_flConstantLifespan:3,m_ConstantColor:cracks?[255,116,34,255]:[255,255,255,255],
    m_BoundingBoxMin:[-560,-560,-16],m_BoundingBoxMax:[560,560,160],
    m_Renderers:[sprite(texture,true,cracks)],
    m_Emitters:[{_class:'C_OP_InstantaneousEmitter',m_nParticlesToEmit:literal(1)}],
    m_Initializers:[{_class:'C_INIT_CreateWithinSphere'},
        init(1,cp(1)),init(3,cp(0)),init(7,literal(cracks?0.54:0.66))],
    m_Operators:[{_class:'C_OP_SetToCP',m_vecOffset:floatVector(0,0,cracks?lavaCrackHeight:lavaGroundHeight)},
        {_class:'C_OP_Decay'},{_class:'C_OP_FadeInSimple',m_flFadeInTime:0.05,m_bProportional:false},
        {_class:'C_OP_EndCapTimedDecay',m_flDecayTime:0.12}],
    ...(cracks?{}:{m_Children:[child('meteor_lava_cracks'),child('meteor_lava_embers')]})};}
definitions.meteor_lava=ground('materials/particle/lava/lava_radial/lava_radial_alphablend.vtex',false);
definitions.meteor_lava_cracks=ground('materials/particle/groundcracks_light.vtex',true);
function sparks(impact){return {_class:'CParticleSystemDefinition',m_nBehaviorVersion:5,m_nMaxParticles:24,
    m_flConstantLifespan:impact?0.45:0.75,m_flConstantRadius:impact?5:3,m_ConstantColor:[255,139,43,255],
    m_BoundingBoxMin:[-550,-550,-8],m_BoundingBoxMax:[550,550,250],
    m_Renderers:[sprite('materials/particle/particle_glow_05.vtex',false)],
    m_Emitters:[impact?{_class:'C_OP_InstantaneousEmitter',m_nParticlesToEmit:literal(24)}:
        {_class:'C_OP_ContinuousEmitter',m_flEmitRate:literal(18),m_flEmissionDuration:cp(1)}],
    m_Initializers:[{_class:'C_INIT_CreateWithinSphere',m_fRadiusMax:impact?90:360,
        m_vecDistanceBias:[1,1,0],m_LocalCoordinateSystemSpeedMin:[impact?-280:-8,impact?-280:-8,40],
        m_LocalCoordinateSystemSpeedMax:[impact?280:8,impact?280:8,impact?220:100]},
        {_class:'C_INIT_PositionOffset',m_OffsetMin:[0,0,12],m_OffsetMax:[0,0,20]},
        init(7,literal(impact?0.8:0.55))],
    m_Operators:[{_class:'C_OP_BasicMovement'},{_class:'C_OP_Decay'},
        {_class:'C_OP_FadeOutSimple',m_flFadeOutTime:0.25},
        {_class:'C_OP_InterpolateRadius',m_flEndScale:0.1},
        {_class:'C_OP_EndCapTimedDecay',m_flDecayTime:0.12}]};}
definitions.meteor_lava_embers=sparks(false);
definitions.meteor_impact_sparks=sparks(true);
definitions.meteor_impact={_class:'CParticleSystemDefinition',m_nBehaviorVersion:5,m_nMaxParticles:1,
    m_flConstantLifespan:0.38,m_ConstantColor:[255,172,77,255],
    m_BoundingBoxMin:[-560,-560,-8],m_BoundingBoxMax:[560,560,200],
    m_Renderers:[sprite('materials/particle/ring01.vtex',true)],
    m_Emitters:[{_class:'C_OP_InstantaneousEmitter',m_nParticlesToEmit:literal(1)}],
    m_Initializers:[{_class:'C_INIT_CreateWithinSphere'},
        {_class:'C_INIT_PositionOffset',m_OffsetMin:[0,0,12],m_OffsetMax:[0,0,12]},
        init(3,cp(0)),init(7,literal(0.7))],
    m_Operators:[{_class:'C_OP_BasicMovement'},{_class:'C_OP_Decay'},
        {_class:'C_OP_FadeOutSimple',m_flFadeOutTime:0.8},
        {_class:'C_OP_InterpolateRadius',m_flStartScale:0.08,m_flEndScale:1}],
    m_Children:[child('meteor_impact_sparks'),{m_ChildRef:nativeRef('particles/units/heroes/hero_phoenix/phoenix_supernova_reborn_sphere.vpcf')} ],
    m_PreEmissionOperators:[{_class:'C_OP_HSVShiftToCP',m_DefaultHSVColor:[226,158,0,255]}]};
// Actual Supernova egg model plus its native moving-core fire and glow.
// Both children follow CP3. Ground rings and full-screen flare stay out of flight.
definitions.meteor_phoenix_fall={_class:'CParticleSystemDefinition',m_nBehaviorVersion:5,
    m_nMaxParticles:1,m_flConstantRadius:1,m_bShouldSort:false,
    m_Renderers:[{_class:'C_OP_RenderModels',m_flAnimationRate:0,m_bOrientZ:true,
        m_ModelList:[{m_model:nativeRef('models/heroes/phoenix/phoenix_egg.vmdl')}],
        m_bAnimated:true,m_nLOD:1,m_bForceLoopingAnimation:true}],
    m_Operators:[{_class:'C_OP_BasicMovement'},
        {_class:'C_OP_SetControlPointsToParticle',m_nFirstControlPoint:3,m_bSetOrientation:true},
        {_class:'C_OP_RemapCPOrientationToYaw',m_nCP:3},{_class:'C_OP_SpinUpdate'}],
    m_Initializers:[{_class:'C_INIT_CreateWithinSphere'},init(3,literal(1.25))],
    m_Emitters:[{_class:'C_OP_InstantaneousEmitter',m_nParticlesToEmit:literal(1)}],
    m_Constraints:[{_class:'C_OP_ConstrainDistanceToPath',m_flTravelTime:0.4,m_flMaxDistance0:0,m_flMaxDistance1:0,
        m_PathParameters:{m_nEndControlPointNumber:1}}],
    m_Children:['glow','lava'].map(suffix=>({m_ChildRef:nativeRef(
        'particles/units/heroes/hero_phoenix/phoenix_supernova_egg_'+suffix+'.vpcf')})),
    m_PreEmissionOperators:[{_class:'C_OP_HSVShiftToCP',m_DefaultHSVColor:[230,123,1,255]},
        {_class:'C_OP_StopAfterCPDuration',m_flDuration:{m_nType:'PF_TYPE_CONTROL_POINT_COMPONENT',
        m_nControlPoint:2,m_nVectorComponent:0}}]};
fs.mkdirSync(out,{recursive:true});
for(const [name,value] of Object.entries(definitions))fs.writeFileSync(path.join(out,name+'.vpcf'),header+kv(value)+'\n');
fs.writeFileSync(path.join(root,'art/effects/skill_visuals/manifest.json'),JSON.stringify({
    generated_by:'tools/map_c6/build-meteor-visual-particles.cjs',
    source_reference:'Valve Phoenix Supernova egg model, native egg glow/lava (with steam) and reborn sphere; native path solver',
    runtime_fall_duration:'0.4 seconds, down from 0.8; unchanged radius, per-cast damage, lava and second-meteor interval',
    lava_particle_budget:26,impact_custom_particle_budget:25,
    lava_ground_layer_heights:[lavaGroundHeight,lavaCrackHeight],
    lava_position_operator:'C_OP_SetToCP with explicit FLOAT vector offsets',
    native_resources:[...nativeRefs],outputs:Object.keys(definitions).map(n=>'particles/survival/skills/'+n+'.vpcf')
},null,2)+'\n');
console.log('METEOR_VISUAL_SOURCES_PASS particles='+Object.keys(definitions).length+' native_refs='+nativeRefs.size);
