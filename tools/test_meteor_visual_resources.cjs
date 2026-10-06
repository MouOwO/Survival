'use strict';
// This checker reads current compiled resources; it never runs the compiler,
// Lua simulations or a map, and cannot grant rendered-pixel acceptance.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert');
const {execFileSync}=require('child_process'),L=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..'),output=path.join(root,'output/meteor_phoenix_20261002');
const dump=path.join(output,'compiled_dump');
const main='particles/survival/skills/meteor_phoenix_impact.vpcf';
const nativeRoot='particles/units/heroes/hero_phoenix/phoenix_supernova_reborn.vpcf';
const report={status:'FAIL',checked_at:new Date().toISOString(),scope:'Current source/content, compiled DATA and installed native dependencies',
    compiled_by_this_check:false,simulation_executed:false,in_game_visual_verified:false,checks:[]};
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function data(text){const at=text.indexOf('--- vpcf block DATA');assert(at>=0);return text.slice(at);}
function refs(bytes){
    const result=[],header=8+bytes.readUInt32LE(8);
    for(let i=0;i<bytes.readUInt32LE(12);i++){
        const block=header+i*12,start=block+4+bytes.readUInt32LE(block+4);
        if(bytes.toString('ascii',block,block+4)!=='RERL')continue;
        const entries=start+bytes.readUInt32LE(start);
        for(let j=0;j<bytes.readUInt32LE(start+4);j++){
            const pointer=entries+j*16+8,target=pointer+Number(bytes.readBigInt64LE(pointer));
            result.push(bytes.toString('utf8',target,bytes.indexOf(0,target)));
        }
    }
    return result;
}
const children=text=>[...text.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(m=>m[1]);
const sorted=values=>[...values].sort();
const nativeClass=name=>name==='C_INIT_CreateWithinSphere'?'C_INIT_CreateWithinSphereTransform':name;
function blocks(text){
    return [...text.matchAll(/_class = "([^"]+)"/g)].map(m=>{
        const open=text.lastIndexOf('{',m.index);return {name:m[1],text:text.slice(open,L.endOf(text,open))};
    });
}
function number(text,key,fallback){
    const value=text.match(new RegExp('\\b'+key+' = ([\\d.e+-]+)'));
    return value?Number(value[1]):fallback;
}
function arrayBody(text,key){
    const match=text.match(new RegExp('\\b'+key+'\\s*=\\s*\\['));
    if(!match)return '[]';
    const open=text.indexOf('[',match.index);return text.slice(open,L.endOf(text,open,'[',']')).replace(/\s+/g,'');
}
try{
    fs.mkdirSync(dump,{recursive:true});
    const manifest=JSON.parse(fs.readFileSync(path.join(root,'art/effects/skill_visuals/manifest.json'),'utf8'));
    const impact=manifest.impact;
    assert.equal(impact.root_particle,main);assert.equal(impact.native_root,nativeRoot);assert.equal(impact.fixed_radius,500);
    assert.equal(impact.maximum_native_tail_seconds,7);assert.equal(impact.fallback_cleanup_seconds,8);
    assert.equal(impact.layers.length,17);assert(manifest.outputs.includes(main));
    assert(!manifest.outputs.some(r=>/\/meteor_impact(?:_sparks)?\.vpcf$/.test(r)));
    const packs={dota:new L.Vpk(path.join(root,'../../dota/pak01_dir.vpk')),core:new L.Vpk(path.join(root,'../../core/pak01_dir.vpk'))};
    const natives=new Map(),locals=new Map();
    function native(resource){
        if(natives.has(resource))return natives.get(resource);
        const origin=Object.keys(packs).find(p=>packs[p].entries.has(resource+'_c'));assert(origin,'Missing Valve dependency '+resource);
        const bytes=packs[origin].read(resource+'_c'),record={resource,origin,bytes:bytes.length,sha256:hash(bytes),dependencies:refs(bytes)};
        natives.set(resource,record);
        if(resource.endsWith('.vpcf')){
            const file=path.join(dump,'native',resource+'_c');fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);
            record.data=data(execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true,maxBuffer:8*1024*1024}));
            fs.writeFileSync(file+'.txt',record.data);
        }
        for(const dependency of record.dependencies)native(dependency);
        return record;
    }
    for(const resource of manifest.native_resources)native(resource);
    for(const resource of manifest.outputs){
        const source=fs.readFileSync(path.join(root,'art/effects/skill_visuals/source',resource));
        const content=fs.readFileSync(path.resolve(root,'../../../content/dota_addons/survival',resource));
        const file=path.join(root,resource+'_c'),bytes=fs.readFileSync(file);assert(source.equals(content),'Source/content mismatch '+resource);
        const text=source.toString('utf8'),compiled=data(execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true,maxBuffer:8*1024*1024}));
        const dumpFile=path.join(dump,'local',resource+'_c.txt');fs.mkdirSync(path.dirname(dumpFile),{recursive:true});fs.writeFileSync(dumpFile,compiled);
        assert(!/\/meteor_impact(?:_sparks)?\.vpcf/.test(text+compiled),'Retired custom explosion reference '+resource);
        if(/_class\s*=\s*"C_INIT_CreateWithinSphere"/.test(text))assert(compiled.includes('C_INIT_CreateWithinSphereTransform'));
        const dependencies=refs(bytes);
        for(const dependency of dependencies){
            assert(manifest.outputs.includes(dependency)||Object.values(packs).some(p=>p.entries.has(dependency+'_c')),'Missing compiled dependency '+dependency);
            if(!manifest.outputs.includes(dependency))native(dependency);
        }
        if(resource.includes('phoenix_fall')){
            assert(compiled.includes('models/heroes/phoenix/phoenix_egg.vmdl'));assert(/m_flTravelTime = 0\.4\b/.test(compiled));
            assert.equal(children(compiled).length,2);
            for(const suffix of ['glow','lava'])assert(compiled.includes('phoenix_supernova_egg_'+suffix+'.vpcf'));
            assert(!compiled.includes('hero_invoker')&&!compiled.includes('rubick_arcana_cube'));
            assert(compiled.includes('C_OP_SetControlPointsToParticle')&&compiled.includes('m_nFirstControlPoint = 3'));
        }
        if(/meteor_lava(?:_cracks)?\.vpcf$/.test(resource)){
            const height=resource.includes('_cracks')?40:32;
            assert(compiled.includes('C_OP_SetToCP')&&!compiled.includes('C_INIT_PositionOffset'));
            assert(new RegExp('m_vecOffset = \\[ 0\\.0, 0\\.0, '+height+'\\.0 \\]').test(compiled));
            assert(compiled.includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'));
        }
        locals.set(resource,{resource,bytes:bytes.length,source_sha256:hash(source),content_sha256:hash(content),compiled_sha256:hash(bytes),dependencies,data:compiled});
    }
    const mapping=new Map(impact.layers.map(layer=>[layer.native_source,layer.resource]));
    assert.equal(mapping.size,17);assert.equal(mapping.get(nativeRoot),main);
    const closure=new Set();
    function visit(resource){if(closure.has(resource))return;closure.add(resource);for(const child of children(native(resource).data))visit(child);}
    visit(nativeRoot);assert.deepEqual(sorted(mapping.keys()),sorted(closure),'Must retain the complete installed native 17-layer graph');
    let removed=0,constrained=0;
    const ranges=[];
    for(const layer of impact.layers){
        const record=locals.get(layer.resource),original=native(layer.native_source);assert(record,'Missing derived layer '+layer.resource);
        assert.equal(record.source_sha256,layer.source_sha256);assert.equal(original.sha256,layer.native_bytes_sha256);
        assert.deepEqual(sorted(children(record.data)),sorted(children(original.data).map(child=>mapping.get(child))),'Native child graph '+layer.resource);
        const nativeBlocks=blocks(original.data),localBlocks=blocks(record.data);
        assert.equal(arrayBody(record.data,'m_Emitters'),arrayBody(original.data,'m_Emitters'),
            'Native emission values remain unchanged '+layer.resource);
        assert.equal(number(record.data,'m_flConstantLifespan',1),number(original.data,'m_flConstantLifespan',1));
        const lifespans=list=>list.filter(b=>b.name==='C_INIT_InitFloat'&&number(b.text,'m_nOutputField',3)===1)
            .map(b=>b.text.replace(/\s+/g,''));
        assert.deepEqual(lifespans(localBlocks),lifespans(nativeBlocks),'Native lifetime values '+layer.resource);
        const colors=list=>list.filter(b=>/Color|HSV/.test(b.name)).map(b=>b.text.replace(/\s+/g,''));
        assert.deepEqual(colors(localBlocks),colors(nativeBlocks),'Native color and HSV parameters '+layer.resource);
        const expected=nativeBlocks.filter(b=>{
            const writer=b.name==='C_OP_SetSingleControlPointPosition'&&/m_nCP1 = 3\b/.test(b.text);
            if(writer)removed++;return !writer;
        }).map(b=>nativeClass(b.name));
        const range=layer.range_contract;
        if(range){
            expected.push('C_OP_ConstrainDistance');constrained++;
            const constraints=localBlocks.filter(b=>b.name==='C_OP_ConstrainDistance');
            assert.equal(constraints.length,1,'One installed native distance constraint '+layer.resource);
            const constraint=constraints[0].text;
            assert.equal(number(constraint,'m_fMaxDistance'),range.center_max_distance,'Actual compiler must retain maximum distance');
            assert.equal(number(constraint,'m_fMinDistance',0),0);
            assert.equal(number(constraint,'m_nControlPointNumber',0),0);
            assert(!/m_bGlobalCenter = true/.test(constraint),'Constraint must follow its fixed world CP0');
            assert(!/m_CenterOffset = \[ (?!0\.0, 0\.0, 0\.0 \])/.test(constraint),'Constraint must have no offset');
            assert.equal(range.fixed_radius,500);assert.equal(range.constraint_cp,0);
            const budget=range.center_max_distance*range.curve_envelope+range.renderer_extent_budget;
            assert(Math.abs(budget-range.allocated_world_extent)<1e-7&&budget<=500,'Numeric renderer/center budget '+layer.resource);
            if(range.radius_override!==null){
                const init=localBlocks.find(b=>b.name==='C_INIT_InitFloat'&&number(b.text,'m_nOutputField',3)===3
                    &&Math.abs(number(b.text,'m_flLiteralValue',NaN)-range.radius_override)<1e-7);
                assert(init,'Compiled radius override '+layer.resource);
            }
            if(range.ring_radius_override!==null){
                assert(localBlocks.some(b=>b.name==='C_INIT_RingWave'&&new RegExp('m_flInitialRadius\\s*=\\s*\\{[^}]*m_flLiteralValue = '+range.ring_radius_override+'\\.0','s').test(b.text)),
                    'Compiled ring radius override '+layer.resource);
            }
            ranges.push({resource:layer.resource,actual_center_max_distance:number(constraint,'m_fMaxDistance'),allocated_world_extent:budget});
        }
        assert.deepEqual(sorted(localBlocks.map(b=>nativeClass(b.name))),sorted(expected),
            'Native classes after the documented sphere compiler migration, plus scoped constraint '+layer.resource);
        assert(!localBlocks.some(b=>b.name==='C_OP_SetSingleControlPointPosition'&&/m_nCP1 = 3\b/.test(b.text)));
        assert.deepEqual(sorted(record.dependencies.filter(r=>!r.endsWith('.vpcf'))),sorted(original.dependencies.filter(r=>!r.endsWith('.vpcf'))),'Preserve native materials/textures/models '+layer.resource);
    }
    assert.equal(removed,2);assert.equal(constrained,16);
    report.checks=['Current source/content hashes and compiled DATA for every output','Complete native 17-layer child graph and drawing/emission/operator classes',
        '16 compiled CP0 distance constraints and numeric 500-unit renderer budgets','Both absolute CP3 writers removed; native textures/materials/models retained',
        'Retired custom explosion/sparks absent; unchanged 0.4s fall and lava ground operators'];
    report.fixed_radius=500;report.cp_contract=impact.cp_contract;report.native_tail_seconds=7;report.cleanup_bound_seconds=8;
    report.range_serialization=ranges;
    report.records=[...locals.values()].map(({data,...record})=>record);
    report.native_dependencies=[...natives.values()].map(({data,...record})=>record);
    report.compiled_outputs_checked=report.records.length;report.native_resources_checked=report.native_dependencies.length;
    report.limitations=impact.validation.scope;report.status='PASS';
}catch(error){report.error=error.stack;process.exitCode=1;}
fs.mkdirSync(output,{recursive:true});fs.writeFileSync(path.join(output,'compiled_resources.json'),JSON.stringify(report,null,2)+'\n');
if(report.status==='PASS')console.log('METEOR_VISUAL_RESOURCES_PASS compiled='+report.compiled_outputs_checked+' native_graph=17 constraints=16 native_dependencies='+report.native_resources_checked+' radius=500; simulation/live not executed');
else console.error(report.error);
