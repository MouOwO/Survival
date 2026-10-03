'use strict';
// Preserve Crimson Progenitor's Bane art; adapt only its linear-Q movement
// to the existing tracking projectile CP0=source, CP1=target, CP2=speed.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk,endOf}=require('./lib.cjs');
const root=path.resolve(__dirname,'../..');
const native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const resource='particles/econ/items/mars/mars_ti9_immortal/mars_ti9_immortal_crimson_spear.vpcf';
const temp=path.join(root,'output/mars_ballista');fs.mkdirSync(temp,{recursive:true});
const file=path.join(temp,'native_spear.vpcf_c');fs.writeFileSync(file,native.read(resource+'_c'));
const dump=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
let data=dump.slice(dump.indexOf('--- vpcf block DATA'));data=data.slice(data.indexOf('{'));
for(const name of ['C_INIT_VelocityFromCP','C_INIT_PositionPlaceOnGround','C_OP_MovementPlaceOnGround']){
    const at=data.indexOf('_class = "'+name+'"');assert(at>=0,name);
    const start=data.lastIndexOf('{',at),end=endOf(data,start);
    data=data.slice(0,start)+data.slice(end).replace(/^\s*,/,'');
}
// Do not let the Luna-based tower's weapon slot override the explicit Mars model.
data=data.replace(/\s*m_EconSlotName = "weapon"/,'');
const movement=data.indexOf('_class = "C_OP_BasicMovement"');
const movementEnd=endOf(data,data.lastIndexOf('{',movement));
data=data.slice(0,movementEnd)+',\n { _class = "C_OP_MaxVelocity" m_nOverrideCP = 2 m_flMaxVelocity = 1250.0 }'+data.slice(movementEnd);
// Native tracking attacks use attraction and an engine-provided speed cap.
data=data.replace(/\}\s*$/,`m_ForceGenerators = [
 { _class = "C_OP_AttractToControlPoint"
   m_fForceAmount = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 1000000.0 }
   m_fFalloffPower = 0.0 m_nControlPointNumber = 1 }
 ]\n}\n`);
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const output=path.join(root,'art/effects/ballista/source/particles/survival/towers/mars_crimson_ballista.vpcf');
fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,header+data);
assert(data.includes('m_nSkin = 1')&&data.includes('mars_ti9_immortal_crimson_spear_end.vpcf'));
console.log('MARS_CRIMSON_BALLISTA_SOURCE_PASS '+output);
