'use strict';
const fs=require('fs'),L=require('./lib.cjs');
const t=fs.readFileSync('output/valley_reference_v3/node.txt','utf8');
function array(t,k){let p=t.indexOf(k+' =');if(p<0)return '';p=t.indexOf('[',p);return t.slice(p,L.endOf(t,p,'[',']'));}
function children(t){const out=[];for(let p=1;p<t.length;){if(t[p]==='{'){const e=L.endOf(t,p);out.push(t.slice(p,e));p=e;}else p++;}return out;}
const groups=children(array(t,'m_aggregateSceneObjects')).map(g=>{
 const model=g.match(/m_renderableModel = resource:"([^"]+)"/)?.[1];
 const parts=children(array(g,'m_aggregateMeshes'));
 const transforms=[...array(g,'m_fragmentTransforms').matchAll(/\[([^\[\]]+)\]/g)].map(m=>m[1].split(',').map(s=>s.trim()).filter(Boolean).map(Number));
 let ti=0;const instances=parts.map(p=>({draw:+p.match(/m_nDrawCallIndex = (\d+)/)?.[1],tint:p.match(/m_vTintColor = \[([^\]]+)\]/)?.[1].split(',').map(Number),transform:p.includes('m_bHasTransform = true')?transforms[ti++]:null}));
 return {model,instances};
});
fs.writeFileSync('output/valley_reference_v3/instances.json',JSON.stringify(groups,null,2));
console.log(groups.filter(g=>/prop/.test(g.model)).map(g=>({model:g.model.split('/').pop(),count:g.instances.length,transformed:g.instances.filter(i=>i.transform).length,draws:[...new Set(g.instances.map(i=>i.draw))].length})).filter(g=>!/cliff|bush_ti10|column/.test(g.model)));
