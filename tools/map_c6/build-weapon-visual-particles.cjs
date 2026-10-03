'use strict';
// Compact, attachment-safe VPCFs built from native Dota textures. Gameplay is
// intentionally absent. CP0 anchor, CP1 (radius, emission/sec, alpha), CP2 RGB.
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'art/effects/weapon_visuals/source/particles/survival/weapons');
fs.mkdirSync(out, { recursive: true });
// The template uses legacy sphere/noise operators. vpcf45 invokes Valve's
// migration to their current Transform variants; declaring vpcf64 skips it.
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const formatSource = text => text.split(/\r?\n/)
  .map(line => line.replace(/[ \t]+$/, ''))
  .filter(line => line.trim() !== '').join('\n') + '\n';
const cp = (number, component) => `{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = ${number} m_nVectorComponent = ${component} m_nMapType = "PF_MAP_TYPE_MULT" m_flMultFactor = 1.0 }`;
for (const [name, texture, mode] of [
  ['weapon_glow', 'materials/particle/particle_glow_01.vtex', 'glow'],
  ['weapon_trail', 'materials/particle/particle_glow_01.vtex', 'trail'],
  ['weapon_shards', 'materials/particle/snowflake/snowflakes_01.vtex', 'shards'],
]) {
  const glow = mode === 'glow', trail = mode === 'trail';
  const text = header + `{
 _class = "CParticleSystemDefinition"
 m_nMaxParticles = ${glow ? 1 : 32}
 m_flConstantLifespan = ${glow ? 999999 : trail ? 0.32 : 0.6}
 m_flConstantRadius = 8.0
 m_nBehaviorVersion = 12
 m_Renderers = [{
  _class = "${trail ? 'C_OP_RenderTrails' : 'C_OP_RenderSprites'}"
  m_flOverbrightFactor = ${glow ? '2.0' : '1.5'}
  ${mode === 'shards' ? '' : 'm_nOutputBlendMode = "PARTICLE_OUTPUT_BLEND_MODE_ADD"'}
  ${trail ? 'm_flMaxLength = 48.0 m_flLengthFadeInTime = 0.05' : ''}
  m_vecTexturesInput = [{ m_hTexture = resource:"${texture}" }]
 }]
 m_Emitters = [{
  _class = "${glow ? 'C_OP_InstantaneousEmitter' : 'C_OP_ContinuousEmitter'}"
  ${glow ? 'm_nParticlesToEmit = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 1.0 }' : 'm_flEmitRate = ' + cp(1, 1)}
 }]
 m_Initializers = [
  { _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = ${glow ? 0 : 5}.0 },
  { _class = "C_INIT_InitFloat" m_nOutputField = 3 m_InputValue = ${cp(1, 0)} },
  { _class = "C_INIT_InitFloat" m_nOutputField = 7 m_InputValue = ${cp(1, 2)} },
  ${glow ? '' : '{ _class = "C_INIT_InitialVelocityNoise" m_vecOutputMin = [ -6.0, -6.0, 8.0 ] m_vecOutputMax = [ 6.0, 6.0, 20.0 ] }'}
 ]
 m_Operators = [
  { _class = "C_OP_SetFloat" m_nOutputField = 7 m_InputValue = ${cp(1, 2)} },
  ${glow ? '{ _class = "C_OP_SetFloat" m_nOutputField = 3 m_InputValue = ' + cp(1, 0) + ' },' : ''}
  { _class = "C_OP_RemapCPtoVector" m_nCPInput = 2 m_nFieldOutput = 6 m_vInputMax = [255.0,255.0,255.0] m_vOutputMax = [1.0,1.0,1.0] },
  ${glow ? '{ _class = "C_OP_SetToCP" },' : '{ _class = "C_OP_BasicMovement" }, { _class = "C_OP_Decay" }, { _class = "C_OP_FadeOutSimple" m_flFadeOutTime = 0.15 }, { _class = "C_OP_InterpolateRadius" m_flEndScale = 0.1 },'}
  { _class = "C_OP_EndCapTimedDecay" m_flDecayTime = 0.15 }
 ]
 m_controlPointConfigurations = [{ m_name = "preview" m_drivers = [
  { m_iControlPoint = 0 m_iAttachType = "PATTACH_WORLDORIGIN" m_entityName = "self" },
  { m_iControlPoint = 1 m_iAttachType = "PATTACH_WORLDORIGIN" m_vecOffset = [8.0,12.0,0.5] m_entityName = "self" },
  { m_iControlPoint = 2 m_iAttachType = "PATTACH_WORLDORIGIN" m_vecOffset = [100.0,190.0,255.0] m_entityName = "self" }
 ] }]
}
`;
  fs.writeFileSync(path.join(out, name + '.vpcf'), formatSource(text));
}
console.log(out);
