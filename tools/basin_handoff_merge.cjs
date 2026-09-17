// Replace generated groups while preserving the user's saved nodes byte-for-byte.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
function end(s,start,op,cl){let d=0,q=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')q=!q;if(!q){if(s[i]===op)d++;if(s[i]===cl&&--d===0)return i;}}throw Error('Unbalanced VMAP');}
function worldChildren(s){const w=s.indexOf('"world" "CMapWorld"');if(w<0)throw Error('World absent');const a=s.indexOf('[',s.indexOf('"children" "element_array"',w)),b=end(s,a,'[',']');let cursor=a+1;const nodes=[];while(cursor<b){const start=s.indexOf('"',cursor);if(start<0||start>=b)break;const body=s.indexOf('{',start);if(body<0||body>=b)throw Error('Invalid child');const stop=end(s,body,'{','}');nodes.push(s.slice(start,stop+1));cursor=stop+1;}return{a,b,nodes};}
function name(n){return n.slice(0,n.indexOf('"children"')).match(/"name"\s+"string"\s+"([^"]+)"/)?.[1]||'';}
function managed(n){return n.startsWith('"CMapDotaTileGrid"')||/^AI_0[123]_/.test(name(n));}
function merge(base,old){
 if(!old)return{source:base,preserved:0};
 const b=worldChildren(base),o=worldChildren(old),kept=o.nodes.filter(n=>!managed(n));
 if(!o.nodes.some(n=>name(n)==='USER_90_DETAILS'))throw Error('User detail group absent: do not guess ownership; keep file unchanged');
 const max=Math.max(0,...kept.flatMap(s=>[...s.matchAll(/"nodeID"\s+"int"\s+"(\d+)"/g)].map(m=>Number(m[1]))));let id=max+1000;
 const generated=b.nodes.filter(managed).map(s=>s.replace(/("nodeID"\s+"int"\s+")\d+/g,(_,p)=>p+id++));
 const source=base.slice(0,b.a+1)+'\n'+generated.concat(kept).join(',\n')+'\n'+base.slice(b.b);
 for(const n of kept)if(!source.includes(n))throw Error('User node changed');
 return{source,preserved:kept.length,preservedSha256:crypto.createHash('sha256').update(kept.join('\n')).digest('hex')};
}
module.exports={worldChildren,name,merge};
if(require.main===module){
 const root=path.resolve(__dirname,'..'),out=path.join(root,'output/basin_review'),target=process.argv[2];if(!target)throw Error('Explicit existing/new editable map path required');
 const base=fs.readFileSync(path.join(out,'survival_basin_review.vmap'),'utf8'),old=fs.existsSync(target)?fs.readFileSync(target,'utf8'):null,result=merge(base,old);
 if(old){const backup=path.join(out,'handoff_backups');fs.mkdirSync(backup,{recursive:true});fs.writeFileSync(path.join(backup,'survival_basin_edit_'+Date.now()+'.vmap'),old);}
 fs.writeFileSync(target,result.source);fs.writeFileSync(path.join(out,'handoff_merge.json'),JSON.stringify({target,preserved:result.preserved,hash:result.preservedSha256,updatedAt:new Date().toISOString()},null,2));console.log('Editable map updated; preserved root nodes:',result.preserved);
}
