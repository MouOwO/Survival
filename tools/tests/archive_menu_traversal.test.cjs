'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const fixture=path.join(__dirname,'archive_v10_lifecycle.test.cjs');
const prefix=fs.readFileSync(fixture,'utf8').split('const shadowRows =')[0];
const cases=`
sources['archive_blackgold_v1.js']=fs.readFileSync(path.join(sourceRoot,'archive_blackgold_v1.js'),'utf8');
graph.splice(graph.indexOf('archive_180de7e38b_titles_compact_v6.js'),0,'archive_blackgold_v1.js');
const api=load();api.Open();
const rows=[{id:'clear_n1_1',name:'通关存档',count:0,target:1}];
snapshot('clear',100,rows);snapshot('shadow',100,[{id:'shadow_01',name:'幻象树枝',count:1,target:10}]);
api.SelectCategory('clear');
const first=cards()[0],glyphs=new Panel('Panel',first.__v10.name,'ArchiveFontV36Glyphs');
for(let i=0;i<500;i++){
 const glyph=new Panel('Panel',glyphs,'');
 glyph.BHasClass=()=>{throw Error('Theme/class lookup descended into font glyphs');};
}
const clearTab=nodes.get('ArchiveTab_clear');
api.SelectCategory('shadow');api.SelectCategory('clear');api.Filter('locked');api.Filter('all');
assert.equal(cards()[0],first,'Cached card survives category/filter changes');
assert.equal(nodes.get('ArchiveTab_clear'),clearTab,'Changing category retains navigation panels');
assert.equal(first.__v10.name.text,'通关存档');
assert.equal(glyphs.Children().length,500,'Visual lookup leaves cached glyphs untouched');
console.log('ARCHIVE_MENU_TRAVERSAL_PASS: retained tabs/cards and glyph subtrees excluded from theme/class walks');
`;
vm.runInNewContext(prefix+cases,{require:require('node:module').createRequire(fixture),__dirname,console},{filename:fixture});
