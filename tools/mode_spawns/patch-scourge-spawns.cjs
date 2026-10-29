// Apply only eight spawn-marker origins to a current saved Hammer snapshot.
'use strict';
const fs=require('fs'),crypto=require('crypto'),assert=require('assert/strict');
const L=require('../map_c6/lib.cjs');
const [input,output]=process.argv.slice(2);
assert(input&&output&&input!==output,'Usage: patch-scourge-spawns.cjs current-text.vmap patched-text.vmap');
const source=fs.readFileSync(input,'utf8');
assert(source.slice(0,100).includes('encoding keyvalues2'));
const row=JSON.parse(fs.readFileSync('art/maps/mode_spawns/layout.json','utf8')).modes.scourge;
const entities=L.blocks(source,'CMapEntity'),edits=[];
for(const [kind,points] of [['player',row.players],['monster',row.monsters]])for(let id=0;id<4;id++){
 const name=`mode_scourge_${kind}_${id}_spawn`,matches=entities.filter(b=>L.value(b.text,'targetname')===name);
 assert.equal(matches.length,1,'Missing/duplicate '+name);
 const block=matches[0],p=points[id],before=L.value(block.text,'origin'),after=[p[0],p[1],p[2]+16].join(' ');
 edits.push({...block,text:L.setValue(block.text,'origin',after),name,before,after});
}
edits.sort((a,b)=>a.start-b.start);let cursor=0;const parts=[];
for(const edit of edits){parts.push(source.slice(cursor,edit.start),edit.text);cursor=edit.end;}
parts.push(source.slice(cursor));const result=parts.join('');
// Reverse the eight origin substitutions to prove every other byte survives.
let restored=result;
for(const edit of edits){const block=L.blocks(restored,'CMapEntity').find(b=>L.value(b.text,'targetname')===edit.name);
 restored=restored.slice(0,block.start)+L.setValue(block.text,'origin',edit.before)+restored.slice(block.end);}
assert.equal(restored,source,'Unrelated map data changed');
fs.writeFileSync(output,result);
fs.writeFileSync(output+'.json',JSON.stringify({source_sha256:crypto.createHash('sha256').update(source).digest('hex'),
 markers:edits.map(({name,before,after})=>({name,before,after})),all_other_map_bytes_preserved:true},null,2)+'\n');
console.log('SCOURGE_MAP_MARKERS_PASS: eight origins changed; terrain, navigation and all unrelated bytes preserved');
