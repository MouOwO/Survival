const fs=require('fs'),vm=require('vm'),assert=require('assert');
const nodes={};for(const id of ['SurvivalPortraitCameraEditor','SurvivalJuggernautPortraitOverlay','SurvivalJuggernautPortraitScene','SurvivalTowerPortraitOverlay','PortraitCameraEditorValues','PortraitCameraEditorStatus'])nodes[id]={visible:true,SetHasClass(){}};
const cfg={},commands={},root={FindChildTraverse:id=>nodes[id],GetParent:()=>null};
const $={GetContextPanel:()=>root,Msg(){},Warning(){},DispatchEvent(){}};
vm.runInNewContext(fs.readFileSync(process.argv[2]||'panorama/src/scripts/custom_game/portrait_camera_editor.js','utf8'),{$,GameUI:{CustomUIConfig:()=>cfg},Game:{AddCommand:(name,fn)=>commands[name]=fn}});
function check(expected){for(const id of ['SurvivalPortraitCameraEditor','SurvivalJuggernautPortraitOverlay','SurvivalJuggernautPortraitScene'])assert.strictEqual(nodes[id].visible,expected,id);assert.strictEqual(nodes.SurvivalTowerPortraitOverlay.visible,true,'normal HUD portrait must not be changed');}
check(false);commands.survival_portrait_camera();check(true);cfg.SurvivalPortraitCameraEditor.SetVisible(false);check(false);cfg.SurvivalPortraitCameraEditor.Toggle();check(true);cfg.SurvivalPortraitCameraEditor.Toggle();check(false);
console.log('PORTRAIT_PREVIEW_PASS: hidden on load, opt-in editor preview, close/reopen, live portrait untouched');
