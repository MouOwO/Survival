'use strict';
// Compile only sources frozen in the reviewed production assembly.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');process.chdir(path.resolve(__dirname,'../..'));
const files=process.argv.slice(2);if(!files.length||new Set(files).size!==files.length)throw Error('Pass an explicit unique source list');
const out='design_refs/item_fill_20261017',visual=JSON.parse(fs.readFileSync(out+'/after/visual_report.json','utf8')),assembly=JSON.parse(fs.readFileSync(out+'/after/assembly.json','utf8'));
if(visual.status!=='PASS'||!visual.notGameCapture)throw Error('Actual-source browser preview must pass before compilation');
const rows=files.map(file=>{if(!/^(scripts|styles|layout)\/[A-Za-z0-9_./-]+\.(js|css|xml)$/.test(file)||file.includes('..'))throw Error('Unexpected source '+file);const sha256=crypto.createHash('sha256').update(fs.readFileSync('panorama/src/'+file)).digest('hex'),reviewed=assembly.sourceGraph.concat(assembly.additionalInactiveSources||[]).find(row=>row.path===file);if(!reviewed||reviewed.sha256!==sha256)throw Error('Source differs from screenshot assembly: '+file);return{path:file,sha256,active:!reviewed.reason};});
fs.writeFileSync(out+'/compile_plan.json',JSON.stringify({at:new Date().toISOString(),scope:'Exact native UI sources changed for item fill only',files:rows},null,2)+'\n');console.log('ITEM_FILL_COMPILE_PLAN '+rows.length+' sources');
