'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const cfg={},jobs=[],created=[];
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/ui_snapshot_cache.js','utf8'),{
    GameUI:{CustomUIConfig:()=>cfg},$:{Schedule:(_,fn)=>jobs.push(fn),GetContextPanel:()=>({}),
        CreatePanel(type,parent,id,attributes){const node={type,parent,attributes,style:{},IsValid:()=>true,SetImage(uri){this.uri=uri;}};created.push(node);return node;}}
});
const cache=cfg.SurvivalSnapshotCache,uri='s2r://panorama/images/custom_game/archive_gpu_regular/portrait_achievement_closeup.vtex';
for(let i=0;i<200;i++)cache.WarmImage(uri);
cache.WarmImage(undefined);cache.WarmImage('https://example.invalid/image.png');
for(let i=0;i<12;i++)cache.WarmImage('file://{images}/custom_game/icon_'+i+'.png');
assert.equal(created.length,0,'Receipt handling queues image work without decoding synchronously');
jobs.shift()();assert.equal(created.filter(n=>n.type==='Image').length,6,'One batch has a bounded image count');
while(jobs.length)jobs.shift()();
const images=created.filter(n=>n.type==='Image');
assert.equal(images.length,13,'Repeated items and snapshots keep exactly one image per URI');
assert.equal(images.filter(n=>n.uri===uri).length,1);
assert(images.every(n=>n.style.width==='128px'&&n.style.height==='128px'),'Warmup requests card-sized textures');
assert.equal(cfg.SurvivalSnapshotCache.Apply({rows:[{count:0}]},[{path:['rows','1','count'],value:3}]).rows[0].count,3);
console.log('ARCHIVE_MENU_WARMUP_PASS: URI deduplication, bounded batches, local images, unchanged data deltas');
