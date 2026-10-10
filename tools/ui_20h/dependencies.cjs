'use strict';const fs=require('fs');const seen=new Set();
function visit(rel){if(seen.has(rel))return;const p='panorama/src/'+rel;if(!fs.existsSync(p))throw Error('Missing UI source '+p);seen.add(rel);const s=fs.readFileSync(p,'utf8');if(rel.endsWith('.xml'))for(const m of s.matchAll(/<include\s+src="file:\/\/\{resources\}\/([^"]+)"/g))visit(m[1]);}
for(const p of ['layout/custom_game/survival_hud.xml','layout/custom_game/archive.xml'])visit(p);
fs.writeFileSync('design_refs/ui_20h/work/dependencies.json',JSON.stringify([...seen],null,2));console.log('UI20H_SOURCE_GRAPH',seen.size);
