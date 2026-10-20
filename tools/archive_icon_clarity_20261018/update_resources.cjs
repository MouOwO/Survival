'use strict';
// Item identity and original art stay centralized; only the texture encoding
// and its factual source dimensions change for the existing 23 shadow items.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),file=path.join(root,'data/ui/item_resources.json');
const table=JSON.parse(fs.readFileSync(file,'utf8'));
const report=path.join(root,'design_refs/archive_icon_clarity_20261018/resource_changes.json');
const prior=fs.existsSync(report)?JSON.parse(fs.readFileSync(report,'utf8')):{changes:[]};
const changes=[];
for(let i=1;i<=23;i++){
    const suffix=String(i).padStart(2,'0'),id='shadow_'+suffix,row=table.items.find(r=>r.id===id);
    assert(row,'Existing canonical item: '+id);
    const uri='s2r://panorama/images/custom_game/archive_icons_hd_v1/'+id+'.vtex';
    assert([uri,'file://{images}/custom_game/archive_v10/items/virtual_'+suffix+'.png'].includes(row.uri),'Unexpected concurrent art remap: '+id);
    const before=prior.changes.find(r=>r.id===id)?.before||JSON.parse(JSON.stringify(row));
    const after={...row,uri,source_size:[256,256]};
    assert(fs.existsSync(path.join(root,uri.slice(6)+'_c')),'Compiled texture must exist before changing registry: '+id);
    if(process.argv.includes('--check'))assert.deepEqual(row,after,'Canonical HD texture and factual dimensions: '+id);
    else Object.assign(row,after);
    changes.push({id,before,after});
}
if(!process.argv.includes('--check')){
    fs.writeFileSync(file,JSON.stringify(table,null,2)+'\n');
    fs.writeFileSync(report,JSON.stringify({scope:'23 original shadow images; no identity, price or gameplay changes',changes},null,2)+'\n');
}
console.log('ARCHIVE_ICON_CLARITY_REGISTRY_'+(process.argv.includes('--check')?'CHECK':'UPDATED')+' 23 items');
