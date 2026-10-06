'use strict';
// Import only the selected reference meshes and their resource dependency closure.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/valley_reference_v3');
const map=new L.Vpk(path.join(root,'output/watch_valley_reference/maps/dota_heroes_td_colosseum_new.vpk'));
const workshop=new L.Vpk('D:/SteamLibrary/steamapps/workshop/content/570/3164617180/3164617180.vpk');
const valve=new L.Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const groups=JSON.parse(fs.readFileSync(path.join(out,'instances.json')));
const selected=groups.filter(g=>/_(flower_set|flower_set_a_leaf|bush_spring_01|bush_spring_02|bush_nettle_a_01|flowers_ti10_01|lilyflowers_ti10_01|crypt_door_01|crypt_statue_01|stone_wall002|flowers_01)\.vmdl$/.test(g.model));
for(const g of selected)if(new Set(g.instances.map(i=>i.draw)).size!==1)throw Error('Not a single mesh: '+g.model);
function refs(b){
 const result=[],h=8+b.readUInt32LE(8);
 for(let i=0;i<b.readUInt32LE(12);i++){
  const q=h+i*12,s=q+4+b.readUInt32LE(q+4);
  if(b.toString('ascii',q,q+4)!=='RERL')continue;
  const e=s+b.readUInt32LE(s);
  for(let j=0;j<b.readUInt32LE(s+4);j++){const r=e+j*16+8,t=r+Number(b.readBigInt64LE(r));result.push(b.toString('utf8',t,b.indexOf(0,t)));}
 }
 return result;
}
const seen=new Set(),records=[];
function copy(resource){
 const key=resource.endsWith('_c')?resource:resource+'_c';if(seen.has(key))return;seen.add(key);
 const pack=map.entries.has(key)?map:workshop.entries.has(key)?workshop:null;
 if(!pack){if(valve.entries.has(key))return;throw Error('Missing dependency '+key);}
 const bytes=pack.read(key),dest=path.join(root,key);
 if(fs.existsSync(dest)&&!fs.readFileSync(dest).equals(bytes))throw Error('Existing resource differs: '+key);
 fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,bytes);
 records.push({resource:key,bytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
 for(const ref of refs(bytes))copy(ref);
}
selected.forEach(g=>copy(g.model));
for(const suffix of ['', '_block'])copy('materials/models/props_tree/cypress/tree_cypress001'+suffix+'.vmat');
fs.writeFileSync(path.join(out,'prop_import.json'),JSON.stringify({workshop:'3164617180',selected:selected.map(g=>g.model),records},null,2));
console.log({groups:selected.length,resources:records.length,bytes:records.reduce((n,r)=>n+r.bytes,0)});
