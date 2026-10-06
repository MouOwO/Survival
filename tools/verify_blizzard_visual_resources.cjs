'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..'),native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk')),
    core=new Vpk(path.resolve(root,'../../core/pak01_dir.vpk'));
const ground='particles/survival/skills/blizzard_ground.vpcf';
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
assert.equal([...texts.get(ground).matchAll(/m_ChildRef/g)].length,1);
assert(texts.get(ground).includes('m_nControlPoint = 2')&&texts.get(ground).includes('C_OP_SetFloat'));
assert(texts.get(snow).includes('m_nMaxParticles = 192'));
assert(texts.get(snow).includes('m_flLiteralValue = 96.0'));
assert(!texts.get(snow).includes('m_ChildRef'));
for(const resource of [ground,snow,'particles/survival/skills/blizzard_wind.vpcf'])assert(!texts.get(resource).includes('m_bDisableZBuffering = true'));
const report={date:'2026-10-02',status:'PASS',roots:[ground,snow],resources:[...records.values()],
    visuals:'Crystal Maiden frost projection and wind; CP2 radius. Isolated snowfall CP1 radius, 96/s, max 192. Five-second visual duration. No native ability states.',
    damage:'Original four damage waves and old fall clock retained pending user range/duration decision.',
    lifecycle:'Two world-owned roots per proc; five-second expiry/dead caster/session init clean up; no per-frame visual update.',
    in_game_visual_verified:false};
fs.writeFileSync(path.join(root,'docs/ai/validation/20261002/blizzard_visual.json'),JSON.stringify(report,null,2)+'\n');
console.log('WYVERN_BLIZZARD_RESOURCES_PASS dependencies='+records.size);
