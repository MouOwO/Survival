'use strict';
// Bounded Source2 texture experiment. Only frozen PNG dependencies may be
// compiled; no UI, account, game-window or registry changes are performed.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),cp=require('node:child_process');
const {textureInfo}=require('../test_construction_grid_resources.cjs');
const {decodePng}=require('../collection_gw2/opaque_probe.cjs');
const root=path.resolve(__dirname,'../..'),engine=path.resolve(root,'../../..');
const content=path.join(engine,'content/dota_addons/Survival/panorama'),runtime=path.join(root,'panorama');
const task='archive_icon_clarity_20261018',planRelative='tools/'+task+'/texture_plan.json';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),fileHash=f=>hash(fs.readFileSync(f));
function checked(base,relative){
 assert(!path.isAbsolute(relative)&&!relative.split(/[\\/]/).includes('..'),'relative path stays inside declared root');
 const out=path.resolve(base,relative);assert(out.toLowerCase().startsWith((path.resolve(base)+path.sep).toLowerCase()),'path escaped intended root');
 let at=out;while(at!==path.parse(at).root){if(fs.existsSync(at))assert(!fs.lstatSync(at).isSymbolicLink(),'unexpected symbolic link: '+at);if(at.toLowerCase()===path.resolve(base).toLowerCase())break;at=path.dirname(at);}return out;
}
function mkdir(f){fs.mkdirSync(path.dirname(f),{recursive:true});}
function writeJson(f,data){mkdir(f);fs.writeFileSync(f,JSON.stringify(data,null,2)+'\n');}
function textureSummary(bytes){const t=textureInfo(bytes);return {width:t.width,height:t.height,depth:t.depth,format:t.format,mips:t.mipLevels,flags:t.flags,no_lod:!!(t.flags&8),payload_bytes:t.payload.length,sha256:hash(bytes)};}
function validateRow(row){
 assert.match(row.id,/^shadow_(?:0[1-9]|1[0-9]|2[0-3])$/);const number=row.id.slice('shadow_'.length),pngStem='images/custom_game/archive_v10/items/virtual_'+number,stem='images/custom_game/archive_icons_hd_v1/'+row.id;
 assert.equal(row.png,'panorama/src/'+pngStem+'.png');assert.equal(row.relative_png,pngStem+'.png');
 assert.equal(row.recipe,'panorama/src/'+stem+'.vtex');assert.equal(row.recipe_art,'art/ui/sources/custom_game/archive_icons_hd_v1/'+row.id+'.vtex');assert.equal(row.relative_recipe,stem+'.vtex');
 assert.equal(row.runtime,'panorama/'+stem+'.vtex_c');assert.equal(row.uri,'s2r://panorama/'+stem+'.vtex');
 assert.equal(row.legacy_uri,'file://{images}/custom_game/archive_v10/items/virtual_'+number+'.png');
 const png=fs.readFileSync(checked(root,row.png)),recipe=fs.readFileSync(checked(root,row.recipe));
 assert.equal(hash(png),row.png_sha256,'frozen original PNG identity');assert.equal(hash(recipe),row.recipe_sha256,'reviewed recipe identity');assert.equal(fileHash(checked(root,row.recipe_art)),row.recipe_sha256,'canonical art recipe mirror');
 const image=decodePng(png);assert.deepEqual([image.width,image.height],row.size);assert([3,4].includes(image.channels));
 assert(recipe.toString().includes('"m_fileName" "string" "panorama/'+row.relative_png+'"'),'recipe original dependency identity');
 assert.match(recipe.toString(),/"m_outputFormat"\s+"string"\s+"BGRA8888"/);assert.match(recipe.toString(),/"m_bNoLod"\s+"bool"\s+"1"/);
 assert.match(recipe.toString(),/"m_mipAlgorithm"\s+"CDmeImageProcessor"\s*\{\s*"m_algorithm"\s+"string"\s+""/);return {png,recipe,image};
}
function audit(row,source=validateRow(row)){
 const raw=fs.readFileSync(checked(root,row.runtime)),t=textureInfo(raw),summary=textureSummary(raw),image=source.image;
 assert.deepEqual([t.width,t.height,t.depth,t.format,t.mipLevels,t.flags],[...row.size,1,28,1,8],row.id+': BGRA8888 single mip NO_LOD exact dimensions');
 assert.equal(t.payload.length,image.width*image.height*4,'complete native pixel payload');
 for(let pixel=0;pixel<image.width*image.height;pixel++){
  const sourceAt=pixel*image.channels,nativeAt=pixel*4;
  for(const [channel,sourceChannel] of [[0,2],[1,1],[2,0]])assert.equal(t.payload[nativeAt+channel],image.pixels[sourceAt+sourceChannel],row.id+': color byte '+nativeAt);
  assert.equal(t.payload[nativeAt+3],image.channels===4?image.pixels[sourceAt+3]:255,row.id+': alpha byte '+nativeAt);
 }
 return {id:row.id,uri:row.uri,png_sha256:row.png_sha256,recipe_sha256:row.recipe_sha256,...summary,native_pixels_exact:true,native_alpha_exact:true,pixels_checked:image.width*image.height};
}
function run(options){
 const plan=JSON.parse(fs.readFileSync(checked(root,planRelative),'utf8'));assert.equal(plan.schema_version,1);assert.equal(new Set(plan.textures.map(r=>r.id)).size,plan.textures.length);
 const selected=options.ids.length?options.ids.map(id=>{const r=plan.textures.find(r=>r.id===id);assert(r,'ID not in frozen plan: '+id);return r;}):plan.textures;
 assert.equal(new Set(selected.map(r=>r.id)).size,selected.length);const sources=selected.map(validateRow);
 if(options.audit)return {status:'PASS_NATIVE_AUDIT',records:selected.map((r,i)=>audit(r,sources[i]))};
 if(!options.apply)return {status:'READ_ONLY_PLAN_PASS',count:selected.length,ids:selected.map(r=>r.id),uri_changes:0,png_changes:0};
 const compiler=path.join(engine,'game/bin/win64/resourcecompiler.exe');assert(fs.existsSync(compiler),'native compiler missing');
 const stamp=new Date().toISOString().replace(/[:.]/g,'-')+'_'+crypto.randomBytes(4).toString('hex'),backupRelative='output/'+task+'/compile_'+stamp,backup=checked(root,backupRelative),targets=[];
 function track(base,relative,kind){const filename=checked(base,relative);assert(!targets.some(t=>t.filename.toLowerCase()===filename.toLowerCase()),'duplicate output target');const saved=checked(backup,'before/'+kind+'/'+relative),existed=fs.existsSync(filename);if(existed){mkdir(saved);fs.copyFileSync(filename,saved);}const record={filename,saved,existed,kind,relative,sha256:existed?fileHash(filename):null};targets.push(record);return filename;}
 for(const row of selected){track(content,row.relative_png,'content');track(content,row.relative_recipe,'content');track(runtime,row.runtime.slice('panorama/'.length),'runtime');if(options.probeAuto)track(runtime,row.relative_png.replace(/\.png$/,'_png.vtex_c'),'runtime');}
 const probeLayoutRelative='layout/custom_game/archive_icon_clarity_probe_20261018.xml';
 if(options.probeAuto){track(content,probeLayoutRelative,'content');track(runtime,probeLayoutRelative.replace(/\.xml$/,'.vxml_c'),'runtime');}
 writeJson(checked(backup,'before.json'),{targets,plan_sha256:fileHash(checked(root,planRelative))});
 function compile(input,id,kind,force='-fshallow'){
  const started=Date.now(),result=cp.spawnSync(compiler,['-i',input,'-game',path.join(engine,'game/dota'),force,'-nop4'],{cwd:root,encoding:'utf8',windowsHide:true,timeout:120000,maxBuffer:8*1024*1024}),log=(result.stdout||'')+(result.stderr||'');
  const logFile=checked(backup,id+'_'+kind+'.log');mkdir(logFile);fs.writeFileSync(logFile,log);assert.equal(result.status,0,id+': compiler failure, '+logFile);assert(log.includes('0 failed'),id+': compiler success marker missing');return {log:path.relative(root,logFile).replaceAll('\\','/'),started};
 }
 const records=[];
 try{
  for(let index=0;index<selected.length;index++){
   const row=selected[index],source=sources[index],contentPng=checked(content,row.relative_png),contentRecipe=checked(content,row.relative_recipe),artifact=checked(root,row.runtime);
   const before=fs.existsSync(artifact)?textureSummary(fs.readFileSync(artifact)):null;
   mkdir(contentPng);mkdir(contentRecipe);fs.copyFileSync(checked(root,row.png),contentPng);fs.copyFileSync(checked(root,row.recipe),contentRecipe);
   const initialCompile=compile(contentRecipe,row.id,'explicit');assert(fs.statSync(artifact).mtimeMs>=initialCompile.started-2000,'stale native artifact');
   let result=audit(row,source),probe=null;
   if(options.probeAuto){
    // PNGs have no standalone compiler. Force an exact one-image Panorama
    // layout dependency, matching ordinary PNG preload/CSS builds.
    const probeLayout=checked(content,probeLayoutRelative);mkdir(probeLayout);fs.writeFileSync(probeLayout,'<root><Panel><Image src="'+row.legacy_uri+'" visible="false" hittest="false" /></Panel></root>\n');
    const explicitHash=fileHash(artifact),automaticCompile=compile(probeLayout,row.id,'automatic_png','-f');const automatic=textureSummary(fs.readFileSync(artifact));
    let exact=false;try{exact=audit(row,source).native_pixels_exact;}catch{}
    probe={...automaticCompile,automatic_texture:automatic,automatic_bytes_equal_to_explicit:automatic.sha256===explicitHash,automatic_pixels_still_exact:exact,explicit_recipe_present:true};
    assert(exact&&automatic.sha256===explicitHash,'automatic PNG dependency compilation must not touch the separate HD runtime');
    const legacy=targets.find(t=>t.kind==='runtime'&&t.relative===row.relative_png.replace(/\.png$/,'_png.vtex_c'));
    if(legacy.existed){fs.copyFileSync(legacy.saved,legacy.filename);assert.equal(fileHash(legacy.filename),legacy.sha256);}else if(fs.existsSync(legacy.filename))fs.unlinkSync(legacy.filename);
    probe.separate_hd_runtime_untouched=true;probe.legacy_runtime_restored=true;result=audit(row,source);
   }
   assert.equal(fileHash(contentPng),row.png_sha256);assert.equal(fileHash(contentRecipe),row.recipe_sha256);validateRow(row);
   const baseline=targets.find(t=>t.kind==='runtime'&&t.filename===artifact);
   const report={...result,before,initial_compile:initialCompile,automatic_png_probe:probe,baseline_runtime:baseline.existed?path.relative(root,baseline.saved).replaceAll('\\','/'):null};records.push(report);
   console.log('ARCHIVE_ICON_CLARITY_NATIVE_PASS '+row.id+' '+result.width+'x'+result.height+' BGRA8888 single_mip NO_LOD exact_pixels');
  }
  for(let i=0;i<selected.length;i++)audit(selected[i],sources[i]);
  if(options.probeAuto){for(const record of targets.filter(t=>t.relative===probeLayoutRelative||t.relative===probeLayoutRelative.replace(/\.xml$/,'.vxml_c'))){if(record.existed){fs.copyFileSync(record.saved,record.filename);assert.equal(fileHash(record.filename),record.sha256);}else if(fs.existsSync(record.filename))fs.unlinkSync(record.filename);}}
  const report={status:'PASS_COMPILED_EXACT_PIXELS',at:new Date().toISOString(),backup:backupRelative,count:records.length,png_bytes_unchanged:true,uri_changes:0,game_verified:false,records};
  writeJson(checked(backup,'result.json'),report);writeJson(checked(root,'design_refs/'+task+'/'+(selected.length===1?'texture_probe.json':'textures_compile.json')),report);return report;
 }catch(error){
  const failures=[];for(const record of targets.slice().reverse()){try{const base=record.kind==='content'?content:runtime;assert.equal(checked(base,record.relative),record.filename);if(record.existed){mkdir(record.filename);fs.copyFileSync(record.saved,record.filename);assert.equal(fileHash(record.filename),record.sha256);}else if(fs.existsSync(record.filename))fs.unlinkSync(record.filename);}catch(e){failures.push(String(e));}}
  writeJson(checked(backup,'failure.json'),{error:String(error),rollback_failures:failures});throw error;
 }
}
function options(argv){const result={apply:false,audit:false,probeAuto:false,ids:[]};for(let i=0;i<argv.length;i++){if(argv[i]==='--apply')result.apply=true;else if(argv[i]==='--audit')result.audit=true;else if(argv[i]==='--probe-auto')result.probeAuto=true;else if(argv[i]==='--ids'){assert(argv[i+1],'--ids requires comma-separated frozen IDs');result.ids=argv[++i].split(',');}else throw Error('Unknown option: '+argv[i]);}assert(!(result.apply&&result.audit));assert(!result.probeAuto||result.apply,'--probe-auto requires --apply');return result;}
if(require.main===module){const result=run(options(process.argv.slice(2)));console.log(JSON.stringify(result,null,2));}
module.exports={audit,run,options,checked};
