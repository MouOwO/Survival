// Move only the four cold spawn markers in the current saved Hammer snapshot.
'use strict';
const fs=require('fs'),crypto=require('crypto'),assert=require('assert/strict');
const L=require('../map_c6/lib.cjs');
const [input,output]=process.argv.slice(2);
assert(input&&output&&input!==output,'Usage: patch-cold-routes.cjs current-text.vmap patched-text.vmap');
const source=fs.readFileSync(input,'utf8');
assert(source.slice(0,100).includes('encoding keyvalues2'),'Input must be the current text DMX');
const layout=JSON.parse(fs.readFileSync('art/maps/mode_spawns/layout.json','utf8')).modes.cold;
const entities=L.blocks(source,'CMapEntity'),edits=[];
for(let id=0;id<4;id++){
 const name='mode_cold_monster_'+id+'_spawn',matches=entities.filter(b=>L.value(b.text,'targetname')===name);
 assert.equal(matches.length,1,'Missing/duplicate '+name);
 const [x,y,z]=layout.monsters[id],court=layout.player_bounds[id];
 assert(x>=layout.bounds[0]&&x<=layout.bounds[2]&&y>=layout.bounds[1]&&y<=layout.bounds[3]);
 assert(id%2===0?x<court[0]:x>court[2],'Arrow must approach its court from the opposite end');
 const block=matches[0],before=L.value(block.text,'origin'),after=[x,y,z+16].join(' ');
 edits.push({...block,text:L.setValue(block.text,'origin',after),name,before,after});
}
edits.sort((a,b)=>a.start-b.start);let cursor=0;const parts=[];
for(const edit of edits){parts.push(source.slice(cursor,edit.start),edit.text);cursor=edit.end;}
parts.push(source.slice(cursor));const result=parts.join('');
// Removing only those four entity blocks must leave exactly the original bytes.
const strip=(text)=>{const blocks=L.blocks(text,'CMapEntity').filter(b=>/^mode_cold_monster_[0-3]_spawn$/.test(L.value(b.text,'targetname')||''));
 let p=0;const out=[];for(const b of blocks){out.push(text.slice(p,b.start));p=b.end;}out.push(text.slice(p));return out.join('');};
assert.equal(strip(result),strip(source),'Unrelated map data changed');
fs.writeFileSync(output,result);
fs.writeFileSync(output+'.json',JSON.stringify({source_sha256:crypto.createHash('sha256').update(source).digest('hex'),
 markers:edits.map(({name,before,after})=>({name,before,after})),all_other_map_bytes_preserved:true},null,2)+'\n');
console.log('COLD_MAP_MARKERS_PASS: four arrow-tail markers; all terrain, navigation, meshes and unrelated entities byte-preserved');
