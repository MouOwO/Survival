'use strict';
// Build the exact 128px prefiltered/single-mip policy selected by a native
// single-picture comparison. Default is a read-only wife_31 plan. --all alone
// is also read-only; production/content/runtime writes require --apply.
// No raster is generated, resized, sharpened, recolored or re-encoded here.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),child=require('node:child_process');
const {textureInfo}=require('../test_construction_grid_resources.cjs');
const {decodePng}=require('../collection_gw2/opaque_probe.cjs');
const root=path.resolve(__dirname,'../..'),engine=path.resolve(root,'../../..');
const content=path.join(engine,'content/dota_addons/Survival/panorama'),runtime=path.join(root,'panorama');
const set='collection_portraits_grid_v2',masterManifest='data/ui/collection_portraits_compact_v1.json',targetManifest='data/ui/'+set+'.json';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),fileHash=p=>hash(fs.readFileSync(p));
function checked(base,relative){
 assert(!path.isAbsolute(relative)&&!relative.split(/[\\/]/).includes('..'),'relative path stays within declared root');
 const target=path.resolve(base,relative),prefix=path.resolve(base)+path.sep;
 assert(target.toLowerCase().startsWith(prefix.toLowerCase()),'target escaped declared root');
 let at=target;while(at!==path.parse(at).root){if(fs.existsSync(at))assert(!fs.lstatSync(at).isSymbolicLink(),'unexpected link in target path: '+at);if(at.toLowerCase()===path.resolve(base).toLowerCase())break;at=path.dirname(at);}
 return target;
}
function load(relative){return fs.readFileSync(checked(root,relative));}
function options(argv){
 const o={ids:['wife_31'],all:false,apply:false,compile:false,audit:false,report:null};let explicitIds=false;
 for(let i=0;i<argv.length;i++){
  const arg=argv[i];
  if(arg==='--all')o.all=true;
  else if(arg==='--apply')o.apply=true;
  else if(arg==='--compile')o.compile=true;
  else if(arg==='--audit')o.audit=true;
  else if(arg==='--ids'){assert(argv[i+1],'--ids requires comma-separated formal IDs');o.ids=argv[++i].split(',').filter(Boolean);explicitIds=true;}
  else if(arg==='--report'){assert(argv[i+1],'--report requires a workspace-relative file');o.report=argv[++i];}
  else throw Error('Usage: node tools/collection_clarity_20261017/build_grid_v2.cjs [--ids wife_31,... | --all] [--apply [--compile]] [--audit] [--report design_refs/...json]');
 }
 assert(!(o.all&&explicitIds),'choose --ids or --all');assert(!o.compile||o.apply,'--compile requires --apply');assert(!o.audit||!o.apply,'--audit is read-only and cannot combine with --apply');
 assert(o.ids.length&&new Set(o.ids).size===o.ids.length,'IDs are nonempty and unique');return o;
}
function plan(o){
 const manifestBytes=load(masterManifest),m=JSON.parse(manifestBytes);assert.equal(m.count,160);assert.equal(m.items.length,160);
 const ids=o.all?m.items.map(x=>x.id):o.ids,selected=ids.map(id=>{const row=m.items.find(x=>x.id===id);assert(row,'Unknown formal collection ID: '+id);return row;});
 const frozen={[masterManifest]:hash(manifestBytes)},records=selected.map(row=>{
  assert.match(row.id,/^(ex|friend|wife|beast)_(0[1-9]|[1-3][0-9]|40)$/);
  assert.equal(row.source,'panorama/src/images/custom_game/'+({wife:'wife_portraits_v1',beast:'archive_items_v2',ex:'archive_portraits_v3',friend:'archive_portraits_v3'}[row.category_id])+'/'+row.id+'.png');
  assert.equal(row.png,'panorama/src/images/custom_game/collection_portraits_compact_v1/'+row.id+'.png');
  assert.equal(row.texture,'panorama/src/images/custom_game/collection_portraits_compact_v1/'+row.id+'.vtex');
  const original=load(row.source),png=load(row.png),sourceRecipe=load(row.texture),image=decodePng(png);
  assert.equal(hash(original),row.source_sha256,row.id+': approved master identity');assert.equal(hash(png),row.png_sha256,row.id+': exact prefiltered PNG');assert.equal(hash(sourceRecipe),row.texture_sha256,row.id+': reviewed compact recipe');
  assert.deepEqual([image.width,image.height,image.channels],[128,128,4],row.id+': real 128px RGBA input');
  const sourceText=sourceRecipe.toString('utf8'),needle='"m_algorithm" "string" "Box"';assert.equal(sourceText.split(needle).length,2,'exactly one mip algorithm');
  const recipe=Buffer.from(sourceText.replace(needle,'"m_algorithm" "string" ""'),'utf8');
  const relative='images/custom_game/'+set+'/'+row.id+'.vtex',source='panorama/src/'+relative,uri='s2r://panorama/'+relative;
  assert(recipe.includes(Buffer.from('"panorama/'+row.png.replace('panorama/src/','')+'"')),'recipe must reference the same existing compact input');
  for(const p of [row.source,row.png,row.texture])frozen[p]=fileHash(checked(root,p));
  return {id:row.id,category_id:row.category_id,source_master:row.source,source_master_sha256:row.source_sha256,png:row.png,png_sha256:row.png_sha256,source,relative,runtime_uri:uri,recipe_sha256:hash(recipe),recipe,pixels:image.pixels};
 });
 const publicRecords=records.map(({recipe,pixels,...r})=>r),manifest={schema_version:1,asset_set:set,usage:'collection_grid',policy:'128px premultiplied-alpha Lanczos source PNG, unchanged bytes; uncompressed NO_LOD single mip',source_manifest:masterManifest,source_manifest_sha256:hash(manifestBytes),count:records.length,dimensions:[128,128],texture:{format:'BGRA8888',no_lod:true,mip_levels:1,payload_bytes_per_texture:65536},source_pngs_unchanged:true,items:publicRecords};
 return {records,frozen,manifest};
}
function assertFrozen(frozen){for(const [relative,expected]of Object.entries(frozen))assert.equal(fileHash(checked(root,relative)),expected,'Source changed during operation: '+relative);}
function auditRecord(row){
 assert.equal(fileHash(checked(root,row.source)),row.recipe_sha256,row.id+': generated recipe identity');
 const filename=checked(runtime,row.relative+'_c'),bytes=fs.readFileSync(filename),info=textureInfo(bytes);
 assert.deepEqual([info.width,info.height,info.depth,info.format,info.mipLevels,info.flags],[128,128,1,28,1,8],row.id+': actual native dimensions/format/single mip/NO_LOD');assert.equal(info.payload.length,65536,row.id+': exact single mip payload');
 // BGRA8888 is stored BGRA. Compare all source R/G/B/A bytes after channel
 // ordering, including transparent RGB. This rejects a wrong character/crop.
 for(let i=0;i<row.pixels.length;i+=4){
  assert.equal(info.payload[i],row.pixels[i+2],row.id+': blue pixel '+i/4);assert.equal(info.payload[i+1],row.pixels[i+1],row.id+': green pixel '+i/4);
  assert.equal(info.payload[i+2],row.pixels[i],row.id+': red pixel '+i/4);assert.equal(info.payload[i+3],row.pixels[i+3],row.id+': alpha pixel '+i/4);
 }
 return {id:row.id,runtime_uri:row.runtime_uri,source:row.source,source_recipe_sha256:row.recipe_sha256,source_png:row.png,source_png_sha256:row.png_sha256,master:row.source_master,master_sha256:row.source_master_sha256,width:info.width,height:info.height,format:'BGRA8888',flags:info.flags,mips:info.mipLevels,no_lod:true,payload_bytes:info.payload.length,all_rgba_pixels_equal_to_png:true,rgba_pixels_checked:16384,compiled_sha256:hash(bytes)};
}
function mkdirFile(p){fs.mkdirSync(path.dirname(p),{recursive:true});}
function apply(p,o){
 const stamp=new Date().toISOString().replace(/[:.]/g,'-')+'_'+crypto.randomBytes(4).toString('hex'),backup=checked(root,'output/collection_clarity_20261017/grid_v2_'+stamp),targets=[];
 function target(base,relative,kind){const filename=checked(base,relative);if(targets.some(x=>x.filename.toLowerCase()===filename.toLowerCase()))return filename;const saved=checked(backup,kind+'/'+relative),existed=fs.existsSync(filename);if(existed){mkdirFile(saved);fs.copyFileSync(filename,saved);}targets.push({filename,saved,existed,kind,relative,before_sha256:existed?fileHash(filename):null});return filename;}
 const manifestPath=target(root,targetManifest,'repo');for(const row of p.records)target(root,row.source,'repo');
 if(o.compile){for(const row of p.records){target(content,row.relative,'content');target(content,row.png.replace('panorama/src/',''),'content');target(runtime,row.relative+'_c','runtime');}}
 mkdirFile(path.join(backup,'before.json'));fs.writeFileSync(path.join(backup,'before.json'),JSON.stringify({targets,frozen:p.frozen},null,2)+'\n');
 const outputs=[];
 try{
  assertFrozen(p.frozen);
  for(const row of p.records){const out=checked(root,row.source);mkdirFile(out);fs.writeFileSync(out,row.recipe);}
  mkdirFile(manifestPath);fs.writeFileSync(manifestPath,JSON.stringify(p.manifest,null,2)+'\n');
  if(o.compile){
   const compiler=path.join(engine,'game/bin/win64/resourcecompiler.exe');assert(fs.existsSync(compiler),'native resourcecompiler missing');
   for(const row of p.records){
    const dependency=checked(content,row.png.replace('panorama/src/','')),recipe=checked(content,row.relative);mkdirFile(dependency);mkdirFile(recipe);
    fs.copyFileSync(checked(root,row.png),dependency);fs.copyFileSync(checked(root,row.source),recipe);assert.equal(fileHash(dependency),row.png_sha256);assert.equal(fileHash(recipe),row.recipe_sha256);
    const started=Date.now(),result=child.spawnSync(compiler,['-i',recipe,'-game',path.join(engine,'game/dota'),'-fshallow','-nop4'],{cwd:root,encoding:'utf8',windowsHide:true,timeout:180000,maxBuffer:8*1024*1024}),log=(result.stdout||'')+(result.stderr||'');
    fs.writeFileSync(path.join(backup,row.id+'.log'),log);assert.equal(result.status,0,row.id+': resourcecompiler failed');assert(log.includes('0 failed'),row.id+': compiler did not report success');
    assert(fs.statSync(checked(runtime,row.relative+'_c')).mtimeMs>=started-2000,row.id+': stale native artifact');assert.equal(fileHash(checked(root,row.png)),row.png_sha256);assert.equal(fileHash(checked(root,row.source_master)),row.source_master_sha256);const audited=auditRecord(row);audited.content_recipe_sha256=fileHash(recipe);audited.content_png_sha256=fileHash(dependency);assert.equal(audited.content_recipe_sha256,row.recipe_sha256);assert.equal(audited.content_png_sha256,row.png_sha256);outputs.push(audited);
    console.log('COLLECTION_GRID_V2_NATIVE_PASS '+row.id);
   }
  }
  assertFrozen(p.frozen);for(const audited of outputs){const row=p.records.find(r=>r.id===audited.id);assert.equal(fileHash(checked(root,row.source)),audited.source_recipe_sha256);assert.equal(fileHash(checked(content,row.relative)),audited.content_recipe_sha256);assert.equal(fileHash(checked(content,row.png.replace('panorama/src/',''))),audited.content_png_sha256);assert.equal(fileHash(checked(runtime,row.relative+'_c')),audited.compiled_sha256);}
  const report={status:o.compile?'PASS_COMPILED_AND_NATIVE_PIXELS_AUDITED':'PASS_GENERATED_NOT_COMPILED',count:p.records.length,source_pixels_modified:false,game_verified:false,backup:path.relative(root,backup).replaceAll('\\','/'),manifest:targetManifest,outputs};fs.writeFileSync(path.join(backup,'result.json'),JSON.stringify(report,null,2)+'\n');return report;
 }catch(error){
  const errors=[];for(const record of targets.slice().reverse()){try{if(record.existed){mkdirFile(record.filename);fs.copyFileSync(record.saved,record.filename);assert.equal(fileHash(record.filename),record.before_sha256);}else if(fs.existsSync(record.filename))fs.unlinkSync(record.filename);}catch(e){errors.push(String(e));}}
  fs.writeFileSync(path.join(backup,'failure.json'),JSON.stringify({error:String(error),rollback_errors:errors},null,2)+'\n');throw error;
 }
}
function main(argv=process.argv.slice(2)){
 const o=options(argv),p=plan(o);let result;
 if(o.audit){assertFrozen(p.frozen);result={status:'PASS_NATIVE_PIXELS_AUDITED',count:p.records.length,source_pixels_modified:false,game_verified:false,outputs:p.records.map(auditRecord)};assertFrozen(p.frozen);}
 else if(o.apply)result=apply(p,o);
 else result={status:'READ_ONLY_PLAN',count:p.records.length,ids:p.records.map(r=>r.id),production_files_written:0,source_pixels_modified:false,expected:{width:128,height:128,format:'BGRA8888',mips:1,no_lod:true,payload_bytes:65536},manifest:p.manifest};
 if(o.report){const reportPath=checked(root,o.report);mkdirFile(reportPath);fs.writeFileSync(reportPath,JSON.stringify(result,null,2)+'\n');}
 const summary={...result};if(summary.manifest&&typeof summary.manifest==='object')summary.manifest={asset_set:summary.manifest.asset_set,count:summary.manifest.count};if(Array.isArray(summary.outputs))summary.outputs={count:summary.outputs.length,all_rgba_pixels_equal_to_png:summary.outputs.every(x=>x.all_rgba_pixels_equal_to_png)};console.log(JSON.stringify(summary,null,2));return result;
}
module.exports={options,plan,auditRecord,main};if(require.main===module)main();
