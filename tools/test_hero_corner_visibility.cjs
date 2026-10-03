const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('panorama/src/scripts/custom_game/portrait_presentation.js','utf8');
let snapshot={},assigned=77,owner=0,name='npc_dota_hero_axe',asset='';
const portrait={SetImage(x){asset=x;}},button={style:{},SetPanelEvent(){},FindChildTraverse(){return portrait;}};
const root={FindChildTraverse(){return button;}};
const env={cfg:{SurvivalHeroSelection:{CanSelect:()=>true}},valid:p=>!!p,style:(p,v)=>Object.assign(p.style,v),
 Game:{GetLocalPlayerID:()=>0},Players:{GetPlayerHeroEntityIndex:()=>assigned},
 CustomNetTables:{GetTableValue:()=>snapshot},Entities:{GetUnitName:()=>name,GetPlayerOwnerID:()=>owner}};
vm.createContext(env);vm.runInContext(source.slice(source.indexOf('    function refreshLocalHeroPortrait('),source.indexOf('    // Read-only Tools diagnostic')),env);
function check(visible){env.refreshLocalHeroPortrait(root);assert.equal(button.visible,visible);assert.equal(button.hittest,visible);assert.equal(button.style.visibility,visible?'visible':'collapse');}
check(false);
snapshot={hero_ready:0,hero_id:'axe',unit_entindex:77};check(false);
snapshot.hero_ready=1;check(true);assert(asset.endsWith('portrait_axe.png'));
assigned=88;check(false);assert.equal(asset,'','stale portrait cleared when the player hero changes');
assigned=77;owner=1;check(false);owner=0;check(true);
name='npc_dota_hero_undying';check(false);
name='npc_dota_hero_axe';snapshot.hero_id='';check(false);
snapshot={};check(false);
const xml=fs.readFileSync('panorama/src/layout/custom_game/survival_hud.xml','utf8');
assert(/id="SurvivalLocalHeroPortrait" visible="false" hittest="false"/.test(xml),'portrait starts hidden before any HUD refresh');
console.log('HERO_CORNER_VISIBILITY_PASS: startup, pending summon, real hero, stale identity, wrong owner, placeholder and cleared snapshot');
