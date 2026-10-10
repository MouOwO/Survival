// Engine-owned nodes are stand-ins in browser preview. The HUD decoration is production code.
Panel.prototype.ToggleClass=function(c){this.el.classList.toggle(c);};
Panel.prototype.GetAttributeString=function(k,f){return f||'';};Panel.prototype.SetAttributeString=function(){};
GameUI.SetDefaultUIEnabled=()=>{};GameUI.SelectUnit=()=>{};GameUI.IsAltDown=()=>false;
window.Abilities={GetAbilityName:i=>['proto_frost_nova','proto_arcane_barrage','proto_void_pulse','proto_magic_slingshot'][i%4],IsHidden:()=>false,GetLevel:()=>1,IsCooldownReady:()=>true,GetCooldownTimeRemaining:()=>0};
Entities.GetAbility=(unit,i)=>i<4?i:-1;Entities.GetHealth=()=>1000;Entities.GetMaxHealth=()=>1000;Entities.GetMana=()=>100;Entities.GetMaxMana=()=>100;Entities.IsAlive=()=>true;Entities.HasModifier=()=>false;Entities.GetUnitLabel=()=>'';
Players.GetPlayerHeroEntityIndex=()=>44;
cfg.HandoffCombat={Entries:()=>[0,1,2,3].map(i=>({ability:i,name:Abilities.GetAbilityName(i)}))};
const nativeHost=new Panel('Panel',root,'NativeEngineStandins');
const scopes={lower_hud:nativeHost,center_with_stats:'lower_hud',center_block:'center_with_stats',PortraitGroup:'center_block',PortraitContainer:'PortraitGroup',portraitHUD:'PortraitGroup',portraitHUDOverlay:'PortraitGroup',AbilitiesAndStatBranch:'center_block',abilities:'AbilitiesAndStatBranch',inventory:'center_block',minimap_container:'lower_hud',minimap_block:'minimap_container',minimap:'minimap_block'};
for(const [id,parent]of Object.entries(scopes))new Panel('Panel',typeof parent==='string'?nodes[parent]:parent,id);
for(let i=0;i<4;i++){const p=new Panel('Panel',nodes.abilities,'Ability'+i),img=new Panel('Image',p,'PreviewAbility'+i);img.SetImage('file://{images}/spellicons/survival/native/'+['skadi','arcane_blink','skill_destroy','mystic_staff'][i]+'.png');img.style.width='100%';img.style.height='100%';}
for(let i=0;i<6;i++)new Panel('Panel',nodes.inventory,'inventory_slot_'+i);
const portrait=new Panel('Image',nodes.PortraitContainer,'PreviewPortrait');portrait.SetImage('file://{images}/spellicons/survival/native/portrait_ogre_magi.png');portrait.style.width='100%';portrait.style.height='100%';
for(const id of ['CombatAttackValue','CombatArmorValue','CombatAttackSpeedValue','CombatStrengthValue','CombatAgilityValue','CombatIntellectValue','SurvivalUnitName','SurvivalHealthValue','SurvivalManaValue']){const p=new Panel('Label',root,id);p.text=id==='SurvivalUnitName'?'食人魔魔法师':'100';p.visible=false;}
new Panel('Panel',root,'HandoffHUD');
CustomNetTables.GetTableValue=table=>table==='survival_ui_state'?{sequence:1,resources:{gold:2283,wood:968,population:3,max_population:6},wave:{current_wave:3,total_waves:30,timer:88,alive:18,alive_limit:90}}:{};
window.selectedEntity=44;root.RemoveClass('HandoffBoot');
