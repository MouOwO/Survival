'use strict';
// Freeze the exact reviewed source list before writing content / runtime files.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const repo=path.resolve(__dirname,'../../..');process.chdir(repo);
const files=process.argv.slice(2);if(!files.length)throw Error('Pass explicit scripts/styles/layout paths relative to panorama/src.');
const distinct=[...new Set(files)];if(distinct.length!==files.length)throw Error('Duplicate source argument.');
const evidence='design_refs/item_resources_20261016/build/',visual=JSON.parse(fs.readFileSync(evidence+'visual_report.json','utf8')),assembly=JSON.parse(fs.readFileSync(evidence+'preview/assembly.json','utf8'));
if(visual.status!=='PASS'||!visual.notGameCapture)throw Error('Reviewed production component preview must pass first.');
const rows=files.map(file=>{if(!/^(scripts|styles|layout)\/[A-Za-z0-9_./-]+\.(js|css|xml)$/.test(file)||file.includes('..'))throw Error('Unexpected source '+file);const sha256=crypto.createHash('sha256').update(fs.readFileSync('panorama/src/'+file)).digest('hex'),reviewed=assembly.sourceGraph.find(row=>row.path===file);if(!reviewed||reviewed.sha256!==sha256)throw Error('Source differs from reviewed screenshot assembly: '+file);return {path:file,sha256};});
const output='design_refs/item_resources_20261016/build/compile_plan.json';fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,JSON.stringify({at:new Date().toISOString(),scope:'Explicit shared resource consumers changed by this task only',files:rows},null,2)+'\n');
console.log('ITEM_RESOURCE_COMPILE_PLAN '+rows.length+' sources '+output);
