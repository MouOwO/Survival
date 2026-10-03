'use strict';
// Keep the native snowflake renderer; omit Freezing Field's extra spell layers.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk,endOf}=require('./lib.cjs');
const root=path.resolve(__dirname,'../..');
const native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const resource='particles/units/heroes/hero_crystalmaiden/maiden_freezing_field_snow.vpcf';
const temp=path.join(root,'output/wyvern_blizzard');fs.mkdirSync(temp,{recursive:true});
const file=path.join(temp,'maiden_freezing_field_snow.vpcf_c');fs.writeFileSync(file,native.read(resource+'_c'));
const dump=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
let data=dump.slice(dump.indexOf('--- vpcf block DATA'));data=data.slice(data.indexOf('{'));
const children=data.indexOf('m_Children'),open=data.indexOf('[',children);
assert(children>=0);data=data.slice(0,children)+data.slice(endOf(data,open,'[',']'));
data=data.replace('m_nMaxParticles = 512','m_nMaxParticles = 128')
    .replace('m_flLiteralValue = 400.0','m_flLiteralValue = 64.0')
    .replace('[ 24.0, 24.0, 824.0 ]','[ 12.0, 12.0, 440.0 ]')
    .replace('[ -24.0, -24.0, 634.0 ]','[ -12.0, -12.0, 340.0 ]')
    .replace('[ -64.0, -64.0, -464.0 ]','[ -24.0, -24.0, -180.0 ]')
    .replace('[ 64.0, 264.0, -364.0 ]','[ 24.0, 24.0, -120.0 ]');
assert(data.includes('m_nMaxParticles = 128')&&data.includes('m_flLiteralValue = 64.0')&&!data.includes('m_ChildRef'));
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const output=path.join(root,'art/effects/skill_visuals/source/particles/survival/skills/wyvern_blizzard_snow.vpcf');
fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,header+data);
console.log('WYVERN_BLIZZARD_SNOW_SOURCE_PASS');
