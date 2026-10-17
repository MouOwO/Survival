'use strict';
// Execute the real archive source graph; only ownership comes from isolated Lua projections.
const fs=require('fs'),path=require('path'),{spawnSync}=require('child_process');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'design_refs/archive_commerce_goods_20261016/ui/preview');
const fixtureFile=process.argv[process.argv.indexOf('--fixture')+1];
if(!process.argv.includes('--fixture')||!fixtureFile)throw Error('Provide --fixture with an isolated authoritative projection JSON.');
const input=path.resolve(repo,fixtureFile),sourceFixture=JSON.parse(fs.readFileSync(input,'utf8').replace(/^\uFEFF/,''));
const fixture=sourceFixture.owned||sourceFixture;
if(!Array.isArray(fixture.rows)||!fixture.rows.length)throw Error('Projection fixture must supply nonempty rows.');
const build=spawnSync(process.execPath,[path.join(repo,'tools/archive_parchment/preview.cjs'),'--out',out],{cwd:repo,encoding:'utf8',windowsHide:true});
if(build.stdout)process.stdout.write(build.stdout);if(build.stderr)process.stderr.write(build.stderr);if(build.status)process.exit(build.status);
const entry=path.join(out,'index.html');let html=fs.readFileSync(entry,'utf8');
const script=`<script>
window.goodsProjectionFixture=${JSON.stringify(fixture).replace(/</g,'\\u003c')};
window.goodsUnknownFixture=${JSON.stringify(sourceFixture.unknown||{rows:[]}).replace(/</g,'\\u003c')};
window.goodsReady=window.previewReady.then(async function(ok){
 if(!ok)return false;
 if(!PREVIEW_FIXTURE.v10.categories.some(function(c){return c.id==='commerce_goods';}))PREVIEW_FIXTURE.v10.categories.push({id:'commerce_goods',name:'商城道具'});
 previewFixturePages.commerce_goods=JSON.parse(JSON.stringify(goodsProjectionFixture.rows));
 await previewSelect('commerce_goods');
 await Promise.all([...document.images].map(function(i){return i.decode().catch(function(){return false;});}));
 syncLayout();return true;
});
</script>`;
html=html.includes('</body>')?html.replace('</body>',script+'</body>'):html+script;
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1商城道具图鉴 · 正式 XML / JS / CSS · Lua 正式配置投影、隔离持有样例 · 尚未游戏内验证$2');
fs.writeFileSync(entry,html);
const assemblyFile=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
assembly.goodsProjection={file:path.relative(repo,input).replaceAll('\\','/'),rows:fixture.rows.length,isolated:true};
fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2));
console.log('ARCHIVE_GOODS_PREVIEW '+path.relative(repo,entry));
