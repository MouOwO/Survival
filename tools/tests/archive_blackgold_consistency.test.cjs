const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const fixture=path.join(__dirname,'archive_v10_lifecycle.test.cjs');
const prefix=fs.readFileSync(fixture,'utf8').split('const shadowRows =')[0];
const cases=`
sources['archive_blackgold_v1.js']=fs.readFileSync(path.join(sourceRoot,'archive_blackgold_v1.js'),'utf8');
graph.splice(graph.indexOf('archive_180de7e38b_titles_compact_v6.js'),0,'archive_blackgold_v1.js');
let api=load();api.Open();
const rows=Array.from({length:15},(_,i)=>({id:'daily_'+i,name:'道具'+i,count:i===0?1:0,count_known:1,target:i<12?999999:1}));
function verify(seq){
 snapshot('clear',seq,[]);snapshot('points',seq,rows);api.SelectCategory('points');advance(.1);
 assert.equal(cards().length,15);assert.equal(cfg.SurvivalArchiveV10.Inspect().layout,'points_grid');
 assert.equal(cards()[7].style.position,'0px 116px 0px');
 const legacy=nodes.get('ArchiveV10CategoryIcon'),symbol=legacy.__archiveBlackGoldSymbol;
 assert(symbol&&symbol.visible);assert.equal(legacy.visible,false);
 const origin=String(legacy.style.position).split(/\\s+/).map(parseFloat),position=String(symbol.style.position).split(/\\s+/).map(parseFloat);
 near(position[0],origin[0]+12,'Header glyph follows the header anchor');near(position[1],origin[1]+12,'Header glyph retains vertical anchor');
 assert(!legacy.GetParent().Children().some(n=>n.BHasClass('ArchiveParchmentIconRing')&&n.visible),'No empty ring remains behind header');
 for(const button of nodes.get('ArchiveV10Sidebar').Children())assert(!button.Children().some(n=>n.BHasClass('ArchiveParchmentIconRing')&&n.visible),'Sidebar legacy rings are hidden');
 assert.equal(cards()[0].__v10.art.style.opacity,'1');assert.equal(cards()[1].__v10.art.style.saturation,'0');
 assert.equal(cards()[0].__v10.countHost.visible,false,'A single daily gem has no capacity badge');
 api.Filter('locked');assert.equal(cards().length,14);api.Filter('all');
 api.Close();api.Open();assert.equal(cfg.SurvivalArchiveV10.Inspect().layout,'points_grid');
}
verify(80);load(['archive_180de7e38b_titles_compact_v6.js']);api=cfg.SurvivalArchive;api.Open();verify(81);
load();api=cfg.SurvivalArchive;api.Open();verify(82);
assert.equal(canvases().length,1);console.log('ARCHIVE_BLACKGOLD_CONSISTENCY_PASS: points grid, header anchor, hidden rings, states, filters, reopen and reload');
`;
vm.runInNewContext(prefix+cases,{require:require('node:module').createRequire(fixture),__dirname,console},{filename:fixture});
