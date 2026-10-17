'use strict';
// Actual collection component + formal catalogue. Only server replies are fixtures.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{spawnSync}=require('child_process');
const out='design_refs/collection_glow_20261015/preview';
const built=spawnSync(process.execPath,['tools/collection_gw2/preview.cjs','--out',out],{encoding:'utf8',windowsHide:true});
if(built.status!==0)throw Error(built.stdout+built.stderr);if(built.stdout)process.stdout.write(built.stdout);
const cssPath=path.join(out,'style.css'),css=fs.readFileSync(cssPath,'utf8');
const matches=[...css.matchAll(/@keyframes\s+(['"])([^'"]+)\1/g)];
fs.writeFileSync(cssPath,css.replace(/@keyframes\s+(['"])([^'"]+)\1/g,'@keyframes $2'));
const state=String.raw`'use strict';
window.glowDrawCalls=()=>previewCalls.filter(call=>call.name==='survival_archive_social_draw');
window.glowReady=previewReady.then(value=>{if(!value)return false;window.glowSamples=[];window.glowAddedLabels=[];window.glowMutations=new MutationObserver(records=>{for(const record of records)for(const node of record.addedNodes){if(!(node instanceof Element))continue;for(const label of [node,...node.querySelectorAll('.label')])if(label.classList.contains('label'))glowAddedLabels.push(label.textContent)}});glowMutations.observe(nodes.CollectionGW2Canvas.el,{subtree:true,childList:true});return true});
window.glowReceiveWin=function(targetId,ackFirst=true){
 const request=glowDrawCalls().at(-1);if(!request)throw Error('Click the actual Draw button first');
 const category=request.payload.pool_id,rows=JSON.parse(JSON.stringify(collectionPreviewPages[category]));
 const target=rows.find(row=>row.id===targetId);if(!target)throw Error('Target not in formal visible category');
 const before=Number(target.count);if(before>=Number(target.target))throw Error('Target already at cap');target.count=before+1;
 const packet=collectionPreviewSnapshot(category);packet.rows=rows;packet.revision=packet.sequence;
 packet.social={...packet.social,tickets:packet.social.tickets-packet.social.draw_cost,total:packet.social.total+1,remaining:packet.social.remaining-1};
 packet.last_draw={id:'offline_collection:social_draw:'+request.payload.request_id,pool_id:category,name:target.name,item_id:target.id};
 const ack={ok:1,terminal:1,pool_id:category,request_id:request.payload.request_id,revision:packet.revision};
 window.glowIntent={category,targetId,name:target.name,before,after:target.count,request_id:request.payload.request_id,packet,ack};
 collectionPreviewPages[category]=rows;
 window.glowSamples=[];window.glowStarted=performance.now();
 if(ackFirst){emit('survival_archive_social_result',ack);emit('survival_archive_snapshot',packet)}else{emit('survival_archive_snapshot',packet);emit('survival_archive_social_result',ack)}
 syncLayout();
 function sample(){const target=nodes['CollectionGW2Item_'+targetId],glow=target&&target.el.querySelector('.CollectionGW2RewardGlow'),elapsed=performance.now()-glowStarted;glowSamples.push({elapsed,opacity:glow?Number(getComputedStyle(glow).opacity):null,highlight:!!target&&target.BHasClass('CollectionGW2RewardHighlight')});if(elapsed<1450)requestAnimationFrame(sample)}
 requestAnimationFrame(sample);
 return {category,targetId,name:target.name,before,after:target.count,request_id:request.payload.request_id};
};
`;
fs.writeFileSync(path.join(out,'glow_fixture.js'),state);
const htmlPath=path.join(out,'index.html');let html=fs.readFileSync(htmlPath,'utf8');html=html.replace('</html>','<script src="glow_fixture.js"></script></html>');fs.writeFileSync(htmlPath,html);
const file=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(file,'utf8'));
assembly.kind='production_collection_winning_cell_glow_browser_preview';
assembly.glowAdapter={keyframeNamesUnquotedForChrome:matches.map(match=>match[2]),animationValuesUnchanged:true,staticHighlightClassForced:false};
assembly.glowProtocol='Actual production Draw sends an in-memory request, then matching request_id/pool/last_draw plus authoritative count+1 snapshot triggers production finishDraw. No real draw, save, account or network.';
assembly.glowFixtureSource=['tools/collection_glow_20261015/preview.cjs',...require('../collection_gw2/fixture.cjs').fixture().source].map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}));
fs.writeFileSync(file,JSON.stringify(assembly,null,2));
console.log('COLLECTION_GLOW_PREVIEW '+out);
