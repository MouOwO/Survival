const fs=require('fs'),vm=require('vm'),assert=require('assert');
const s=fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js','utf8');
const body=s.slice(s.indexOf('    function updateCosmeticPortrait(snapshot)'),s.indexOf('    function cosmeticPortraitSentinel()'));
let multi=false,hidden=[],calls=[];
const scene={style:{},SetUnit:(...args)=>calls.push(args)}, overlay={style:{}};
const context={String,Number,Error,activePortraitKey:'',activePortraitMode:'',activePortraitUnit:'',activePortraitEntity:-1,portraitTransitionSignature:'',
 multiSelectionPortraitActive:()=>multi,hideCosmeticPortrait:reason=>hidden.push(reason),displayUnit:()=>7,
 towerPortraitOverlayPanel:()=>overlay,towerPortraitScenePanel:()=>scene,officialPortraitPanel:()=>({id:'PortraitScene'}),
 mountTowerPortraitAtNativeLayer:()=>true,applyTowerPortraitContentScale:()=>{},positionCosmeticPortrait:()=>true,
 setPortraitAnchorDiagnostic:()=>{},restoreNativePortraitsExcept:()=>{},dimNativePortraitOpacity:()=>{},
 formatPortraitRect:()=>'',portraitRect:()=>({}),$:{Msg:()=>{},Warning:()=>{}}};
vm.createContext(context);vm.runInContext(body,context);
const data={entindex:7,model_asset_id:'challenge_monster_terrorblade_fractal_horns',portrait_unit_name:'npc_dota_hero_terrorblade',portrait_item_def:''};
assert(context.updateCosmeticPortrait(data));assert.deepStrictEqual(calls,[['npc_dota_hero_terrorblade','default',false]]);assert.equal(overlay.style.visibility,'visible');
assert(context.updateCosmeticPortrait(data));assert.equal(calls.length,1,'same identity must not recreate a scene');
assert.equal(context.updateCosmeticPortrait({...data,entindex:8}),false);
assert.equal(context.updateCosmeticPortrait({...data,model_asset_id:'challenge_monster_terrorblade_fractal_horns_wrong'}),false);
multi=true;assert.equal(context.updateCosmeticPortrait(data),false);assert.equal(hidden.at(-1),'multi_selection');
console.log('SEVEN_SINS_PORTRAIT_PASS: complete native hero, exact asset/selection, stable scene, multiselect restoration');

multi=false;
for(const [asset,unit] of Object.entries({beastmaster_legacy:'beastmaster',morphling:'morphling',ember_searing_path:'ember_spirit',primal_beast_svarog:'primal_beast',spectre_phantom_advent:'spectre'})){
 assert(context.updateCosmeticPortrait({...data,model_asset_id:'challenge_monster_'+asset,portrait_unit_name:'npc_dota_hero_'+unit}));
 assert.equal(calls.at(-1)[0],'npc_dota_hero_'+unit);
}
assert(context.updateCosmeticPortrait({...data,model_asset_id:'hero_permanent_hero_doom',portrait_unit_name:'npc_dota_hero_doom_bringer'}));
console.log('CHALLENGE_DOOM_PORTRAIT_PASS: five complete challenge heroes and Doom');
