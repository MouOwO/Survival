'use strict';
// Formal catalogue and art, explicitly synthetic local progress. No account I/O.
const path=require('path'),{csv}=require('../shop_ui_12h/catalog.cjs');
const repo=path.resolve(__dirname,'../..');
// Preview-only probabilities for the explicitly synthetic inventory below.
// Production always uses the authoritative row fields returned by the server.
function rarityProbabilities(rows,rule,initial=false){
 const qualities=['N','R','SR','SSR','UR'],remaining={},weights={};
 for(const quality of qualities){remaining[quality]=rows.filter(row=>row.draw_enabled!==0&&row.quality===quality).reduce((sum,row)=>sum+Math.max(0,row.target-(initial?0:row.count)),0);weights[quality]=remaining[quality]>0?Number(rule['quality_weight_'+quality.toLowerCase()])||0:0;}
 const total=qualities.reduce((sum,quality)=>sum+weights[quality],0);
 return rows.map(row=>{const left=row.draw_enabled===0?0:Math.max(0,row.target-(initial?0:row.count)),tier=total?weights[row.quality]/total:0;return {item:left&&remaining[row.quality]?tier*left/remaining[row.quality]:0,tier};});
}
function fixture(){
 const read=name=>csv(path.join(repo,'data/csv/存档系统',name+'.csv')).filter(row=>row.enabled==='1');
 const iconBy=Object.fromEntries(read('archive_item_icons').map(row=>[row.item_id,row.icon_path]));
 const definitions=read('archive_social_items'),rules=read('archive_social_rules');
 const pages={},social={};
 for(const category of ['ex','friend','wife','beast']){
  const rule=rules.find(row=>row.pool_id===category);
  if(!rule)continue;
  const poolRows=definitions.filter(row=>row.pool_id===category);
  if(category==='wife')poolRows.sort((a,b)=>a.item_id<b.item_id?-1:a.item_id>b.item_id?1:0);
  // Leave one enabled UR unowned so a real pointer can inspect its positive
  // current probability; other sample rows still exercise capped/zero states.
  const firstUR=poolRows.findIndex(row=>row.quality==='UR'&&row.draw_enabled!=='0');
  pages[category]=poolRows.map((row,index)=>({id:row.item_id,name:row.display_name,description:row.description,quality:row.quality,count:row.draw_enabled==='0'||index===firstUR?0:Math.min(+row.max_owned,[0,1,3,7,12,2][index%6]),count_known:1,target:+row.max_owned,max_owned:+row.max_owned,draw_enabled:row.draw_enabled==='0'?0:1,availability_note:row.availability_note||'',icon:'file://{images}/'+iconBy[row.item_id]}));
  const current=rarityProbabilities(pages[category],rule),initial=rarityProbabilities(pages[category],rule,true);
  pages[category].forEach((row,index)=>Object.assign(row,{draw_probability:current[index].item,initial_draw_probability:initial[index].item,quality_draw_probability:current[index].tier}));
  const total=pages[category].reduce((sum,row)=>sum+row.count,0),remaining=pages[category].filter(row=>row.draw_enabled!==0).reduce((sum,row)=>sum+row.target-row.count,0);
  social[category]={tickets:10,currency_name:rule.currency_name,draw_cost:+rule.draw_cost,remaining,total,unlocked:total>=+rule.unlock_count?1:0};
 }
 const categories=read('archive_categories').map(row=>({id:row.category_id,name:row.display_name,renderer:row.renderer,order:+row.sort_order}));
 return {pages,social,categories,tabs:[{id:'ex',name:'前女友'},{id:'friend',name:'前男友'},{id:'wife',name:'老婆',configured:!!social.wife},{id:'beast',name:'瑞兽赐福'}],runtimeValues:'Explicit isolated sample ownership, currency, unlock and sequence values; never a real player save. Every configured pool is read from the formal CSV catalogue.',source:['data/csv/存档系统/archive_social_items.csv','data/csv/存档系统/archive_social_rules.csv','data/csv/存档系统/archive_item_icons.csv','data/csv/存档系统/archive_categories.csv']};
}
module.exports={fixture,rarityProbabilities};
if(require.main===module)console.log(JSON.stringify(fixture(),null,2));
