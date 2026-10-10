'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const base='design_refs/purple_ui_10h/work',name=process.argv[2];
if(!name||!/^[a-zA-Z0-9_]+$/.test(name))throw Error('Provide a unique checkpoint name');
const output=base+'/checkpoints/'+name;if(fs.existsSync(output))throw Error('Checkpoint already exists');
const files=[
 'layout/custom_game/archive.xml','layout/custom_game/survival_hud.xml','layout/custom_game/payment_test.xml',
 'scripts/custom_game/common/purple_shell.js','styles/custom_game/common/purple_shell.css',
 'scripts/custom_game/common/ui_components.js','scripts/custom_game/ui_layers.js',
 'scripts/custom_game/survival_ui.js',
 'scripts/custom_game/archive_purple.js','styles/custom_game/archive_purple.css',
 'scripts/custom_game/archive_180de7e38b_titles_compact_v6.js','scripts/custom_game/archive_handoff_180de7e38b.js',
 'scripts/custom_game/reference_windows.js','scripts/custom_game/remaining_5d5c1152eb.js',
 'scripts/custom_game/shop_remaining_5d5c1152eb.js','scripts/custom_game/shop_tooltip_remaining_5d5c1152eb.js',
 'styles/custom_game/shop_purple.css','scripts/custom_game/common/commerce_components.js',
 'scripts/custom_game/commerce_remaining_5d5c1152eb.js','styles/custom_game/common/commerce_purple.css',
 'scripts/custom_game/menu_purple.js','styles/custom_game/menu_purple.css',
 'scripts/custom_game/vip_window.js','styles/custom_game/vip_purple.css',
 'scripts/custom_game/payment_test.js','scripts/custom_game/commerce_wallet.js','styles/custom_game/common/checkout_purple.css',
 'scripts/custom_game/lottery_handoff_bb9968eef7.js','scripts/custom_game/lottery_cinematic_v1.js','scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','scripts/custom_game/daily_remaining_5d5c1152eb.js',
 'scripts/custom_game/treasure_history.js','styles/custom_game/daily_purple.css','styles/custom_game/treasure_purple.css',
 'scripts/custom_game/icons_remaining_5d5c1152eb.js'
].filter(p=>fs.existsSync('panorama/src/'+p));
const records=[];
for(const relative of files){
 for(const [kind,source] of [['source','panorama/src/'+relative],['runtime','panorama/'+relative.replace(/\.js$/,'.vjs_c').replace(/\.css$/,'.vcss_c').replace(/\.xml$/,'.vxml_c')]]){
  if(!fs.existsSync(source))continue;
  const bytes=fs.readFileSync(source),saved=output+'/'+kind+'/'+relative;fs.mkdirSync(path.dirname(saved),{recursive:true});fs.writeFileSync(saved,bytes);
  records.push({kind,source,saved,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),bytes:bytes.length});
 }
}
fs.writeFileSync(output+'/manifest.json',JSON.stringify({at:new Date().toISOString(),name,records},null,2));
fs.writeFileSync(base+'/compile_scope.json',JSON.stringify(files,null,2));
console.log('PURPLE_CHECKPOINT '+name+' '+records.length+' files');
