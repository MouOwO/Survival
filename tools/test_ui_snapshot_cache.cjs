const fs=require('fs'),vm=require('vm'),assert=require('assert');const cfg={};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/ui_snapshot_cache.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
const base={rows:[{id:'a',count:0},{id:'b',count:5}],online:{seconds:2}};
const result=cfg.SurvivalSnapshotCache.Apply(base,[{path:['rows','2','count'],value:6},{path:['online','seconds'],value:3}]);
assert.equal(result.rows[1].count,6);assert.equal(result.rows[0].id,'a');assert.equal(base.rows[1].count,5);
const removed=cfg.SurvivalSnapshotCache.Apply(result,[{path:['rows','2'],remove:1}]);assert.equal(removed.rows.length,1);
const object=cfg.SurvivalSnapshotCache.Apply({rows:{'1':{count:2}}},[{path:{'1':'rows','2':'1','3':'count'},value:4}]);assert.equal(object.rows['1'].count,4);
console.log('UI_SNAPSHOT_CACHE_PASS: sparse patches, Lua indices, arrays, object packets, deletion and immutable baseline');
