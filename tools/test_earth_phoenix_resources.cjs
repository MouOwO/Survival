'use strict';
// Compare every generated Earth layer with the existing Phoenix source adapter,
// then optionally inspect the engine's real compiled DATA and resource closure.
const fs=require('fs'),path=require('path'),assert=require('assert'),cp=require('child_process');
const {endOf}=require('./map_c6/lib.cjs');
const repo=path.resolve(__dirname,'..');
const manifest=require('../art/effects/earth_phoenix_impact/manifest.json');
require('./map_c6/build-earth-phoenix-impact.cjs').check(manifest);
function parse(text) {
    const tokens=text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g);let i=0;
    function value() {
        const token=tokens[i++];
        if(token==='{'){const result={};while(tokens[i]!=='}'){const key=tokens[i++];assert.equal(tokens[i++],'=');result[key]=value();if(tokens[i]===',')i++;}i++;return result;}
        if(token==='['){const result=[];while(tokens[i]!==']'){result.push(value());if(tokens[i]===',')i++;}i++;return result;}
        if(token.startsWith('resource:'))return {resource:JSON.parse(token.slice(9))};
        if(token.startsWith('"'))return JSON.parse(token);
        if(token==='true'||token==='false')return token==='true';
        if(token==='null')return null;
        assert(Number.isFinite(Number(token)),'Unexpected KV3 token '+token);return Number(token);
    }
    const result=value();assert.equal(i,tokens.length);return result;
}
function source(relative){const text=fs.readFileSync(path.join(repo,relative),'utf8');return parse(text.slice(text.indexOf('\n')+1));}
function compareScaled(before,after,factor,label) {
    if(JSON.stringify(before)===JSON.stringify(after))return;
    if(typeof before==='number'&&typeof after==='number'){
        assert(Math.abs(after-before*factor)<1e-7*Math.max(1,Math.abs(after)),'Unexpected spatial change '+label);return;
    }
    if(Array.isArray(before)&&Array.isArray(after)){
        assert.equal(before.length,after.length,label);before.forEach((value,index)=>compareScaled(value,after[index],factor,label+'['+index+']'));return;
    }
    assert(before&&after&&typeof before==='object'&&typeof after==='object','Unexpected native structure change '+label);
    assert.deepEqual(Object.keys(before).sort(),Object.keys(after).sort(),label);
    for(const key of Object.keys(before))compareScaled(before[key],after[key],factor,label+'.'+key);
}
const children=tree=>(tree.m_Children||[]).map(child=>child.m_ChildRef.resource);
const lifetimes=tree=>(tree.m_Initializers||[]).filter(item=>item._class==='C_INIT_InitFloat'&&item.m_nOutputField===1);
const fades=tree=>(tree.m_Operators||[]).filter(item=>/Decay|Kill|Fade/.test(item._class));
const ground=['scorch_b','ground_flare','scorch','shockwave','shake'];
const core=['embers','glow','light','sparks','sphere','sphere_model','flek','star_sphere'];
const sourceTrees=new Map();
for(const layer of manifest.layers) {
    const isCore=layer.resource===manifest.airborne_core.root_particle;
    const match=layer.resource.match(/earth_phoenix_impact_(75|125|300)(?:_(.+))?\.vpcf$/);
    const radius=isCore?300:Number(match[1]),suffix=isCore?'':match[2]||'';
    const prefix='particles/survival/skills/earth_phoenix_impact_'+radius;
    let baseline=source('art/effects/skill_visuals/source/particles/survival/skills/meteor_phoenix_impact'+(suffix?'_'+suffix:'')+'.vpcf');
    const nativeSpatialBaseline=structuredClone(baseline);
    baseline=JSON.parse(JSON.stringify(baseline).replaceAll('particles/survival/skills/meteor_phoenix_impact',prefix));
    if(!suffix)baseline.m_Children=(isCore?core:ground).map(name=>({m_ChildRef:{resource:prefix+'_'+name+'.vpcf'}}));
    if(radius===300&&suffix==='sphere_model'){
        const offsets=baseline.m_Initializers.filter(item=>item._class==='C_INIT_PositionOffset');assert.equal(offsets.length,1);
        offsets[0].m_OffsetMin=[0,0,0];offsets[0].m_OffsetMax=[0,0,0];
    }
    const actual=source(layer.source);sourceTrees.set(layer.resource,actual);
    compareScaled(baseline,actual,radius/500,layer.resource);
    assert.deepEqual(actual.m_Emitters||[],nativeSpatialBaseline.m_Emitters||[],'Unchanged native emission');
    assert.deepEqual(lifetimes(actual),lifetimes(nativeSpatialBaseline),'Unchanged native lifetime');
    assert.deepEqual(fades(actual),fades(nativeSpatialBaseline),'Unchanged native fades');
    assert.deepEqual(actual.m_Renderers||[],nativeSpatialBaseline.m_Renderers||[],'Unchanged native rendering/materials');
}
assert(manifest.airborne_core.model_axis_radius>95,'Explosion model must cover the original rolling meteor');
assert.equal(manifest.airborne_core.height,90,'The airborne root matches the rolling meteor center');
const args=process.argv.slice(2);assert(args.length===0||(args.length===1&&args[0]==='--compiled'));
if(args.includes('--compiled')) {
    const resourceinfo=path.resolve(repo,'../../bin/win64/resourceinfo.exe');
    for(const layer of manifest.layers) {
        const raw=cp.execFileSync(resourceinfo,['-i',path.join(repo,layer.resource+'_c'),'-all'],{encoding:'utf8',windowsHide:true,maxBuffer:8*1024*1024});
        const at=raw.indexOf('--- vpcf block DATA'),open=raw.indexOf('{',at);assert(at>=0);
        const actual=parse(raw.slice(open,endOf(raw,open))),expected=sourceTrees.get(layer.resource);
        assert.deepEqual(children(actual),children(expected),'Compiled child closure '+layer.resource);
        assert.deepEqual(actual.m_Emitters||[],expected.m_Emitters||[],'Compiled emission '+layer.resource);
        assert.deepEqual(lifetimes(actual),lifetimes(expected),'Compiled life '+layer.resource);
        assert.deepEqual(fades(actual),fades(expected),'Compiled fades '+layer.resource);
        const spatial=layer.range_contract;
        if(spatial){assert.equal(actual.m_Constraints.length,1);assert.equal(actual.m_Constraints[0]._class,'C_OP_ConstrainDistance');assert.equal(actual.m_Constraints[0].m_fMaxDistance,spatial.center_max_distance);}
        if(layer.resource.endsWith('_300_sphere_model.vpcf')){
            const offset=actual.m_Initializers.find(item=>item._class==='C_INIT_PositionOffset');
            // Resourcecompiler may omit the now-zero no-op initializer entirely.
            if(offset){assert.deepEqual(offset.m_OffsetMin||[0,0,0],[0,0,0]);assert.deepEqual(offset.m_OffsetMax||[0,0,0],[0,0,0]);}
        }
    }
}
console.log('EARTH_PHOENIX_RESOURCES_PASS layers=52 ground_radii=75,125,300 core_height=90 core_radius='+manifest.airborne_core.model_axis_radius.toFixed(1)+' native_emission_life_fade=preserved compiled='+args.includes('--compiled'));
