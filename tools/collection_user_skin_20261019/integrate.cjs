'use strict';
// Update only the collection background binding. Search controls are absent from the current renderer.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/collection_user_skin_20261019'),file=path.join(root,'panorama/src/scripts/custom_game/collection_gw2.js');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),before=fs.readFileSync(file);let source=before.toString().replaceAll('\r\n','\n');
const old='var background=art(canvas,"window_background",0,0,size[0],size[1],"CollectionGW2Background");style(background,{opacity:"1",backgroundColor:"#171e24"});';
const replacement='var background=make("Panel",canvas,"CollectionGW2Background","CollectionGW2Art");rect(background,0,0,size[0],size[1]);background.hittest=false;background.hittestchildren=false;style(background,{backgroundImage:\'url("s2r://panorama/images/custom_game/collection_user_skin_v1/background.vtex")\',backgroundSize:"100% 100%",backgroundRepeat:"no-repeat",opacity:"1",backgroundColor:"#171e24"});';
assert(source.includes(old)||source.includes(replacement),'Expected original collection background geometry');source=source.replace(old,replacement);
assert(!/CollectionGW2Search|搜索收藏|ontextentrychange/.test(source),'Search field and its callbacks must not be created');
if(!before.equals(Buffer.from(source))){const backup=path.join(out,'baseline_'+Date.now(),'collection_gw2.js');fs.mkdirSync(path.dirname(backup),{recursive:true});fs.writeFileSync(backup,before);assert.equal(hash(fs.readFileSync(file)),hash(before),'Concurrent collection source change');fs.writeFileSync(file,source);}
const files=['scripts/custom_game/collection_gw2.js','styles/custom_game/collection_gw2.css','layout/custom_game/collection_user_skin_assets.xml',...['background.png','background.vtex'].map(name=>'images/custom_game/collection_user_skin_v1/'+name)].map(relative=>({path:relative,sha256:hash(fs.readFileSync(path.join(root,'panorama/src',relative)))}));
fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'compile_plan.json'),JSON.stringify({files},null,2));console.log('COLLECTION_USER_SKIN_INTEGRATION_PASS '+files[0].sha256+' search controls absent');
