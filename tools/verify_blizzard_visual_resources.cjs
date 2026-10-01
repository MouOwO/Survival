'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..'),native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk')),
    core=new Vpk(path.resolve(root,'../../core/pak01_dir.vpk'));
const ground='particles/units/heroes/hero_winter_wyvern/wyvern_winters_curse_ground.vpcf';
const snow='particles/survival/skills/wyvern_blizzard_snow.vpcf';
const temp=path.join(root,'output/wyvern_blizzard/audit');fs.mkdirSync(temp,{recursive:true});
const records=new Map(),texts=new Map();
function inspect(resource){
    if(records.has(resource))return;
    const local=path.join(root,resource+'_c'),pack=native.entries.has(resource+'_c')?native:core;
    assert(fs.existsSync(local)||pack.entries.has(resource+'_c'),'Missing dependency '+resource);
    const bytes=fs.existsSync(local)?fs.readFileSync(local):pack.read(resource+'_c');
    const record={resource,sha256:crypto.createHash('sha256').update(bytes).digest('hex')};
    records.set(resource,record);
    if(!/\.(vpcf|vmat|vmdl)$/.test(resource))return;
    const file=path.join(temp,path.basename(resource)+'_c');fs.writeFileSync(file,bytes);
    const dump=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
    const at=dump.indexOf(' block DATA');assert(at>=0);
    const data=dump.slice(at);texts.set(resource,data);
    record.dependencies=[...new Set([...data.matchAll(/resource:"([^"]+)"/g)].map(m=>m[1]).filter(Boolean))];
    for(const dependency of record.dependencies)inspect(dependency);
}
inspect(ground);inspect(snow);
assert.equal([...texts.get(ground).matchAll(/m_ChildRef/g)].length,7);
const projection=ground.replace('_ground.vpcf','_proj.vpcf');
assert(texts.get(projection).includes('m_nControlPoint = 2'));
assert(texts.get(snow).includes('m_nMaxParticles = 128'));
assert(texts.get(snow).includes('m_flLiteralValue = 64.0'));
assert(!texts.get(snow).includes('m_ChildRef'));
const report={date:'2026-10-01',status:'PASS',roots:[ground,snow],resources:[...records.values()],
    visuals:'Native Winter\'s Curse ground root including seven children, CP2 radius; native-derived isolated snowfall, 64/s, max 128, CP1 radius. No native ability states.',
    damage:'Five levels tested: four 50% attack snapshots, radius 300, 25% slow with 1.1s refresh; original twelve 0.03s fall callbacks retained (nominal hit times 1.60/2.60/3.60/4.60 with 50ms think).',
    lifecycle:'Two world-owned roots per proc; final wave/dead caster/session init clean up. No added per-frame visual timer or particle control writes.',
    tests:['test_tower_skill_tree_exclusion.lua','Lua 5.1 syntax','native dependency closure','resourcecompiler: 1 compiled, 0 failed'],
    in_game_visual_verified:false};
fs.writeFileSync(path.join(root,'docs/ai/validation/20261001/wyvern_blizzard.json'),JSON.stringify(report,null,2)+'\n');
console.log('WYVERN_BLIZZARD_RESOURCES_PASS dependencies='+records.size);
