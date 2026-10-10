const fs=require('fs'),vm=require('vm'),assert=require('assert');
const hud=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
assert(!hud.includes('HandoffTowerAuto') && !hud.includes('updateTowerAuto('),
 'the separate tower auto-upgrade control and its refresh must be removed');
console.log('AUTO_TOWER_BUTTON_PASS: separate control and per-HUD-update polling removed');
const themeConfig={},skin={GameUI:{CustomUIConfig:()=>themeConfig}};
vm.createContext(skin);
['archive_theme_tokens.js','archive_theme.js'].forEach(name=>vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+name,'utf8'),skin));
skin.palette=themeConfig.ArchiveTheme.Apply;
function panel(type,id,classes=[],children=[]){return {paneltype:type,id,style:{color:'#ffffaa',backgroundImage:'ivory'},enabled:true,checked:false,BHasClass:c=>classes.includes(c),Children:()=>children};}
const name=panel('Label','',['ArchiveItemName']),count=panel('Label','',['ArchiveCount']),level=panel('Label','',['ArchiveFragmentLevel']);
const label=panel('Label',''),promote=panel('Button','',['ArchivePromote'],[label]);promote.enabled=false;
const filterText=panel('Label',''),filter=panel('RadioButton','ArchiveFilter_all',[],[filterText]);filter.checked=true;
const effect=panel('Label','ArchiveTooltipEffect'),title=panel('Label','ArchiveTooltipName');
skin.palette(panel('Panel','ArchiveWindow',[],[name,count,level,promote,filter]));skin.palette(panel('Panel','ArchiveTooltip',[],[effect,title]));
assert.equal(name.style.color,'#d8e0e8');assert.equal(count.style.color,'#f0d48a');assert.equal(level.style.color,count.style.color);assert.equal(promote.style.backgroundImage,'none');assert.equal(promote.style.backgroundColor,'#263440');assert.equal(label.style.color,'#aebdcc');assert.equal(label.style.opacity,'1');assert.equal(filterText.style.color,'#f0d48a');assert.equal(effect.style.color,'#d8e0e8');assert.equal(title.style.color,'#ffffff');assert.equal(name.style.textShadow,'none');
promote.enabled=true;skin.palette(promote);assert.equal(promote.style.backgroundColor,'#334c5b');assert.equal(label.style.color,'#dce6ed');
console.log('ARCHIVE_PALETTE_PASS: names, counts, levels, selection, disabled/enabled dark promotion buttons, tooltip and stale inline skin override');

assert.equal(name.style.fontFamily,undefined,"palette must preserve CSS font metrics");
