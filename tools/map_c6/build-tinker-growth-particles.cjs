'use strict';
// Native Tinker layouts/timing; add a radius multiplier and recolor SR's red layers.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk,endOf}=require('./lib.cjs');
const root=path.resolve(__dirname,'../..'),vpk=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const out=path.join(root,'art/effects/tinker_growth'),temp=path.join(root,'output/tinker_growth');
fs.mkdirSync(temp,{recursive:true});
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const base='particles/units/heroes/hero_tinker/';
const immortal='particles/econ/items/tinker/tinker_ti10_immortal_laser/';
const roots={R:base+'tinker_laser.vpcf',SR:immortal+'tinker_ti10_immortal_laser.vpcf',SSR:immortal+'tinker_ti10_immortal_laser_aghs.vpcf'};
const beams=new Set(['tinker_laser','tinker_laser_e','tinker_laser_b','tinker_ti10_immortal_laser',
 'tinker_ti10_immortal_laser_core','tinker_ti10_immortal_laser_burn','tinker_ti10_immortal_laser_aghs',
 'tinker_ti10_immortal_laser_aghs_core','tinker_ti10_immortal_laser_aghs_burn']);
const outputs=[],cache=new Map();
function write(resource,data){const f=path.join(out,'source',resource);fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,data);outputs.push({resource});}
function dump(resource){if(cache.has(resource))return cache.get(resource);const f=path.join(temp,path.basename(resource)+'_c');fs.writeFileSync(f,vpk.read(resource+'_c'));let s=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',f,'-all'],{encoding:'utf8',windowsHide:true});s=s.slice(s.indexOf(' block DATA'));s=s.slice(s.indexOf('{'));cache.set(resource,s);return s;}
const materials={};
for(const [name,shader,bright,tint,texture] of [
 ['cable','cables.vfx',12,'0.247059 0.60 1.0 0','materials/particle/beam_noise_01_psd_a34b319d.vtex'],
 ['pulse','global_lit_simple.vfx',10,'0.364706 0.65 1.0 0','materials/particle/beam_hot_slim_psd_58ebf0e9.vtex']]){
 const r='materials/survival/tinker_growth/sr_'+name+'.vmat';materials[name]=r;
 const textureInput=path.join(temp,path.basename(texture)+'_c');fs.writeFileSync(textureInput,vpk.read(texture+'_c'));
 const image='materials/survival/tinker_growth/'+name+'.png',imageOutput=path.join(out,'source',image);
 fs.mkdirSync(path.dirname(imageOutput),{recursive:true});
 cp.execFileSync(path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'),['-i',textureInput,'-o',imageOutput,'-d'],{windowsHide:true});
 const decoded=path.join(path.dirname(imageOutput),path.basename(texture,'.vtex')+'.png');
 if(decoded!==imageOutput&&fs.existsSync(decoded)){fs.renameSync(decoded,imageOutput);}
 assert(fs.existsSync(imageOutput));outputs.push({resource:image,compile:false});
 write(r,`"Layer0"\n{\n"shader" "${shader}"\n"F_RENDER_BACKFACES" "1"\n"F_ADDITIVE_BLEND" "1"\n"F_TRANSLUCENT" "1"\n"g_flOpacityScale" "1"\n"g_flOverbrightFactor" "${bright}"\n"g_vColorTint" "[${tint}]"\n"g_vTexCoordScale" "[${name==='pulse'?'1.5':'1'} 1 0 0]"\n"TextureColor" "${image}"\n}\n`);
}
const created=new Map();
function adapt(resource,tier){
 const name=path.basename(resource,'.vpcf'),key=tier+':'+resource;
 if(tier!=='SR'&&!beams.has(name))return resource;
 if(created.has(key))return created.get(key);
 const dest='particles/survival/tinker_growth/'+tier.toLowerCase()+'_'+name+'.vpcf';created.set(key,dest);
 let data=dump(resource);
 if(beams.has(name)){
  // CP60.x scales the existing initialized radius, preserving each native curve.
  // Aghanim's native Q is smaller; normalize it to the SR beam before growth.
  const calibration=name.endsWith('_aghs')?3:name.endsWith('_aghs_core')?2.25:name.endsWith('_aghs_burn')?4/3:1;
  const at=data.indexOf('m_Initializers'),a=data.indexOf('[',at),end=endOf(data,a,'[',']');assert(at>=0);
  const scale=`{ _class = "C_INIT_InitFloat" m_nOutputField = 3 m_nSetMethod = "PARTICLE_SET_SCALE_CURRENT_VALUE" m_InputValue = { m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 60 m_nVectorComponent = 0 m_nMapType = "PF_MAP_TYPE_MULT" m_flMultFactor = ${calibration} } },\n`;
  data=data.slice(0,end-1)+scale+data.slice(end-1);
 }
 if(tier==='SR'){
  // All red/pink particle tints, including impact/embers, become cool blue.
  data=data.replace(/(m_(?:ConstantColor|ColorMin|ColorMax|ColorFade|LiteralColor) = )\[([^\]]+)\]/g,(all,key,values)=>{
   const c=values.split(',').map(Number);if(c[0]>c[2]){const r=c[0];c[0]=c[2];c[2]=r;c[1]=Math.max(c[1],Math.round(r*.45));}return key+'[ '+c.join(', ')+' ]';
  }).replaceAll('materials/models/items/tinker/tinker_ti10_immortal_laser/tinker_ti10_immortal_laser_cable.vmat',materials.cable)
    .replaceAll('materials/models/items/tinker/tinker_ti10_immortal_laser/beam_glow.vmat',materials.pulse);
 }
 data=data.replace(/m_ChildRef = resource:"([^"]+)"/g,(_,child)=>'m_ChildRef = resource:"'+adapt(child,tier)+'"');
 write(dest,header+data);return dest;
}
const selected=Object.fromEntries(Object.entries(roots).map(([tier,r])=>[tier,adapt(r,tier)]));
fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({roots:selected,native_roots:roots,width_control:60,outputs},null,2)+'\n');
console.log('TINKER_GROWTH_SOURCE_PASS files='+outputs.length);
