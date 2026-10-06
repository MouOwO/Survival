'use strict';
// Trial 1: native ground layers and projectile adapters. No combat parameters.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk,endOf}=require('./lib.cjs');
const root=path.resolve(__dirname,'../..'),pack=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const out=path.join(root,'art/effects/tower_trial'),temp=path.join(root,'output/tower_trial');
fs.mkdirSync(temp,{recursive:true});
const prefix='particles/survival/towers/trial/';
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const outputs=[];
function native(hero,name){return 'particles/units/heroes/hero_'+hero+'/'+name+'.vpcf';}
function dump(resource){const f=path.join(temp,path.basename(resource)+'_c');fs.writeFileSync(f,pack.read(resource+'_c'));let s=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',f,'-all'],{encoding:'utf8',windowsHide:true});s=s.slice(s.indexOf('--- vpcf block DATA'));return s.slice(s.indexOf('{'));}
function array(s,key){const m=new RegExp('\\b'+key+'\\s*=').exec(s);assert(m,key);const a=s.indexOf('[',m.index);return s.slice(a,endOf(s,a,'[',']'));}
function setArray(s,key,value){const m=new RegExp('\\b'+key+'\\s*=').exec(s);if(!m)return s.replace(/}\s*$/,key+' = '+value+'\n}\n');const a=s.indexOf('[',m.index);return s.slice(0,a)+value+s.slice(endOf(s,a,'[',']'));}
function append(s,key,block){const a=array(s,key);return setArray(s,key,a.slice(0,-1).replace(/,\s*$/, '')+',\n'+block+'\n]');}
function removeClass(s,name){for(;;){const m=new RegExp('_class = "'+name+'"').exec(s);if(!m)return s;const a=s.lastIndexOf('{',m.index),b=endOf(s,a);s=s.slice(0,a)+s.slice(b).replace(/^\s*,/,'');}}
const literal=n=>'{ m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = '+Number(n).toFixed(3)+' }';
const input=(axis,factor=1)=>'{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 1 m_nVectorComponent = '+axis+' m_nMapType = "PF_MAP_TYPE_MULT" m_flMultFactor = '+factor.toFixed(3)+' }';
const init=(field,value)=>'{ _class = "C_INIT_InitFloat" m_nOutputField = '+field+' m_InputValue = '+value+' }';
const once=n=>'{ _class = "C_OP_InstantaneousEmitter" m_nParticlesToEmit = '+literal(n)+' }';
const rate=n=>'{ _class = "C_OP_ContinuousEmitter" m_flEmitRate = '+literal(n)+' }';
const color='{ _class = "C_OP_RemapCPtoVector" m_nCPInput = 2 m_nFieldOutput = 6 m_vInputMax = [255.0,255.0,255.0] m_vOutputMax = [1.0,1.0,1.0] }';
const lock='{ _class = "C_OP_PositionLock" }';
const offset=z=>'{ _class = "C_INIT_PositionOffset" m_OffsetMin = [0.0,0.0,'+z+'.0] m_OffsetMax = [0.0,0.0,'+z+'.0] }';
function renderer(s){return array(s,'m_Renderers').replace(/\s*m_nHSVShiftControlPoint = 62/g,'').replace(/m_bDisableZBuffering = true/g,'m_bDisableZBuffering = false');}
function write(name,s,source,role){const resource=prefix+name+'.vpcf';const f=path.join(out,'source',resource);fs.mkdirSync(path.dirname(f),{recursive:true});s=(header+s.replace(/m_bDisableZBuffering = true/g,'m_bDisableZBuffering = false')).split(/\r?\n/).map(l=>l.trimEnd()).join('\n').trim()+'\n';fs.writeFileSync(f,s);outputs.push({resource,native:source,role});return resource;}
function ground(name,source,cap,render,initial,operators,emit,children=[]){
 // Networked CPs can arrive after the initial burst. Persistent particles must
 // keep reading radius/alpha, otherwise their first zero value is permanent.
 for(const op of initial) if(op.includes('PF_TYPE_CONTROL_POINT_COMPONENT') && op.includes('C_INIT_InitFloat')) operators.push(op.replace('C_INIT_InitFloat','C_OP_SetFloat'));
 operators.push('{ _class = "C_OP_EndCapTimedDecay" m_flDecayTime = 0.15 }');
 return write(name,`{
 _class = "CParticleSystemDefinition" m_nBehaviorVersion = 12
 m_nMaxParticles = ${cap} m_BoundingBoxMin = [-160.0,-160.0,-20.0] m_BoundingBoxMax = [160.0,160.0,220.0] m_flConstantLifespan = 999999.0 m_ConstantColor = [255,255,255,255]
 m_Renderers = ${render}
 m_Initializers = [${initial.join(',\n')}]
 m_Operators = [${operators.join(',\n')}]
 m_Emitters = [${emit.join(',\n')}]
 m_Children = [${children.map(r=>'{ m_ChildRef = resource:"'+r+'" }').join(',')}]
}`,source,'persistent_ground');}
// Reference: the supplied Valley workshop's actual persistent tower auras.
// Reuse its flat dual-layer sigils, with bounded radius/alpha and no body curtain.
const valley=new Vpk('D:/SteamLibrary/steamapps/workshop/content/570/3164617180/3164617180.vpk');
function valleyDump(resource){const f=path.join(temp,path.basename(resource)+'_c');fs.writeFileSync(f,valley.read(resource+'_c'));let s=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',f,'-all'],{encoding:'utf8',windowsHide:true});s=s.slice(s.indexOf('--- vpcf block DATA'));return s.slice(s.indexOf('{'));}
const valleyLayers={};
for(const [name,original] of [['dark','aura_dark'],['durable','aura_durable'],['evil','aura_evil_b']]){
 const source='particles/units/towers/'+original+'.vpcf',data=valleyDump(source);
 const render=renderer(data).replace(/m_flAddSelfAmount = 10.0/g,'m_flAddSelfAmount = 2.0');
 // These textures also ship with Dota; fail explicitly rather than omit a dependency.
 for(const m of render.matchAll(/resource:"([^"]+)"/g))assert(pack.entries.has(m[1]+'_c'),'Missing Valley aura dependency '+m[1]);
 valleyLayers[name]=ground('valley_'+name,source,1,render,[
  '{ _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 }',init(3,input(0)),init(7,input(2,.9)),init(1,literal(999999))
 ],[color,'{ _class = "C_OP_SetToCP" m_vecOffset = [0.0,0.0,24.0] }','{ _class = "C_OP_RampScalarLinear" m_nField = 4 m_RateMin = 0.05 m_RateMax = 0.05 m_flEndTime_min = 999999.0 m_flEndTime_max = 999999.0 }'],[once(1)]);
}
// Native Weave rope silhouette; no remap of the ever-growing spawn count.
let src=native('dazzle','dazzle_weave_circle_trace'),s=dump(src);
ground('death_ground',src,32,renderer(s),[
 init(3,literal(5)),init(1,literal(.65)),init(7,input(2,.75)),
 '{ _class = "C_INIT_CreateInEpitrochoid" m_flRadius1 = 48.0 m_flRadius2 = 38.0 m_flOffset = 0.0 m_flParticleDensity = 17.0 m_bUseCount = true }',offset(24)
],[lock,color,'{ _class = "C_OP_FadeInSimple" m_flFadeInTime = 0.1 }','{ _class = "C_OP_FadeOutSimple" m_flFadeOutTime = 0.5 }','{ _class = "C_OP_Decay" }'],[rate(48)]);
// Formation dots only: remove the native wall and its outward expansion.
src=native('disruptor','disruptor_kineticfield_formation_markers');s=dump(src);
ground('lightning_ground',src,18,renderer(s),[
 '{ _class = "C_INIT_RingWave" m_bEvenDistribution = true m_flParticlesPerOrbit = 12.0 m_flInitialRadius = '+input(0,.85)+' m_flInitialSpeedMin = '+literal(0)+' m_flInitialSpeedMax = '+literal(0)+' }',
 init(3,literal(11)),init(7,input(2,.85)),init(1,literal(1.5)),offset(24)
],[lock,color,'{ _class = "C_OP_Decay" }'],[rate(12)]);
// Native Clinkz ember texture, small upward drift; no stop-after-20s operator.
src=native('clinkz','clinkz_burning_army_ground_sparks');s=dump(src);
const embers=ground('multi_embers',src,8,renderer(s),[
 '{ _class = "C_INIT_RingWave" m_flInitialRadius = '+input(0,.55)+' m_flInitialSpeedMin = '+literal(5)+' m_flInitialSpeedMax = '+literal(12)+' }',
 init(3,literal(3)),init(1,literal(.65)),init(7,input(2,.65)),offset(24)
],[lock,color,'{ _class = "C_OP_BasicMovement" m_Gravity = [0.0,0.0,25.0] }','{ _class = "C_OP_FadeOutSimple" }','{ _class = "C_OP_Decay" }'],[rate(8)]);
src=native('clinkz','clinkz_burning_army_ground_swirl');s=dump(src);
let render=renderer(s).replace('m_bSaturateColorPreAlphaBlend = false','m_bSaturateColorPreAlphaBlend = false\n m_nOutputBlendMode = "PARTICLE_OUTPUT_BLEND_MODE_ADD"');
ground('multi_ground',src,2,render,[
 '{ _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 }',init(3,input(0,.82)),init(7,input(2,.65)),init(1,literal(999999)),
 '{ _class = "C_INIT_InitFloat" m_nOutputField = 4 m_InputValue = { m_nType = "PF_TYPE_RANDOM_UNIFORM" m_flRandomMin = 0.0 m_flRandomMax = 360.0 } }'
],[color,'{ _class = "C_OP_SetToCP" m_vecOffset = [0.0,0.0,24.0] }','{ _class = "C_OP_RampScalarLinear" m_nField = 4 m_RateMin = -0.15 m_RateMax = 0.15 m_flEndTime_min = 999999.0 m_flEndTime_max = 999999.0 }'],[once(2)],[embers]);
// Ice Vortex ground material + sparse native crystal flecks. No huge cloud.
src=native('ancient_apparition','ancient_ice_vortex_f');s=dump(src);
const flecks=ground('frost_flecks',src,12,renderer(s),[
 '{ _class = "C_INIT_RingWave" m_flInitialRadius = '+input(0,.72)+' m_flInitialSpeedMin = '+literal(0)+' m_flInitialSpeedMax = '+literal(0)+' }',
 init(3,literal(3.5)),init(1,literal(1)),init(7,input(2,.75)),offset(24),'{ _class = "C_INIT_RandomSequence" m_nSequenceMax = 63 }'
],[lock,color,'{ _class = "C_OP_BasicMovement" m_Gravity = [0.0,0.0,8.0] }','{ _class = "C_OP_FadeOutSimple" }','{ _class = "C_OP_Decay" }'],[rate(10)]);
src=native('ancient_apparition','ancient_ice_vortex_d');s=dump(src);
ground('frost_ground',src,1,renderer(s),['{ _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 }',init(3,input(0,1.05)),init(7,input(2,.7)),init(1,literal(999999))],[color,'{ _class = "C_OP_SetToCP" m_vecOffset = [0.0,0.0,160.0] }'],[once(1)],[flecks]);
// Leshrac W ground swirl: one persistent ground layer, without timed gaps.
src=native('leshrac','leshrac_diabolic_edict');
const edictFile=path.join(root,'art/effects/leshrac_base/source/particles/survival/towers/leshrac_base/leshrac_diabolic_groundflash.vpcf');
s=fs.readFileSync(edictFile,'utf8');
let edictRender=renderer(s).replace('m_flOverbrightFactor = 4.0','m_flOverbrightFactor = 1.3');
ground('mystery_ground',src,1,edictRender,[
 '{ _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 }',init(3,input(0)),init(7,input(2,.7)),init(1,literal(999999))
],[color,'{ _class = "C_OP_SetToCP" m_vecOffset = [0.0,0.0,24.0] }','{ _class = "C_OP_RampScalarLinear" m_nField = 4 m_RateMin = 0.18 m_RateMax = 0.18 m_flEndTime_min = 999999.0 m_flEndTime_max = 999999.0 }'],[once(1)]);
// Alternate SSR Lich fallback: keep the TI8 crystal silhouette; it is a custom
// scale adapter, not a nonexistent third cosmetic. Native speed remains intact.
const lichPrefix='particles/econ/items/lich/lich_ti8_immortal_arms/lich_ti8_chain_frost';
const lichChildren={};
for(const child of ['model','flare','light']){
 const original=lichPrefix+'_'+child+'.vpcf';let data=dump(original);
 data=append(data,'m_Initializers',init(3,literal(1.45)).replace('m_nOutputField = 3','m_nOutputField = 3 m_nSetMethod = "PARTICLE_SET_SCALE_CURRENT_VALUE"'));
 lichChildren[original]=write('frost_ssr_chain_'+child,data,original,'projectile_child');
}
src=lichPrefix+'.vpcf';s=dump(src);
for(const [original,replacement] of Object.entries(lichChildren))s=s.split(original).join(replacement);
write('frost_ssr_chain',s,src,'tracking_projectile');
// Rocket's native ballistic offset aims 2000 units above the target: remove it.
src=native('rattletrap','rattletrap_rocket_flare');s=removeClass(dump(src),'C_OP_CPOffsetToPercentageBetweenCPs');s=s.replace('m_nControlPointNumber = 4','m_nControlPointNumber = 1').replace(/m_flDelay = 0.1/,'m_flDelay = 0.0');
s=s.replace(native('rattletrap','rattletrap_rocket_flare_explosion'),native('gyrocopter','gyro_base_attack_explosion'));
write('anti_air_sr_rocket',s,src,'tracking_projectile');
// Distinct SSR comet: native AA ice fragments + compact glow on tracking controller.
const aa=n=>'ancient_apparition_ice_blast_'+n;
for(const [name,emission,cap] of [['main',24,12],['ice_b',20,16]]){
 src=native('ancient_apparition',aa(name));s=dump(src);s=setArray(s,'m_Children','[]');s=setArray(s,'m_Emitters','['+once(3)+','+rate(emission)+']');
 s=s.replace(/m_nMaxParticles = \d+/, 'm_nMaxParticles = '+cap).replace(/m_nHSVShiftControlPoint = 62/g,'').replace(/m_bDisableZBuffering = true/g,'m_bDisableZBuffering = false');
 if(name==='main'){s=s.replace('m_flLiteralValue = 80.0','m_flLiteralValue = 18.0').replace('m_flStartScale = 3.0','m_flStartScale = 1.2');}
 write('frost_comet_'+name,s,src,'projectile_child');
}
src=native('ancient_apparition',aa('final'));s=dump(src);s=removeClass(removeClass(s,'C_INIT_VelocityFromCP'),'C_OP_MovementPlaceOnGround');s=setArray(s,'m_PreEmissionOperators','[]');s=setArray(s,'m_Renderers','[]');s=setArray(s,'m_Children','[{ m_ChildRef = resource:"'+prefix+'frost_comet_main.vpcf" },{ m_ChildRef = resource:"'+prefix+'frost_comet_ice_b.vpcf" },{ m_bEndCap = true m_ChildRef = resource:"particles/units/heroes/hero_lich/lich_chain_frost_explode.vpcf" }]');
s=append(s,'m_Operators','{ _class = "C_OP_MaxVelocity" m_nOverrideCP = 2 m_flMaxVelocity = 1000.0 }');s=setArray(s,'m_ForceGenerators','[{ _class = "C_OP_AttractToControlPoint" m_nControlPointNumber = 1 m_fFalloffPower = 0.0 m_fForceAmount = '+literal(1000000)+' }]');
write('frost_ssr_comet',s,src,'tracking_projectile');
// Keep native white-blue Zeus appearance; wider main trunk distinguishes SSR.
src=native('zuus','zuus_arc_lightning');s=dump(src);s=append(s,'m_Initializers','{ _class = "C_INIT_InitFloat" m_nOutputField = 3 m_nSetMethod = "PARTICLE_SET_SCALE_CURRENT_VALUE" m_InputValue = '+literal(1.8)+' }');write('lightning_ssr_arc',s,src,'native_beam_variant');
for(const [name,style] of Object.entries({death_ground:'dark',mystery_ground:'evil',lightning_ground:'durable',multi_ground:'dark',frost_ground:'evil'})){
 const file=path.join(out,'source',prefix+name+'.vpcf');let data=fs.readFileSync(file,'utf8');
 const children=array(data,'m_Children');const body=children.slice(1,-1).trim();
 data=setArray(data,'m_Children','['+body+(body?',':'')+'{ m_ChildRef = resource:"'+valleyLayers[style]+'" }]');fs.writeFileSync(file,data);
}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({revision:'skin_presets_20261002',control_points:'Ground: CP0 feet, CP1 x radius/z alpha, CP2 RGB. Tracking: native CP0 source/CP1 target/CP2 speed.',outputs},null,2)+'\n');
console.log('TOWER_TRIAL_SOURCE_PASS '+outputs.length+' outputs');
