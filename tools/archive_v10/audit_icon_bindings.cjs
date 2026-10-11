'use strict';
// Read-only audit of active mappings, source dimensions and installed Valve resources.
// Writes evidence only under the ignored work directory, never changes UI or mappings.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../..'),work=path.join(root,'design_refs/archive_v10/work');
const {csv}=require(path.join(root,'tools/shop_ui_12h/catalog.cjs'));
const source=fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js'),'utf8');
const entries=JSON.parse(source.match(/entries=(\[[^\n]+\]);/)[1]);
const formal=csv(path.join(root,'data/csv/存档系统/archive_item_icons.csv')).filter(x=>x.enabled==='1');
function size(file){if(!fs.existsSync(file))return null;const b=fs.readFileSync(file);return b.subarray(1,4).toString()==='PNG'?[b.readUInt32BE(16),b.readUInt32BE(20)]:null;}
const images={};for(const e of entries){const file=path.join(root,'panorama/src/images',e.icon_path);if(!images[e.icon_path])images[e.icon_path]={path:e.icon_path,size:size(file),uri:e.runtime_uri,declared_size:[e.display_width,e.display_height],status:e.art_status};}
const categories=csv(path.join(root,'data/csv/存档系统/archive_categories.csv')).map(c=>{const rows=entries.filter(e=>e.category_id===c.category_id),paths=[...new Set(rows.map(e=>e.icon_path))];return {id:c.category_id,name:c.display_name,enabled:c.enabled,mapping_count:rows.length,unique_source_count:paths.length,sources:paths.map(p=>({path:p,count:rows.filter(e=>e.icon_path===p).length,first_ids:rows.filter(e=>e.icon_path===p).slice(0,5).map(e=>e.item_id),...images[p]}))};});
const mismatches=formal.map(e=>({key:e.category_id+':'+e.item_id,formal:e.icon_path,active:entries.find(x=>x.category_id===e.category_id&&x.item_id===e.item_id)?.icon_path})).filter(e=>e.formal!==e.active);
const {open}=require(path.join(root,'tools/vpk_inspect.cjs')),vpk=open(path.resolve(root,'../../dota/pak01_dir.vpk'));
const chosen=[...new Set(formal.filter(e=>e.art_status==='valve_native'||e.art_status==='valve_shop').map(e=>'panorama/images/'+e.icon_path.replace(/\.png$/,'_png.vtex_c')))];
for(const hero of ['axe','drow_ranger','sven','monkey_king','dragon_knight'])for(const dir of ['heroes','heroes/icons','heroes/selection'])chosen.push('panorama/images/'+dir+'/npc_dota_hero_'+hero+'_png.vtex_c');
for(const ability of ['attribute_bonus','alchemist_goblins_greed','alchemist_chemical_rage','chen_holy_persuasion','omniknight_guardian_angel','treant_living_armor','wisp_tether','lone_druid_spirit_bear'])chosen.push('panorama/images/spellicons/'+ability+'_png.vtex_c');
const native=[],viewer=path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'),nativeDir=path.join(work,'icon_audit_native');fs.mkdirSync(nativeDir,{recursive:true});
for(const resource of chosen){const entry=vpk.entries.find(e=>e.path===resource);if(!entry){native.push({resource,missing:true});continue;}const file=path.join(nativeDir,resource.replace(/[\\/]/g,'__'));fs.writeFileSync(file,vpk.read(entry));const text=cp.execFileSync(viewer,['-i',file,'-b','DATA'],{encoding:'utf8',windowsHide:true});const w=text.match(/^Width\s*=\s*(\d+)/m),h=text.match(/^Height\s*=\s*(\d+)/m);native.push({resource,size:w&&h?[Number(w[1]),Number(h[1])]:null,file:path.relative(root,file)});}
const localExamples=['custom_game/archive_portraits_v1/achievement_closeup.png','custom_game/archive_handoff_v1/art_01.png','spellicons/survival/native/portrait_drow_ranger.png','spellicons/survival/native/skill_drow_companion.png'].map(p=>({path:p,size:size(path.join(root,'panorama/src/images',p))}));
const report={generated_at:new Date().toISOString(),kind:'read_only_actual_icon_source_and_installed_vpk_audit',active_source:'panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js',categories,mapping_mismatches:mismatches,images:Object.values(images),native_resources:native,local_examples:localExamples};
fs.writeFileSync(path.join(work,'icon_binding_audit.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({categories:categories.map(c=>({id:c.id,mapped:c.mapping_count,unique:c.unique_source_count,sources:c.sources.slice(0,3).map(s=>({path:s.path,count:s.count,size:s.size}))})),mapping_mismatches:mismatches,native_resources:native,local_examples:localExamples},null,2));
