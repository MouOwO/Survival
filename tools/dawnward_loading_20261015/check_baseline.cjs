'use strict';
const fs=require('fs'),Module=require('module'),path=require('path'),assert=require('assert');
const fixtureFile=path.resolve('tools/test_startup_loading_ui.js');
let source=fs.readFileSync(fixtureFile,'utf8');
for(const relative of ['scripts/custom_game/startup_loading.js','layout/custom_game/startup_loading.xml','layout/custom_game/custom_loading_screen.xml'])
 source=source.replace('panorama/src/'+relative,'design_refs/dawnward_loading_20261015/baseline/sources/panorama/src/'+relative);
source=source.replaceAll('image.includes("dawnward_citadel_background")','image.includes("server_loading_background")');
const fixture=new Module(fixtureFile,module);fixture.filename=fixtureFile;fixture.paths=Module._nodeModulePaths(path.dirname(fixtureFile));fixture._compile(source,fixtureFile);
const file=path.resolve('tools/test_match_setup_ui.cjs'),test=new Module(file,module);
test.filename=file;test.paths=Module._nodeModulePaths(path.dirname(file));
const normalRequire=test.require.bind(test);
test.require=id=>id==='./test_startup_loading_ui.js'?fixture.exports:normalRequire(id);
let failure;
try{test._compile(fs.readFileSync(file,'utf8'),file)}catch(error){failure=error;}
assert(failure&&failure.message.includes('engine has entered game: fresh phase without nettable or shared cache never flashes loading'));
const result={baseline_before_this_task:true,same_failure_as_current:true,test:'tools/test_match_setup_ui.cjs',assertion:failure.message,scope:'Original source snapshot, authored XML and genuine VM harness; no production or test edits to change behavior'};
fs.writeFileSync('design_refs/dawnward_loading_20261015/baseline/existing_match_setup_failure.json',JSON.stringify(result,null,2));
console.log('BASELINE_SAME_EXISTING_MATCH_SETUP_FAILURE_CONFIRMED');
