'use strict';
// Formal CSV reward IDs/names/quantities with explicitly synthetic local progress.
const {csv}=require('../shop_ui_12h/catalog.cjs');
const files={items:'data/csv/存档系统/archive_daily_items.csv',schedule:'data/csv/存档系统/archive_daily_schedule.csv',rules:'data/csv/存档系统/archive_daily_rules.csv'};
function fixture(){
 const source={items:csv(files.items).filter(row=>row.enabled==='1'),schedule:csv(files.schedule).filter(row=>row.enabled==='1'),rules:csv(files.rules)[0]};
 const byId=Object.fromEntries(source.items.map(row=>[row.item_id,row]));
 const rewards=source.schedule.map(row=>({day:Number(row.day_id),rewards:row.item_ids.split('|').map((id,index)=>({id,name:byId[id].display_name,description:byId[id].description,quality:byId[id].quality,count:Number(row.item_counts.split('|')[index])}))}));
 if(rewards.length!==7||rewards.some((row,index)=>row.day!==index+1))throw Error('Expected current authoritative seven-step reward schedule.');
 const specials=source.rules.pass_item_ids.split('|').map((id,index)=>({id,day:Number(source.rules.pass_milestones.split('|')[index]),name:byId[id].display_name,description:byId[id].description,owned:0}));
 return {source:files,rewards,specials,rules:source.rules,runtimeValues:'Explicit browser-only progress, timestamps, entitlement and claim states; actual CSV rewards repeat on their original seven-claim cycle. No account or network.'};
}
module.exports={fixture};
