'use strict';
// Read-only archive navigation/inspection. No reward, purchase or account mutation.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const repo=path.resolve(__dirname,'../..'),log=path.resolve(repo,'../../dota/console.log');
const action=process.argv[2]||'audit';
if(!['category points','category commerce_goods','scroll bottom','scroll top','audit','dump','close'].includes(action))throw Error('Read-only archive action required');
const generations=[...fs.readFileSync(log,'utf8').matchAll(/ARCHIVE_DIAGNOSTIC archive_view_dump_([0-9]+)/g)];
if(!generations.length)throw Error('No running archive diagnostic generation');
const generation=generations.at(-1)[1],offset=fs.statSync(log).size;
const command=action==='dump'?'archive_view_dump_'+generation:'archive_view_action_'+generation+' '+action;
const result=spawnSync(process.execPath,[path.join(repo,'tools/map_c6/console.cjs'),command,'--timeout-ms','500'],{cwd:repo,encoding:'utf8',windowsHide:true,timeout:6000,maxBuffer:2*1024*1024});
if(result.status!==0)throw Error('Local console navigation failed: '+(result.error?.code||result.status));
setTimeout(()=>{
 const bytes=fs.readFileSync(log),tail=bytes.subarray(Math.min(offset,bytes.length)).toString('utf8');
 const markers=tail.split(/\r?\n/).filter(line=>/ARCHIVE_(VIEW|V10_VIEW|AUDIT|ACTION_ARGS) /.test(line));
 const report={at:new Date().toISOString(),action,consoleSuccess:true,markers};
 const out=path.join(repo,'design_refs/points_goods_unique_20261018/native');fs.mkdirSync(out,{recursive:true});
 fs.writeFileSync(path.join(out,action.replaceAll(' ','_')+'.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({action,consoleSuccess:true,markers:markers.length,view:markers.map(line=>{const m=line.match(/ARCHIVE_(?:V10_VIEW|VIEW|AUDIT) (\{.*\})/);if(!m)return null;try{const d=JSON.parse(m[1]);return {category:d.category,layout:d.layout,open:d.open,rows:Array.isArray(d.rows)?d.rows.length:d.rows,first:Array.isArray(d.rows)?d.rows[0]?.id:undefined,last:Array.isArray(d.rows)?d.rows.at(-1)?.id:undefined,grid:d.grid?.slice(0,1),window:d.window};}catch{return null;}}).filter(Boolean)}));
},350);
