'use strict';
// Formal catalogue and art, explicitly synthetic local progress. No account I/O.
const path=require('path'),{csv}=require('../shop_ui_12h/catalog.cjs');
const repo=path.resolve(__dirname,'../..');
function fixture(){
 const read=name=>csv(path.join(repo,'data/csv/存档系统',name+'.csv')).filter(row=>row.enabled==='1');
 const iconBy=Object.fromEntries(read('archive_item_icons').map(row=>[row.item_id,row.icon_path]));
 const definitions=read('archive_social_items'),rules=read('archive_social_rules');
 const pages={},social={};
 for(const category of ['ex','friend','beast']){
  pages[category]=definitions.filter(row=>row.pool_id===category).map((row,index)=>({id:row.item_id,name:row.display_name,description:row.description,quality:row.quality,count:Math.min(+row.max_owned,[0,1,3,7,12,2][index%6]),count_known:1,target:+row.max_owned,max_owned:+row.max_owned,icon:'file://{images}/'+iconBy[row.item_id]}));
  const rule=rules.find(row=>row.pool_id===category),total=pages[category].reduce((sum,row)=>sum+row.count,0),remaining=pages[category].reduce((sum,row)=>sum+row.target-row.count,0);
  social[category]={tickets:10,currency_name:rule.currency_name,draw_cost:+rule.draw_cost,remaining,total,unlocked:total>=+rule.unlock_count?1:0};
 }
 const categories=read('archive_categories').map(row=>({id:row.category_id,name:row.display_name,renderer:row.renderer,order:+row.sort_order}));
 return {pages,social,categories,tabs:[{id:'ex',name:'前女友'},{id:'friend',name:'前男友'},{id:'wife',name:'老婆',configured:false},{id:'beast',name:'瑞兽赐福'}],runtimeValues:'Explicit isolated sample ownership, currency, unlock and sequence values; never a real player save. Wife is intentionally unconfigured and has no server pool or request.',source:['data/csv/存档系统/archive_social_items.csv','data/csv/存档系统/archive_social_rules.csv','data/csv/存档系统/archive_item_icons.csv','data/csv/存档系统/archive_categories.csv']};
}
module.exports={fixture};
if(require.main===module)console.log(JSON.stringify(fixture(),null,2));
