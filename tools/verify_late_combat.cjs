'use strict';
const fs=require('fs'),cp=require('child_process'),path=require('path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/late_combat_20261008/regression_final');fs.mkdirSync(out,{recursive:true});
const lua='C:/Program Files/lua/bin/lua5.1.exe';
const luaNames=[
 'test_combat_effect_visibility','test_combat_particle_lifecycle','test_damage_transaction_lifecycle','test_custom_monster_armor','test_boss_performance_filter',
 'test_tower_projectile_visual','test_tower_damage_observer','test_tower_skill_runtime','test_tower_skill_tree_exclusion','test_tower_attack_audio','test_tower_laser_visual','test_tower_laser_damage','test_tower_laser_health_prediction',
 'test_tower_visual_relocation','test_tower_destruction_rebuild','test_tower_target_selection','test_particle_cleanup_reentry','test_seven_sins_visuals',
 'test_combat_performance_capture','test_builder_io_presentation','test_builder_yield_construction','test_building_upgrade_lifecycle','test_tower_class_preflight',
 'test_production_ui_router','test_research_runtime_projection','test_research_production_auto','test_resource_ui_coalescing',
 'test_resource_opening_wood','test_lumberjack_fusion_runtime','test_lumberjack_fusion','test_lumberjack_fusion_ui','test_lumberjack_training_queue_integration',
 'test_hero_summon_runtime_availability','test_hero_summon_flow'
];
const nodeNames=['test_action_resources_tooltip.cjs','test_research_hud_completion.cjs','test_ability_tooltip_stability.cjs','test_ability_tooltip_recovery.cjs','test_grid_placement_client.cjs','test_world_overlay_visibility.cjs','test_world_health_bar.js','test_tower_rank_ui.cjs','test_worker_ability_visibility.cjs','test_hero_summon_initial_availability.cjs'];
const rows=[];
for(const [command,files,prefix] of [[lua,luaNames,'scripts/vscripts/tests/'],[lua,['test_scheduler_profile.lua','test_scheduler_replacement.lua','test_deadline_scheduler.lua'],'tools/'],[process.execPath,nodeNames,'tools/']]){
 for(const name of files){const relative=prefix+name+(prefix.startsWith('scripts')?'.lua':'');if(!fs.existsSync(path.join(root,relative))){rows.push({test:name,missing:true});continue;}
 const result=cp.spawnSync(command,[relative],{cwd:root,encoding:'utf8',windowsHide:true,timeout:60000,maxBuffer:8e6});
 const output=(result.stdout||'')+(result.stderr||'');fs.writeFileSync(path.join(out,name+'.log'),output);
 rows.push({test:name,exit_code:result.status,passed:result.status===0,error:result.error?.message});console.log((result.status===0?'PASS ':'FAIL ')+name);
 }
}
const report={created_at:new Date().toISOString(),scope:'Offline production Lua and Panorama regression; no FPS claims',tests:rows};
fs.writeFileSync(path.join(out,'results.json'),JSON.stringify(report,null,2));
console.log('REGRESSIONS',rows.filter(x=>x.passed).length+'/'+rows.length);
if(rows.some(x=>!x.passed))process.exitCode=1;
