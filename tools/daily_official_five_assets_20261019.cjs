'use strict';
// Exact installed Valve texture extraction for a standalone review gallery.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const {open}=require('./vpk_inspect.cjs');
const repo=path.resolve(__dirname,'..'),base=path.join(repo,'design_refs/daily_official_five_20261019'),out=path.join(base,'assets');
const source=path.resolve(repo,'../../dota/pak01_dir.vpk'),vpk=open(source),viewer=path.join(repo,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
const defs=[
 ['crownfall','bg','events/crownfall/backgrounds/bg_png'],
 ['crownfall','bg_act3','events/crownfall/backgrounds/bg_act3_png'],
 ['crownfall','panel','events/crownfall/backgrounds/actiii_popup_background_png'],
 ['crownfall','header','events/crownfall/overworld/header_bg_fill_png'],
 ['crownfall','button','events/crownfall/buttons/button_primary_bg_psd'],
 ['crownfall','button_outline','events/crownfall/buttons/button_primary_outline_psd'],
 ['crownfall','button_secondary','events/crownfall/buttons/button_secondary_bg_psd'],
 ['crownfall','tab','events/crownfall/buttons/tab_background_png'],
 ['crownfall','frame','events/crownfall/dashboard/act_container_border_png'],
 ['crownfall','slot','events/crownfall/tokens/token_outer_border_png'],
 ['crownfall','corner','events/crownfall/emblems/corner_border_png'],
 ['crownfall','divider','events/crownfall/fishing/divider_graphic_minigame_png'],
 ['classic','bg','backgrounds/dashboard_background_ingame_psd'],
 ['classic','panel','hud/reborn/inventory_panel_png'],
 ['classic','button','backgrounds/background_play_button_2x_png'],
 ['classic','button_red','textures/glassbutton_red_hover_psd_1478a57f'],
 ['classic','button_teal','textures/glassbutton_teal_psd'],
 ['classic','header','textures/header_texture_png'],
 ['classic','header_cap','hud/reborn/header_endcap_psd'],
 ['classic','slot','hud/reborn/active_ability_border_psd'],
 ['classic','slot_active','hud/reborn/autocastable_ability_border_active_psd'],
 ['classic','side_panel','hud/reborn/statbranch_background_description_psd'],
 ['dpc','bg','backgrounds/generic_background_png'],
 ['dpc','header','dpc/supclub_header_bg_psd'],
 ['dpc','header_right','dpc/header_right_bg_psd'],
 ['dpc','team_header','dpc/team_header_bg_psd'],
 ['dpc','panel','compendium/international2020/home_block_backgrounds/silver_panel_psd'],
 ['dpc','button','textures/glassbutton_darkmoon_psd'],
 ['dpc','button_hover','textures/glassbutton_darkmoon_hover_psd'],
 ['dpc','slot','compendium/international2023/rewardpage_innerborder_psd'],
 ['dpc','frame','compendium/international2023/rewardpage_outerborder_wide_psd'],
 ['ti2026','bg','events/international_2026/backgrounds/ti2026_background_png'],
 ['ti2026','galaxy','events/international_2026/backgrounds/galaxy_background_home_png'],
 ['ti2026','panel','events/international_2026/backgrounds/talent_bundle_texture_standard_png'],
 ['ti2026','panel_gold','events/international_2026/backgrounds/talent_bundle_texture_gold_png'],
 ['ti2026','slot','events/international_2026/artwork/cell_border_png'],
 ['ti2026','button','dota_plus/shop_button_bg_psd'],
 ['ti2026','button_weekly','dota_plus/weekly_reward_button_psd'],
 ['ti2026','header','dota_plus/dota_plus_horizontal_banner_background_png'],
 ['ti2026','texture','dota_plus/dota_plus_background_texture_large_png'],
 ['carnival','bg','events/dark_carnival/backgrounds/sky_background_png'],
 ['carnival','panel','events/dark_carnival/splash/panel_background_png'],
 ['carnival','panel_border','events/dark_carnival/splash/panel_border_png'],
 ['carnival','frame','events/dark_carnival/overworld/inner_panel_border_png'],
 ['carnival','wood','events/dark_carnival/overworld/rewards_panel/wood_panel_large_png'],
 ['carnival','header','events/dark_carnival/overworld/panel_title_container_png'],
 ['carnival','button','events/dark_carnival/buttons/button_border_png'],
 ['carnival','button_fill','textures/glassbutton_pink_psd'],
 ['carnival','slot','events/dark_carnival/tokens/token_slot_border_psd'],
 ['carnival','divider','events/dark_carnival/postgame/rewards_divider_png'],
 ['carnival','tooltip','events/dark_carnival/textures/tooltip_background_png'],
 ['shared','check','control_icons/check_png'],
 ['shared','check_glow','control_icons/check_gradient_png'],
 ['shared','lock','control_icons/lock_large_png'],
 ['shared','close','control_icons/x_close_png'],
 ['shared','plus','control_icons/plus_png'],
 ['shared','gold_panel','compendium/international2020/home_block_backgrounds/gold_panel_psd'],
 ['shared','reward_ring','cavern/reward_ring_fg_psd'],
 ['shared','reward_ring_bg','cavern/reward_ring_bg_psd'],
];
fs.mkdirSync(out,{recursive:true});
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),records=[];
for(const [theme,key,relative] of defs){
 const resource='panorama/images/'+relative+'.vtex_c',entry=vpk.entries.find(e=>e.path===resource);
 if(!entry)throw Error('Missing official asset '+resource);
 const stem=theme+'_'+key,input=path.join(out,stem+'.vtex_c'),output=path.join(out,stem+'.png'),bytes=vpk.read(entry);
 fs.writeFileSync(input,bytes);cp.execFileSync(viewer,['-i',input,'-o',output,'-d'],{windowsHide:true,stdio:'pipe'});
 const png=fs.readFileSync(output),width=png.readUInt32BE(16),height=png.readUInt32BE(20);
 records.push({key:stem,theme,role:key,original:resource,vpkURI:'s2r://'+resource.slice(0,-2),local:'assets/'+stem+'.png',dimensions:{width,height},hash:{source:sha(bytes),png:sha(png)},method:'Source2Viewer exact native texture decode at original resolution; no visual editing'});
}
const manifest={kind:'installed_dota_official_daily_rewards_preview_assets',sourceArchive:source,productionFilesChanged:false,count:records.length,records};
fs.writeFileSync(path.join(base,'native_assets.json'),JSON.stringify(manifest,null,2));
const esc=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const sections=[...new Set(records.map(r=>r.theme))].map(t=>'<h2>'+t+'</h2><div class="grid">'+records.filter(r=>r.theme===t).map(r=>'<article><div class="image"><img src="'+r.local+'"></div><strong>'+r.key+'</strong><small>'+r.dimensions.width+' × '+r.dimensions.height+'</small><code>'+esc(r.vpkURI)+'</code></article>').join('')+'</div>').join('');
fs.writeFileSync(path.join(base,'native_asset_sheet.html'),'<!doctype html><meta charset="utf-8"><title>Official Dota asset selection</title><style>*{box-sizing:border-box}body{background:#171b21;color:#e3e7ec;font:16px Arial;padding:30px}h2{margin-top:50px}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}article{padding:12px;border:1px solid #68717c;background:#242b34}.image{height:200px;display:flex;align-items:center;justify-content:center;background:repeating-conic-gradient(#30343b 0 25%,#252930 0 50%) 0/20px 20px}img{max-width:100%;max-height:100%;object-fit:contain}strong,small,code{display:block;margin-top:10px}code{font-size:10px;overflow-wrap:anywhere}</style><h1>官方 Dota 原始组件 · 五套每日奖励方案素材</h1><p>所有图片均从本机 Valve VPK 原尺寸解码，未重绘。</p>'+sections);
console.log(JSON.stringify({status:'PASS',count:records.length,records:records.map(({key,dimensions,local})=>({key,...dimensions,local})),manifest:path.relative(repo,path.join(base,'native_assets.json'))}));
