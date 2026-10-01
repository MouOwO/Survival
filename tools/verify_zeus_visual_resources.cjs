'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..'),native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk')),
    core=new Vpk(path.resolve(root,'../../core/pak01_dir.vpk'));
const output=path.join(root,'art/effects/lightning/reference'),temp=path.join(root,'output/zeus_visuals/audit');
fs.mkdirSync(output,{recursive:true});fs.mkdirSync(temp,{recursive:true});
const csv=fs.readFileSync(path.join(root,'data/csv/建筑与工人系统/防御塔/tower_lightning_effects.csv'),'utf8');
const rows=csv.trim().split(/\r?\n/).slice(3).map(line=>line.split(','));
assert.equal(rows.length,3);
const roots=rows.flatMap(r=>r.slice(1,4).filter(Boolean));
const records=new Map(),texts=new Map();
function inspect(resource){
    if(records.has(resource))return;
    const pack=native.entries.has(resource+'_c')?native:core;
    assert(pack.entries.has(resource+'_c'),'Missing native dependency '+resource);
    const bytes=pack.read(resource+'_c');
    const record={resource,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),children:[]};
    records.set(resource,record);
    if(!resource.endsWith('.vpcf'))return;
    const file=path.join(temp,path.basename(resource)+'_c');fs.writeFileSync(file,bytes);
    const dump=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
    const at=dump.indexOf('--- vpcf block DATA');assert(at>=0);
    const data=dump.slice(at);texts.set(resource,data);
    record.children=[...data.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(m=>m[1]);
    record.dependencies=[...new Set([...data.matchAll(/resource:"([^"]+)"/g)].map(m=>m[1]).filter(Boolean))];
    for(const dependency of record.dependencies)inspect(dependency);
}
for(const resource of roots)inspect(resource);
const sr=rows.find(r=>r[0]==='SR'),ssr=rows.find(r=>r[0]==='SSR'),strike=rows.find(r=>r[0]==='strike');
assert(sr[1].endsWith('/zeus_ti8_immortal_arc.vpcf'));
assert.equal(ssr[1],'particles/units/heroes/hero_zuus/zuus_arc_lightning.vpcf');
assert.equal(ssr[2],'','Third stage must not add golden impact effects');
for(const resource of [sr[1],ssr[1]])assert(/m_nEndControlPointNumber = 1\b/.test(texts.get(resource)));
assert(strike[1].endsWith('/disruptor_2022_immortal_static_storm.vpcf'));
assert(strike[2]===''&&strike[3]==='', 'No Zeus bolt/cast attached to the area storm');
assert(texts.get(strike[1]).includes('C_OP_StopAfterCPDuration'));
assert(texts.get(strike[1]).includes('m_nControlPoint = 2')&&texts.get(strike[1]).includes('m_bEndCap = true'));
const edge=strike[1].replace('static_storm.vpcf','static_storm_cloudbase_aoe_edge.vpcf');
assert(records.has(edge),'Complete native R must include its radius edge');
assert(texts.get(edge).includes('m_nControlPoint = 1'),'Native area must read skill radius from CP1');
const items=native.read('scripts/items/items_game.txt').toString('utf8');
function item(id){
    const at=items.indexOf('\n\t\t"'+id+'"\r\n');assert(at>=0);
    const end=items.indexOf('\n\t\t"',at+1);return items.slice(at,end);
}
const itemRows=[{id:12323,name:'风暴之示',key:'Tempest_Revelation',resource:sr[1]},
    {id:23655,name:'风暴串联之震',key:'Tremors_of_the_Tandem_Storm',resource:strike[1]}];
for(const row of itemRows){const data=item(row.id);assert(data.includes(row.resource));fs.writeFileSync(path.join(output,row.key+'.txt'),data);}
for(const resource of [...roots,edge])fs.writeFileSync(path.join(output,path.basename(resource)+'.txt'),texts.get(resource));
const report={date:'2026-10-01',status:'PASS',source:'Local Valve Dota/core VPK; original native resources unmodified',
    items:itemRows,rarity_rule:'R unchanged; SR full Tempest Revelation Q; SSR default Zeus Arc Lightning including red stars, no extra golden hit effects',
    strike_rule:'Tremors of the Tandem Storm native Static Storm replaces falling bolts; CP1.x is gameplay radius, CP2.x duration. Hero same-target repeat strikes share one area; tower uses one area for its configured duration.',
    native_roots:roots,particle_systems:texts.size,resources:[...records.values()],in_game_visual_verified:false};
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(report,null,2)+'\n');
console.log('LIGHTNING_NATIVE_RESOURCES_PASS roots='+roots.length+' particle_systems='+texts.size+' dependencies='+records.size+' immortal_static_storm=verified');
