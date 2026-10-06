'use strict';
// Diabolic Edict's ground layers, adapted from a short burst to a persistent base.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk,endOf}=require('./lib.cjs');
const root=path.resolve(__dirname,'../..'),pack=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const out=path.join(root,'art/effects/leshrac_base'),temp=path.join(root,'output/leshrac_base');
fs.mkdirSync(temp,{recursive:true});
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const names=['leshrac_diabolic_groundflash','leshrac_diabolic_groundflash_lines','leshrac_diabolic_groundflash_lines2'];
const prefix='particles/survival/towers/leshrac_base/';
const outputs=[];
for(let index=0;index<names.length;index++){
 const name=names[index],native='particles/units/heroes/hero_leshrac/'+name+'.vpcf';
 const file=path.join(temp,name+'.vpcf_c');fs.writeFileSync(file,pack.read(native+'_c'));
 let data=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
 data=data.slice(data.indexOf('--- vpcf block DATA'));data=data.slice(data.indexOf('{'));
 const at=data.indexOf('m_Emitters'),start=data.indexOf('[',at),end=endOf(data,start,'[',']');assert(at>=0);
 data=data.slice(0,start)+`[
 { _class = "C_OP_InstantaneousEmitter" m_nParticlesToEmit = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${index===0?2:3}.0 } },
 { _class = "C_OP_ContinuousEmitter" m_flEmitRate = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${index===2?8:4}.0 } }
 ]`+data.slice(end);
 // The shortest ring originally stayed at its spawn position. Lock it as well.
 if(!data.includes('C_OP_PositionLock')){
  const at=data.indexOf('m_Operators'),start=data.indexOf('[',at);
  data=data.slice(0,start+1)+'\n{ _class = "C_OP_PositionLock" m_nControlPointNumber = 1 },\n'+data.slice(start+1);
 }
 for(const child of names)data=data.replaceAll('particles/units/heroes/hero_leshrac/'+child+'.vpcf',prefix+child+'.vpcf');
 const resource=prefix+name+'.vpcf',dest=path.join(out,'source',resource);
 fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,header+data);outputs.push({resource,native});
}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({root:outputs[0].resource,outputs,emission_rates:[4,4,8],max_particles:8,control_point:1},null,2)+'\n');
console.log('LESHRAC_BASE_SOURCE_PASS: three ground layers, max eight live particles');
