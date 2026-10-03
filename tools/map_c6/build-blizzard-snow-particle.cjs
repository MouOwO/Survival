'use strict';
// Crystal Maiden Freezing Field snow and frost projection, sized by the skill.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk,endOf}=require('./lib.cjs');
const root=path.resolve(__dirname,'../..'),pack=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const temp=path.join(root,'output/wyvern_blizzard');fs.mkdirSync(temp,{recursive:true});
const prefix='particles/survival/skills/',out=path.join(root,'art/effects/skill_visuals/source');
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
function dump(name){const r='particles/units/heroes/hero_crystalmaiden/maiden_freezing_field_'+name+'.vpcf',f=path.join(temp,path.basename(r)+'_c');fs.writeFileSync(f,pack.read(r+'_c'));let s=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',f,'-all'],{encoding:'utf8',windowsHide:true});s=s.slice(s.indexOf('--- vpcf block DATA'));return s.slice(s.indexOf('{'));}
function replaceArray(s,key,value){const at=s.indexOf(key),a=s.indexOf('[',at);assert(at>=0);return s.slice(0,a)+value+s.slice(endOf(s,a,'[',']'));}
function array(s,key){const a=s.indexOf('[',s.indexOf(key));return s.slice(a,endOf(s,a,'[',']'));}
function write(name,data){const f=path.join(out,prefix+name+'.vpcf');fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,header+data.replaceAll('m_bDisableZBuffering = true','m_bDisableZBuffering = false'));}
let snow=dump('snow');snow=replaceArray(snow,'m_Children','[]');
snow=snow.replace('m_nMaxParticles = 512','m_nMaxParticles = 192').replace('m_flLiteralValue = 400.0','m_flLiteralValue = 96.0')
 .replace('[ 24.0, 24.0, 824.0 ]','[ 12.0, 12.0, 360.0 ]').replace('[ -24.0, -24.0, 634.0 ]','[ -12.0, -12.0, 240.0 ]')
 .replace('[ -64.0, -64.0, -464.0 ]','[ -40.0, -40.0, -250.0 ]').replace('[ 64.0, 264.0, -364.0 ]','[ 40.0, 40.0, -200.0 ]');
// CP1 x/y provide outer disk scale; ring thickness spans its center as well.
snow=snow.replace('m_flMultFactor = 0.6','m_flMultFactor = 0.5').replace('m_flMultFactor = 0.6','m_flMultFactor = 1.0');
write('wyvern_blizzard_snow',snow);
const lit=n=>'{ m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = '+n.toFixed(3)+' }';
const radius=k=>'{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 2 m_nVectorComponent = 0 m_nMapType = "PF_MAP_TYPE_MULT" m_flMultFactor = '+k.toFixed(3)+' }';
const init=(f,v)=>'{ _class = "C_INIT_InitFloat" m_nOutputField = '+f+' m_InputValue = '+v+' }';
let ground=`{ _class = "CParticleSystemDefinition" m_nBehaviorVersion = 12 m_nMaxParticles = 1 m_flConstantLifespan = 999999.0 m_ConstantColor = [155,214,245,255]
 m_Renderers = ${array(dump('snow_d'),'m_Renderers')}
 m_Initializers = [{ _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 },${init(3,radius(1))},${init(7,lit(.45))}]
 m_Operators = [{ _class = "C_OP_SetFloat" m_nOutputField = 3 m_InputValue = ${radius(1)} },{ _class = "C_OP_SetToCP" m_vecOffset = [0.0,0.0,200.0] },{ _class = "C_OP_EndCapTimedDecay" m_flDecayTime = 0.15 }]
 m_Emitters = [{ _class = "C_OP_InstantaneousEmitter" m_nParticlesToEmit = ${lit(1)} }]
 m_Children = [{ m_ChildRef = resource:"${prefix}blizzard_wind.vpcf" }]
}`;
write('blizzard_ground',ground);
write('blizzard_wind',`{ _class = "CParticleSystemDefinition" m_nBehaviorVersion = 12 m_nMaxParticles = 12 m_ConstantColor = [165,215,250,255]
 m_Renderers = ${array(dump('snow_c'),'m_Renderers')}
 m_Initializers = [{ _class = "C_INIT_RingWave" m_flInitialRadius = ${radius(.55)} m_flThickness = ${radius(.5)} m_flInitialSpeedMin = ${lit(0)} m_flInitialSpeedMax = ${lit(0)} },${init(3,radius(.2))},${init(7,lit(.22))},${init(1,lit(1.5))},{ _class = "C_INIT_PositionOffset" m_OffsetMin = [0.0,0.0,20.0] m_OffsetMax = [0.0,0.0,24.0] }]
 m_Operators = [{ _class = "C_OP_Decay" },{ _class = "C_OP_FadeInSimple" m_flFadeInTime = 0.15 },{ _class = "C_OP_FadeOutSimple" m_flFadeOutTime = 0.35 },{ _class = "C_OP_RampScalarLinear" m_nField = 4 m_RateMin = -0.5 m_RateMax = -0.3 }]
 m_Emitters = [{ _class = "C_OP_ContinuousEmitter" m_flEmitRate = ${lit(8)} }]
}`);
console.log('BLIZZARD_SOURCE_PASS 3 resources; CP2 ground radius; CP1 snowfall radius');
