const fs=require('fs'),path=require('path'),crypto=require('crypto'),cp=require('child_process'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..');
const native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk'));
const core=new Vpk(path.resolve(root,'../../core/pak01_dir.vpk'));
const csv=fs.readFileSync(path.join(root,'data/csv/建筑与工人系统/防御塔/tower_laser_effects.csv'),'utf8');
const rows=csv.split(/\r?\n/).filter(s=>s.startsWith('laser_lv')).map(s=>s.split(','));
const selected=[...new Set(rows.map(r=>r[3]))];
assert.equal(rows.length,20);assert.equal(selected.length,3);
const expected={
    default:'particles/units/heroes/hero_tinker/tinker_laser.vpcf',
    R:'particles/units/heroes/hero_tinker/tinker_laser.vpcf',
    SR:'particles/econ/items/tinker/tinker_ti10_immortal_laser/tinker_ti10_immortal_laser.vpcf',
    SSR:'particles/econ/items/tinker/tinker_ti10_immortal_laser/tinker_ti10_immortal_laser_aghs.vpcf'
};
const growth=JSON.parse(fs.readFileSync(path.join(root,'art/effects/tinker_growth/manifest.json'),'utf8'));
for(const [rarity,particle] of Object.entries(expected)){
    for(let level=1;level<=5;level++){
        const key='laser_lv0'+level+':'+rarity;
        const matches=rows.filter(r=>r[0]===key);
        assert.equal(matches.length,1,key);assert.equal(matches[0][3],growth.roots[rarity==='default'?'R':rarity],key);
        assert.equal(matches[0][20],'60');
        assert.equal(Number(matches[0][21]),rarity==='SSR'?2:rarity==='SR'?1.5:1);
        assert.equal(Number(matches[0][22]),0.1);
        assert.equal(Number(matches[0][16])>Number(matches[0][18]),rarity==='SSR');
    }
}
const output=path.join(root,'art/effects/laser/reference/tinker_native');
const temporary=path.join(root,'output/tinker_native');
fs.mkdirSync(output,{recursive:true});fs.mkdirSync(temporary,{recursive:true});
const records=[];
for(const resource of [...new Set(Object.values(expected))]){
    assert(resource.includes('tinker')&&!resource.includes('mecha_hornet'));
    const bytes=native.read(resource+'_c');
    const file=path.join(temporary,path.basename(resource)+'_c');
    fs.writeFileSync(file,bytes);
    const info=cp.spawnSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
    assert.equal(info.status,0);
    const at=info.stdout.indexOf('--- vpcf block DATA');assert(at>=0);
    const data=info.stdout.slice(at);
    assert(/m_nStartControlPointNumber\s*=\s*9\b/.test(data)&&/m_nEndControlPointNumber\s*=\s*1\b/.test(data));
    assert(data.includes('C_OP_Decay')&&/m_flLiteralValue = 0\.7\b/.test(data));
    const dependencies=[...data.matchAll(/resource:"([^"]+)"/g)].map(m=>m[1]).filter(Boolean);
    for(const dependency of dependencies) assert(native.entries.has(dependency+'_c')||core.entries.has(dependency+'_c'),'Missing native dependency '+dependency);
    fs.writeFileSync(path.join(output,path.basename(resource)+'.txt'),data);
    records.push({resource,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),dependencies});
}
const adapted=new Map(),texts=new Map();
function inspect(resource){
    if(adapted.has(resource))return;
    const file=path.join(root,resource+'_c');
    const pack=native.entries.has(resource+'_c')?native:core;
    assert(fs.existsSync(file)||pack.entries.has(resource+'_c'),'Missing '+resource);
    const bytes=fs.existsSync(file)?fs.readFileSync(file):pack.read(resource+'_c');
    const record={resource,sha256:crypto.createHash('sha256').update(bytes).digest('hex')};adapted.set(resource,record);
    if(!/\.(vpcf|vmat)$/.test(resource))return;
    const temp=path.join(temporary,path.basename(resource)+'_c');fs.writeFileSync(temp,bytes);
    const info=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',temp,'-all'],{encoding:'utf8',windowsHide:true});
    const data=info.slice(info.indexOf(' block DATA'));texts.set(resource,data);
    record.dependencies=[...new Set([...data.matchAll(/resource:"([^"]+)"/g)].map(m=>m[1]).filter(Boolean))];
    record.dependencies.forEach(inspect);
}
selected.forEach(inspect);
let scaled=0;
for(const [resource,data] of texts){
    if(!resource.includes('/tinker_growth/'))continue;
    assert(!data.includes('C_INIT_RemapCPtoScalar'),'Obsolete initializer is not supported by this runtime');
    if(data.includes('m_nControlPoint = 60')){
        scaled++;
        assert(data.includes('PARTICLE_SET_SCALE_CURRENT_VALUE'));
        // Radius (3) is C_INIT_InitFloat's default; the compiler omits it.
        const at=data.indexOf('m_nControlPoint = 60');
        const start=data.lastIndexOf('_class = "C_INIT_InitFloat"',at);
        assert(start>=0&&data.slice(start,at+450).includes('PARTICLE_SET_SCALE_CURRENT_VALUE'));
    }
    if(resource.includes('/sr_')&&resource.endsWith('.vpcf')){
        for(const m of data.matchAll(/m_(?:ConstantColor|ColorMin|ColorMax|ColorFade|LiteralColor) = \[([^\]]+)\]/g)){
            const c=m[1].split(',').map(Number);assert(c[0]<=c[2],'SR red tint remains in '+resource);
        }
        assert(!data.includes('tinker_ti10_immortal_laser_cable.vmat')&&!data.includes('/beam_glow.vmat'),'SR must use blue materials');
    }
}
assert.equal(scaled,9,'All nine beam/core/burn layers scale with CP60');
for(const tier of ['R','SR','SSR']){
    const data=texts.get(growth.roots[tier]);
    assert(data.includes('m_nStartControlPointNumber = 9')&&data.includes('m_nEndControlPointNumber = 1'));
    assert(/m_flLiteralValue = 0\.7\b/.test(data)&&data.includes('C_OP_Decay'));
}
for(const resource of ['materials/survival/tinker_growth/sr_cable.vmat','materials/survival/tinker_growth/sr_pulse.vmat']){
    const data=texts.get(resource);assert(data);
    const color=data.match(/m_name = "g_vColorTint"\s*m_value = \[([^\]]+)\]/);assert(color);
    const c=color[1].split(',').map(Number);assert(c[2]>c[0]);
}
const report={source:'Local Valve native resources adapted for presentation',status:'PASS',selections:rows.map(r=>({skill:r[1],rarity:r[0].split(':')[1],particle:r[3]})),
    implementation:'Preserved native children, emission, CP9/1 and segment lifetime. CP60 multiplies initialized beam radii. Blue SR particle tints plus cable/pulse materials; native SSR red.',
    selection_rule:'R 1.0-1.4; SR 1.5-1.9; SSR 2.0-2.4; SSR red stars 2.5-2.9. Native Aghanim shrink compensated. No combat changes.',records,adapted_resources:[...adapted.values()],in_game_visual_verified:false};
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(report,null,2)+'\n');
fs.writeFileSync(path.join(root,'docs/ai/validation/20261001/tinker_level_width.json'),JSON.stringify(report,null,2)+'\n');
console.log('NATIVE_TINKER_GROWTH_PASS: 20 rows, 9 scaled layers, blue SR materials, native red SSR, dependencies='+adapted.size);
