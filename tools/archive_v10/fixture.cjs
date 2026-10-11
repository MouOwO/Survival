'use strict';
// Read-only formal definitions. Only runtime progress/ownership is synthetic.
const fs=require('fs'),path=require('path');
const {csv}=require('../shop_ui_12h/catalog.cjs');
const base='data/csv/存档系统/';
const enabled=name=>csv(base+name+'.csv').filter(r=>r.enabled==='1');
function fixture(){
 const icons=enabled('archive_item_icons'),iconBy=Object.fromEntries(icons.map(r=>[r.item_id,r.icon_path]));
 const sources={};
 const sample=i=>i%6===0?0:i%6===1?1:i%6===2?3:i%6===3?7:i%6===4?12:2;
 function project(category,file,mapper,filter=()=>true){sources[category]=base+file+'.csv';return enabled(file).filter(filter).map((r,i)=>{const item={id:r.item_id||r.achievement_id||r.level_id||r.fragment_id||r.reward_id||r.tier_id||r.title_id,name:r.display_name,description:r.description||'',icon_style:r.icon_style||'seal',quality:r.quality||'N',count:sample(i),count_known:1,...mapper(r,i)};if(iconBy[item.id])item.icon='file://{images}/'+iconBy[item.id];return item;});}
 const pages={};
 pages.clear=project('clear','archive_achievements',(r,i)=>({count:7,target:+r.required_count,completed:7>=+r.required_count?1:0,rune:String(r.difficulty_id).toUpperCase()}));
 pages.shadow=project('shadow','archive_shadow_items',r=>({target:+r.max_owned,max_owned:+r.max_owned}));
 pages.map_level=project('map_level','archive_map_levels',r=>({count:180,target:+r.required_seconds/60,completed:180>=+r.required_seconds/60?1:0,rune:r.level,description:'累计有效在线时长：'+(+r.required_seconds/3600)+'小时\n'+r.description}));
 pages.work=project('work','archive_work_items',(r,i)=>({count:i%4===0?1:0,level:i%4===0?1:0,target:+r.max_level,cost:+r.cost,can_upgrade:i%4===0?0:1,completed:i%4===0?1:0,description:r.description+'\n激活消耗：'+r.cost+'软妹币'}));
 pages.gift=project('gift','archive_welfare_rewards',r=>({count:8,target:+r.required_wins,completed:8>=+r.required_wins?1:0,progress_kind:r.progress_kind,unlock_condition:(r.progress_kind==='cooperative'?'与真人队友共同':'累计')+'胜利'+r.required_wins+'次'}));
 const fragmentLevels=enabled('archive_fragment_levels');
 pages.fragment=project('fragment','archive_fragment_definitions',(r,i)=>({count:sample(i)*20,level:sample(i),target:+r.max_owned,promotion_target:r.promotion_target,promotion_cost:+r.promotion_cost,can_promote:sample(i)*20>=+r.promotion_required_total?1:0,description:'当前Lv'+sample(i)+'，每'+r.fragments_per_level+'片晋升1级。\n'+fragmentLevels.filter(l=>l.fragment_id===r.fragment_id).map(l=>'Lv'+l.level+' '+l.description).join('\n')}));
 pages.pet=project('pet','archive_cage_items',r=>({target:+r.max_owned}));
 pages.boss=project('boss','archive_boss_achievements',r=>({count:40,target:+r.required_kills,completed:40>=+r.required_kills?1:0,unlock_condition:'累计挑战BOSS击杀'+r.required_kills+'次'}));
 pages.endless=project('endless','archive_endless_achievements',r=>({count:8500,target:+r.required_score,completed:8500>=+r.required_score?1:0,unlock_condition:'无尽累计积分达到'+r.required_score+'分'}));
 pages.building=project('building','archive_building_items',(r,i)=>({count:i%3,level:i%3,target:+r.max_level,cost:+r.cost,completed:0,can_upgrade:1,description:r.description+'\n当前等级：'+i%3+'/'+r.max_level+'\n每级消耗：'+r.cost+'信仰值'}));
 for(const category of ['friend','ex','beast'])pages[category]=project(category,'archive_social_items',r=>({target:+r.max_owned}),r=>r.pool_id===category);
 pages.fishing=project('fishing','archive_fishing_items',r=>({target:+r.max_owned}));
 pages.points=project('points','archive_daily_items',r=>({target:+r.max_owned}));
 const lottery=csv('data/csv/抽奖系统/lottery_item_definitions.csv').filter(r=>r.enabled==='1'&&r.item_type==='积分道具');
 pages.points.push(...lottery.map((r,i)=>({id:r.item_id,name:r.display_name,description:r.description,icon:r.icon,icon_type:r.icon_type,quality:r.quality,count:sample(i),count_known:1,target:+r.max_owned})));
 sources.points+=' + data/csv/抽奖系统/lottery_item_definitions.csv';
 pages.starjoy_points=project('starjoy_points','archive_starjoy_levels',r=>({count:500,target:+r.required_points,completed:500>=+r.required_points?1:0}));
 pages.titles=project('titles','archive_titles',(r,i)=>({count:i===0?1:0,completed:i===0?1:0,unlocked:i===0?1:0,equipped:0,target:1,icon:r.icon,condition:r.unlock_condition||r.condition||'',preview_only:0}));
 // Read-only inventory catalogue, no purchase action or invented reward.
 const content=csv('data/csv/物品系统/content_catalog.csv');
 pages.shop=content.filter(r=>r.enabled==='1'&&r.content_type!=='service').slice(0,32).map((r,i)=>({id:r.content_id,name:r.name,description:r.description,icon:r.icon,icon_type:r.icon.startsWith('item_')?'item':'ability',count:sample(i),count_known:1,quality:'N'}));
 sources.shop='data/csv/物品系统/content_catalog.csv (explicit local acquired catalogue samples; server integration separately verified)';
 const categories=enabled('archive_categories').map(r=>({id:r.category_id,name:r.display_name,renderer:r.renderer,order:+r.sort_order}));
 if(!categories.some(r=>r.id==='shop'))categories.push({id:'shop',name:'商城道具',renderer:'inventory',order:100});
 const social=Object.fromEntries(enabled('archive_social_rules').map(r=>[r.pool_id,{tickets:10,currency_name:r.currency_name,draw_cost:+r.draw_cost,remaining:100,total:7,unlocked:1}]));
 return {pages,categories,social,sources,runtimeValues:'Explicit local read-only samples, not real saves. Formal IDs, names, effects, targets and costs come from repository CSV, not package preview JSON.'};
}
module.exports={fixture};
if(require.main===module)console.log(JSON.stringify(fixture(),null,2));
