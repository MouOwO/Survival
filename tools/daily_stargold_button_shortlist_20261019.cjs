'use strict';
// Read-only Valve source extraction; output is an unmodified review asset gallery.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const {open}=require('./vpk_inspect.cjs');
const root=path.resolve(__dirname,'..'),base=path.join(root,'design_refs/daily_stargold_polish_20261019'),out=path.join(base,'assets');
const source=path.resolve(root,'../../dota/pak01_dir.vpk'),vpk=open(source),viewer=path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
const defs=[
 ['gold_weekly','dota_plus/weekly_reward_button_psd'],
 ['gold_shop','dota_plus/shop_button_bg_psd'],
 ['gold_column','dota_plus/column_button_psd'],
 ['gold_ti10_normal','compendium/international2020/tip_button_points_psd'],
 ['gold_ti10_hover','compendium/international2020/tip_button_points_hover_psd'],
 ['gold_ti19_normal','compendium/international2019/tip_button_points_psd'],
 ['gold_ti19_hover','compendium/international2019/tip_button_points_hover_psd'],
 ['gold_relic_rare','dota_plus/relic_rare_button_psd'],
 ['gold_diretide_wide','econ/diretide/chest_button_texture_wide_psd'],
 ['gold_diretide_unlock','econ/diretide/chest_button_texture_unlock_psd'],
 ['gold_hud_secondary','hud/button_thin_secondary_png'],
 ['gold_gray_normal','gray_button_off_png'],
 ['gold_gray_hover','gray_button_on_png'],
 ['gold_cavern','cavern/cavern_button_psd'],
 ['gold_ti26_slot','events/international_2026/artwork/cell_border_png'],
 ['gold_ti23_title','compendium/international2023/frontpage_title_border_psd'],
 ['gold_ti23_inner','compendium/international2023/rewardpage_innerborder_psd'],
 ['gold_ti23_outer','compendium/international2023/rewardpage_outerborder_wide_psd'],
 ['gold_ti10_corner','compendium/international2020/wriath_king_arcana/seal-left_corner_psd'],
 ['gold_bounty_border','hud/bounty_hunter/button_border_png'],
 ['gold_bounty_fill','hud/bounty_hunter/button_background_png'],
 ['gold_hud_buyback','hud/reborn/buyback_button_psd'],
 ['gold_hud_grab','hud/reborn/stash_grab_all_button_psd'],
 ['gold_hud_square','hud/button_square_brushed-1_png'],
 ['gold_relic_uni','dota_plus/relic_uni_button_psd'],
 ['gold_relic_frame','hero_relics/hero_relic_rare_border_normal_psd'],
 ['gold_diamonds','border_diamonds_png'],
 ['gold_crown_divider','events/crownfall/fishing/divider_graphic_minigame_png'],
 ['gold_crown_corner','events/crownfall/emblems/corner_border_png'],
 ['gold_crown_outline','events/crownfall/buttons/button_primary_outline_psd'],
 ['gold_crown_outline_edge','events/crownfall/buttons/button_primary_outline_edge_png'],
 ['gold_carnival_button','events/dark_carnival/buttons/button_border_png'],
];
fs.mkdirSync(out,{recursive:true});
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),records=[];
for(const [key,rel] of defs){
 const sourcePath='panorama/images/'+rel+'.vtex_c',entry=vpk.entries.find(e=>e.path===sourcePath);
 if(!entry)throw Error(sourcePath);
 const bytes=vpk.read(entry),input=path.join(out,key+'.vtex_c'),output=path.join(out,key+'.png');
 fs.writeFileSync(input,bytes);cp.execFileSync(viewer,['-i',input,'-o',output,'-d'],{windowsHide:true,stdio:'pipe'});
 const png=fs.readFileSync(output);
 records.push({key,vpkURI:'s2r://'+sourcePath.slice(0,-2),sourcePath,local:'assets/'+key+'.png',dimensions:{width:png.readUInt32BE(16),height:png.readUInt32BE(20)},hash:{source:sha(bytes),png:sha(png)},method:'Valve original VPK texture, exact native Source2Viewer decode, unmodified pixels'});
}
fs.writeFileSync(path.join(base,'provenance.json'),JSON.stringify({kind:'official_stargold_controls_shortlist',sourceArchive:source,productionFilesChanged:false,records},null,2));
console.log(JSON.stringify({status:'PASS',count:records.length,records:records.map(({key,local,dimensions})=>({key,local,dimensions}))}));
