// Synchronize challenge names into CSV, runtime Lua, native units and localization.
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
function read(p){return fs.readFileSync(path.join(root,p),'utf8');}
function write(p,s){fs.writeFileSync(path.join(root,p),s);}
function cells(line){return (line.match(/(?:"(?:[^"]|"")*"|[^,]*)(?:,|$)/g)||[]).filter(Boolean).map(x=>x.replace(/,$/,'')).map(x=>x.startsWith('"')?x.slice(1,-1).replace(/""/g,'"'):x);}
function table(p){const lines=read(p).replace(/^\uFEFF/,'').split(/\r?\n/),headers=cells(lines[0]);return {p,lines,headers,rows:lines.map((line,i)=>({line,i,v:cells(line)})).filter(r=>r.line&&!r.line.startsWith('#')&&!r.line.startsWith('"#')&&r.i>0).map(r=>({...r,data:Object.fromEntries(headers.map((h,i)=>[h,r.v[i]||'']))}))};}
function save(t){write(t.p,t.lines.join('\n'));}
function set(t,r,key,value){const i=t.headers.indexOf(key);assert(i>=0);r.v[i]=value;r.data[key]=value;t.lines[r.i]=r.v.map(v=>/[",\n]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v).join(',');}
const challenge=table('data/csv/挑战与奖励系统/challenge_definitions.csv');
const rebirth=table('data/csv/挑战与奖励系统/rebirth_challenges.csv');
const encounters=table('data/csv/怪物与波次系统/monster_encounters.csv');
const archetypes=table('data/csv/怪物与波次系统/monster_archetypes.csv');
const members=table('data/csv/挑战与奖励系统/encounter_members.csv');
const buildings=table('data/csv/挑战与奖励系统/building_challenge_definitions.csv');
const names=new Map([...challenge.rows,...rebirth.rows].map(r=>[r.data.encounter_id,r.data.name]));
const units=new Map();
const spirits=[['practice_wood','木头精'],['practice_gold','金币精'],['practice_attribute','属性精'],['practice_greater_attribute','大属性精']];
const clones=[];
for(const [id,name] of spirits){
 const member=members.rows.find(r=>r.data.member_id===id);assert(member);
 const target=id+'_spirit';let row=archetypes.rows.find(r=>r.data.archetype_id===target);
 if(!row){
  const source=archetypes.rows.find(r=>r.data.archetype_id===member.data.archetype_id);assert(source);
  row={i:archetypes.lines.length,line:source.line,v:[...source.v],data:{...source.data}};
  archetypes.lines.push(source.line);archetypes.rows.push(row);
  clones.push([source.data.archetype_id,target]);
  set(archetypes,row,'archetype_id',target);
 }
 // Preserve the original combat template when the visual archetype becomes dedicated.
 if(!member.data.combat_archetype_id)set(members,member,'combat_archetype_id',member.data.archetype_id);
 set(members,member,'archetype_id',target);units.set(target,name);
}
for(const r of encounters.rows){
 const name=names.get(r.data.encounter_id);if(!name)continue;
 set(encounters,r,'display_name',name);
 if(r.data.archetype_id)units.set(r.data.archetype_id,name);
}
for(const r of members.rows){
 const a=archetypes.rows.find(a=>a.data.archetype_id===r.data.archetype_id);
 // Practice rooms share normal wave archetypes; only rename dedicated challenge creatures.
 if(a&&names.has(r.data.encounter_id)&&['boss','challenge'].includes(a.data.display_group))units.set(r.data.archetype_id,names.get(r.data.encounter_id));
}
for(const r of archetypes.rows)if(units.has(r.data.archetype_id)){
 set(archetypes,r,'display_name',units.get(r.data.archetype_id));
 set(archetypes,r,'unit_name','npc_survival_named_'+r.data.archetype_id);
}
for(const r of buildings.rows){
 units.set(r.data.challenge_id,r.data.display_name);
 set(buildings,r,'unit_name','npc_survival_named_'+r.data.challenge_id);
}
save(archetypes);save(encounters);save(buildings);save(members);
const archetypeLua='scripts/vscripts/config/generated/monster_archetypes.lua';
let archetypeSource=read(archetypeLua);
for(const [from,to] of clones){
 const line=archetypeSource.split('\n').find(line=>line.includes('archetype_id = "'+from+'"'));assert(line);
 archetypeSource=archetypeSource.replace(/\r?\n}\r?\nM.by_id/, '\n'+line.replace('archetype_id = "'+from+'"','archetype_id = "'+to+'"')+'\n}\nM.by_id');
}
write(archetypeLua,archetypeSource);
const memberLua='scripts/vscripts/config/generated/encounter_members.lua';
write(memberLua,read(memberLua).split('\n').map(line=>{
 const row=members.rows.find(r=>line.includes('member_id = "'+r.data.member_id+'"'));if(!row)return line;
 line=line.replace(/\barchetype_id = "[^"]*"/,'archetype_id = '+JSON.stringify(row.data.archetype_id));
 if(row.data.combat_archetype_id&&!line.includes('combat_archetype_id ='))line=line.replace(/ },/ ,', combat_archetype_id = '+JSON.stringify(row.data.combat_archetype_id)+' },');
 return line;
}).join('\n'));
// Preserve all generated combat conversions; project only the two naming columns.
for(const [t,key] of [[archetypes,'archetype_id'],[encounters,'encounter_id'],[buildings,'challenge_id']]){
 const p='scripts/vscripts/config/generated/'+path.basename(t.p,'.csv')+'.lua';
 const rows=new Map(t.rows.map(r=>[r.data[key],r.data]));
 const out=read(p).split('\n').map(line=>{
  const id=line.match(new RegExp('\\{ '+key+' = "([^"]+)"'));if(!id)return line;
  const row=rows.get(id[1]);assert(row);
  for(const field of t===encounters?['display_name']:['display_name','unit_name'])line=line.replace(new RegExp(field+' = "(?:[^"\\\\]|\\\\.)*"'),field+' = '+JSON.stringify(row[field]));
  return line;
 }).join('\n');write(p,out);
}
const kvPath='scripts/npc/npc_units_custom.txt';let kv=read(kvPath);
const template=kv.match(/"npc_survival_wave_monster"\s*(\{[^{}]*\})/);assert(template);
const begin='// BEGIN GENERATED CHALLENGE UNIT NAMES',end='// END GENERATED CHALLENGE UNIT NAMES';
kv=kv.replace(new RegExp('\\s*'+begin+'[\\s\\S]*?'+end),'');
const block=[begin,...[...units.keys()].map(id=>{
 // Start with the declared body, rather than loading Undying before SetModel.
 const archetype=archetypes.rows.find(r=>r.data.archetype_id===id);
 let body=template[1];
 if(archetype&&archetype.data.model_path)body=body.replace(/("Model"\s*)"[^"]*"/,'$1'+JSON.stringify(archetype.data.model_path));
 return '    "npc_survival_named_'+id+'"\n    '+body;
}),end].join('\n');
const close=kv.lastIndexOf('}');write(kvPath,kv.slice(0,close)+'\n'+block+'\n'+kv.slice(close));
for(const p of ['resource/addon_schinese.txt','resource/localization/addon_schinese.txt']){
 let s=read(p).replace(new RegExp('\\s*'+begin+'[\\s\\S]*?'+end),'');
 const tokens=[begin,...[...units].map(([id,name])=>'        "npc_survival_named_'+id+'" '+JSON.stringify(name)),end].join('\n');
 assert(/"Tokens"\s*\{/.test(s));s=s.replace(/("Tokens"\s*\{)/,'$1\n'+tokens+'\n');write(p,s);
}
console.log('Synced '+units.size+' dedicated challenge unit names from challenge CSVs.');
