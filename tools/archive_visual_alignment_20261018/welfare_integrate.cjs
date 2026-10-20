'use strict';
// Frozen one-texture migration: preserve all source pixels and all unrelated
// resource rows. No archive layout, CSS or gameplay behavior is changed.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),cp=require('child_process'),assert=require('assert/strict');
const {textureInfo}=require('../test_construction_grid_resources.cjs');
const {decodePng}=require('../collection_gw2/opaque_probe.cjs');
const root=path.resolve(__dirname,'../..'),engine=path.resolve(root,'../../..'),content=path.join(engine,'content/dota_addons/Survival/panorama'),runtime=path.join(root,'panorama');
const planPath='tools/archive_visual_alignment_20261018/welfare_plan.json',registryPath='data/ui/item_resources.json';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),fileHash=f=>hash(fs.readFileSync(f));
function checked(base,relative){assert(!path.isAbsolute(relative)&&!relative.split(/[\\/]/).includes('..'));const target=path.resolve(base,relative);assert(target.toLowerCase().startsWith((base+path.sep).toLowerCase()));return target;}
function mkdir(file){fs.mkdirSync(path.dirname(file),{recursive:true});}
function json(file,value){mkdir(file);fs.writeFileSync(file,JSON.stringify(value,null,2)+'\n');}
function source(){
 const p=JSON.parse(fs.readFileSync(checked(root,planPath),'utf8'));
 assert.equal(p.source,'panorama/src/images/custom_game/archive_handoff_v1/art_01.png');assert.equal(p.recipe,'panorama/src/images/custom_game/archive_icons_hd_v1/welfare_seal.vtex');assert.equal(p.runtime,'panorama/images/custom_game/archive_icons_hd_v1/welfare_seal.vtex_c');assert.equal(p.uri,'s2r://panorama/images/custom_game/archive_icons_hd_v1/welfare_seal.vtex');
 assert.equal(p.affected_ids.length,36);assert.equal(new Set(p.affected_ids).size,36);assert(p.affected_ids.every(id=>/^welfare_(?:coop|finish|victory)_\d\d$/.test(id)));
 const png=fs.readFileSync(checked(root,p.source)),recipe=fs.readFileSync(checked(root,p.recipe));assert.equal(hash(png),p.source_sha256);assert.equal(hash(recipe),p.recipe_sha256);assert.equal(fileHash(checked(root,p.recipe_art)),p.recipe_sha256);
 const image=decodePng(png);assert.deepEqual([image.width,image.height],[130,95]);assert([3,4].includes(image.channels));assert(recipe.toString().includes('panorama/images/custom_game/archive_handoff_v1/art_01.png'));assert.match(recipe.toString(),/"m_outputFormat"\s+"string"\s+"BGRA8888"/);assert.match(recipe.toString(),/"m_bNoLod"\s+"bool"\s+"1"/);return {p,png,recipe,image};
}
function audit(s){
 const raw=fs.readFileSync(checked(root,s.p.runtime)),t=textureInfo(raw);assert.deepEqual([t.width,t.height,t.depth,t.format,t.mipLevels,t.flags],[130,95,1,28,1,8]);assert.equal(t.payload.length,49400);
 for(let n=0;n<130*95;n++){const a=n*s.image.channels,b=n*4;assert.equal(t.payload[b],s.image.pixels[a+2]);assert.equal(t.payload[b+1],s.image.pixels[a+1]);assert.equal(t.payload[b+2],s.image.pixels[a]);assert.equal(t.payload[b+3],s.image.channels===4?s.image.pixels[a+3]:255);}
 return {width:t.width,height:t.height,format:'BGRA8888',format_id:t.format,mips:t.mipLevels,no_lod:!!(t.flags&8),payload_bytes:t.payload.length,pixels_checked:12350,native_pixels_exact:true,native_alpha_exact:true,compiled_sha256:hash(raw)};
}
function main(){
 const s=source(),p=s.p;
 if(process.argv.includes('--audit')){const table=JSON.parse(fs.readFileSync(checked(root,registryPath),'utf8'));for(const id of p.affected_ids){const row=table.items.find(r=>r.id===id);assert.equal(row.uri,p.uri);assert.deepEqual(row.source_size,[130,95]);}console.log(JSON.stringify({status:'PASS_WELFARE_NATIVE_AUDIT',affected:36,...audit(s)}));return;}
 assert(process.argv.includes('--apply'),'Use --apply or --audit');
 const stamp=new Date().toISOString().replace(/[:.]/g,'-')+'_'+crypto.randomBytes(3).toString('hex'),backupRelative='output/archive_visual_alignment_20261018/welfare_'+stamp,backup=checked(root,backupRelative),targets=[];
 function track(base,relative,kind){const file=checked(base,relative),saved=checked(backup,'before/'+kind+'/'+relative),existed=fs.existsSync(file);if(existed){mkdir(saved);fs.copyFileSync(file,saved);}const row={file,saved,existed,kind,relative,sha256:existed?fileHash(file):null};targets.push(row);return file;}
 const relativePng=p.source.slice('panorama/src/'.length),relativeRecipe=p.recipe.slice('panorama/src/'.length),relativeRuntime=p.runtime.slice('panorama/'.length),jsRelative='scripts/custom_game/common/item_resources.js',jsRuntime='scripts/custom_game/common/item_resources.vjs_c';
 const sourceOutputs=['data/ui/item_resources.json','panorama/src/scripts/custom_game/common/item_resources.js','scripts/vscripts/config/generated/item_resources.lua','panorama/src/scripts/custom_game/native_ui_icons.js','panorama/src/scripts/custom_game/archive_v10_icons.js','panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js','panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js'];
 for(const f of sourceOutputs)track(root,f,'source');track(content,relativePng,'content');track(content,relativeRecipe,'content');track(runtime,relativeRuntime,'runtime');track(content,jsRelative,'content');track(runtime,jsRuntime,'runtime');
 json(checked(backup,'before.json'),{planPath,plan_sha256:fileHash(checked(root,planPath)),targets});
 const compiler=path.join(engine,'game/bin/win64/resourcecompiler.exe'),python='C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe';
 function run(executable,args,label){const started=Date.now(),r=cp.spawnSync(executable,args,{cwd:root,encoding:'utf8',windowsHide:true,timeout:60000,maxBuffer:8*1024*1024}),log=(r.stdout||'')+(r.stderr||'');fs.writeFileSync(checked(backup,label+'.log'),log);assert.equal(r.status,0,label+' failed');return {started,log};}
 function compile(relative,label){const r=run(compiler,['-i',checked(content,relative),'-game',path.join(engine,'game/dota'),'-fshallow','-nop4'],label);assert(r.log.includes('0 failed'));return r;}
 try{
  for(const [relative,data] of [[relativePng,s.png],[relativeRecipe,s.recipe]]){const target=checked(content,relative);mkdir(target);fs.writeFileSync(target,data);}
  const compiled=compile(relativeRecipe,'texture_compile');assert(fs.statSync(checked(root,p.runtime)).mtimeMs>=compiled.started-2000);const native=audit(s);
  const registry=checked(root,registryPath),beforeBytes=fs.readFileSync(registry),before=JSON.parse(beforeBytes),after=structuredClone(before),ids=new Set(p.affected_ids);
  assert.equal(after.items.filter(r=>ids.has(r.id)).length,36);
  for(const row of after.items)if(ids.has(row.id)){assert([p.old_uri,p.uri].includes(row.uri),row.id+': unexpected current URI');row.uri=p.uri;row.source_size=[130,95];}
  for(let i=0;i<before.items.length;i++){const a=before.items[i],b=after.items[i];assert.equal(a.id,b.id);if(ids.has(a.id)){const expected={...a,uri:p.uri,source_size:[130,95]};assert.deepEqual(b,expected);}else assert.deepEqual(a,b);}
  for(const key of Object.keys(before))if(key!=='items')assert.deepEqual(after[key],before[key]);
  assert.equal(fileHash(registry),hash(beforeBytes),'Registry changed concurrently');
  // Existing JSON uses two-space indentation; preserve its newline convention.
  const newline=beforeBytes.includes(Buffer.from('\r\n'))?'\r\n':'\n';fs.writeFileSync(registry,(JSON.stringify(after,null,2)+'\n').replaceAll('\n',newline));
  run(python,['tools/build_item_resources.py'],'registry_build');run(python,['tools/build_item_resources.py','--check'],'registry_check');run(process.execPath,['--check','panorama/src/scripts/custom_game/common/item_resources.js'],'registry_syntax');
  const changedSources=sourceOutputs.filter(f=>fileHash(checked(root,f))!==targets.find(t=>t.kind==='source'&&t.relative===f).sha256);
  assert(changedSources.every(f=>[registryPath,'panorama/src/scripts/custom_game/common/item_resources.js','scripts/vscripts/config/generated/item_resources.lua'].includes(f)),'Unrelated generated adapter changed');
  const jsSource=checked(root,'panorama/src/'+jsRelative),jsContent=checked(content,jsRelative);mkdir(jsContent);fs.copyFileSync(jsSource,jsContent);const js=compile(jsRelative,'registry_compile');assert(fs.statSync(checked(runtime,jsRuntime)).mtimeMs>=js.started-2000);assert.equal(fileHash(jsSource),fileHash(jsContent));
  source();audit(s);assert.equal(fileHash(checked(content,relativePng)),p.source_sha256);assert.equal(fileHash(checked(content,relativeRecipe)),p.recipe_sha256);
  const actual=JSON.parse(fs.readFileSync(registry,'utf8'));assert.deepEqual(actual,after);
  const report={status:'PASS_WELFARE_LOSSLESS_INTEGRATION',at:new Date().toISOString(),backup:backupRelative,plan:planPath,affected_ids:p.affected_ids,changed_sources:changedSources,unrelated_rows_preserved:true,source_pixels_modified:false,native,registry_source_sha256:fileHash(jsSource),registry_compiled_sha256:fileHash(checked(runtime,jsRuntime)),content_synced:true,compiled:true,native_game_verified:false};
  json(checked(backup,'result.json'),report);json(checked(root,'output/archive_visual_alignment_20261018/welfare_integration.json'),report);console.log(JSON.stringify(report));
 }catch(error){
  const failures=[];for(const row of targets.slice().reverse())try{if(row.existed){mkdir(row.file);fs.copyFileSync(row.saved,row.file);assert.equal(fileHash(row.file),row.sha256);}else if(fs.existsSync(row.file))fs.unlinkSync(row.file);}catch(e){failures.push(String(e));}
  json(checked(backup,'failure.json'),{error:String(error),rollback_failures:failures});throw error;
 }
}
main();
