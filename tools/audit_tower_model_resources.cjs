const fs=require('fs'),path=require('path'),{open}=require('./vpk_inspect.cjs');
const root=path.resolve(__dirname,'..'),engine=path.resolve(root,'../../..');
const out=path.join(root,'output/tower_model_audit_20260929');
const routes=JSON.parse(fs.readFileSync(path.join(out,'routes.json'),'utf8'));
const archives=[];
for(const game of ['dota','core']){
 const file=path.join(engine,'game',game,'pak01_dir.vpk');
 if(fs.existsSync(file)){const v=open(file);archives.push({v,entries:new Map(v.entries.map(e=>[e.path,e]))});}
}
const missing=[],checked=new Map(),errors=[];
function locate(name){
 const compiled=name.endsWith('_c')?name:name+'_c';
 for(const base of [root,path.join(engine,'game/dota'),path.join(engine,'game/core')]){
  const file=path.join(base,compiled);if(fs.existsSync(file))return {read:()=>fs.readFileSync(file),source:file};
 }
 for(const a of archives){const e=a.entries.get(compiled);if(e)return {read:()=>a.v.read(e),source:'VPK:'+compiled};}
 return null;
}
function refs(b){
 if(b.length<16)throw Error('Short compiled resource');
 const table=8+b.readUInt32LE(8),count=b.readUInt32LE(12),result=[];
 if(count>1000||table+count*12>b.length)throw Error('Invalid resource block table');
 for(let i=0;i<count;i++){
  const at=table+i*12;if(b.toString('ascii',at,at+4)!=='RERL')continue;
  const data=at+4+b.readUInt32LE(at+4),size=b.readUInt32LE(at+8);
  if(!size)continue;if(data+size>b.length)throw Error('RERL outside resource');
  const list=data+b.readUInt32LE(data),n=b.readUInt32LE(data+4);
  if(list+n*16>data+size)throw Error('Invalid RERL count');
  for(let j=0;j<n;j++){
   const pointer=list+j*16+8,start=pointer+Number(b.readBigInt64LE(pointer));
   const end=b.indexOf(0,start);if(start<data||end<start||end>data+size)throw Error('Invalid RERL path');
   const name=b.toString('utf8',start,end);if(name)result.push(name);
  }
 }
 return result;
}
function check(name,parent){
 if(checked.has(name))return;
 const file=locate(name);checked.set(name,{path:name,parent,source:file?.source||null});
 if(!file){missing.push({path:name,parent});return;}
 if(!/\.(vmdl|vmesh|vmat|vpcf|vagrp|vanim|vseq|vsnap|vphys|vdata)(?:_c)?$/.test(name))return;
 try{for(const child of refs(file.read()))check(child,name);}catch(e){errors.push({path:name,error:e.message});}
}
for(const row of routes)for(const resource of row.resources)check(resource.path,row.id);
const models=[...checked.keys()].filter(x=>/\.vmdl(?:_c)?$/.test(x));
const report={routeLevels:routes.length,uniqueModelResources:models.length,totalResources:checked.size,missing,errors,resources:[...checked.values()]};
fs.writeFileSync(path.join(out,'resource_audit.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({...report,resources:undefined}));
if(missing.length||errors.length)process.exitCode=1;
