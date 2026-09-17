// One-time/idempotent typography-only migration. Geometry and handlers stay intact.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),src=path.join(root,'panorama/src');
const files=JSON.parse(fs.readFileSync(path.join(root,'art/ui/development/ui_reuse_import/page_files.json')));
for(const file of files.filter(f=>f.endsWith('.css')).concat('styles/custom_game/common/ui_components.css')){
 const p=path.join(src,file),original=fs.readFileSync(p,'utf8');
 fs.writeFileSync(p,original.replace(/font-(?:family|weight)\s*:[^;}]+;?/g,''));
}
for(const name of ['archive.xml','survival_hud.xml','rogue_reward_ui.xml']){
 const p=path.join(src,'layout/custom_game',name);let text=fs.readFileSync(p,'utf8');
 if(!text.includes('/common/ui_typography.css'))text=text.replace('</styles>','<include src="file://{resources}/styles/custom_game/common/ui_typography.css"/></styles>');
 if(name==='survival_hud.xml'&&!text.includes('/common/ui_typography.js'))text=text.replace('</scripts>','<include src="file://{resources}/scripts/custom_game/common/ui_typography.js"/></scripts>');
 fs.writeFileSync(p,text);
}
const components=path.join(src,'scripts/custom_game/common/ui_components.js');
let js=fs.readFileSync(components,'utf8');
js=js.replace('if(valid(props.titlePanel))apply(props.titlePanel,{fontFamily:U.Tokens.fonts.title+", SimSun",color:U.Tokens.colors.text_on_dark});',
 'if(valid(props.titlePanel)){props.titlePanel.AddClass("UIFontTitle");apply(props.titlePanel,{color:U.Tokens.colors.text_on_dark});}');
fs.writeFileSync(components,js);
const tokenPath=path.join(src,'ui/design_tokens.json'),tokens=JSON.parse(fs.readFileSync(tokenPath));
tokens.fonts={title:'Source Han Serif SC',body:'Source Han Sans SC',medium:'Source Han Sans SC',
 title_weight:'bold',body_weight:'normal',medium_weight:'medium',
 fallback:'Noto Sans SC, Microsoft YaHei',title_fallback:'Noto Serif SC, SimSun',
 manifest:'font_manifest.json',styles:'styles/custom_game/common/ui_typography.css'};
fs.writeFileSync(tokenPath,JSON.stringify(tokens,null,2)+'\n');
console.log('TYPOGRAPHY_MIGRATION_PASS: common font roles; existing sizes, geometry and handlers retained.');
