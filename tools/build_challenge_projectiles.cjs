'use strict';
// Enlarge the native Lina projectile visually; keep flight/CP/lifetime intact.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const {Vpk,endOf}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..'),engine=path.resolve(root,'../../..');
const game=path.join(engine,'game/dota'),content=path.join(engine,'content/dota_addons/Survival');
const prefix='particles/units/heroes/hero_lina/lina_base_attack';
const target='particles/survival/challenge/fire_troll_attack',factor=1.6;
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const hash=raw=>crypto.createHash('sha256').update(raw).digest('hex');
const numeric=n=>({__number:n,raw:Number.isInteger(n)?n.toFixed(1):String(n)});
function parse(text){
 const tokens=text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g);let i=0;
 function value(){const t=tokens[i++];
  if(t==='{'){const o={};while(tokens[i]!=='}'){const k=tokens[i++];assert.equal(tokens[i++],'=');o[k]=value();if(tokens[i]===',')i++;}i++;return o;}
  if(t==='['){const a=[];while(tokens[i]!==']'){a.push(value());if(tokens[i]===',')i++;}i++;return a;}
  if(t.startsWith('resource:'))return {__resource:JSON.parse(t.slice(9))};
  if(t.startsWith('"'))return JSON.parse(t);
  if(t==='true'||t==='false')return t==='true';if(t==='null')return null;
  assert(Number.isFinite(Number(t)),'Unexpected KV3 token '+t);return {__number:Number(t),raw:t};
 }const result=value();assert.equal(i,tokens.length);return result;
}
function kv(v,depth=0){
 if(v===null)return 'null';if(Array.isArray(v))return '[ '+v.map(x=>kv(x,depth)).join(', ')+' ]';
 if(v&&typeof v==='object'&&'__number'in v)return v.raw;
 if(v&&typeof v==='object'&&'__resource'in v)return 'resource:'+JSON.stringify(v.__resource);
 if(typeof v==='object')return '{\n'+Object.entries(v).map(([k,x])=>'\t'.repeat(depth+1)+k+' = '+kv(x,depth+1)).join('\n')+'\n'+'\t'.repeat(depth)+'}';
 return JSON.stringify(v);
}
function resources(tree,result=[]){
 if(tree&&typeof tree==='object'){
  if(tree.__resource?.startsWith(prefix)&&tree.__resource.endsWith('.vpcf'))result.push(tree.__resource);
  else for(const child of Object.values(tree))resources(child,result);
 }return result;
}
function remap(tree){
 if(tree&&typeof tree==='object'){
  if(tree.__resource?.startsWith(prefix)&&tree.__resource.endsWith('.vpcf'))tree.__resource=tree.__resource.replace(prefix,target);
  else for(const child of Object.values(tree))remap(child);
 }
}
const vpk=new Vpk(path.join(game,'pak01_dir.vpk')),nodes=new Map();
function load(resource){
 if(nodes.has(resource))return;
 const native=vpk.read(resource+'_c');
 const raw=cp.execFileSync(path.join(engine,'game/bin/win64/resourceinfo.exe'),['-game',game,'-i',resource+'_c','-all'],{encoding:'utf8',maxBuffer:16*1024*1024,windowsHide:true});
 const marker=raw.indexOf('--- vpcf block DATA'),open=raw.indexOf('{',marker);assert(marker>=0,resource);
 const tree=parse(raw.slice(open,endOf(raw,open)));
 nodes.set(resource,{tree,native_sha256:hash(native)});
 for(const child of resources(tree))load(child);
}
load(prefix+'.vpcf');
const renderers=new Set(['C_OP_RenderSprites','C_OP_RenderTrails','C_OP_RenderDeferredLight']);
let enlarged=0;
const outputs=[];
for(const [resource,node] of nodes){
 for(const renderer of node.tree.m_Renderers||[]){
  assert(renderers.has(renderer._class),'Unreviewed native renderer '+renderer._class);
  const radius=renderer.m_flRadiusScale;
  if(radius===undefined){renderer.m_flRadiusScale=renderer._class==='C_OP_RenderDeferredLight'?numeric(factor):{m_nType:'PF_TYPE_LITERAL',m_flLiteralValue:numeric(factor)};}
  else if('__number'in radius)renderer.m_flRadiusScale=numeric(radius.__number*factor);
  else {assert.equal(radius.m_nType,'PF_TYPE_LITERAL');const n=radius.m_flLiteralValue?.__number??0;renderer.m_flRadiusScale={...radius,m_flLiteralValue:numeric(n*factor)};}
  enlarged++;
 }
 remap(node.tree);
 const relative=resource.replace(prefix,target),text=header+kv(node.tree)+'\n';
 outputs.push({resource:relative,native_resource:resource,native_sha256:node.native_sha256,source_sha256:hash(text),text});
}
assert(enlarged>0);
const recipes={
 challenge_07_ember_spirit:{member_id:'challenge_07_molten_minion',theme:'fire',projectile:prefix+'.vpcf'},
 challenge_08_primal_beast_svarog:{member_id:'challenge_08_boss',theme:'large_fire',projectile:target+'.vpcf'},
 challenge_09_spectre:{member_id:'challenge_09_boss',theme:'ice',projectile:'particles/units/heroes/hero_ancient_apparition/ancient_apparition_base_attack.vpcf'},
 challenge_05_beastmaster:{member_id:'challenge_05_boss',theme:'starlight',projectile:'particles/units/heroes/hero_wisp/wisp_base_attack.vpcf'},
 challenge_10_terrorblade_fractal:{member_id:'seven_sins_minion',theme:'poison',projectile:'particles/units/heroes/hero_viper/viper_base_attack.vpcf'},
};
for(const recipe of Object.values(recipes)){
 recipe.attack_range=300;recipe.projectile_speed=1600;
 if(recipe.theme!=='large_fire')recipe.native_sha256=hash(vpk.read(recipe.projectile+'_c'));
}
const manifest={date:'2026-10-29',renderer_radius_factor:factor,enlarged_renderers:enlarged,recipes,
 outputs:outputs.map(({text,...entry})=>entry)};
const manifestFile=path.join(root,'art/effects/challenge_projectiles/manifest.json');
const manifestText=JSON.stringify(manifest,null,2)+'\n';
if(process.argv.includes('--check')){
 assert(fs.readFileSync(manifestFile,'utf8').replace(/\r\n/g,'\n')===manifestText,'Manifest differs from native recipe');
 // Source hashes describe canonical UTF-8/LF; honor each repo's checkout EOLs.
 for(const output of outputs)assert(fs.readFileSync(path.join(content,output.resource),'utf8').replace(/\r\n/g,'\n')===output.text,'Particle source differs: '+output.resource);
}else{
 for(const output of outputs){const file=path.join(content,output.resource);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,output.text);}
 fs.mkdirSync(path.dirname(manifestFile),{recursive:true});fs.writeFileSync(manifestFile,manifestText);
}
console.log(JSON.stringify({ok:true,check:process.argv.includes('--check'),particles:outputs.length,enlarged_renderers:enlarged,radius_factor:factor,recipes:Object.keys(recipes).length}));
