'use strict';
// Independent read-only validation: the maintained table, JS consumer, native VPK,
// existing custom sources and formal product / lottery identities.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),cp=require('node:child_process'),assert=require('node:assert/strict');
const repo=path.resolve(__dirname,'../../..'),out=path.join(repo,'design_refs/item_resources_20261016/build');process.chdir(repo);fs.mkdirSync(out,{recursive:true});
const tablePath='data/ui/item_resources.json',resolverPath='panorama/src/scripts/custom_game/common/item_resources.js';
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const source=JSON.parse(fs.readFileSync(tablePath,'utf8').replace(/^\uFEFF/,''));
const cfg={},context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg}});vm.runInContext(fs.readFileSync(resolverPath,'utf8'),context,{filename:resolverPath,timeout:5000});
const registry=cfg.SurvivalItemResources;assert(registry&&typeof registry.Lookup==='function'&&typeof registry.Resolve==='function');
function vpkPaths(file){const fd=fs.openSync(file,'r'),header=Buffer.alloc(28);fs.readSync(fd,header,0,28,0);assert.equal(header.readUInt32LE(0),0x55aa1234);const size=header.readUInt32LE(8),tree=Buffer.alloc(size);fs.readSync(fd,tree,0,size,header.readUInt32LE(4)===2?28:12);fs.closeSync(fd);let position=0;const result=new Set();function text(){const end=tree.indexOf(0,position);assert(end>=position);const value=tree.toString('utf8',position,end);position=end+1;return value;}for(let extension;(extension=text());)for(let folder;(folder=text());)for(let name;(name=text());){const preload=tree.readUInt16LE(position+4);position+=18+preload;result.add((folder===' '?'':folder+'/')+name+'.'+extension);}return result;}
const vpkFile=path.resolve(repo,'../../dota/pak01_dir.vpk'),native=vpkPaths(vpkFile);
assert(Array.isArray(source.items),'The maintained item table uses explicit rows');
const resources=source.items.map((row,index)=>({where:'table.items.'+index,row}));
assert(resources.length>683,'Registry includes permanent rewards beyond the 683 native content mappings');
const identities=new Map();
for(const {row}of resources)for(const identity of [row.id,...row.aliases||[]]){
 assert(typeof identity==='string'&&identity.length>0,'Explicit identity is required');
 assert(!identities.has(identity),'An identity may select only one maintained row: '+identity);
 identities.set(identity,row.id);const actual=registry.Lookup(identity);assert(actual&&actual.id===row.id,'Generated JS agrees with the master table: '+identity);
}
const resourceChecks=[],missing=[];
for(const {where,row}of resources){
 const record={id:row.id||where,kind:row.kind,uri:row.uri};let existing=false;
 if(row.kind==='vip'&&!row.uri){existing=Number(row.vip_level)>=1&&Number(row.vip_level)<=12;record.renderer='SurvivalVIPBadges';}
 else if(row.kind==='hero'&&!row.uri){const id=String(row.hero_name||'').replace(/^npc_dota_hero_/,'');existing=native.has('panorama/images/heroes/'+id+'_png.vtex_c');record.native='panorama/images/heroes/'+id+'_png.vtex_c';}
 else if(/^file:\/\/\{images\}\//.test(row.uri||'')){
  const relative=row.uri.slice('file://{images}/'.length);assert(!relative.includes('..'),'Unsafe resource path: '+relative);
  if(relative.startsWith('custom_game/')){record.source=['art/ui/sources/','panorama/src/images/'].map(prefix=>prefix+relative).find(p=>fs.existsSync(p));record.runtime=['panorama/images/'+relative.replace(/\.png$/,'_png.vtex_c'),'panorama/images/'+relative.replace(/\.png$/,'.vtex_c')].find(p=>fs.existsSync(p))||null;existing=!!(record.source||record.runtime);}
  else {const texture='panorama/images/'+relative.replace(/\.png$/,'_png.vtex_c');existing=native.has(texture);record.native=texture;}
 }
 else if(/^s2r:\/\//.test(row.uri||'')){const compiled=row.uri.slice('s2r://'.length)+'_c';record.runtime=compiled;existing=fs.existsSync(compiled)||native.has(compiled);}
 record.status=existing?'PASS':'FAIL';if(!existing)missing.push(record);resourceChecks.push(record);
}
assert.deepEqual(missing,[],'Every registered resource has an existing source or native renderer');
const {csv}=require('../../shop_ui_12h/catalog.cjs');
const formalCommerce=csv('data/csv/商城兑换系统/commerce_products.csv').filter(r=>r.enabled==='1');
const formalLottery=csv('data/csv/抽奖系统/lottery_item_definitions.csv').filter(r=>r.enabled==='1');
const expected=[['video_p042','commerce_p042','lottery_muramasa'],['video_p043','commerce_p043','lottery_kings_treasure'],['video_p048','commerce_p048','lottery_spear_of_longinus']];
const identityChecks=[];
for(const [sku,archive,lottery]of expected){const product=formalCommerce.find(r=>r.sku===sku),prize=formalLottery.find(r=>r.item_id===lottery);assert(product&&prize);const a=registry.Lookup(product),b=registry.Lookup(archive),c=registry.Lookup(prize);assert(a&&b&&c,'Explicit aliases exist for '+sku);assert.equal(a.id,b.id);assert.equal(a.id,c.id);assert.equal(registry.Resolve(product),registry.Resolve(prize));assert.equal(registry.Resolve(archive),registry.Resolve(prize));identityChecks.push({sku,archive,lottery,id:a.id,uri:a.uri,status:'PASS'});}
const muramasa=registry.Lookup('video_p042'),spirit=registry.Lookup('video_p151');assert(muramasa&&spirit);assert.notEqual(muramasa.id,spirit.id,'妖刀村正 and 斩魄刀 have independent identities');assert.notEqual(muramasa.uri,spirit.uri,'妖刀村正 and 斩魄刀 keep distinct artworks');
assert.equal(registry.Lookup('__definitely_unknown_item_resource__'),null,'Unknown identities do not guess from a name');
const unknown={id:'__unknown_dedicated_resource__',name:'妖刀村正',icon:'file://{images}/custom_game/dedicated_server_art.png'};assert.equal(registry.Lookup(unknown),null,'Same display name never aliases an unknown item');
const fixtureFile=path.join(out,'projection_fixture.json'),lua=process.env.LUA51||'C:/Program Files/lua/bin/lua5.1.exe';
const projectionResult=cp.spawnSync(lua,['tools/item_resources_20261016/build/project_fixture.lua',fixtureFile],{cwd:repo,encoding:'utf8',windowsHide:true});assert.equal(projectionResult.status,0,(projectionResult.stdout||'')+(projectionResult.stderr||'')+String(projectionResult.error||''));
const projection=JSON.parse(fs.readFileSync(fixtureFile,'utf8'));assert.equal(projection.resource_source_hash,hash(tablePath),'The native Lua module was generated from the exact current master table');assert.equal(projection.rows.length,178);
const projectionChecks=projection.rows.map(row=>{const expected=registry.Lookup(row.id);assert(expected,'All projected goods have one registered identity: '+row.id);assert.equal(row.resource_id,expected.id,'Native Lua projection has canonical resource_id: '+row.id);assert.equal(row.icon,expected.uri,'Native Lua projection uses authoritative URI: '+row.id);return{id:row.id,resource_id:row.resource_id,icon:row.icon};});
const historyReport='design_refs/archive_commerce_goods_20261016/projection_validation.json';
let quantityRegression=null;if(fs.existsSync(historyReport)){const original=JSON.parse(fs.readFileSync(historyReport,'utf8'));assert.equal(original.status,'PASS');assert.equal(original.groups,23);for(const[file,expected]of Object.entries(original.source_hashes))assert.equal(hash(file),expected,'Quantity/ownership regression report matches current production source: '+file);fs.copyFileSync(historyReport,path.join(out,'projection_quantity_regression.json'));quantityRegression={status:'PASS',groups:original.groups,source:historyReport,copied:'design_refs/item_resources_20261016/build/projection_quantity_regression.json'};}
const report={status:'PASS',tablePath,resolverPath,hashes:{[tablePath]:hash(tablePath),[resolverPath]:hash(resolverPath),'scripts/vscripts/config/generated/item_resources.lua':hash('scripts/vscripts/config/generated/item_resources.lua')},resourceCount:resources.length,identityCount:identities.size,nativeVpkEntries:native.size,resourceChecks,identityChecks,projection:{status:'PASS',rows:projectionChecks,sourceHash:projection.resource_source_hash,fixtureSha256:hash(fixtureFile)},quantityRegression,separateMuramasaAndSpiritKatana:{muramasa:{id:muramasa.id,uri:muramasa.uri},spirit:{id:spirit.id,uri:spirit.uri},status:'PASS'},unknownIdentityIsNotGuessed:true,networkRequests:0,saveWrites:0};
fs.writeFileSync(path.join(out,'validation.json'),JSON.stringify(report,null,2)+'\n');
console.log('ITEM_RESOURCES_INDEPENDENT_PASS '+resources.length+' existing resources, '+identityChecks.length+' shared identities, distinct P042/P151');
