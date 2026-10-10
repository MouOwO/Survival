'use strict';
const fs=require('fs'),path=require('path');
const files=['panorama/src/layout/custom_game/archive.xml','panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js'];
for(const file of files){const dest='design_refs/void_shadow_v1/work/checkpoint/source/'+file;fs.mkdirSync(path.dirname(dest),{recursive:true});if(!fs.existsSync(dest))fs.copyFileSync(file,dest);}
function change(file,edits){let source=fs.readFileSync(file,'utf8').replaceAll('\r\n','\n');for(const [from,to]of edits){if(!source.includes(from))throw Error('Integration anchor absent: '+from.slice(0,80));source=source.replace(from,to);}fs.writeFileSync(file,source);}
if(!fs.readFileSync(files[0],'utf8').includes('archive_void_v1_data.js'))change(files[0],[['</styles>','<include src="file://{resources}/styles/custom_game/archive_void_v1.css" /></styles>'],['<include src="file://{resources}/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js" />','<include src="file://{resources}/scripts/custom_game/archive_void_v1_data.js" /><include src="file://{resources}/scripts/custom_game/archive_void_v1.js" /><include src="file://{resources}/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js" />']]);
change(files[1],[
 ['    function tabs() {','    var archiveFit={reference:[1920,1080]};\n    function renderVoid(data){return cfg.SurvivalArchiveVoidV1&&cfg.SurvivalArchiveVoidV1.Render(data,current,filterMode,categories,archiveFit);}\n    function tabs() {'],
 ['                tabs();\n                // Coalesce fast toggle changes','                tabs();\n                renderVoid(null);\n                // Coalesce fast toggle changes'],
 ['        tabs();\n        var social = data.social','        tabs();\n        if(renderVoid(data))return;\n        var social = data.social'],
 ['        opened = false; fitGeneration++;','        opened = false; fitGeneration++;\n        if(cfg.SurvivalArchiveVoidV1)cfg.SurvivalArchiveVoidV1.Leave();'],
 ['        if(purpleShell&&purpleShell.Dispose)purpleShell.Dispose();','        if(purpleShell&&purpleShell.Dispose)purpleShell.Dispose();\n        if(cfg.SurvivalArchiveVoidV1)cfg.SurvivalArchiveVoidV1.Dispose();'],
 ['width:1280,height:800,fit:{reference:[1920,1080]},onClose:close','width:1280,height:800,fit:archiveFit,onClose:close'],
 ['}else request(true);','}else {renderVoid(null);request(true);}'],
 ['filterMode=mode;if(lastData)render(lastData);','filterMode=mode;if(lastData)render(lastData);else renderVoid(null);']
]);
console.log('VOID_PAGE_WIRED');
